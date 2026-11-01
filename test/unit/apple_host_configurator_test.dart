import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/model_pack/apple_host_configurator.dart';

const _staticFrameworks = 'use_frameworks! :linkage => :static';

// Excerpts of what `flutter create` generates.
const _iosPodfile = '''
# Uncomment this line to define a global platform for your project
# platform :ios, '13.0'

target 'Runner' do
  use_frameworks!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
''';

const _macosPodfile = '''
platform :osx, '10.15'

target 'Runner' do
  use_frameworks!

  flutter_install_all_macos_pods File.dirname(File.realpath(__FILE__))
end
''';

String _pbxproj(String setting, String version) =>
    '''
		97C147031CF9000F007C117D /* Debug */ = {
			buildSettings = {
				$setting = $version;
			};
		};
		97C147041CF9000F007C117D /* Release */ = {
			buildSettings = {
				$setting = $version;
			};
		};
''';

void main() {
  late Directory project;

  setUp(() async {
    project = await Directory.systemTemp.createTemp('apple_host_test');
  });

  tearDown(() async {
    await project.delete(recursive: true);
  });

  Future<File> write(String relative, String content) async {
    final file = File('${project.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  AppleHostConfigurator configurator() =>
      AppleHostConfigurator(projectDirectory: project);

  test('raises a freshly generated iOS and macOS host', () async {
    final iosPodfile = await write('ios/Podfile', _iosPodfile);
    final iosProject = await write(
      'ios/Runner.xcodeproj/project.pbxproj',
      _pbxproj('IPHONEOS_DEPLOYMENT_TARGET', '13.0'),
    );
    final macosPodfile = await write('macos/Podfile', _macosPodfile);
    final macosProject = await write(
      'macos/Runner.xcodeproj/project.pbxproj',
      _pbxproj('MACOSX_DEPLOYMENT_TARGET', '10.15'),
    );

    final changes = await configurator().configure();

    expect(changes.map((c) => c.path), [
      'ios/Podfile',
      'ios/Podfile',
      'ios/Runner.xcodeproj/project.pbxproj',
      'macos/Podfile',
      'macos/Podfile',
      'macos/Runner.xcodeproj/project.pbxproj',
    ]);
    expect(
      await iosPodfile.readAsString(),
      _iosPodfile
          .replaceFirst("# platform :ios, '13.0'", "platform :ios, '16.0'")
          .replaceFirst('use_frameworks!', _staticFrameworks),
    );
    expect(
      await iosProject.readAsString(),
      _pbxproj('IPHONEOS_DEPLOYMENT_TARGET', '16.0'),
    );
    expect(
      await macosPodfile.readAsString(),
      _macosPodfile
          .replaceFirst("'10.15'", "'14.0'")
          .replaceFirst('use_frameworks!', _staticFrameworks),
    );
    expect(
      await macosProject.readAsString(),
      _pbxproj('MACOSX_DEPLOYMENT_TARGET', '14.0'),
    );

    expect(await configurator().configure(), isEmpty);
  });

  test('keeps targets that are already high enough', () async {
    const podfile =
        "platform :ios, '17.0'\n"
        "target 'Runner' do\n  use_frameworks! :linkage => :static\nend\n";
    final file = await write('ios/Podfile', podfile);
    await write(
      'ios/Runner.xcodeproj/project.pbxproj',
      _pbxproj('IPHONEOS_DEPLOYMENT_TARGET', '16.4'),
    );

    expect(await configurator().configure(), isEmpty);
    expect(await file.readAsString(), podfile);
  });

  test('check reports the changes without writing', () async {
    final file = await write('ios/Podfile', _iosPodfile);

    final changes = await configurator().configure(check: true);

    expect(changes.map((c) => c.description), [
      contains('commented out'),
      contains(':linkage => :static'),
    ]);
    expect(await file.readAsString(), _iosPodfile);
  });

  test('adds a missing platform line with the file line endings', () async {
    const podfile = "target 'Runner' do\r\n  use_frameworks!\r\nend\r\n";
    final file = await write('macos/Podfile', podfile);

    await configurator().configure();

    expect(
      await file.readAsString(),
      "platform :osx, '14.0'\r\n"
      "target 'Runner' do\r\n  $_staticFrameworks\r\nend\r\n",
    );
  });

  test('switches dynamic framework linkage to static', () async {
    final file = await write(
      'ios/Podfile',
      "platform :ios, '16.0'\n  use_frameworks! :linkage => :dynamic\n",
    );

    await configurator().configure();

    expect(
      await file.readAsString(),
      "platform :ios, '16.0'\n  $_staticFrameworks\n",
    );
  });

  test('leaves a Podfile without use_frameworks! linking statically', () async {
    const podfile = "platform :ios, '16.0'\ntarget 'Runner' do\nend\n";
    final file = await write('ios/Podfile', podfile);

    expect(await configurator().configure(), isEmpty);
    expect(await file.readAsString(), podfile);
  });

  test('skips host platforms the app does not have', () async {
    expect(await configurator().configure(), isEmpty);
  });
}
