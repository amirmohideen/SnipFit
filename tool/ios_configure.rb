# Wires Snipfit's iOS project: native sources, privacy manifest, entitlements,
# iOS 16 minimum, iPhone-only, and dev/prod flavors (build configurations +
# shared schemes) as expected by `flutter build ios --flavor <name>`.
# Idempotent: safe to re-run. Usage: ruby tool/ios_configure.rb
require 'xcodeproj'
require 'fileutils'

root = File.expand_path('../ios', __dir__)
project_path = File.join(root, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' }
tests = project.targets.find { |t| t.name == 'RunnerTests' }
group = project.main_group.find_subpath('Runner', false)

# 1. Native sources and resources.
%w[SnipfitChannels.swift VideoEncoder.swift ShareTargets.swift TapSegmenter.swift].each do |name|
  next if group.files.any? { |f| f.path == name }
  ref = group.new_reference(name)
  runner.source_build_phase.add_file_reference(ref)
end
unless group.files.any? { |f| f.path == 'PrivacyInfo.xcprivacy' }
  ref = group.new_reference('PrivacyInfo.xcprivacy')
  runner.resources_build_phase.add_file_reference(ref)
end
group.new_reference('Runner.entitlements') unless group.files.any? { |f| f.path == 'Runner.entitlements' }

# 2. Flavor build configurations.
flutter_group = project.main_group.find_subpath('Flutter', false)
# The Flutter group has no folder of its own, so its file paths are relative
# to ios/ (exactly like Flutter's own Debug.xcconfig: path = Flutter/Debug.xcconfig).
def xcconfig_ref(flutter_group, name)
  ref = flutter_group.files.find { |f| f.path == name || f.path == "Flutter/#{name}" } ||
        flutter_group.new_reference("Flutter/#{name}")
  ref.path = "Flutter/#{name}"
  ref.name = name
  ref
end

bases = { 'Debug' => :debug, 'Release' => :release, 'Profile' => :release }
%w[dev prod].each do |flavor|
  bases.each do |base, type|
    name = "#{base}-#{flavor}"
    [project, runner, tests].each do |owner|
      list = owner.build_configuration_list
      base_cfg = list.build_configurations.find { |c| c.name == base }
      cfg = list.build_configurations.find { |c| c.name == name }
      unless cfg
        cfg = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
        cfg.name = name
        list.build_configurations << cfg
      end
      cfg.build_settings = Marshal.load(Marshal.dump(base_cfg.build_settings))
      cfg.base_configuration_reference = base_cfg.base_configuration_reference
      if owner.equal?(runner)
        cfg.base_configuration_reference = xcconfig_ref(flutter_group, "#{name}.xcconfig")
      end
    end
  end
end

# 3. Common settings.
project.build_configurations.each do |c|
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
end
runner.build_configurations.each do |c|
  s = c.build_settings
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  s.delete('PRODUCT_BUNDLE_IDENTIFIER') # comes from ios/config/<flavor>.xcconfig
  s['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait'
end
tests.build_configurations.each do |c|
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.snipfit.app.RunnerTests'
end
project.save

# 4. Shared schemes "dev" and "prod" (copies of Runner with flavor configs).
schemes_dir = File.join(project_path, 'xcshareddata', 'xcschemes')
template = File.read(File.join(schemes_dir, 'Runner.xcscheme'))
%w[dev prod].each do |flavor|
  xml = template.dup
  xml.gsub!('buildConfiguration = "Debug"', "buildConfiguration = \"Debug-#{flavor}\"")
  xml.gsub!('buildConfiguration = "Release"', "buildConfiguration = \"Release-#{flavor}\"")
  xml.gsub!('buildConfiguration = "Profile"', "buildConfiguration = \"Profile-#{flavor}\"")
  File.write(File.join(schemes_dir, "#{flavor}.xcscheme"), xml)
end
puts "Configured #{project_path}"
puts "Configurations: #{project.build_configurations.map(&:name).sort.join(', ')}"
