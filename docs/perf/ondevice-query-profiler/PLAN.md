# On-Device RAG Query Profiler — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable on-device Flutter `integration_test` that decomposes RAG query latency into stages (embed / activate / search / hydrate), captures I/O counters + an FFI-overhead figure, and exports p50/p95 to JSON+CSV so the real bottleneck is found from data.

**Architecture:** Approach C (phased). Phase 1 = coarse, Dart-only segments (zero Rust change) reusing `benchmark_service.dart` stats utilities; runs in the **example app** (which bundles the real ONNX model + tokenizer assets) so `embed` is real. Phase 2 = conditional drill-down into whichever bucket dominates. Spec: [DESIGN.md](DESIGN.md).

**Tech Stack:** Flutter `integration_test`, Dart `Stopwatch`, existing `EmbeddingService` / `SourceRagService` / `query_metrics` FFI, `dart:convert` + `dart:io` for export.

**Verified-fact anchors (do not re-derive):** one-active-collection singleton; `activateCollectionForHybridSearch` is a *separate* call (switch cost lives there, NOT inside `searchMetaHybrid`); active-collection queries do zero BM25 re-tokenization (0.18.4); filtered search → i8 exact-scan. See DESIGN §1.

---

## PR Decomposition (mirrors vector-math-refactor journal; each → a Linear issue)

| PR | Title | Linear | Host-testable? |
|----|-------|--------|----------------|
| P1 | Stats + report model + export utils (pure, host-TDD) | LOC-66 | ✅ yes (`flutter test`) |
| P2 | example integration_test wiring + A/B fixture builder | LOC-67 | device |
| P3 | Segment timing loop + 3 scenarios + query_metrics snapshot | LOC-68 | device |
| P4 | JSON/CSV export to app-docs + structured log + run metadata | LOC-69 | device + host(serialize) |
| P5 | Phase-2 quality/latency drill-down | LOC-70 | P5-① recall complete; P5-②~④ deferred after 0.18.6 |

Each PR: branch from main, commit (no Claude attribution), open PR, CI green (`cargo test -- --test-threads=1` unaffected — Dart-only), **user merges**. Fill `PRn.md` + README row before merge.

---

## File Structure

- Create `lib/services/benchmark_service.dart` → **add** one public method `statsFromSamples` (reuses existing private `_percentileFromSorted`/`_stdDev`). (P1)
- Create `example/lib/profiling/query_profile_report.dart` — pure model + JSON/CSV serializers + FFI-overhead computation. (P1)
- Create `example/lib/profiling/query_fixture.dart` — deterministic A/B corpus + 2-lane query set. (P2)
- Create `example/lib/profiling/query_profiler.dart` — the segment-timing driver (embed/activate/search/hydrate + metrics snapshot). (P3)
- Create `example/integration_test/query_profile_test.dart` — entrypoint: init engine, build fixture, run scenarios, export. (P2 skeleton → P3/P4 fill)
- Modify `example/pubspec.yaml` — add `integration_test` dev-dep. (P2)
- Create `test/unit/query_profile_report_test.dart` + `test/unit/benchmark_stats_test.dart` — host unit tests. (P1)

---

## Task P1.1: Public stats-from-samples helper

**Files:**
- Modify: `lib/services/benchmark_service.dart` (add method; reuse existing private helpers at lines 29-54)
- Test: `test/unit/benchmark_stats_test.dart`

