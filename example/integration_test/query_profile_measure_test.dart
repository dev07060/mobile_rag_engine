import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/runtime_info.dart'
    as runtime_info;
import 'package:mobile_rag_engine_example/profiling/native_runtime_expectations.dart';
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/example_model.dart';
import 'package:mobile_rag_engine_example/profiling/fixture_cells.dart';
import 'package:mobile_rag_engine_example/profiling/query_profiler.dart';
import 'package:mobile_rag_engine_example/profiling/run_conditions.dart';
import 'package:mobile_rag_engine_example/profiling/query_profile_report.dart';
import 'package:mobile_rag_engine_example/profiling/profile_export.dart';

// On-device RAG query profiler — P3 (LOC-68) measurement + P4 (LOC-69) export.
//
// Runs ALONE in its own process (separate from the P2 smoke) under flutter
// drive in PROFILE mode, so the shipped `vector_faer,vector_quant_i8` backend
// is exercised (flutter test hard-pins debug = fallback backend = invalid):
//
//   cd example && flutter drive \
//       --driver=test_driver/integration_test.dart \
//       --target=integration_test/query_profile_measure_test.dart \
//       --profile -d <device-id> --dart-define=EXAMPLE_MODEL=minilm|koen
//
// The model comes from example/assets/models/<id>/ (not in git; see the
// README there). Conditions for docs/milestones.md rule 9 are written into
// every run's meta (lib/profiling/run_conditions.dart).
//
// Clean state is established by DELETING the DB files before initialize (not
// clearAllData, whose async re-init races the first seed and trips
// "database is locked"). Per-collection index files are removed after init.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const measuredDocs = 500; // representative; raise for scan-bound runs
  const warmup = 5;
  const measured = 30;
  const topK = 10; // QueryProfiler.measureOnce default
  const expectedNativeAllocator = String.fromEnvironment(
    'EXPECTED_NATIVE_ALLOCATOR',
  );
  const expectedRustFeatures = String.fromEnvironment('EXPECTED_RUST_FEATURES');

  test(
    'profiler: pure_cold / pure_warm / switching_cold x 2 lanes',
    () async {
      _assertProfileMode();

      // Fresh DB without clearAllData: delete the SQLite files BEFORE
      // initialize so the engine starts clean and nothing races the seed.
      final docsDir = await getApplicationDocumentsDirectory();
      final model = resolveExampleModel();
      final dbStem = '${docsDir.path}/profile_${model.id}.sqlite';
      for (final p in [
        dbStem,
        '$dbStem-wal',
        '$dbStem-shm',
        '$dbStem-journal',
      ]) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }

      // The Model Pack chosen with --dart-define=EXAMPLE_MODEL (default
      // minilm); see assets/models/<id>/README.md.
      await model.initialize(databaseName: 'profile.sqlite');

      final nativeInfo = runtime_info.nativeRuntimeInfo();
      verifyNativeRuntimeExpectations(
        actualAllocator: nativeInfo.nativeAllocator,
        actualRustFeatures: nativeInfo.rustFeatures,
        expectedAllocator: expectedNativeAllocator,
        expectedRustFeatures: expectedRustFeatures,
      );

      final ids = await QueryFixture.seed(docsPerCollection: measuredDocs);
      expect(ids[QueryFixture.collectionA]!.length, measuredDocs);
      expect(ids[QueryFixture.collectionB]!.length, measuredDocs);

      final (vectorWeight, bm25Weight) = model.effectiveWeights;
      final profiler = QueryProfiler(
        dbPath: MobileRag.instance.dbPath,
        vectorWeight: vectorWeight,
        bm25Weight: bm25Weight,
      );

      final meta = <String, Object?>{
        ...await collectRunConditions(model),
        'expected_native_allocator': expectedNativeAllocator,
        'expected_rust_features': expectedRustFeatures,
        'docs_per_collection': measuredDocs,
        'top_k': topK,
        // Cold-activate semantics differ per cell: pure_cold rebuilds A's index
        // from the DB (on-disk index deleted, slot evicted); switching_cold then
        // loads A from disk (pure_cold's activate re-saved it). Both are genuine
        // cold costs; the switch is the realistic production figure.
        'cold_note': 'pure_cold=rebuild-from-db; switching_cold=load-from-disk',
      };

      final runs = await runFixtureCells(
        profiler: profiler,
        sourceIds: ids,
        meta: meta,
        warmup: warmup,
        measured: measured,
      );

      // P3: per-segment p50/p95 to the device log (greppable CSV block).
      final report = QueryProfileReport(runs: runs);
      _emitReport(report);

      // P4: export JSON + CSV to the app documents dir (the baseline artifact)
      // and log the dir + filename so the operator can pull them off-device.
      final tsTag = DateTime.now().millisecondsSinceEpoch.toString();
      final dir = await ProfileExport.write(report, tsTag: tsTag);
      // ignore: avoid_print
      print('PROFILE_EXPORT_DIR $dir');
      // ignore: avoid_print
      print(
        'PROFILE_EXPORT_FILE query_profile_$tsTag.json '
        'query_profile_$tsTag.csv',
      );
    },
    // Seeding 2x500 real ONNX embeddings + the measured loops far exceed the
    // default 30s per-test timeout; give it generous headroom.
    timeout: const Timeout(Duration(minutes: 15)),
    // `flutter test` is always debug -> fallback backend. Skip there so an
    // invalid baseline is never produced; runs only under flutter drive --profile.
    skip: kDebugMode
        ? 'Measurement requires `flutter drive --profile` '
              '(flutter test is debug = fallback backend = invalid baseline).'
        : false,
  );
}

/// Fail-closed backend gate (defense-in-depth alongside the test-level skip).
/// Debug builds compile the cargokit debug profile = fallback Rust backend (no
/// vector_faer / vector_quant_i8), so any debug baseline is invalid. kDebugMode
/// is a compile-time const, false under a real profile/release build.
void _assertProfileMode() {
  if (kDebugMode) {
    fail(
      'Query profiler must run in PROFILE/RELEASE via flutter drive.\n'
      'Run: cd example && flutter drive '
      '--driver=test_driver/integration_test.dart '
      '--target=integration_test/query_profile_measure_test.dart '
      '--profile -d <device-id>\n'
      'Debug builds use the cargokit debug profile = fallback Rust backend '
      '(no vector_faer / vector_quant_i8), so the baseline would be invalid. '
      'Aborting to avoid a fake-green baseline. '
      '(detected: kDebugMode=$kDebugMode, kProfileMode=$kProfileMode, '
      'kReleaseMode=$kReleaseMode)',
    );
  }
}

/// Print the report to the device log in greppable blocks. Each CSV row is a
/// SEPARATE print: the device console truncates long single lines, so one big
/// multi-line print(toCsv()) loses the tail (e.g. switching_cold's activate).
void _emitReport(QueryProfileReport report) {
  for (final line in report.toCsv().trimRight().split('\n')) {
    // ignore: avoid_print
    print('PROFILE_CSV $line');
  }
  for (final r in report.runs) {
    // ignore: avoid_print
    print('PROFILE_IO ${r.lane}/${r.category} ${r.io}');
  }
}
