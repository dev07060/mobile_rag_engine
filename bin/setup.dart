import 'dart:io';

import 'package:mobile_rag_engine/src/model_pack/apple_host_configurator.dart';
import 'package:mobile_rag_engine/src/model_pack/model_pack_installer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(
      'Usage: dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en [--output assets/mobile_rag] [--check|--repair] [--skip-host-config]',
    );
    return;
  }
  String? preset;
  var output = 'assets/mobile_rag';
  var check = false;
  var repair = false;
  var hostConfig = true;
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--preset' && i + 1 < arguments.length) {
      preset = arguments[++i];
    } else if (arg == '--output' && i + 1 < arguments.length) {
      output = arguments[++i];
    } else if (arg == '--check') {
      check = true;
    } else if (arg == '--repair') {
      repair = true;
    } else if (arg == '--skip-host-config') {
      hostConfig = false;
    } else {
      stderr.writeln('Unknown or incomplete option: $arg');
      exitCode = 64;
      return;
    }
  }
  if (preset == null) {
    stderr.writeln('--preset is required.');
    exitCode = 64;
    return;
  }
  try {
    final result = await ModelPackInstaller(
      projectDirectory: Directory.current,
    ).install(preset: preset, output: output, check: check, repair: repair);
    stdout.writeln(
      '${result.verified ? 'MODEL_PACK_VERIFIED' : 'MODEL_PACK_READY'} ${result.manifestPath}',
    );
    if (hostConfig) {
      final changes = await AppleHostConfigurator(
        projectDirectory: Directory.current,
      ).configure(check: check);
      if (check && changes.isNotEmpty) {
        stderr.writeln(
          'Apple host settings are below what the native dependencies need. '
          'Run setup without --check to apply:',
        );
        for (final change in changes) {
          stderr.writeln('  $change');
        }
        exitCode = 1;
      } else if (changes.isNotEmpty) {
        stdout.writeln('Updated Apple host settings:');
        for (final change in changes) {
          stdout.writeln('  $change');
        }
      }
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