- [ ] **Step 1: Write failing test**
```dart
// test/unit/benchmark_stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/benchmark_service.dart';
import 'package:mobile_rag_engine/models/benchmark_models.dart';

void main() {
  test('statsFromSamples computes p50/p95/avg/stddev', () {
    final s = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final DetailedBenchmarkStats st =
        BenchmarkService.statsFromSamples(s, warmupIterations: 0, measuredIterations: s.length);
    expect(st.measuredIterations, 10);
    expect(st.minMs, 1);
    expect(st.maxMs, 10);
    expect(st.avgMs, closeTo(5.5, 1e-9));
    expect(st.p50Ms, closeTo(5.5, 1e-9)); // (10-1)*0.5 = 4.5 → interp between 5 and 6
    expect(st.p95Ms, closeTo(9.55, 1e-9)); // (10-1)*0.95 = 8.55 → between 9 and 10
    expect(st.stdDevMs, greaterThan(0));
  });

  test('statsFromSamples handles empty', () {
    final st = BenchmarkService.statsFromSamples(<double>[], warmupIterations: 0, measuredIterations: 0);
    expect(st.p50Ms, 0.0);
    expect(st.p95Ms, 0.0);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**
Run: `flutter test test/unit/benchmark_stats_test.dart`
Expected: FAIL — `statsFromSamples` not defined.

- [ ] **Step 3: Implement (add to `class BenchmarkService`)**
```dart
/// Build DetailedBenchmarkStats from already-collected samples (ms).
/// Reuses the existing percentile/stddev helpers.
static DetailedBenchmarkStats statsFromSamples(
  List<double> samples, {
  required int warmupIterations,
  required int measuredIterations,
}) {
  if (samples.isEmpty) {
    return DetailedBenchmarkStats(
      warmupIterations: warmupIterations,
      measuredIterations: measuredIterations,
      samplesMs: const [],
      avgMs: 0, minMs: 0, maxMs: 0, p50Ms: 0, p95Ms: 0, stdDevMs: 0,
    );
  }
  final sorted = [...samples]..sort();
  final avg = samples.reduce((a, b) => a + b) / samples.length;
  return DetailedBenchmarkStats(
    warmupIterations: warmupIterations,
    measuredIterations: measuredIterations,
    samplesMs: samples,
    avgMs: avg,
    minMs: sorted.first,
    maxMs: sorted.last,
    p50Ms: _percentileFromSorted(sorted, 0.50),
    p95Ms: _percentileFromSorted(sorted, 0.95),
    stdDevMs: _stdDev(samples, avg),
  );
}
```

- [ ] **Step 4: Run test, verify PASS**
Run: `flutter test test/unit/benchmark_stats_test.dart` → Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/services/benchmark_service.dart test/unit/benchmark_stats_test.dart
git commit -m "feat(profiling): public statsFromSamples on BenchmarkService (LOC-66)"
```

---

## Task P1.2: Query profile report model (segments + FFI-overhead + JSON/CSV)

**Files:**
- Create: `example/lib/profiling/query_profile_report.dart`
- Test: `test/unit/query_profile_report_test.dart`

- [ ] **Step 1: Write failing test**
```dart
// test/unit/query_profile_report_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_engine_example/profiling/query_profile_report.dart';

void main() {
  test('SegmentSamples aggregates and serializes', () {
    final seg = SegmentSamples('embed')..addAll([10, 12, 11, 13, 9]);
    final j = seg.toJson();
    expect(j['segment'], 'embed');
    expect(j['p50_ms'], isNotNull);
    expect((j['samples_ms'] as List).length, 5);
  });

  test('ffiOverheadMs = dart segment minus rust internal', () {
    expect(QueryProfileRun.ffiOverheadMs(dartMs: 5.0, rustInternalMs: 3.2), closeTo(1.8, 1e-9));
    // never negative (clock noise) -> clamp to 0
    expect(QueryProfileRun.ffiOverheadMs(dartMs: 3.0, rustInternalMs: 3.4), 0.0);
  });

  test('report toCsv has one row per (lane,category,segment)', () {
    final run = QueryProfileRun(
      lane: 'unfiltered', category: 'pure_warm',
      segments: {
        'embed': SegmentSamples('embed')..addAll([10, 11]),
        'search': SegmentSamples('search')..addAll([2, 3]),
      },
      io: const {'scoped_exact_scan_rows': 0},
      meta: const {'device': 'test'},
    );
    final report = QueryProfileReport(runs: [run]);
    final csv = report.toCsv();
    expect(csv, contains('lane,category,segment,p50_ms,p95_ms,avg_ms,min_ms,max_ms,stddev_ms,n'));
    expect(csv, contains('unfiltered,pure_warm,embed,'));
    expect(csv, contains('unfiltered,pure_warm,search,'));
    final map = report.toJson();
    expect((map['runs'] as List).length, 1);
  });
}
```

