#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates G6SensorKit.xcodeproj from the source layout.
#
# Pattern borrowed from LibreLoop/Scripts/generate_project.rb: the project
# file is generated rather than hand-maintained, so target settings stay
# reviewable in one place. Build settings are modeled on G7SensorKit.
#
#   gem install xcodeproj
#   ruby Scripts/generate_project.rb
#
# LoopKit and LoopKitUI are referenced from BUILT_PRODUCTS_DIR: this project
# only builds inside a host workspace that also builds LoopKit (LoopWorkspace
# for Loop, Trio.xcworkspace for Trio).

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'G6SensorKit.xcodeproj')

DEPLOYMENT_TARGET = '15.1'
SWIFT_VERSION = '5.9'
BUNDLE_PREFIX = 'org.nightscout'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

# ---------------------------------------------------------------- base config

def base_settings(deployment_target, swift_version)
  {
    'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
    'CURRENT_PROJECT_VERSION' => '1',
    'DEFINES_MODULE' => 'YES',
    'DYLIB_COMPATIBILITY_VERSION' => '1',
    'DYLIB_CURRENT_VERSION' => '1',
    'DYLIB_INSTALL_NAME_BASE' => '@rpath',
    'ENABLE_MODULE_VERIFIER' => 'NO',
    'IPHONEOS_DEPLOYMENT_TARGET' => deployment_target,
    'MARKETING_VERSION' => '1.0',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SDKROOT' => 'iphoneos',
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'SWIFT_VERSION' => swift_version,
    'TARGETED_DEVICE_FAMILY' => '1',
    # Required for a framework consumed by a host built separately.
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@loader_path/Frameworks'
    ]
  }
end

project.root_object.development_region = 'en'
project.root_object.known_regions = %w[en Base]

project.build_configurations.each do |config|
  config.build_settings.merge!(
    'ALWAYS_SEARCH_USER_PATHS' => 'NO',
    'CLANG_ANALYZER_NONNULL' => 'YES',
    'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'YES',
    'COPY_PHASE_STRIP' => 'NO',
    'ENABLE_STRICT_OBJC_MSGSEND' => 'YES',
    'GCC_NO_COMMON_BLOCKS' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'SWIFT_VERSION' => SWIFT_VERSION
  )

  if config.name == 'Debug'
    config.build_settings.merge!(
      'DEBUG_INFORMATION_FORMAT' => 'dwarf',
      'ENABLE_TESTABILITY' => 'YES',
      'GCC_OPTIMIZATION_LEVEL' => '0',
      'ONLY_ACTIVE_ARCH' => 'YES',
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG',
      'SWIFT_OPTIMIZATION_LEVEL' => '-Onone'
    )
  else
    config.build_settings.merge!(
      'DEBUG_INFORMATION_FORMAT' => 'dwarf-with-dsym',
      'ENABLE_NS_ASSERTIONS' => 'NO',
      'SWIFT_COMPILATION_MODE' => 'wholemodule',
      'SWIFT_OPTIMIZATION_LEVEL' => '-O',
      'VALIDATE_PRODUCT' => 'YES'
    )
  end
end

# --------------------------------------------- LoopKit framework file refs

# Use the project's own Frameworks group. Creating one by hand left two
# groups of the same name in the navigator, since xcodeproj makes its own as
# soon as anything is linked — every other kit here shows one.
frameworks_group = project.frameworks_group

def built_product_ref(project, group, name)
  ref = group.new_reference(name)
  ref.source_tree = 'BUILT_PRODUCTS_DIR'
  ref.set_explicit_file_type('wrapper.framework')
  ref.include_in_index = '0'
  ref
end

loopkit_ref = built_product_ref(project, frameworks_group, 'LoopKit.framework')
loopkitui_ref = built_product_ref(project, frameworks_group, 'LoopKitUI.framework')

# ------------------------------------------------------- G6SensorCore package

# The LoopKit-free core ships as a SwiftPM package at the repo root and is
# statically linked into G6SensorKit.framework so the plugin bundle stays
# self-contained.
core_package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
core_package.relative_path = '.'
project.root_object.package_references << core_package

core_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
core_dependency.product_name = 'G6SensorCore'

# --------------------------------------------------------------- helpers

# Group paths are already set to the source directory, so references are
# added relative to the group to avoid a duplicated path segment.
def add_sources(project, target, group, dir)
  absolute = File.join(ROOT, dir)
  Dir.glob(File.join(absolute, '**', '*.swift')).sort.each do |path|
    relative = path.sub("#{absolute}/", '')
    ref = group.new_reference(relative)
    target.add_file_references([ref])
  end
end

# String Catalogs, as EversenseKit, AccuChekKit, MedtrumKit and OmnipodKit
# ship them. Each framework carries its own, because LocalizedString resolves
# against the bundle it was compiled into.
def add_string_catalog(target, group, directory)
  path = File.join(ROOT, directory, 'Localizable.xcstrings')
  return unless File.exist?(path)

  ref = group.new_reference('Localizable.xcstrings')
  target.resources_build_phase.add_file_reference(ref, true)
end

def link(target, ref)
  target.frameworks_build_phase.add_file_reference(ref, true)
end

# ================================================= G6SensorKit.framework

