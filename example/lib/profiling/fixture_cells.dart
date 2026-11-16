// Per-segment query latency on the synthetic two-collection fixture
// (QueryFixture): pure_cold, pure_warm (unfiltered and filtered) and
// switching_cold. Shared by integration_test/query_profile_measure_test.dart
// and integration_test/m5_device_measure_test.dart.
//
// Expects MobileRag to be initialized and the fixture seeded (QueryFixture.seed).
import 'query_fixture.dart';
import 'query_profile_report.dart';
import 'query_profiler.dart';
import 'rss_sampler.dart';

Future<List<QueryProfileRun>> runFixtureCells({
  required QueryProfiler profiler,
  required Map<String, List<int>> sourceIds,
  required Map<String, Object?> meta,
  int warmup = 5,
  int measured = 30,
}) async {
  final q = QueryFixture.unfilteredQueries;
  final runs = <QueryProfileRun>[];

  // Per-collection index files survive across runs; delete them so the first
  // activate rebuilds the current corpus from the DB, then evict A from the
  // single global HNSW slot so pure_cold's activate is genuinely cold.
  await profiler.deleteOnDiskIndex(QueryFixture.collectionA);
  await profiler.deleteOnDiskIndex(QueryFixture.collectionB);
  await profiler.activateOnly(QueryFixture.collectionB); // active := B

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
    List<int>? filterIds,
  }) async {
    final measuresActivate = activateOnce || activatePerIter;
    final segs = {
      for (final n in [
        'embed',
        'search',
        'hydrate',
        if (measuresActivate) 'activate',
      ])
        n: SegmentSamples(n),
    };
    final allowed = filterIds?.toSet();

    // Warm cells: ensure A is active, then warm caches (discarded). Cold
    // cells (warmupN == 0) skip this so the measured shot stays cold.
    if (warmupN > 0) {
      await profiler.activateOnly(QueryFixture.collectionA);
      for (var i = 0; i < warmupN; i++) {
        await profiler.measureOnce(
          collectionId: QueryFixture.collectionA,
          query: q[i % q.length],
          sourceIds: filterIds,
        );
      }
    }

    QueryProfiler.resetIo(); // I/O snapshot reflects measured iters only
    final rss = RssSampler().start();
    final activation = <String, int>{};
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
        sourceIds: filterIds,
        activate: measuresActivate,
      );
      r.ms.forEach((k, v) => segs[k]?.add(v));
      _addNumericMap(activation, r.activation);
      final hitCount = r.hitSourceIds.length;
      if (minHits < 0 || hitCount < minHits) minHits = hitCount;
      // Fail-closed (filtered lane): every hit must come from the requested
      // sources, which proves the filter actually applied.
      if (allowed != null) {
        _check(
          r.hitSourceIds.every(allowed.contains),
          '$lane/$category returned a hit outside requested '
          'sourceIds - filter not applied',
        );
      }
      rss.sample();
    }
    final io = {
      ...profiler.snapshotIo(),
      ...activation,
      ...rss.finish().toJson(prefix: 'rss'),
    };

    // Fail-closed: a wrong index path or empty corpus would return 0 hits.
    _check(
      minHits > 0,
      '$lane/$category returned 0 hits - wrong index path/corpus',
    );
    return QueryProfileRun(
      lane: lane,
      category: category,
      segments: segs,
      io: io,
      meta: meta,
    );
  }

  // Pure Cold (first query, cold index build). Leaves A active.
  runs.add(
    await runCell(
      lane: 'unfiltered',
      category: 'pure_cold',
      warmupN: 0,
      measuredN: 1,
      activateOnce: true,
    ),
  );
  // Pure Warm (collection already active), both lanes.
  runs.add(
    await runCell(
      lane: 'unfiltered',
      category: 'pure_warm',
      warmupN: warmup,
      measuredN: measured,
    ),
  );
  runs.add(
    await runCell(
      lane: 'filtered',
      category: 'pure_warm',
      warmupN: warmup,
      measuredN: measured,
      filterIds: sourceIds[QueryFixture.collectionA]!.take(3).toList(),
    ),
  );
  // Switching Cold (A -> B -> A each iter), unfiltered.
  runs.add(
    await runCell(
      lane: 'unfiltered',
      category: 'switching_cold',
      warmupN: warmup,
      measuredN: measured,
      activatePerIter: true,
    ),
  );

  // Fail-closed: every cell has at least one sample per segment.
  for (final r in runs) {
    for (final s in r.segments.values) {
      _check(
        s.samplesMs.isNotEmpty,
        'no samples: ${r.lane}/${r.category}/${s.segment}',
      );
    }
  }
  return runs;
}

void _addNumericMap(Map<String, int> totals, Map<String, Object?> values) {
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is int) {
      totals.update(entry.key, (c) => c + value, ifAbsent: () => value);
    } else if (value is BigInt) {
      final asInt = value.toInt();
      totals.update(entry.key, (c) => c + asInt, ifAbsent: () => asInt);
    }
  }
}

void _check(bool ok, String message) {
  if (!ok) throw StateError(message);
}