- [ ] **Step 2: Run, verify FAIL**
Run: `flutter test test/unit/query_profile_report_test.dart` → FAIL (library missing).
> Note: `rag_engine_example` is the example app package name — confirm in `example/pubspec.yaml` `name:` and use it in the import.

- [ ] **Step 3: Implement**
```dart
// example/lib/profiling/query_profile_report.dart
import 'dart:convert';
import 'package:mobile_rag_engine/services/benchmark_service.dart';
import 'package:mobile_rag_engine/models/benchmark_models.dart';

/// Per-segment sample collector that defers stats to BenchmarkService.
class SegmentSamples {
  final String segment;
  final List<double> samplesMs = [];
  SegmentSamples(this.segment);
  void add(double ms) => samplesMs.add(ms);
  void addAll(Iterable<double> ms) => samplesMs.addAll(ms);

  DetailedBenchmarkStats stats() => BenchmarkService.statsFromSamples(
        samplesMs, warmupIterations: 0, measuredIterations: samplesMs.length);

  Map<String, dynamic> toJson() {
    final s = stats();
    return {'segment': segment, ...s.toJson()};
  }
}

/// One scenario run: a (lane, category) cell with its measured segments.
class QueryProfileRun {
  final String lane;       // 'unfiltered' | 'filtered'
  final String category;   // 'pure_cold' | 'switching_cold' | 'pure_warm'
  final Map<String, SegmentSamples> segments;
  final Map<String, Object?> io;   // query_metrics snapshot (rows/bytes/nanos)
  final Map<String, Object?> meta; // device/config

  QueryProfileRun({
    required this.lane, required this.category,
    required this.segments, required this.io, required this.meta,
  });

  /// FFI marshalling + isolate context-switch cost = Dart-measured − Rust-internal.
  /// Clamped to 0 (clock noise can make it slightly negative).
  static double ffiOverheadMs({required double dartMs, required double rustInternalMs}) {
    final d = dartMs - rustInternalMs;
    return d > 0 ? d : 0.0;
  }

  Map<String, dynamic> toJson() => {
    'lane': lane,
    'category': category,
    'segments': segments.map((k, v) => MapEntry(k, v.toJson())),
    'io': io,
    'meta': meta,
  };
}

class QueryProfileReport {
  final List<QueryProfileRun> runs;
  QueryProfileReport({required this.runs});

  Map<String, dynamic> toJson() => {'runs': runs.map((r) => r.toJson()).toList()};
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toCsv() {
    final b = StringBuffer()
      ..writeln('lane,category,segment,p50_ms,p95_ms,avg_ms,min_ms,max_ms,stddev_ms,n');
    for (final r in runs) {
      for (final seg in r.segments.values) {
        final s = seg.stats();
        b.writeln('${r.lane},${r.category},${seg.segment},'
            '${s.p50Ms},${s.p95Ms},${s.avgMs},${s.minMs},${s.maxMs},${s.stdDevMs},'
            '${seg.samplesMs.length}');
      }
    }
    return b.toString();
  }
}
```

- [ ] **Step 4: Run, verify PASS**
Run: `flutter test test/unit/query_profile_report_test.dart` → PASS.

- [ ] **Step 5: Commit**
```bash
git add example/lib/profiling/query_profile_report.dart test/unit/query_profile_report_test.dart
git commit -m "feat(profiling): query profile report model + JSON/CSV (LOC-66)"
```

> **PR P1 ends here.** Open PR, fill `PR-P1.md` + README row, user merges.

---

## Task P2.1: Add integration_test dependency to the example app

**Files:** Modify `example/pubspec.yaml`

- [ ] **Step 1:** Add under `dev_dependencies:`
```yaml
  integration_test:
    sdk: flutter
```
- [ ] **Step 2:** Run `cd example && flutter pub get` → Expected: resolves, no errors.
- [ ] **Step 3: Commit**
```bash
git add example/pubspec.yaml example/pubspec.lock
git commit -m "build(example): add integration_test dev-dep (LOC-67)"
```

