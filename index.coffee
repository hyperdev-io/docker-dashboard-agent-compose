fs            = require 'fs-extra'
path          = require 'path'
Mqtt          = require '@bigboat/mqtt-client'
config        = require './src/coffee/config'
packageJson   = require './package.json'
events = require 'events'

try
  fs.mkdirSync (projectDataPath = path.join config.dataDir, config.domain)
catch err
  unless err.code is 'EEXIST'
    console.error 'Unable to create project data directory', projectDataPath
    process.exit 1

libcompose = (require './src/coffee/compose') config

mqtt = Mqtt()

logsEventEmitter = new events.EventEmitter()

publishSystemMem = (data) -> mqtt.publish '/system/memory', data
publishSystemUptime = (data) -> mqtt.publish '/system/uptime', data
publishSystemCpu = (data) -> mqtt.publish '/system/cpu', data
require('./src/js/os-monitor')(publishSystemMem, publishSystemUptime, publishSystemCpu)

compose = require('./src/coffee/compose/actions') config
startHandler = (data) ->
  instanceName = data.instance.name
  options = data.instance.options

  console.log(data.app.dockerCompose)
  
  compose.config instanceName, data.app.dockerCompose, data, (err, composev2) ->
    if err
      console.log(err)
      mqtt.publish '/agent/docker/log/startup/error',
        instance: instanceName
        data: err
    else
      composition = libcompose.augmentCompose instanceName, options, composev2

      start = compose.start instanceName, composition, data
      start.on 'pulling', (event) ->
        event.instance = instanceName
        mqtt.publish '/agent/docker/pulling', event
      start.on 'startup-log', (logData) ->
        event =
          instance: instanceName
          data: logData
        mqtt.publish '/agent/docker/log/startup', event

stopHandler = (data) ->
  console.log('stop', data)
  instanceName = data.instance.name
  stop = compose.stop instanceName, data
  stop.on 'teardown-log', (logData) ->
    event =
      instance: instanceName
      data: logData
    mqtt.publish '/agent/docker/log/teardown', event

startLogsHandler = (data) ->
  logs = compose.logs data, logsEventEmitter
  logsEventEmitter.on 'stop_log_' + data.serviceName+data.sessionId, () ->
    console.log('stop','stop_log_' + data.serviceName)
    console.log('closed pid', logs.pid)
    logs.stdout.destroy();
    logs.stderr.destroy();
    logs.kill();
  logsEventEmitter.on 'send_log' + data.serviceName+data.sessionId, (logData) ->
    console.log(logData)
    mqtt.publish '/send_log/'+data.serviceName+'/'+data.sessionId, logData

stopLogsHandler = (data) ->
  logsEventEmitter.emit 'stop_log_' + data.serviceName+data.sessionId

require('./src/coffee/storage') mqtt, config

mqtt.on 'message', (topic, data) -> 
  switch topic
    when '/commands/instance/stop' then stopHandler JSON.parse data
    when '/commands/instance/start' then startHandler JSON.parse data
    when '/commands/logs/start' then startLogsHandler JSON.parse data
    when '/commands/logs/stop' then stopLogsHandler JSON.parse data

mqtt.subscribe('/commands/instance/stop')
mqtt.subscribe('/commands/instance/start')
mqtt.subscribe('/commands/logs/start')
mqtt.subscribe('/commands/logs/stop')