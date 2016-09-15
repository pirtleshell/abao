async = require 'async'
_ = require 'underscore'
csonschema = require 'csonschema'


parseSchema = (source) ->
  if source.contains('$schema')
    #jsonschema
    # @response.schema = JSON.parse @response.schema
    JSON.parse source
  else
    csonschema.parse source
    # @response.schema = csonschema.parse @response.schema

parseHeaders = (raml) ->
  return {} unless raml

  headers = {}
  raml.forEach (header) ->
    headers[header.name()] = header.example()?.value()

  headers

getContentType = (bodyArray) ->
  return null unless bodyArray

  contentTypes = []
  bodyArray.forEach (body) ->
    if body.name().match(/^application\/(.*\+)?json/i)
      contentTypes.push(body.name())

  if contentTypes.length > 0 then contentTypes[0] else null

# addTests(raml, tests, [parent], callback, config)
addTests = (raml, tests, hooks, parent, callback, testFactory) ->

  # Handle 4th optional param
  if _.isFunction(parent)
    testFactory = callback
    callback = parent
    parent = null

  return callback() unless raml.resources().length > 0

  if raml.expand
    raml.expandLibraries()
    raml = raml.expand()

  schemas = {}
  if raml.schemas
    raml.schemas().forEach (type) ->
      schemas[type.name()] = type

  types = {}
  if raml.types
    raml.types().forEach (type) ->
      types[type.name()] = type

  # Iterate endpoint
  async.each raml.resources(), (resource, callback) ->
    path = resource.relativeUri().value()
    params = {}
    query = {}

    # Apply parent properties
    if parent
      path = parent.path + path
      params = _.clone parent.params

    # Setup param
    resource.uriParameters().forEach (up) ->
      if up.example()?
        params[up.name()] = up.example().value()
      else if up.type().length > 0 && types[up.type()[0]]?
        type = up.type()[0]
        if types[type].example()?
          params[up.name()] = types[type].example().value()
        else if types[up.type()[0]].examples().length > 0
          params[up.name()] = types[type].examples()[0].value()

    # In case of issue #8, resource does not define methods
    resource.methods ?= []

    # Iterate response method
    async.each resource.methods(), (api, callback) ->
      method = api.method().toUpperCase()

      # Setup query
      api.queryParameters().forEach (qp) ->
        if (!!qp.required())
          query[qp.name()] = qp.example().value()

      # Iterate response status
      api.responses().forEach (res) ->

        status = res.code().value()
        testName = "#{method} #{path} -> #{status}"

        # Append new test to tests
        test = testFactory.create(testName, hooks.contentTests[testName])
        tests.push test

        # Update test.request
        test.request.path = path
        test.request.method = method
        test.request.headers = parseHeaders(api.headers())

        contentType = getContentType(api.body())

        # select compatible content-type in request body (to support vendor tree types, i.e. application/vnd.api+json)
#        contentType = (type for type of api.body() when type.match(/^application\/(.*\+)?json/i))?[0]
        if contentType
          test.request.headers['Content-Type'] = contentType
          try
            api.body().forEach (body) ->
              if body.name() == contentType
                test.request.body = JSON.parse body.example().value()
          catch
            console.warn "cannot parse JSON example request body for #{test.name}"
        test.request.params = params
        test.request.query = query

        # Update test.response
        test.response.status = status
        test.response.schema = null

        if res?.body().length > 0
          # expect content-type of response body to be identical to request body
          if contentType
            res.body().forEach (body) ->
              if !test.response.schema && body.name() == contentType
                test.response.schema = parseSchema body.schema()[0]
          # otherwise filter in responses section for compatible content-types
          # (vendor tree, i.e. application/vnd.api+json)
          else
            res.body().forEach (body) ->
              if body.schema().length > 0 && !test.response.schema && body.name().match(/^application\/(.*\+)?json/i)
                schema = body.schema()[0]
                try
                  test.response.schema = parseSchema schemas[schema].type()[0]
                catch
                  test.response.schema = parseSchema  schema

      callback()
    , (err) ->
      if err
        console.error(err)
        return callback(err)

      # Recursive
      addTests resource, tests, hooks, {path, params}, callback, testFactory
  , callback


module.exports = addTests

