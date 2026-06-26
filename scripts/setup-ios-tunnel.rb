#!/usr/bin/env ruby
# Adds the ErebrusTunnel Network Extension target to ios/Runner.xcodeproj.
# Usage: ./scripts/setup-ios-tunnel.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')
FRAMEWORK_PATH = 'Frameworks/Libbox.xcframework'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless runner

if project.targets.any? { |t| t.name == 'ErebrusTunnel' }
  puts '✓ ErebrusTunnel target already exists'
  exit 0
end

# Groups
ios_group = project.main_group
shared_group = ios_group.new_group('Shared', 'Shared')
tunnel_group = ios_group.new_group('ErebrusTunnel', 'ErebrusTunnel')

def add_file(group, path, target, project, headers: nil)
  ref = group.new_file(path)
  if path.end_with?('.swift')
    target.source_build_phase.add_file_reference(ref)
  elsif path.end_with?('.xcframework')
    target.frameworks_build_phase.add_file_reference(ref)
    ref.path = path
  end
  project.targets.each do |t|
    next unless t.name == 'Runner' || t.name == 'ErebrusTunnel'
    next if t == target
    next unless path.end_with?('.swift') && path.start_with?('Shared/')
    t.source_build_phase.add_file_reference(ref) unless t.source_build_phase.files_references.include?(ref)
  end
  ref
end

# Extension target
extension = project.new_target(
  :app_extension,
  'ErebrusTunnel',
  :ios,
  '15.0',
  project.products_group,
  :swift
)
extension.product_type = 'com.apple.product-type.app-extension'

tunnel_plist = tunnel_group.new_file('ErebrusTunnel/Info.plist')
tunnel_ent = tunnel_group.new_file('ErebrusTunnel/ErebrusTunnel.entitlements')

%w[
  Shared/TunnelConstants.swift
  Shared/FilePath.swift
  Shared/RunBlocking.swift
  ErebrusTunnel/PacketTunnelProvider.swift
  ErebrusTunnel/ExtensionPlatformInterface.swift
  ErebrusTunnel/TunnelStatsMonitor.swift
].each do |rel|
  group = rel.start_with?('Shared/') ? shared_group : tunnel_group
  add_file(group, rel, extension, project)
end

frameworks_group = ios_group['NativeFrameworks'] || ios_group.new_group('NativeFrameworks')
framework_ref = frameworks_group.files.find { |f| f.path&.include?('Libbox.xcframework') } ||
                frameworks_group.new_file(FRAMEWORK_PATH)
framework_ref.source_tree = 'SOURCE_ROOT'
framework_ref.last_known_file_type = 'wrapper.xcframework'
extension.frameworks_build_phase.add_file_reference(framework_ref)

# Runner additions
runner_group = ios_group.groups.find { |g| g.name == 'Runner' } || ios_group
runner_tunnel_mgr = runner_group.new_file('Runner/TunnelManager.swift')
runner.source_build_phase.add_file_reference(runner_tunnel_mgr)

runner_ent = runner_group.new_file('Runner/Runner.entitlements')
runner_constants = shared_group.files.find { |f| f.path&.end_with?('TunnelConstants.swift') } ||
                   shared_group.new_file('TunnelConstants.swift')
runner_constants.path = 'TunnelConstants.swift'
unless runner.source_build_phase.files_references.include?(runner_constants)
  runner.source_build_phase.add_file_reference(runner_constants)
end

# Embed extension in Runner
embed_phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed App Extensions'
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  runner.build_phases.delete(embed_phase)
  thin = runner.build_phases.find { |p| p.display_name == 'Thin Binary' }
  if thin
    idx = runner.build_phases.index(thin)
    runner.build_phases.insert(idx, embed_phase)
  else
    runner.build_phases << embed_phase
  end
end
build_file = embed_phase.add_file_reference(extension.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

runner.add_dependency(extension)

# Build settings
extension.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'ErebrusTunnel/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'ErebrusTunnel/ErebrusTunnel.entitlements'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.erebrus.vpn.ErebrusTunnel'
  config.build_settings['PRODUCT_NAME'] = 'ErebrusTunnel'
  config.build_settings['DEVELOPMENT_TEAM'] = 'VV2P8ZJ55M'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = [
    '$(inherited)',
    '$(PROJECT_DIR)/Frameworks',
  ]
end

runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.save
puts '✓ Added ErebrusTunnel target to ios/Runner.xcodeproj'
puts '  Next: ./scripts/build-libbox-ios.sh'