sms = require("source-map-support").install({handleUncaughtExceptions: false})
ramlParser = require 'raml-1-parser'
async = require 'async'

options = require './options'
addTests = require './add-tests'
TestFactory = require './test'
addHooks = require './add-hooks'
Runner = require './test-runner'
applyConfiguration = require './apply-configuration'
hooks = require './hooks'
Mocker = require './mocker'

class Abao
  constructor: (config) ->
    @configuration = applyConfiguration(config)
    @tests = []
    @hooks = hooks

  mock: ->
    @configuration.options.mocker = true
    @run()

  run: (done) ->
    config = @configuration
    tests = @tests
    hooks = @hooks

    # Inject the JSON refs schemas
    factory = new TestFactory(config.options.schemas)

    async.waterfall [
      # Parse hooks
      (callback) ->
        addHooks hooks, config.options.hookfiles
        callback()
      ,
      # Load RAML
      (callback) ->
        ramlParser.loadApi(config.ramlPath || '').then (raml) ->
          callback(null, raml)
        , callback
      ,
      # Parse tests from RAML
      (raml, callback) ->
        if !config.options.server
          if 'baseUri' in raml
            config.options.server = raml.baseUri
        try
          baseUri = raml.baseUri().value()
          raml.allBaseUriParameters().forEach (param) ->
            baseUri = baseUri.replace('{'+param.name()+'}', param.toJSON({serializeMetadata: false}).enum[0])
          addTests raml, tests, hooks, {}, callback, factory, baseUri
        catch err
          callback(err)
      ,
      # Run tests
      (callback) ->
      
        if config.options.mocker
          console.log('Creating mock server')
          try
            mocker = new Mocker(config.options, config.ramlPath)
            mocker.run(tests, hooks, callback)
          catch err
            console.error(err, err.stack)
          return

        runner = new Runner config.options, config.ramlPath
        runner.run tests, hooks, callback
    ], done


module.exports = Abao
module.exports.options = options