## Task P2.2: Deterministic A/B fixture + 2-lane query set

**Files:** Create `example/lib/profiling/query_fixture.dart`

- [ ] **Step 1: Implement** (deterministic text; ingest builds chunks+embeddings+indexes)
```dart
// example/lib/profiling/query_fixture.dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

class QueryFixture {
  static const collectionA = 'profile_a';
  static const collectionB = 'profile_b';

  /// Deterministic short docs. `count` controls corpus size for the run.
  static List<String> docs(String seedTag, int count) => List.generate(
        count,
        (i) => 'doc $seedTag $i: mobile retrieval augmented generation '
            'embedding vector search bm25 ranking topic${i % 17} '
            'token${(i * 7) % 53} alpha beta gamma delta epsilon',
      );

  /// Two query lanes. Lane 2 (filtered) injects sourceIds at call time.
  static const unfilteredQueries = <String>[
    'vector search ranking', 'embedding topic3 retrieval',
    'bm25 token alpha', 'mobile generation gamma', 'topic9 delta epsilon',
  ];

  /// Seed both collections. Returns the source ids per collection (for filtered lane).
  static Future<Map<String, List<int>>> seed({required int docsPerCollection}) async {
    final ids = <String, List<int>>{};
    for (final c in [collectionA, collectionB]) {
      final col = MobileRag.instance.inCollection(c);
      final srcIds = <int>[];
      for (final d in docs(c, docsPerCollection)) {
        final r = await col.addDocumentUtf8(content: d); // confirm exact arg name in source_rag_service.inCollection().addDocumentUtf8
        srcIds.add(r.sourceId); // confirm field on the add-result type
      }
      ids[c] = srcIds;
    }
    return ids;
  }
}
```
> Execution note: confirm `addDocumentUtf8` parameter name + the returned source-id field against `SourceRagService` (rag_controller.dart uses `_activeCollection.addDocumentUtf8(...)`). Adjust the two flagged lines to the real signature — no other logic changes.

- [ ] **Step 2: Commit**
```bash
git add example/lib/profiling/query_fixture.dart
git commit -m "feat(profiling): deterministic A/B fixture + query lanes (LOC-67)"
```

## Task P2.3: integration_test entrypoint skeleton (engine init + fixture + smoke)

**Files:** Create `example/integration_test/query_profile_test.dart`

- [ ] **Step 1: Implement skeleton**
```dart
// example/integration_test/query_profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:rag_engine_example/profiling/query_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const docsPerCollection = 500; // representative; raise for scan-bound runs

  testWidgets('profiler: engine init + fixture builds', (tester) async {
    await MobileRag.initialize(
      tokenizerAsset: 'assets/tokenizer.json',
      modelAsset: 'assets/model.onnx',
      databaseName: 'profile.sqlite',
      deferIndexWarmup: true,
    );
    final ids = await QueryFixture.seed(docsPerCollection: docsPerCollection);
    expect(ids[QueryFixture.collectionA]!.length, docsPerCollection);
    expect(ids[QueryFixture.collectionB]!.length, docsPerCollection);
  });
}
```

- [ ] **Step 2: Run on the connected device**
Run: `cd example && flutter test integration_test/query_profile_test.dart -d <device-id>`
Expected: PASS (fixture builds on device). `flutter devices` to get `<device-id>`.

- [ ] **Step 3: Commit**
```bash
git add example/integration_test/query_profile_test.dart
git commit -m "test(profiling): integration_test entrypoint + fixture smoke (LOC-67)"
```

> **PR P2 ends here.** Open PR, fill `PR-P2.md` + README, user merges.

---

## Task P3.1: Segment-timing driver (embed/activate/search/hydrate + metrics)

**Files:** Create `example/lib/profiling/query_profiler.dart`

Segments are measured by replicating the steps the high-level `searchHybrid` bundles, so each is isolated:
`embed` = `EmbeddingService.embed`; `activate` = `activateCollectionForHybridSearch`; `search` = raw `searchMetaHybrid` (no embed/activate inside it — verified); `hydrate` = `handle.hydrateChunks`.

