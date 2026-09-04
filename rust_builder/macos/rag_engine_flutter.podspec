#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rag_engine_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rag_engine_flutter'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust rag_engine_flutter',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # build_pod.sh outputs to ${PODS_CONFIGURATION_BUILD_DIR}/${PRODUCT_NAME}
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/${PRODUCT_NAME}/librag_engine_flutter.a"],
  }

  # Pod target build settings (merged, no duplicates)
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librag_engine_flutter.a',
  }

  # App target (Runner) build settings - keeps FRB's process lookup symbols in
  # the main executable as well as force-loading the static Rust archive.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -force_load ${BUILT_PRODUCTS_DIR}/rag_engine_flutter/librag_engine_flutter.a -Wl,-export_dynamic',
  }
end
