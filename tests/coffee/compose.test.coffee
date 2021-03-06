assert  = require 'assert'
compose = require '../../src/coffee/compose.coffee'

standardCfg =
  net_container:
    image: 'ictu/pipes:2'
  network:
    name: 'apps'

describe 'Compose', ->
  describe 'augmentCompose', ->
    it 'should set the deploy_placement', ->
      doc =
        services:
          www: image: 'nginx'
          db: image: 'postgres'
        networks: {}
      compose(Object.assign {}, standardCfg, {swarm: deploy_placement: '{ "node" : { "role" : "worker" } }'}).augmentCompose '', {}, doc
      assert.equal doc.services.www.deploy.placement, '{ "node" : { "role" : "worker" } }'
    it 'should set the compose version to 3.3', ->
      doc =
        version: '1.0'
        services: {}
      compose(standardCfg).augmentCompose '', {}, doc
      assert.equal doc.version, '3.3'
    it 'should delete the volumes section from the compose file', ->
      doc = volumes: {}
      assert.equal doc.volumes?, true
      compose(standardCfg).augmentCompose '', {}, doc
      assert.equal doc.volumes?, false
    it 'should set only public network if there is only 1 service', ->
      doc =
        services: www: image: 'nginx'
        networks: {}
      assert.equal doc.networks?, true
      compose(standardCfg).augmentCompose '', {}, doc
      assert.deepEqual doc.networks,
        public: external: name: 'apps'
    it 'should set public and private networks if there is more than 1 service', ->
      doc =
        services:
          www: image: 'nginx'
          db: image: 'postgres'
        networks: {}
      assert.equal doc.networks?, true
      compose(standardCfg).augmentCompose '', {}, doc
      assert.deepEqual doc.networks,
        private: null
        public: external: name: 'apps'

  describe '_restrictCompose', ->
    it 'should drop certain service capabilities', ->
      service =
        cap_add: 1
        cap_drop: 1
        cgroup_parent: 1
        devices: 1
        dns: 1
        dns_search: 1
        ports: 1
        privileged: 1
        tmpfs: 1
        this_is_not_dropped: 1
      compose(standardCfg)._restrictCompose service
      assert.deepEqual service, this_is_not_dropped: 1

  describe '_resolvePath', ->
    it 'should resolve a path relative to a given root', ->
      c = compose(standardCfg)
      assert.equal c._resolvePath('/some/root', '/my/rel/path'), '/some/root/my/rel/path'
      assert.equal c._resolvePath('/some/root/', '/my/rel/path'), '/some/root/my/rel/path'
      assert.equal c._resolvePath('/some/root', 'my/rel/path'), '/some/root/my/rel/path'
      assert.equal c._resolvePath('/some/root', './my/rel/path'), '/some/root/my/rel/path'
      assert.equal c._resolvePath('/some/root', '/other/../my/rel/path'), '/some/root/my/rel/path'
      assert.equal c._resolvePath('/some/root/', '/some/root/../../one/level/up'), '/some/root/one/level/up'
    it 'should throw an error when a relative path resolves outside of the given root', ->
      assert.throws ->
        compose(standardCfg)._resolvePath '/some/root/', '../one/level/up'
      , Error
      assert.throws ->
        compose(standardCfg)._resolvePath '/some/root/', '/../../.././one/level/up'
      , Error

  describe '_addExtraLabels', ->
    it 'should add bigboat domain and tld labels based on configuration', ->
      service = labels: existing_label: 'value'
      labels =
        existing_label: 'value'
        'bigboat.domain': 'google'
        'bigboat.tld': 'com'
      compose(Object.assign {}, standardCfg, {domain:'google', tld:'com'})._addExtraLabels 'myService', service, 'myInstance'
      assert.deepEqual service,
        labels: labels
        deploy: labels: labels
    it 'should add traefik labels based on service labels', ->
      service = deploy: labels: 'hyperdev.public.proxy.port': 3000
      compose(Object.assign {}, standardCfg, {domain:'google', tld:'com', })._addExtraLabels 'myService', service, 'myInstance'
      assert.equal service.labels['traefik.frontend.rule'], 'Host:myService.myInstance.google.public.com'
      assert.equal service.labels['traefik.port'], 3000

  describe '_addVolumeMapping', ->
    volumeTest = (inputVolume, expectedVolume, opts = {storageBucket: 'bucket1'}) ->
      c = compose Object.assign {}, standardCfg, dataDir: '/local/data/', domain: 'google'
      service = volumes: [inputVolume]
      c._addVolumeMapping service, opts
      assert.deepEqual service, volumes: [expectedVolume]
    it 'should root a volume to a base path (data bucket)', ->
      volumeTest '/my/mapping:/internal/volume', '/local/data/google/bucket1/my/mapping:/internal/volume'
    it 'should remove a volume\'s mapping when no storage bucket is given (no persistence)', ->
      volumeTest '/my/mapping:/internal/volume', '/internal/volume', {}
    it 'should leave a :rw postfix intact', ->
      volumeTest '/my/mapping:/internal/volume:rw', '/local/data/google/bucket1/my/mapping:/internal/volume:rw'
    it 'should leave a :ro postfix intact', ->
      volumeTest '/my/mapping:/internal/volume:ro', '/local/data/google/bucket1/my/mapping:/internal/volume:ro'
    it 'should remove the postfix when no storage bucket is given (compose bug)', ->
      volumeTest '/my/mapping:/internal/volume:rw', '/internal/volume', {}
    it 'should not do anything to an unmapped volume', ->
      volumeTest '/internal/volume', '/internal/volume'
    it 'should not do anything to an unmapped volume when no data bucket is given', ->
      volumeTest '/internal/volume', '/internal/volume', {}
    it 'should remove a postfix (:ro) from an unmapped volume when no data bucket is given (compose bug)', ->
      volumeTest '/internal/volume:ro', '/internal/volume', {}
    it 'should remove a postfix (:rw) from an unmapped volume when no data bucket is given (compose bug)', ->
      volumeTest '/internal/volume:rw', '/internal/volume'
    it 'should discard a volume with a mapping that resolves outside of the bucket root', ->
      c = compose Object.assign {}, standardCfg, dataDir: '/local/data/', domain: 'google'
      service = volumes: ['../../my-malicious-volume/:/internal']
      c._addVolumeMapping service, storageBucket: 'bucket1'
      assert.deepEqual service, volumes: []
    it 'should not create invalid volume section', ->
      c = compose Object.assign {}, standardCfg, dataDir: '/local/data/', domain: 'google'
      service = image: 'something'
      c._addVolumeMapping service, {storageBucket: 'bucket1'}
      assert.deepEqual service, image: 'something'

  describe '_addLocaltimeMapping', ->
    localtimeTest = (service) ->
      c = compose Object.assign {}, standardCfg, dataDir: '/local/data/', domain: 'google'
      c._addLocaltimeMapping service
      expected = service.volumes or []
      expected.push '/etc/localtime:/etc/localtime:ro'
      assert.deepEqual service, volumes: expected
    it 'should add /etc/localtime volume mapping when there are no volumes', ->
      localtimeTest {}
    it 'should add /etc/localtime volume mapping when there are other volumes', ->
      localtimeTest volumes: ['volume1', '/mapped:/volume']
