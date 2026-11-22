import 'dart:io';

/// One Apple host platform and the minimum deployment target it needs.
///
/// `flutter_onnxruntime` requires iOS 16.0 and macOS 14.0, while
/// `flutter create` still generates iOS 13.0 and macOS 10.15 projects, so a
/// fresh app fails in `pod install` until both are raised. Some pods (Flutter
/// itself, `path_provider_foundation`) keep their own lower targets, which
/// Xcode 27 rejects, so the Podfile also raises those.
class AppleHostPlatform {
  const AppleHostPlatform._({
    required this.directory,
    required this.podPlatform,
    required this.buildSetting,
    required this.minimum,
    required this.podBuildSettingsHook,
  });

  static const ios = AppleHostPlatform._(
    directory: 'ios',
    podPlatform: 'ios',
    buildSetting: 'IPHONEOS_DEPLOYMENT_TARGET',
    minimum: '16.0',
    podBuildSettingsHook: 'flutter_additional_ios_build_settings',
  );

  static const macos = AppleHostPlatform._(
    directory: 'macos',
    podPlatform: 'osx',
    buildSetting: 'MACOSX_DEPLOYMENT_TARGET',
    minimum: '14.0',
    podBuildSettingsHook: 'flutter_additional_macos_build_settings',
  );

  static const all = [ios, macos];

  /// Host directory inside the Flutter project, such as `ios`.
  final String directory;

  /// The Podfile `platform` symbol, such as `osx`.
  final String podPlatform;

  /// The Xcode build setting that holds the deployment target.
  final String buildSetting;

  /// The lowest deployment target the native dependencies accept.
  final String minimum;

  /// The per-pod call in the generated Podfile's `post_install` block, such
  /// as `flutter_additional_ios_build_settings`.
  final String podBuildSettingsHook;
}

/// A file that needs, or received, a host setting change.
class AppleHostChange {
  const AppleHostChange(this.path, this.description);

  /// Project-relative path, such as `ios/Podfile`.
  final String path;

  /// What was (or would be) changed.
  final String description;

  @override
  String toString() => '$path: $description';
}

/// A Podfile setting that setup cannot read or change safely.
class AppleHostConfigurationException implements Exception {
  const AppleHostConfigurationException(this.problems);

  /// One line per setting, with its file and line number.
  final List<String> problems;

  @override
  String toString() =>
      'Apple host settings need a manual change (setup changed no files):\n'
      '${problems.map((p) => '  $p').join('\n')}';
}

/// One Podfile line split into Ruby code and a trailing `#` comment.
class _PodfileLine {
  _PodfileLine._(this.indent, this.code, this.comment);

  factory _PodfileLine.parse(String line) {
    final indent = RegExp(r'^[ \t]*').stringMatch(line)!;
    String? quote;
    for (var i = indent.length; i < line.length; i++) {
      final char = line[i];
      if (quote != null) {
        if (char == '\\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
      } else if (char == "'" || char == '"') {
        quote = char;
      } else if (char == '#') {
        final code = line.substring(indent.length, i);
        final trimmed = code.trimRight();
        return _PodfileLine._(
          indent,
          trimmed,
          line.substring(indent.length + trimmed.length),
        );
      }
    }
    return _PodfileLine._(indent, line.substring(indent.length), '');
  }

  final String indent;
  final String code;

  /// The comment with the whitespace before it, or an empty string.
  final String comment;

  String replaceCode(String replacement) => '$indent$replacement$comment';
}

/// Applies the iOS and macOS host settings the package needs: the minimum
/// deployment targets, static framework linkage in the Podfile, and a
/// `post_install` step that raises pods below the minimum.
///
/// Only targets below the minimum are changed, so newer targets and the rest
/// of the Podfile and Xcode project are left as they are. Host platforms the
/// app does not have are skipped.
class AppleHostConfigurator {
  AppleHostConfigurator({required this.projectDirectory});

  final Directory projectDirectory;

