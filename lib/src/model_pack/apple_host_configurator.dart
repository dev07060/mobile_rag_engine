import 'dart:io';

/// One Apple host platform and the minimum deployment target it needs.
///
/// `flutter_onnxruntime` requires iOS 16.0 and macOS 14.0, while
/// `flutter create` still generates iOS 13.0 and macOS 10.15 projects, so a
/// fresh app fails in `pod install` until both are raised.
class AppleHostPlatform {
  const AppleHostPlatform._({
    required this.directory,
    required this.podPlatform,
    required this.buildSetting,
    required this.minimum,
  });

  static const ios = AppleHostPlatform._(
    directory: 'ios',
    podPlatform: 'ios',
    buildSetting: 'IPHONEOS_DEPLOYMENT_TARGET',
    minimum: '16.0',
  );

  static const macos = AppleHostPlatform._(
    directory: 'macos',
    podPlatform: 'osx',
    buildSetting: 'MACOSX_DEPLOYMENT_TARGET',
    minimum: '14.0',
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

/// Applies the iOS and macOS host settings the package needs: the minimum
/// deployment targets and static framework linkage in the Podfile.
///
/// Only targets below the minimum are changed, so newer targets and the rest
/// of the Podfile and Xcode project are left as they are. Host platforms the
/// app does not have are skipped.
class AppleHostConfigurator {
  AppleHostConfigurator({required this.projectDirectory});

  final Directory projectDirectory;

  /// Returns the changes needed. Files are only written when [check] is false.
  Future<List<AppleHostChange>> configure({bool check = false}) async {
    final changes = <AppleHostChange>[];
    for (final platform in AppleHostPlatform.all) {
      final podfile = _file('${platform.directory}/Podfile');
      if (await podfile.exists()) {
        final updated = _updatePodfile(
          await podfile.readAsString(),
          platform,
          changes,
        );
        if (updated != null && !check) {
          await podfile.writeAsString(updated);
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
        if (updated != null && !check) {
          await pbxproj.writeAsString(updated);
        }
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
  ) {
    final path = '${platform.directory}/Podfile';
    var updated = content;

    final wanted = "platform :${platform.podPlatform}, '${platform.minimum}'";
    final platformLine = RegExp(
      '^([ \\t]*)(#[ \\t]*)?platform[ \\t]+:${platform.podPlatform}'
      "[ \\t]*,[ \\t]*['\"]([0-9.]+)['\"][ \\t]*(?=\\r?\$)",
      multiLine: true,
    );
    final match = platformLine.firstMatch(updated);
    if (match == null) {
      final newline = updated.contains('\r\n') ? '\r\n' : '\n';
      changes.add(AppleHostChange(path, 'added `$wanted`'));
      updated = '$wanted$newline$updated';
    } else {
      final commented = match.group(2) != null;
      final version = match.group(3)!;
      if (commented || _compareVersions(version, platform.minimum) < 0) {
        changes.add(
          AppleHostChange(
            path,
            commented
                ? 'enabled `$wanted` (the platform line was commented out, '
                      'so CocoaPods assumed $version)'
                : 'raised the platform from $version to ${platform.minimum}',
          ),
        );
        updated = updated.replaceRange(
          match.start,
          match.end,
          '${match[1]}$wanted',
        );
      }
    }

    // ONNX Runtime ships static binaries, which CocoaPods refuses to embed in
    // dynamic frameworks. A Podfile without use_frameworks! already links
    // statically and is left alone.
    final frameworks = RegExp(
      '^([ \\t]*)use_frameworks!(?:[ \\t]*\\(?[ \\t]*'
      ':linkage[ \\t]*=>[ \\t]*:(\\w+)[ \\t]*\\)?)?[ \\t]*(?=\\r?\$)',
      multiLine: true,
    );
    final usesFrameworks = frameworks.firstMatch(updated);
    if (usesFrameworks != null && usesFrameworks.group(2) != 'static') {
      changes.add(
        AppleHostChange(
          path,
          'set `use_frameworks! :linkage => :static` '
          '(ONNX Runtime is a static binary)',
        ),
      );
      updated = updated.replaceRange(
        usesFrameworks.start,
        usesFrameworks.end,
        '${usesFrameworks[1]}use_frameworks! :linkage => :static',
      );
    }

    return updated == content ? null : updated;
  }

  String? _updatePbxproj(
    String content,
    AppleHostPlatform platform,
    List<AppleHostChange> changes,
  ) {
    final setting = RegExp('${platform.buildSetting} = ([0-9.]+);');
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
