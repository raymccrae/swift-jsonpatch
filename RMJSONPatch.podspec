Pod::Spec.new do |s|
  s.name = 'RMJSONPatch'
  s.version = '2.0.0'
  s.summary = 'A Swift library for applying and generating RFC 6902 JSON patches.'
  s.description = 'JSONPatch uses Foundation JSONSerialization to apply and generate JSON patches, with Codable support.'
  s.homepage = 'https://github.com/raymccrae/swift-jsonpatch'
  s.license = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author = { 'Raymond McCrae' => 'raymccrae@yahoo.com' }
  s.source = { :git => 'https://github.com/raymccrae/swift-jsonpatch.git', :tag => "v#{s.version}" }
  s.module_name = 'JSONPatch'
  s.source_files = 'Sources/JSONPatch/**/*.swift'
  s.swift_versions = ['6.0']
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'
end
