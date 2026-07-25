#!/usr/bin/env ruby
# Adds the sandboxed ErebrusTunnel Packet Tunnel Provider to the macOS project.
# Safe to rerun; existing targets, source references, and embed phases are reused.
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'macos', 'Runner.xcodeproj')
FRAMEWORK_PATH = 'Frameworks/Libbox.xcframework'
TEAM_ID = '76KW3AMAW5'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |target| target.name == 'Runner' }
abort('Runner target not found') unless runner

root_group = project.main_group
shared_candidates = root_group.groups.select { |group| group.display_name == 'Shared' }
shared_group = shared_candidates.find do |group|
  group.files.any? do |file|
    runner.source_build_phase.files_references.include?(file)
  end
end || shared_candidates.first || root_group.new_group('Shared', 'Shared')
tunnel_group = root_group.groups.find { |group| group.display_name == 'ErebrusTunnel' } ||
               root_group.new_group('ErebrusTunnel', 'ErebrusTunnel')
frameworks_group = root_group.groups.find { |group| group.display_name == 'NativeFrameworks' } ||
                   root_group.new_group('NativeFrameworks')

extension = project.targets.find { |target| target.name == 'ErebrusTunnel' }
unless extension
  extension = project.new_target(
    :app_extension,
    'ErebrusTunnel',
    :osx,
    '10.15',
    project.products_group,
    :swift
  )
  extension.product_type = 'com.apple.product-type.app-extension'
end

def file_reference(group, name)
  group.files.find { |file| File.basename(file.path.to_s) == File.basename(name) } ||
    group.new_file(name)
end

def add_source(target, reference)
  return if target.source_build_phase.files_references.include?(reference)

  target.source_build_phase.add_file_reference(reference)
end

# Older project revisions already had an unnamed Shared group. Consolidate any
# duplicate created by Xcode or an earlier setup-script run before adding files.
(shared_candidates - [shared_group]).each do |duplicate_group|
  duplicate_group.files.dup.each do |duplicate|
    primary = file_reference(shared_group, File.basename(duplicate.path.to_s))
    project.targets.each do |target|
      next unless target.respond_to?(:source_build_phase)

      duplicate_build_files = target.source_build_phase.files.select do |build_file|
        build_file.file_ref == duplicate
      end
      next if duplicate_build_files.empty?

      duplicate_build_files.each(&:remove_from_project)
      add_source(target, primary)
    end
    duplicate.remove_from_project
  end
  duplicate_group.remove_from_project
end

file_reference(tunnel_group, 'Info.plist')
file_reference(tunnel_group, 'ErebrusTunnel.entitlements')

%w[
  PacketTunnelProvider.swift
  ExtensionPlatformInterface.swift
  TunnelStatsMonitor.swift
].each do |name|
  add_source(extension, file_reference(tunnel_group, name))
end

%w[
  TunnelConstants.swift
  FilePath.swift
  RunBlocking.swift
].each do |name|
  reference = file_reference(shared_group, name)
  add_source(extension, reference)
end

constants = file_reference(shared_group, 'TunnelConstants.swift')
add_source(runner, constants)

framework = frameworks_group.files.find do |file|
  file.path.to_s.include?('Libbox.xcframework')
end
unless framework
  framework = frameworks_group.new_file(FRAMEWORK_PATH)
  framework.source_tree = 'SOURCE_ROOT'
  framework.last_known_file_type = 'wrapper.xcframework'
end
unless extension.frameworks_build_phase.files_references.include?(framework)
  extension.frameworks_build_phase.add_file_reference(framework)
end

embed_phase = runner.copy_files_build_phases.find do |phase|
  phase.name == 'Embed App Extensions'
end
unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed App Extensions'
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  runner.build_phases << embed_phase
end
unless embed_phase.files_references.include?(extension.product_reference)
  build_file = embed_phase.add_file_reference(extension.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

unless runner.dependencies.any? { |dependency| dependency.target == extension }
  runner.add_dependency(extension)
end

generated_config = project.files.find do |file|
  file.path.to_s.end_with?('Flutter-Generated.xcconfig')
end

extension.build_configurations.each do |config|
  config.base_configuration_reference = generated_config if generated_config
  config.build_settings.merge!(
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'CODE_SIGN_ENTITLEMENTS' => 'ErebrusTunnel/ErebrusTunnel.entitlements',
    'CODE_SIGN_IDENTITY' => 'Apple Development',
    'CODE_SIGN_STYLE' => 'Automatic',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)',
    'DEVELOPMENT_TEAM' => TEAM_ID,
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'FRAMEWORK_SEARCH_PATHS' => [
      '$(PROJECT_DIR)/Frameworks',
    ],
    'INFOPLIST_FILE' => 'ErebrusTunnel/Info.plist',
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/../Frameworks',
      '@loader_path/../Frameworks',
    ],
    'MACOSX_DEPLOYMENT_TARGET' => '11.0',
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'OTHER_LDFLAGS' => '',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.erebrus.vpn.ErebrusTunnel',
    'PRODUCT_NAME' => 'ErebrusTunnel',
    'SDKROOT' => 'macosx',
    'SKIP_INSTALL' => 'YES',
    'SWIFT_VERSION' => '5.0'
  )
end

runner.build_configurations.each do |config|
  config.build_settings['DEVELOPMENT_TEAM'] = TEAM_ID
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
end

target_attributes = project.root_object.attributes['TargetAttributes'] ||= {}
target_attributes[extension.uuid] = {
  'CreatedOnToolsVersion' => Xcodeproj::Constants::LAST_KNOWN_OBJECT_VERSION.to_s,
  'ProvisioningStyle' => 'Automatic',
  'SystemCapabilities' => {
    'com.apple.NetworkExtensions' => { 'enabled' => 1 },
    'com.apple.Sandbox' => { 'enabled' => 1 },
  },
}

runner_attributes = target_attributes[runner.uuid] ||= {}
capabilities = runner_attributes['SystemCapabilities'] ||= {}
capabilities['com.apple.ApplicationGroups.Mac'] = { 'enabled' => 1 }
capabilities['com.apple.NetworkExtensions'] = { 'enabled' => 1 }
capabilities['com.apple.Sandbox'] = { 'enabled' => 1 }

project.save
puts '✓ macOS ErebrusTunnel target is configured and embedded'
puts '  Next: ./scripts/build-libbox-macos.sh'
