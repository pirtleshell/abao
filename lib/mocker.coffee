async = require 'async'
path = require 'path'
_ = require 'underscore'
generateHooks = require './generate-hooks'
express = require('express')
jsf = require('json-schema-faker')

class Mocker
  constructor: (options, ramlFile) ->
    @options = options
    @ramlFile = ramlFile
    @app = express()
    @

  validateUriParameters: (resourceParams, requestParams) ->

    for key, param of resourceParams

      return false unless key of requestParams

      value = requestParams[key]

      switch param.type
        when 'number', 'integer'
          asInt = parseInt(value)
          return false if isNaN( asInt )

      return false if 'enum' of param && param.enum.indexOf(value) < 0

    return true

  addToServer: (test, hooks) ->

    uri = test.request.path.replace /{([\w]+)}/ig, (matcher, val) ->
      return ":"+val

    @app[test.request.method.toLowerCase()] uri, (req, res, next) =>
      console.log('Validate uri parameters for ',  req.path)
      if @validateUriParameters(test.request.params, req.params)
        res.status(test.response.status)
        res.type('application/json')
        body = if test.response.example then test.response.example else jsf(test.response.schema)
        res.send(body)
      else
        res.status(404)
        res.end('404; Invalid parameters')
  run: (tests, hooks, done) ->

    @addToServer test for test in tests

    @app.listen 3000, ->
      console.log('Server listening on port 3000')

    done

module.exports = Mocker