  /// Returns the changes needed. Files are only written when [check] is false.
  ///
  /// Throws [AppleHostConfigurationException], before writing anything, when
  /// a setting is written in a form this cannot read (for example a version
  /// taken from `ENV`), so a host that still needs a change is never reported
  /// as configured.
  Future<List<AppleHostChange>> configure({bool check = false}) async {
    final changes = <AppleHostChange>[];
    final problems = <String>[];
    final writes = <File, String>{};
    for (final platform in AppleHostPlatform.all) {
      final podfile = _file('${platform.directory}/Podfile');
      if (await podfile.exists()) {
        final updated = _updatePodfile(
          await podfile.readAsString(),
          platform,
          changes,
          problems,
        );
        if (updated != null) {
          writes[podfile] = updated;
        }
      }
      final pbxproj = _file(
        '${platform.directory}/Runner.xcodeproj/project.pbxproj',
      );
      if (await pbxproj.exists()) {
        final updated = _updatePbxproj(
          await pbxproj.readAsString(),
          platform,
          changes,
        );
        if (updated != null) {
          writes[pbxproj] = updated;
        }
      }
    }
    if (problems.isNotEmpty) {
      throw AppleHostConfigurationException(problems);
    }
    if (!check) {
      for (final entry in writes.entries) {
        await entry.key.writeAsString(entry.value);
      }
    }
    return changes;
  }

  File _file(String relative) => File(
    '${projectDirectory.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}',
  );

  String? _updatePodfile(
    String content,
    AppleHostPlatform platform,
    List<AppleHostChange> changes,
    List<String> problems,
  ) {
    final path = '${platform.directory}/Podfile';
    final newline = content.contains('\r\n') ? '\r\n' : '\n';
    final lines = content.split(newline);
    final wanted = "platform :${platform.podPlatform}, '${platform.minimum}'";
    const staticFrameworks = 'use_frameworks! :linkage => :static';

    final platformCall = RegExp(
      '^platform[ \\t]*\\(?[ \\t]*:${platform.podPlatform}\\b(.*)\$',
    );
    final platformVersion = RegExp(
      '^(?:[ \\t]*,[ \\t]*([\'"])([0-9]+(?:\\.[0-9]+)*)\\1)?[ \\t]*\\)?[ \\t]*\$',
    );
    final commentedPlatform = RegExp(
      '^#[ \\t]*platform[ \\t]+:${platform.podPlatform}[ \\t]*,'
      '[ \\t]*[\'"]([0-9.]+)[\'"][ \\t]*\$',
    );
    final frameworksCall = RegExp('^use_frameworks!(.*)\$');
    final linkage = RegExp(
      '^[ \\t]*\\(?[ \\t]*(?::linkage[ \\t]*=>|linkage:)[ \\t]*:(\\w+)'
      '[ \\t]*\\)?[ \\t]*\$',
    );

    final firstChange = changes.length;
    var activePlatform = false;
    int? commentedLine;
    for (var i = 0; i < lines.length; i++) {
      final line = _PodfileLine.parse(lines[i]);
      final code = line.code.trim();

      final call = platformCall.firstMatch(code);
      if (call != null) {
        activePlatform = true;
        final version = platformVersion.firstMatch(call.group(1)!);
        if (version == null) {
          problems.add(
            '$path:${i + 1}: cannot read `$code`. Set it to `$wanted` by hand.',
          );
          continue;
        }
        final current = version.group(2);
        if (current == null ||
            _compareVersions(current, platform.minimum) < 0) {
          changes.add(
            AppleHostChange(
              path,
              current == null
                  ? 'set `$wanted` (the platform line had no version)'
                  : 'raised the platform from $current to ${platform.minimum}',
            ),
          );
          lines[i] = line.replaceCode(wanted);
        }
        continue;
      }
      if (commentedLine == null &&
          commentedPlatform.hasMatch(lines[i].trim())) {
        commentedLine = i;
        continue;
      }

      // ONNX Runtime ships static binaries, which CocoaPods refuses to
      // embed in dynamic frameworks. A Podfile without use_frameworks!
      // already links statically and is left alone.
      final frameworks = frameworksCall.firstMatch(code);
      if (frameworks != null) {
        final arguments = frameworks.group(1)!;
        if (arguments.trim().isNotEmpty) {
          final mode = linkage.firstMatch(arguments);
          if (mode == null) {
            problems.add(
              '$path:${i + 1}: cannot read `$code`. '
              'Change it to `$staticFrameworks` by hand.',
            );
            continue;
          }
          if (mode.group(1) == 'static') {
            continue;
          }
        }
        changes.add(
          AppleHostChange(
            path,
            'set `$staticFrameworks` (ONNX Runtime is a static binary)',
          ),
        );
        lines[i] = line.replaceCode(staticFrameworks);
      }
    }

    if (!activePlatform) {
      if (commentedLine != null) {
        final version = commentedPlatform
            .firstMatch(lines[commentedLine].trim())!
            .group(1)!;
        changes.insert(
          firstChange,
          AppleHostChange(
            path,
            'enabled `$wanted` (the platform line was commented out, '
            'so CocoaPods assumed $version)',
          ),
        );
        final indent = RegExp(r'^[ \t]*').stringMatch(lines[commentedLine])!;
        lines[commentedLine] = '$indent$wanted';
      } else {
        changes.insert(firstChange, AppleHostChange(path, 'added `$wanted`'));
        lines.insert(0, wanted);
      }
    }

    _raisePodTargets(lines, platform, path, changes);

    final updated = lines.join(newline);
    return updated == content ? null : updated;
  }