- [ ] **Step 1: Implement**
```dart
// example/lib/profiling/query_profiler.dart
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;
import 'package:mobile_rag_engine/src/rust/api/query_metrics.dart' as qm;
import 'package:mobile_rag_engine/services/source_rag_service.dart' show kDefaultVectorWeight, kDefaultBm25Weight;
import 'query_profile_report.dart';

class QueryProfiler {
  final String indexBasePath; // _indexPath used by activate (confirm via SourceRagService._indexPath getter or MobileRag)
  QueryProfiler(this.indexBasePath);

  static Future<double> _timeMs(Future<void> Function() fn) async {
    final sw = Stopwatch()..start();
    await fn();
    return sw.elapsedMicroseconds / 1000.0;
  }

  /// One measured query. If [activateCollection] != null, the activate segment
  /// is measured (switching/cold). Returns segment ms keyed by name.
  Future<Map<String, double>> measureOnce({
    required String collectionId,
    required String query,
    List<int>? sourceIds,    // non-null => filtered lane (i8 exact-scan)
    String? activateCollection, // non-null => measure activate (switch)
    int topK = 10,
  }) async {
    final out = <String, double>{};

    if (activateCollection != null) {
      out['activate'] = await _timeMs(() => rust_rag.activateCollectionForHybridSearch(
            collectionId: activateCollection, basePath: indexBasePath));
    }

    late final dynamic embedding;
    out['embed'] = await _timeMs(() async { embedding = await EmbeddingService.embed(query); });

    qm.resetQueryContentReadStats();

    late final rust_rag.SearchHandle handle;
    out['search'] = await _timeMs(() async {
      handle = await rust_rag.searchMetaHybrid(
        collectionId: collectionId,
        queryText: query,
        queryEmbedding: embedding,
        options: rust_rag.SearchMetaHybridOptions(
          topK: topK,
          vectorWeight: kDefaultVectorWeight,
          bm25Weight: kDefaultBm25Weight,
          sourceIds: sourceIds == null ? null : _toI64(sourceIds),
          adjacentChunks: 0,
        ),
      );
    });

    final hits = await handle.hitMeta();
    final chunkIds = _toI64(hits.map((h) => h.chunkId as int).toList()); // confirm hit field name
    out['hydrate'] = await _timeMs(() async { await handle.hydrateChunks(chunkIds: chunkIds); });

    await handle.dispose();
    return out;
  }

  // dart:typed_data Int64List builder; confirm _toInt64List equivalent exists or inline.
  static dynamic _toI64(List<int> v) => /* Int64List.fromList(v) */ throw UnimplementedError();
}
```
> Execution notes (confirm against signatures, adjust only flagged lines): `indexBasePath` source (`SourceRagService` builds `_indexPath` from the docs dir + collection — reuse that construction); the hit's chunk-id field name (`SearchHitMeta`); replace `_toI64` with `Int64List.fromList` (import `dart:typed_data`). No control-flow changes.

- [ ] **Step 2: Snapshot helper for query_metrics → io map**
```dart
Map<String, Object?> snapshotIo() {
  final s = qm.takeQueryContentReadStats();
  return {
    'scoped_exact_scan_rows': s.scopedExactScanRows.toInt(),
    'scoped_exact_scan_content_bytes': s.scopedExactScanContentBytes.toInt(),
    'scoped_exact_scan_tokens': s.scopedExactScanTokens.toInt(),
    'scoped_exact_scan_tokenization_nanos': s.scopedExactScanTokenizationNanos.toInt(),
    'full_hydrate_rows': s.fullHydrateRows.toInt(),
    'full_hydrate_content_bytes': s.fullHydrateContentBytes.toInt(),
  };
}
```
- [ ] **Step 3: Commit**
```bash
git add example/lib/profiling/query_profiler.dart
git commit -m "feat(profiling): per-segment query profiler driver (LOC-68)"
```

## Task P3.2: Scenario runner — Pure Cold / Switching Cold / Pure Warm × 2 lanes

**Files:** Modify `example/integration_test/query_profile_test.dart`

