import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/profiling/query_profiler.dart';
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
//       --profile -d <device-id>
//
// Clean state is established by DELETING the DB files before initialize (not
// clearAllData, whose async re-init races the first seed and trips
// "database is locked"). Per-collection index files are removed after init.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const measuredDocs = 500; // representative; raise for scan-bound runs
  const warmup = 5;
  const measured = 30;
  const topK = 10;

  test(
    'profiler: pure_cold / pure_warm / switching_cold x 2 lanes',
    () async {
      _assertProfileMode();

      // Fresh DB without clearAllData: delete the SQLite files BEFORE
      // initialize so the engine starts clean and nothing races the seed.
      final docsDir = await getApplicationDocumentsDirectory();
      final dbStem = '${docsDir.path}/profile.sqlite';
      for (final p in [dbStem, '$dbStem-wal', '$dbStem-shm', '$dbStem-journal']) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }

      await MobileRag.initialize(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
        databaseName: 'profile.sqlite',
        deferIndexWarmup: true,
      );

      final ids = await QueryFixture.seed(docsPerCollection: measuredDocs);
      expect(ids[QueryFixture.collectionA]!.length, measuredDocs);
      expect(ids[QueryFixture.collectionB]!.length, measuredDocs);

      final profiler = QueryProfiler(dbPath: MobileRag.instance.dbPath);
      final q = QueryFixture.unfilteredQueries;
      final runs = <QueryProfileRun>[];

      final meta = <String, Object?>{
        'build_mode':
            kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
        'features': 'vector_faer,vector_quant_i8', // shipped in profile/release
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        // Device model + charging state: document manually in PR-P4.md.
        'docs_per_collection': measuredDocs,
        'top_k': topK,
        'vector_weight': profiler.vectorWeight,
        'bm25_weight': profiler.bm25Weight,
        // Cold-activate semantics differ per cell: pure_cold rebuilds A's index
        // from the DB (on-disk index deleted, slot evicted); switching_cold then
        // loads A from disk (pure_cold's activate re-saved it). Both are genuine
        // cold costs; the switch is the realistic production figure.
        'cold_note': 'pure_cold=rebuild-from-db; switching_cold=load-from-disk',
      };

      // Per-collection index files survive across runs; delete them so the first
      // activate rebuilds the current corpus from the DB, then evict A from the
      // single global HNSW slot so pure_cold's activate is genuinely cold.
      await profiler.deleteOnDiskIndex(QueryFixture.collectionA);
      await profiler.deleteOnDiskIndex(QueryFixture.collectionB);
      await profiler.activateOnly(QueryFixture.collectionB); // active := B (A evicted)

      /// Run one (lane, category) cell.
      /// - [activateOnce]: single cold shot measures the activate segment (pure_cold).
      /// - [activatePerIter]: re-activate A every iter after evicting it (switching_cold).
      Future<QueryProfileRun> runCell({
        required String lane,
        required String category,
        required int warmupN,
        required int measuredN,
        bool activateOnce = false,
        bool activatePerIter = false,
        List<int>? sourceIds,
      }) async {
        final measuresActivate = activateOnce || activatePerIter;
        final segs = {
          for (final n in ['embed', 'search', 'hydrate',
              if (measuresActivate) 'activate'])
            n: SegmentSamples(n),
        };
        final allowed = sourceIds?.toSet();

        // Warm cells: ensure A is active, then warm caches (discarded). Cold
        // cells (warmupN == 0) skip this so the measured shot stays cold.
        if (warmupN > 0) {
          await profiler.activateOnly(QueryFixture.collectionA);
          for (var i = 0; i < warmupN; i++) {
            await profiler.measureOnce(
              collectionId: QueryFixture.collectionA,
              query: q[i % q.length],
              sourceIds: sourceIds,
            );
          }
        }

        QueryProfiler.resetIo(); // I/O snapshot reflects measured iters only
        var minHits = -1;
        for (var i = 0; i < measuredN; i++) {
          if (activatePerIter) {
            // Evict A (no query, so collection-B I/O does not pollute the
            // snapshot) so the measured activate(A) pays the real switch cost.
            await profiler.activateOnly(QueryFixture.collectionB);
          }
          final r = await profiler.measureOnce(
            collectionId: QueryFixture.collectionA,
            query: q[i % q.length],
            sourceIds: sourceIds,
            activate: activateOnce || activatePerIter,
          );
          r.ms.forEach((k, v) => segs[k]?.add(v));
          final hitCount = r.hitSourceIds.length;
          if (minHits < 0 || hitCount < minHits) minHits = hitCount;
          // Fail-closed (filtered lane): every hit must come from the requested
          // sources — proves the filter actually applied. (Replaces the
          // scoped_exact_scan_rows counter, which the engine never increments.)
          if (allowed != null) {
            expect(r.hitSourceIds.every(allowed.contains), isTrue,
                reason: '$lane/$category returned a hit outside requested '
                    'sourceIds — filter not applied');
          }
        }
        final io = profiler.snapshotIo();

        // Fail-closed: a wrong index path or empty corpus would return 0 hits.
        expect(minHits, greaterThan(0),
            reason: '$lane/$category returned 0 hits — wrong index path/corpus');
        return QueryProfileRun(
            lane: lane, category: category, segments: segs, io: io, meta: meta);
      }

      // Pure Cold (first query, cold index build) — unfiltered one-shot.
      // Runs first; it leaves collection A active for the warm cells below.
      runs.add(await runCell(
        lane: 'unfiltered',
        category: 'pure_cold',
        warmupN: 0,
        measuredN: 1,
        activateOnce: true,
      ));

      // Pure Warm (collection already active) — both lanes.
      runs.add(await runCell(
        lane: 'unfiltered',
        category: 'pure_warm',
        warmupN: warmup,
        measuredN: measured,
      ));
      runs.add(await runCell(
        lane: 'filtered',
        category: 'pure_warm',
        warmupN: warmup,
        measuredN: measured,
        sourceIds: ids[QueryFixture.collectionA]!.take(3).toList(),
      ));

      // Switching Cold (A -> B -> A each iter) — unfiltered (expensive path).
      runs.add(await runCell(
        lane: 'unfiltered',
        category: 'switching_cold',
        warmupN: warmup,
        measuredN: measured,
        activatePerIter: true,
      ));

      // Fail-closed: every cell has at least one sample per segment.
      for (final r in runs) {
        for (final s in r.segments.values) {
          expect(s.samplesMs.length, greaterThan(0),
              reason: '${r.lane}/${r.category}/${s.segment}');
        }
      }

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
      print('PROFILE_EXPORT_FILE query_profile_$tsTag.json '
          'query_profile_$tsTag.csv');
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
