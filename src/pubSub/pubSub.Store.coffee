{split: splitPath, lookup} = require '../path'
{finishAfter} = require '../util'
{fetchQueryData, deserialize} = queryPubSub = require './queryPubSub'

module.exports =
  type: 'Store'

  events:
    init: (store) ->
      store._liveQueries = liveQueries = {}
      store._clientSockets = clientSockets = {}
      pubSub = store._pubSub
      journal = store._journal

      pubSub.on 'noSubscribers', (path) ->
        delete liveQueries[path]

      pubSub.on 'message', (clientId, [type, data]) ->
        pubSub.emit type, clientId, data

      # Live Query Channels
      # These following 2 channels are for informing a client about
      # changes to their data set based on mutations that add/rm docs
      # to/from the data set enclosed by the live queries the client
      # subscribes to.
      ['addDoc', 'rmDoc'].forEach (message) ->
        pubSub.on message, (clientId, data) ->
          journal.nextTxnNum clientId, (err, num) ->
            throw err if err
            return clientSockets[clientId].emit message, data, num

    socket: (store, socket) ->

      # Called when a client first connects
      socket.on 'sub', (clientId, targets, ver, clientStartId) ->

        store._clientSockets[clientId] = socket
        socket.on 'disconnect', ->
          store.unsubscribe clientId
          store._journal.unregisterClient clientId
          delete store._clientSockets[clientId]

        # This promise is created in the txns.Store mixin
        socket._clientIdPromise.clear().resolve clientId

        store._checkVersion socket, ver, clientStartId, (err) ->
          # An error message will be sent to the client in checkVersion
          return if err

          socket.on 'fetch', (clientId, targets, callback) ->
            # Only fetch data
            store.fetch clientId, deserialize(targets), callback

          socket.on 'subAdd', (clientId, targets, callback) ->
            # Setup subscriptions and fetch data
            store.subscribe clientId, deserialize(targets), callback

          socket.on 'subRemove', (clientId, targets, callback) ->
            store.unsubscribe clientId, deserialize(targets), callback

          # Setup subscriptions only
          send 'subscribe', store, clientId, deserialize(targets)

  proto:
    fetch: (clientId, targets, callback) ->
      data = []
      pubSub = @_pubSub
      finish = finishAfter targets.length, (err) ->
        out = {data}
        # Note that `out` may be mutated by ot or other plugins
        pubSub.emit 'fetch', out, clientId, targets
        callback err, out

      for target in targets
        if target.isQuery
          fetchQueryData this, data, target, finish
        else
          fetchPathData this, data, target, finish
      return

    # Fetch the set of data represented by `targets` and subscribe to future
    # changes to this set of data.
    # @param {String} clientId representing the subscriber
    # @param {[String|Query]} targets (i.e., paths, or queries) to subscribe to
    # @param {Function} callback(err, data)
    subscribe: (clientId, targets, callback) ->
      data = null
      finish = finishAfter 2, (err) ->
        callback err, data
      # This call to subscribe must come before the fetch, since a liveQuery
      # is created in subscribe that may be accessed during the fetch
      send 'subscribe', this, clientId, targets, finish
      @fetch clientId, targets, (err, _data) ->
        data = _data
        finish err

    unsubscribe: (clientId, targets, callback) ->
      send 'unsubscribe', this, clientId, targets, callback

    publish: (path, type, data, meta) ->
      message = [type, data]
      queryPubSub.publish this, path, message, meta
      @_pubSub.publish path, message

    query: queryPubSub.query

send = (method, store, clientId, targets, callback) ->
  if targets
    channels = []
    queries = []
    for target in targets
      queue = if target.isQuery then queries else channels
      queue.push target
    numChannels = channels.length
    numQueries = queries.length
    count = if numChannels && numQueries then 2 else 1
    finish = finishAfter count, callback
    if numQueries
      queryPubSub[method] store, clientId, queries, finish
    if numChannels
      store._pubSub[method] clientId, channels, finish
    return

  # Unsubscribing without any targets removes all subscriptions
  # for a given clientId
  finish = finishAfter 2, callback
  queryPubSub[method] store, clientId, null, finish
  store._pubSub[method] clientId, null, finish

# Accumulates an array of tuples to set [path, value, ver]
#
# @param {Array} data is an array that gets mutated
# @param {String} root is the part of the path up to ".*"
# @param {String} remainder is the part of the path after "*"
# @param {Object} value is the lookup value of the rooth path
# @param {Number} ver is the lookup ver of the root path
addSubDatum = (data, root, remainder, value, ver) ->
  # Set the entire object
  return data.push [root, value, ver]  unless remainder?

  # Set each property one level down, since the path had a '*'
  # following the current root
  [appendRoot, remainder] = splitPath remainder
  for prop of value
    nextRoot = if root then root + '.' + prop else prop
    nextValue = value[prop]
    if appendRoot
      nextRoot += '.' + appendRoot
      nextValue = lookup appendRoot, nextValue

    addSubDatum data, nextRoot, remainder, nextValue, ver
  return

fetchPathData = (store, data, path, finish) ->
  [root, remainder] = splitPath path
  store.get root, (err, value, ver) ->
    # addSubDatum mutates data argument
    addSubDatum data, root, remainder, value, ver
    finish err
