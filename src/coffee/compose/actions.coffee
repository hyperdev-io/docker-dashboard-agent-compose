events = require 'events'
spawn  = require('child_process').spawn
yaml   = require 'js-yaml'
fs     = require 'fs'
mkdirp = require 'mkdirp'
_      = require 'lodash'

module.exports = (config) ->

  buildScriptPaths = (instance) ->
    [scriptDir = "#{config.compose.scriptBaseDir}/#{config.domain}/#{instance}", "#{scriptDir}/docker-compose.yml"]

  start: (instance, composition, data) ->
    eventEmitter = new events.EventEmitter()
    compose = yaml.safeDump composition
    [scriptDir, scriptPath] = buildScriptPaths instance

    pullCb = (data) ->
      data = data.toString()
      if m = data.match /(.+): Pulling from (.+)/i
        [all, version, image] = m
        eventEmitter.emit 'pulling', {image: image, version: version}
      else console.log 'pull output unknown', data
    upCb = (data) -> console.log 'UP', data.toString()

    env = buildEnv config, data

    emitLogCb = (data) -> eventEmitter.emit 'startup-log', data.toString()

    ensureMkdir scriptDir, ->
      writeFile scriptPath, compose, ->
        runCmd 'docker-compose', ['-f', scriptPath, '-p', instance, 'pull'], env, {stdout: pullCb, stderr: emitLogCb}, ->
          runCmd 'docker-compose', ['-f', scriptPath, '-p', instance, 'up', '-d', '--remove-orphans'], env, {stderr: emitLogCb}, ->
            console.log 'Done, started', instance
    eventEmitter

  stop: (instance, data) ->
    eventEmitter = new events.EventEmitter()
    [scriptDir, scriptPath] = buildScriptPaths instance

    env = buildEnv config, data
    emitLogCb = (data) -> eventEmitter.emit 'teardown-log', data.toString()

    runCmd 'docker-compose', ['-f', scriptPath, '-p', instance, 'down', '--remove-orphans'], env, {stderr: emitLogCb}, ->
      console.log 'Done, stopped', instance
    eventEmitter

#
# Helper functions to write files and run processes
#

buildEnv = (cfg, instanceCfg) ->
  BIGBOAT_PROJECT: cfg.domain
  BIGBOAT_DOMAIN: cfg.domain
  BIGBOAT_TLD: cfg.tld
  BIGBOAT_APPLICATION_NAME: instanceCfg.app.name
  BIGBOAT_APPLICATION_VERSION: instanceCfg.app.version
  BIGBOAT_INSTANCE_NAME: instanceCfg.instance.name

runCmd = (cmd, args, env, callbacks, exitCb) ->
  spawned = spawn cmd, args, env: (_.extend {}, process.env, env)
  if spawned.error
    console.error "Error, unable to execute", cmd, args, pull.error
  else
    console.log 'success', cmd, args
    spawned.stdout.on 'data', callbacks.stdout if callbacks.stdout
    spawned.stderr.on 'data', callbacks.stderr if callbacks.stderr
    spawned.stdout.on 'end', exitCb

ensureMkdir = (scriptDir, success) ->
  mkdirp scriptDir, (err) ->
    unless not err or err.code is 'EEXIST'
      console.log 'Cannot make dir', scriptDir, err
    else
      success()

writeFile = (path, contents, success) ->
  fs.writeFile path, contents, (err) ->
    if err then console.error 'Error writing file', err
    else success()