  /// First line of the block [_raisePodTargets] adds; also how a Podfile
  /// that already has the block is recognized.
  static String _podTargetsMarker(AppleHostPlatform platform) =>
      '# Added by mobile_rag_engine setup: raise pods below '
      '${platform.minimum}, which newer Xcode versions reject.';

  /// Adds, after the Flutter template's per-pod call in `post_install`, a
  /// block that raises each pod target below the minimum. Pods that already
  /// target higher, or set the target through a variable, are left alone. A
  /// Podfile without the template call is left as it is.
  void _raisePodTargets(
    List<String> lines,
    AppleHostPlatform platform,
    String path,
    List<AppleHostChange> changes,
  ) {
    final marker = _podTargetsMarker(platform);
    if (lines.any((line) => line.trim() == marker)) {
      return;
    }
    final hook = RegExp(
      '^${platform.podBuildSettingsHook}[ \\t]*\\(?[ \\t]*(\\w+)[ \\t]*\\)?\$',
    );
    for (var i = 0; i < lines.length; i++) {
      final line = _PodfileLine.parse(lines[i]);
      final call = hook.firstMatch(line.code.trim());
      if (call == null) {
        continue;
      }
      final target = call.group(1)!;
      final setting = "config.build_settings['${platform.buildSetting}']";
      final minimum = "'${platform.minimum}'";
      final indent = line.indent;
      lines.insertAll(i + 1, [
        '$indent$marker',
        '$indent$target.build_configurations.each do |config|',
        '$indent  current = $setting.to_s',
        '$indent  if current.match?(/\\A\\d+(\\.\\d+)*\\z/) && '
            'Gem::Version.new(current) < Gem::Version.new($minimum)',
        '$indent    $setting = $minimum',
        '$indent  end',
        '${indent}end',
      ]);
      changes.add(
        AppleHostChange(
          path,
          'raised pods below ${platform.minimum} in `post_install` '
          '(Xcode 27 rejects their lower targets)',
        ),
      );
      return;
    }
  }

  String? _updatePbxproj(
    String content,
    AppleHostPlatform platform,
    List<AppleHostChange> changes,
  ) {
    final setting = RegExp(
      '${platform.buildSetting} = "?([0-9]+(?:\\.[0-9]+)*)"?;',
    );
    final lower = <String>{};
    final updated = content.replaceAllMapped(setting, (match) {
      final version = match.group(1)!;
      if (_compareVersions(version, platform.minimum) >= 0) {
        return match.group(0)!;
      }
      lower.add(version);
      return '${platform.buildSetting} = ${platform.minimum};';
    });
    if (lower.isEmpty) {
      return null;
    }
    changes.add(
      AppleHostChange(
        '${platform.directory}/Runner.xcodeproj/project.pbxproj',
        'raised ${platform.buildSetting} from ${lower.join(', ')} '
            'to ${platform.minimum}',
      ),
    );
    return updated;
  }

  static int _compareVersions(String a, String b) {
    final left = a.split('.').map(int.parse).toList();
    final right = b.split('.').map(int.parse).toList();
    for (var i = 0; i < left.length || i < right.length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) {
        return l.compareTo(r);
      }
    }
    return 0;
  }
}
