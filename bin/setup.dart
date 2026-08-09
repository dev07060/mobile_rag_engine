import 'dart:io';

import 'package:mobile_rag_engine/src/model_pack/model_pack_installer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(
      'Usage: dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en [--output assets/mobile_rag] [--check|--repair]',
    );
    return;
  }
  String? preset;
  var output = 'assets/mobile_rag';
  var check = false;
  var repair = false;
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
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
