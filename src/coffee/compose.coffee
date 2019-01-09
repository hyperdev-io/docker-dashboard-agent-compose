_         = require 'lodash'
path      = require 'path'
resolvep  = require 'resolve-path'

composeLib = require './compose/lib.coffee'

module.exports = (config) ->
  _restrictCompose: restrictCompose = (service) ->
    delete service.mem_limit
    delete service.cap_add
    delete service.cap_drop
    delete service.cgroup_parent
    delete service.devices
    delete service.dns
    delete service.dns_search
    delete service.ports
    delete service.privileged
    delete service.tmpfs

  _resolvePath: resolvePath = (root, path) ->
    path = path[1...] if path[0] is '/'
    resolvep root, path

  _addExtraLabels: addExtraLabels = (serviceName, service, instance) ->
    labels = _.extend {}, service.labels, (service.deploy?.labels or {}),
      'bigboat.domain': config.domain
      'bigboat.tld': config.tld

    if labels?['hyperdev.public.proxy.port']
      publicHost = "#{serviceName}.#{instance}.#{config.domain}.public.#{config.tld}"
      labels = _.extend labels,
        'hyperdev.public.proxy.host': publicHost
        'traefik.frontend.rule': "Host:#{publicHost}"
        'traefik.port': labels?['hyperdev.public.proxy.port']
    service.deploy = if service.deploy then service.deploy else {}
    service.labels = service.deploy.labels = labels

  _addVolumeMapping: addVolumeMapping = (service, options) ->
    bucketPath = path.join config.dataDir, config.domain, options.storageBucket if options.storageBucket
    service.volumes = service.volumes?.map (v) ->
      vsplit = v.split ':'
      try
        if vsplit.length is 2
          if vsplit[1] in ['rw', 'ro']
            vsplit[0]
          else if bucketPath
            "#{resolvePath bucketPath, vsplit[0]}:#{vsplit[1]}"
          else vsplit[1]
        else if vsplit.length is 3
          if bucketPath
            "#{resolvePath bucketPath, vsplit[0]}:#{vsplit[1]}:#{vsplit[2]}"
          else "#{vsplit[1]}"
        else v
      catch e
        console.error "Error while mapping volumes. Root: #{bucketPath}, path: #{v}", e
        null
    delete service.volumes unless service.volumes
    service.volumes = service.volumes.filter((s) -> s) if service.volumes

  _addLocaltimeMapping: addLocaltimeMapping = (service) ->
    service.volumes = [] unless service.volumes
    service.volumes.push "/etc/localtime:/etc/localtime:ro"

  _addNetworkSettings: addNetworkSettings = (serviceName, service, instance, doc) ->
    subDomain = "#{instance}.#{config.domain}.#{config.tld}"
    hostname = "#{serviceName}.#{instance}".replace(/_/g, "")
    service.hostname = hostname if hostname.length < 64
    service.networks = public: aliases: ["#{serviceName}.#{subDomain}"]
    service.networks.private = null if doc.services and Object.keys(doc.services)?.length > 1
    delete service.network_mode

  _addDeploymentSettings: addDeploymentSettings = (service) ->
    defaultResources =
      limits:
        memory: '1G'
      reservations:
        memory: _.get(service, 'deploy.resources.limits.memory', '1G')
    service.deploy = _.merge {},
      mode: 'replicated'
      endpoint_mode: 'dnsrr'
      resources: defaultResources
      placement: config.swarm?.deploy_placement
    , service.deploy

  _addNetworks: addNetworks = (doc) ->
    doc.networks = public: external: name: config.network.name
    doc.networks.private = null if doc.services and Object.keys(doc.services)?.length > 1

  _addDockerMapping: addDockerMapping = (service) ->
    if service.labels?['bigboat.container.map_docker'] is 'true'
      service.volumes = [] unless service.volumes
      service.volumes.push '/var/run/docker.sock:/var/run/docker.sock'

  augmentCompose: (instance, options, doc) ->
    addNetworks doc
    for serviceName, service of doc.services
      addDeploymentSettings service
      addExtraLabels serviceName, service, instance
      addNetworkSettings serviceName, service, instance, doc
      addVolumeMapping service, options
      addLocaltimeMapping service
      addDockerMapping service
      restrictCompose service

    doc.version = '3.3'
    delete doc.volumes
    # console.log JSON.stringify doc, null, 2

    doc
