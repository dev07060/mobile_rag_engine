// Measurement conditions written into every result file
// (docs/milestones.md rule 9): model and fingerprint, engine commit, build
// mode and Rust features, device and OS, host toolchain, date.
//
// Values the app cannot see itself come from --dart-define:
//   ENGINE_COMMIT   git rev-parse HEAD of the engine checkout
//   DEVICE_LABEL    e.g. "iPhone 17 (iPhone18,3)"
//   HOST_TOOLCHAIN  e.g. "Xcode 27.1 (27A9275); Flutter 3.35.5; rustc 1.91.1"
//   RUN_NOTE        e.g. "charging: no; other apps: none"
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/runtime_info.dart'
    as runtime_info;

import '../example_model.dart';

const engineCommit = String.fromEnvironment('ENGINE_COMMIT');
const deviceLabel = String.fromEnvironment('DEVICE_LABEL');
const hostToolchain = String.fromEnvironment('HOST_TOOLCHAIN');
const runNote = String.fromEnvironment('RUN_NOTE');

String get buildModeName =>
    kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

/// Call after [MobileRag.initialize].
Future<Map<String, Object?>> collectRunConditions(ExampleModel model) async {
  final pack =
      jsonDecode(await rootBundle.loadString(model.manifestAsset))
          as Map<String, dynamic>;
  final native = runtime_info.nativeRuntimeInfo();
  final (v, b) = model.effectiveWeights;
  return {
    'model_id': model.id,
    'model_label': model.label,
    'model_pack_id': pack['modelId'],
    'model_pack_revision': pack['revision'],
    'model_sha256': pack['modelSha256'],
    'tokenizer_sha256': pack['tokenizerSha256'],
    'model_bytes': pack['modelBytes'],
    'embedding_fingerprint': MobileRag.instance.currentEmbeddingFingerprint,
    'engine_commit': engineCommit,
    'build_mode': buildModeName,
    'debug_build': kDebugMode,
    'rust_features': native.rustFeatures,
    'native_allocator': native.nativeAllocator,
    'device': deviceLabel,
    'os': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'cpu_count': Platform.numberOfProcessors,
    'dart_version': Platform.version,
    'host_toolchain': hostToolchain,
    'run_note': runNote,
    'thread_level': 'medium',
    'vector_weight': v,
    'bm25_weight': b,
    'measured_at_utc': DateTime.now().toUtc().toIso8601String(),
  };
}
