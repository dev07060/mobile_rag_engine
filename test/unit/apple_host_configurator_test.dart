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

  group('Podfile variants', () {
    test('raises a platform line that ends with a comment', () async {
      const podfile =
          "platform :ios, '13.0' # 한국어 주석, 日本語のコメント, 中文注释 🚀 v3.14\n"
          "target 'Runner' do\n  $_staticFrameworks\nend\n";
      final file = await write('ios/Podfile', podfile);

      final changes = await configurator().configure();

      expect(changes.map((c) => c.description), [
        'raised the platform from 13.0 to 16.0',
      ]);
      expect(
        await file.readAsString(),
        podfile.replaceFirst("'13.0'", "'16.0'"),
      );
      expect(await configurator().configure(check: true), isEmpty);
    });

    test('repairs a Podfile an earlier setup patched next to a commented '
        'platform line', () async {
      // Earlier setups did not match the commented line, prepended a new
      // line, and left the old one, which CocoaPods applies last.
      const podfile =
          "platform :ios, '16.0'\n"
          "platform :ios, '13.0' # keep in sync with Xcode\n"
          "target 'Runner' do\n  $_staticFrameworks\nend\n";
      final file = await write('ios/Podfile', podfile);

      expect((await configurator().configure(check: true)).map((c) => c.path), [
        'ios/Podfile',
      ]);
      await configurator().configure();

      expect(await file.readAsString(), isNot(contains('13.0')));
      expect(await configurator().configure(check: true), isEmpty);
    });

    test('reads double quotes, tabs and a version without a minor', () async {
      const podfile =
          '\tplatform  :osx ,  "11"\n'
          "target 'Runner' do\n\tuse_frameworks!\nend\n";
      final file = await write('macos/Podfile', podfile);

      await configurator().configure();

      expect(
        await file.readAsString(),
        "\tplatform :osx, '14.0'\n"
        "target 'Runner' do\n\t$_staticFrameworks\nend\n",
      );
    });

    test('raises a platform line without a version', () async {
      final file = await write(
        'ios/Podfile',
        "platform :ios\ntarget 'Runner' do\nend\n",
      );

      await configurator().configure();

      expect(
        await file.readAsString(),
        "platform :ios, '16.0'\ntarget 'Runner' do\nend\n",
      );
    });

    for (final line in [
      'use_frameworks! linkage: :dynamic',
      'use_frameworks!(linkage: :dynamic)',
      'use_frameworks! :linkage => :dynamic # needed by a Swift pod',
      'use_frameworks!(:linkage=>:dynamic)',
      'use_frameworks! # 動的フレームワーク',
    ]) {
      test('switches `$line` to static linkage', () async {
        final comment = line.contains('#')
            ? ' ${line.substring(line.indexOf('#'))}'
            : '';
        final file = await write(
          'ios/Podfile',
          "platform :ios, '16.0'\ntarget 'Runner' do\n  $line\nend\n",
        );

        final changes = await configurator().configure();

        expect(changes.map((c) => c.description), [
          contains(':linkage => :static'),
        ]);
        expect(
          await file.readAsString(),
          "platform :ios, '16.0'\n"
          "target 'Runner' do\n  $_staticFrameworks$comment\nend\n",
        );
        expect(await configurator().configure(check: true), isEmpty);
      });
    }

    test('switches every use_frameworks! in the file', () async {
      final file = await write(
        'ios/Podfile',
        "platform :ios, '16.0'\n"
            "target 'Runner' do\n  use_frameworks!\nend\n"
            "target 'Widget' do\n  use_frameworks! linkage: :dynamic\nend\n",
      );

      await configurator().configure();

      final content = await file.readAsString();
      expect(content, isNot(contains('dynamic')));
      expect(_staticFrameworks.allMatches(content), hasLength(2));
    });

    test('leaves correct variants untouched', () async {
      for (final podfile in [
        "platform :ios, '17.0' # Swift concurrency\n"
            "target 'Runner' do\n  use_frameworks! linkage: :static\nend\n",
        'platform :ios, "16.0"\r\n'
            "target 'Runner' do\r\n"
            "  use_frameworks!(:linkage => :static) # ORT\r\nend\r\n",
        "# platform :ios, '12.0'\nplatform :ios, '16.0'\n"
            "target 'Runner' do\nend\n",
        "platform :ios, '16.0'\n# use_frameworks!\n",
      ]) {
        final file = await write('ios/Podfile', podfile);
        expect(await configurator().configure(), isEmpty, reason: podfile);
        expect(await file.readAsString(), podfile);
      }
    });

    for (final podfile in [
      "platform :ios, ENV['IOS_DEPLOYMENT_TARGET']\n",
      "platform :ios, '16.0'\nuse_frameworks! :linkage => linkage_mode\n",
    ]) {
      test('fails instead of guessing on `${podfile.trim()}`', () async {
        final file = await write('ios/Podfile', podfile);

        for (final check in [true, false]) {
          await expectLater(
            configurator().configure(check: check),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                allOf(contains('ios/Podfile:'), contains('by hand')),
              ),
            ),
          );
        }
        expect(await file.readAsString(), podfile);
      });
    }
  });

  test('raises a quoted deployment target in the Xcode project', () async {
    final file = await write(
      'ios/Runner.xcodeproj/project.pbxproj',
      _pbxproj('IPHONEOS_DEPLOYMENT_TARGET', '"13.0"'),
    );

    await configurator().configure();

    expect(
      await file.readAsString(),
      _pbxproj('IPHONEOS_DEPLOYMENT_TARGET', '16.0'),
    );
  });

  test('skips host platforms the app does not have', () async {
    expect(await configurator().configure(), isEmpty);
  });
}
