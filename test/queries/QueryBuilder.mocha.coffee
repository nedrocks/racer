QueryBuilder = require '../../lib/queries/QueryBuilder'
expect = require 'expect.js'
{deepEqual} = require '../../lib/util'

query = (ns, params = {}) ->
  params.from = ns
  return new QueryBuilder params

describe 'QueryBuilder', ->
  describe 'fromJSON', ->
    it 'should instantiate the correct query', ->
      q0 = query('users').where('name').equals('brian').where('age').equals(26).sort(['name', 'asc']).limit(5).skip(10)
      json = q0.toJSON()
      qf = QueryBuilder.fromJSON(json)
      expect(qf).to.eql(q0)

  describe '#hash', ->
    it 'should create the same hash for 2 equivalent queries that exhibit different method call ordering', ->
      q1 = query('users').where('name').equals('brian').where('age').equals(26)
      q2 = query('users').where('age').equals(26).where('name').equals('brian')
      expect(q1.hash()).to.eql q2.hash()

      q1 = query('users').where('votes').lt(20).gt(10).where('followers').gt(100).lt(200)
      q2 = query('users').where('followers').lt(200).gt(100).where('votes').gt(10).lt(20)
      expect(q1.hash()).to.eql q2.hash()

    it 'should create different hashes for different queries', ->
      q1 = query('users').where('name').equals('brian')
      q2 = query('users').where('name').equals('nate')
      expect(q1.hash()).to.not.eql q2.hash()

    it 'should create different hash for byKey vs empty query', ->
      q1 = query('users')
      q2 = query('users').byKey('1')
      expect(q1.hash()).to.not.eql q2.hash()

    it 'should create different hashes for conditions involving strings vs numbers', ->
      q1 = query('users').byKey(1)
      q2 = query('users').byKey('1')
      expect(q1.hash()).to.not.eql q2.hash()

  describe 'coffee-style vs JavaScript style function signatures', ->

    it 'should return equivalent queries', ->
      js = query('users').where('name').equals('brian').where('age').equals(26)
      cs = query 'users',
        where:
          name: 'brian'
          age: 26

      expect(js.hash()).to.eql(cs.hash())

      js = query('users')
        .where('name').equals('Gnarls')
        .where('gender').notEquals('female')
        .where('age').gt(21).lte(30)
        .where('numFriends').gte(100).lt(200)
        .where('tags').contains(['super', 'derby'])
        .where('shoe').within(['nike', 'adidas'])
        .skip(10).limit(5)

      cs = query 'users',
        where:
          name:
            equals: 'Gnarls'
          gender:
            notEquals: 'female'
          age:
            gt: 21
            lte: 30
          numFriends:
            gte: 100
            lt: 200
          tags:
            contains: ['super', 'derby']
          shoe:
            within: ['nike', 'adidas']
        skip: 10
        limit: 5

      expect(js.hash()).to.eql(cs.hash())

      js = query('users').byKey('1')
      cs = query 'users', byKey: '1'
      expect(js.hash()).to.eql(cs.hash())