kit = project.new_target(:framework, 'G6SensorKit', :ios, DEPLOYMENT_TARGET)
kit_group = project.new_group('G6SensorKit', 'G6SensorKit', '<group>')
common_group = project.new_group('Common', 'Common', '<group>')

kit.build_configurations.each do |config|
  config.build_settings.merge!(base_settings(DEPLOYMENT_TARGET, SWIFT_VERSION))
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_PREFIX}.G6SensorKit"
  config.build_settings['INFOPLIST_FILE'] = 'G6SensorKit/Info.plist'
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '$(BUILT_PRODUCTS_DIR)']
end

add_sources(project, kit, kit_group, 'G6SensorKit')
add_sources(project, kit, common_group, 'Common')
add_string_catalog(kit, kit_group, 'G6SensorKit')
link(kit, loopkit_ref)
kit.package_product_dependencies << core_dependency

# If G6SensorCore ever ships resources, SwiftPM emits
# G6SensorCore_G6SensorCore.bundle into BUILT_PRODUCTS_DIR but does NOT embed
# it in a framework that statically links the package — Bundle.module then
# traps at runtime inside the plugin. The core deliberately has no resources
# (see Sources/G6SensorCore/Support/LocalizedString.swift); this guard fails
# the generation loudly if that changes without the bundle being embedded.
core_resource_dirs = Dir.glob(File.join(ROOT, 'Sources', 'G6SensorCore', 'Resources'))
unless core_resource_dirs.empty?
  abort <<~MESSAGE
    G6SensorCore now contains Resources/, which SwiftPM turns into a separate
    resource bundle. That bundle is not embedded automatically and Bundle.module
    will crash at runtime inside the plugin. Either remove the resources or add
    G6SensorCore_G6SensorCore.bundle to G6SensorKit's resources build phase here.
  MESSAGE
end

# =============================================== G6SensorKitUI.framework

kitui = project.new_target(:framework, 'G6SensorKitUI', :ios, DEPLOYMENT_TARGET)
kitui_group = project.new_group('G6SensorKitUI', 'G6SensorKitUI', '<group>')

kitui.build_configurations.each do |config|
  config.build_settings.merge!(base_settings(DEPLOYMENT_TARGET, SWIFT_VERSION))
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_PREFIX}.G6SensorKitUI"
  config.build_settings['INFOPLIST_FILE'] = 'G6SensorKitUI/Info.plist'
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '$(BUILT_PRODUCTS_DIR)']
end

add_sources(project, kitui, kitui_group, 'G6SensorKitUI')
add_string_catalog(kitui, kitui_group, 'G6SensorKitUI')
link(kitui, loopkit_ref)
link(kitui, loopkitui_ref)
link(kitui, kit.product_reference)
kitui.add_dependency(kit)

# Asset catalog for onboarding artwork (original assets only).
assets_path = File.join(ROOT, 'G6SensorKitUI', 'Assets.xcassets')
if Dir.exist?(assets_path)
  assets_ref = kitui_group.new_reference('Assets.xcassets')
  kitui.resources_build_phase.add_file_reference(assets_ref, true)
end

# ============================================ G6SensorKitPlugin.loopplugin

plugin = project.new_target(:framework, 'G6SensorKitPlugin', :ios, DEPLOYMENT_TARGET)
plugin_group = project.new_group('G6SensorKitPlugin', 'G6SensorKitPlugin', '<group>')

plugin.build_configurations.each do |config|
  config.build_settings.merge!(base_settings(DEPLOYMENT_TARGET, SWIFT_VERSION))
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_PREFIX}.G6SensorKitPlugin"
  config.build_settings['INFOPLIST_FILE'] = 'G6SensorKitPlugin/Info.plist'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['DEFINES_MODULE'] = 'NO'
  # Loop's PluginManager discovers bundles by this extension; its
  # copy-plugins.sh renames it to .framework inside the app.
  config.build_settings['WRAPPER_EXTENSION'] = 'loopplugin'
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '$(BUILT_PRODUCTS_DIR)']
end

add_sources(project, plugin, plugin_group, 'G6SensorKitPlugin')
link(plugin, loopkit_ref)
link(plugin, loopkitui_ref)
link(plugin, kit.product_reference)
link(plugin, kitui.product_reference)
plugin.add_dependency(kit)
plugin.add_dependency(kitui)

# copy-plugins.sh expects dependent frameworks inside the plugin's own
# Frameworks/ directory; without this, dyld cannot resolve
# @rpath/G6SensorKit.framework when Loop calls Bundle.loadAndReturnError().
embed = plugin.new_copy_files_build_phase('Embed Frameworks')
embed.symbol_dst_subfolder_spec = :frameworks
[kit, kitui].each do |dependency|
  build_file = embed.add_file_reference(dependency.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

# ------------------------------------------------------------------ schemes

# Sources first, Products and Frameworks last, as in the neighbouring kits.
sorted = project.main_group.children.sort_by do |child|
  case child.display_name
  when 'Products' then 2
  when 'Frameworks' then 3
  else 1
  end
end
project.main_group.children.replace(sorted)

project.save

[kit, kitui, plugin].each do |target|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.save_as(PROJECT_PATH, target.name, true)
end

puts "Generated #{PROJECT_PATH}"
puts 'Targets: G6SensorKit, G6SensorKitUI, G6SensorKitPlugin (.loopplugin)'
puts 'Note: builds only inside a host workspace that provides LoopKit + LoopKitUI.'