- [ ] **Step 1: Implement scenarios** (append a second `testWidgets`)
```dart
testWidgets('profiler: scenarios x lanes', (tester) async {
  await MobileRag.initialize(
    tokenizerAsset: 'assets/tokenizer.json', modelAsset: 'assets/model.onnx',
    databaseName: 'profile.sqlite', deferIndexWarmup: true);
  final ids = await QueryFixture.seed(docsPerCollection: 500);
  final profiler = QueryProfiler(/* indexBasePath */);
  final runs = <QueryProfileRun>[];
  const measured = 30, warmup = 5;

  Future<void> runCell({required String lane, required String category,
      List<int>? sourceIds, bool measureActivate = false}) async {
    final segs = {
      for (final n in ['embed','search','hydrate', if (measureActivate) 'activate'])
        n: SegmentSamples(n),
    };
    final q = QueryFixture.unfilteredQueries;
    // warmup (discard)
    for (var i = 0; i < warmup; i++) {
      await profiler.measureOnce(collectionId: QueryFixture.collectionA,
        query: q[i % q.length], sourceIds: sourceIds);
    }
    for (var i = 0; i < measured; i++) {
      // switching_cold: re-activate A each iter after touching B; else activate once/never
      final actCol = measureActivate ? QueryFixture.collectionA : null;
      if (measureActivate) {
        await profiler.measureOnce(collectionId: QueryFixture.collectionB,
          query: q[0], activateCollection: QueryFixture.collectionB); // touch B → A is now cold
      }
      final m = await profiler.measureOnce(collectionId: QueryFixture.collectionA,
        query: q[i % q.length], sourceIds: sourceIds, activateCollection: actCol);
      m.forEach((k, v) => segs[k]?.add(v));
    }
    runs.add(QueryProfileRun(lane: lane, category: category,
      segments: segs, io: profiler.snapshotIo(), meta: const {}));
  }

  // Pure Warm (no activate between iters) — both lanes
  await runCell(lane: 'unfiltered', category: 'pure_warm');
  await runCell(lane: 'filtered', category: 'pure_warm',
    sourceIds: ids[QueryFixture.collectionA]!.take(3).toList());
  // Switching Cold (A→B→A each iter) — unfiltered (the expensive path)
  await runCell(lane: 'unfiltered', category: 'switching_cold', measureActivate: true);

  // sanity: every cell has >=1 sample per segment (fail-closed)
  for (final r in runs) {
    for (final s in r.segments.values) {
      expect(s.samplesMs.length, greaterThan(0), reason: '${r.lane}/${r.category}/${s.segment}');
    }
  }
  // exported in P4
});
```
> Pure Cold (app first launch) is a separate one-shot: capture the very first `measureOnce` before any warmup in a dedicated `testWidgets` that does NOT pre-warm. Add as `category: 'pure_cold'` with `measuredIterations: 1`.

- [ ] **Step 2: Run on device**
Run: `cd example && flutter test integration_test/query_profile_test.dart -d <device-id>`
Expected: PASS; logs show per-segment counts. Inspect the printed numbers.

- [ ] **Step 3: Commit**
```bash
git add example/integration_test/query_profile_test.dart
git commit -m "test(profiling): cold/switch/warm scenarios x 2 lanes (LOC-68)"
```

> **PR P3 ends here.** Open PR, fill `PR-P3.md` (paste observed per-segment p50/p95!) + README, user merges.

---

## Task P4.1: Export JSON+CSV to app docs dir + structured log + metadata

**Files:** Modify `example/integration_test/query_profile_test.dart`; add `example/lib/profiling/profile_export.dart`

