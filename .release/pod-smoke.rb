require 'xcodeproj'
project = Xcodeproj::Project.new('Smoke.xcodeproj')
target = project.new_target(:static_library, 'Smoke', :ios, '13.0')
source = project.main_group.new_file('Smoke.swift')
target.source_build_phase.add_file_reference(source)
target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
end
project.save
File.write('Smoke.swift', <<~SWIFT)
  import Foundation
  import JSONPatch
  public func smokePatch() throws -> JSONPatch {
      try JSONPatch(data: Data("[]".utf8))
  }
SWIFT
File.write('Podfile', <<~PODFILE)
  platform :ios, '13.0'
  use_frameworks!
  project 'Smoke.xcodeproj'
  target 'Smoke' do
    pod 'RMJSONPatch', :git => 'https://github.com/raymccrae/swift-jsonpatch.git', :tag => 'v2.0.0'
  end
PODFILE