- [ ] **Step 1: Implement exporter**
```dart
// example/lib/profiling/profile_export.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'query_profile_report.dart';

class ProfileExport {
  /// Writes <docs>/query_profile.json and .csv; returns the dir path.
  static Future<String> write(QueryProfileReport report, {required String tsTag}) async {
    final dir = await getApplicationDocumentsDirectory();
    final base = '${dir.path}/query_profile_$tsTag';
    await File('$base.json').writeAsString(report.toJsonString(), flush: true);
    await File('$base.csv').writeAsString(report.toCsv(), flush: true);
    // structured one-line log per run for live logcat/console monitoring
    for (final r in report.runs) {
      // ignore: avoid_print
      print('PROFILE ${r.toJson()}');
    }
    return dir.path;
  }
}
```
- [ ] **Step 2: Wire into the scenario test** (after building `runs`)
```dart
final report = QueryProfileReport(runs: runs);
final ts = DateTime.now().millisecondsSinceEpoch.toString();
final path = await ProfileExport.write(report, tsTag: ts);
print('PROFILE_EXPORT_DIR $path'); // adb pull / xcrun simctl from here
```
> Attach run metadata in `meta`: device model, OS, corpus size, top_k, feature flags (release ships `vector_faer,vector_quant_i8`), charging state (document manually — In scope per DESIGN §10). Populate `meta` map in `runCell`.

- [ ] **Step 3: Run on device + pull**
Run: `flutter test integration_test/query_profile_test.dart -d <device-id>`
Then Android: `adb shell run-as <app-id> cat files/query_profile_<ts>.json > out.json` (or `adb pull` from app docs); iOS: `xcrun simctl get_app_container booted <bundle-id> data` then read Documents.
Expected: JSON+CSV present, one `PROFILE` log line per run.

- [ ] **Step 4: Commit**
```bash
git add example/lib/profiling/profile_export.dart example/integration_test/query_profile_test.dart
git commit -m "feat(profiling): JSON/CSV export + structured log + metadata (LOC-69)"
```

> **PR P4 ends here.** This is the **baseline deliverable** — open PR, fill `PR-P4.md` with the pulled baseline numbers + which segment dominates, README, user merges.

---

## Phase 2 (PR P5, CONDITIONAL — gated on P3/P4 data)

Decision rule from the baseline (do NOT pre-build):
- **embed dominates** → no Rust work. Conclusion: next target is ONNX inference (out of this crate). Record in `PR-P5.md` / RETRO; close initiative.
- **activate dominates (cold/switch)** → split `activate` into `bm25_rebuild` vs `hnsw_load`: add timing around `rebuild_chunk_bm25_index_for_collection` vs `load_hnsw_index` (Rust log timestamps or a small `QueryTimings`-style snapshot mirroring `query_metrics.rs`). **Mandatory for cold/switch.**
- **search dominates (warm)** → add Rust `QueryTimings` (thread-local `Instant` stage timers in the hybrid path, FFI snapshot like `query_metrics.rs`) splitting ANN / BM25-rank / RRF; surface via the same export.
- **hydrate/IO dominates** → already covered by `query_metrics` counters; just chart them.

---

## Self-Review (run against DESIGN.md)

**Spec coverage:** embed/activate/search/hydrate segments → P3.1 ✅; FFI-overhead formula → P1.2 `ffiOverheadMs` ✅; 2 lanes → P3.2 (`sourceIds`) ✅; Cold/Switching/Warm → P3.2 + Pure-Cold one-shot ✅; A→B→A switch → P3.2 `measureActivate` ✅; query_metrics I/O → P3.1 `snapshotIo` ✅; JSON/CSV+log+metadata → P4.1 ✅; reuse benchmark_service → P1.1 ✅; fail-closed N>0 → P3.2 ✅; example-app/real-ONNX → P2.3 ✅; Phase-2 gate → P5 ✅. Out-of-scope (indexing/memory/battery/CI-gate/recall) correctly absent.

**Placeholder scan:** Remaining `confirm ...` notes are execution-time signature confirmations on **flagged single lines** (addDocumentUtf8 arg, source-id field, hit chunk-id field, `_toI64`→`Int64List.fromList`, `indexBasePath` source), each with the exact reference to confirm against — not vague requirements. All logic/control-flow is concrete.

**Type consistency:** `SegmentSamples`/`QueryProfileRun`/`QueryProfileReport` used consistently P1.2→P3→P4; `statsFromSamples` signature matches P1.1; `DetailedBenchmarkStats.toJson` field names match benchmark_models.dart.
