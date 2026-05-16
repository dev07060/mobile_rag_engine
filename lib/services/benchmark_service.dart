// lib/services/benchmark_service.dart
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/hybrid_search.dart';
import 'package:mobile_rag_engine/src/rust/api/ingest_metrics.dart'
    as ingest_metrics;
import 'package:mobile_rag_engine/src/rust/api/ingest_session.dart'
    as ingest_session;
import 'package:mobile_rag_engine/src/rust/api/query_metrics.dart'
    as query_metrics;
import 'package:mobile_rag_engine/src/rust/api/semantic_chunker.dart'
    as semantic_chunker;
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as source_rag;
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mobile_rag_engine/models/benchmark_models.dart';

/// Performance benchmark service
class BenchmarkService {
  static double _percentileFromSorted(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0.0;
    if (sorted.length == 1) return sorted.first;

    final clamped = p.clamp(0.0, 1.0);
    final pos = (sorted.length - 1) * clamped;
    final lower = pos.floor();
    final upper = pos.ceil();

    if (lower == upper) return sorted[lower];
    final weight = pos - lower;
    return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
  }

  static double _stdDev(List<double> values, double mean) {
    if (values.length <= 1) return 0.0;
    final variance =
        values
            .map((v) {
              final diff = v - mean;
              return diff * diff;
            })
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }

  /// Collect measured samples after warmup.
  static Future<List<double>> collectSamples(
    Future<void> Function() fn, {
    int warmupIterations = 5,
    int measuredIterations = 30,
  }) async {
    for (var i = 0; i < warmupIterations; i++) {
      await fn();
    }

    final samples = <double>[];
    for (var i = 0; i < measuredIterations; i++) {
      final ms = await measureMs(fn);
      samples.add(ms);
    }
    return samples;
  }

  /// Summarize measured samples with p50/p95/stddev.
  static DetailedBenchmarkStats summarizeSamples(
    List<double> samplesMs, {
    required int warmupIterations,
  }) {
    final copied = List<double>.from(samplesMs)..sort();
    final measured = samplesMs.length;
    final avg = measured == 0
        ? 0.0
        : samplesMs.reduce((a, b) => a + b) / measured;
    final min = copied.isEmpty ? 0.0 : copied.first;
    final max = copied.isEmpty ? 0.0 : copied.last;
    final p50 = copied.isEmpty ? 0.0 : _percentileFromSorted(copied, 0.50);
    final p95 = copied.isEmpty ? 0.0 : _percentileFromSorted(copied, 0.95);
    final stdDev = _stdDev(samplesMs, avg);

    return DetailedBenchmarkStats(
      warmupIterations: warmupIterations,
      measuredIterations: measured,
      samplesMs: samplesMs,
      avgMs: avg,
      minMs: min,
      maxMs: max,
      p50Ms: p50,
      p95Ms: p95,
      stdDevMs: stdDev,
    );
  }

  /// Run detailed benchmark with warmup and reproducible summary.
  static Future<DetailedBenchmarkStats> benchmarkDetailed(
    Future<void> Function() fn, {
    int warmupIterations = 5,
    int measuredIterations = 30,
  }) async {
    final samples = await collectSamples(
      fn,
      warmupIterations: warmupIterations,
      measuredIterations: measuredIterations,
    );
    return summarizeSamples(samples, warmupIterations: warmupIterations);
  }

  /// Aggregate multiple round stats by flattening all measured samples.
  static DetailedBenchmarkStats aggregateRoundStats(
    List<DetailedBenchmarkStats> rounds,
  ) {
    final allSamples = <double>[];
    var warmup = 0;
    for (final round in rounds) {
      warmup = round.warmupIterations;
      allSamples.addAll(round.samplesMs);
    }
    return summarizeSamples(allSamples, warmupIterations: warmup);
  }

  /// Measure execution time of async code block
  static Future<double> measureMs(Future<void> Function() fn) async {
    final sw = Stopwatch()..start();
    await fn();
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  }

  /// Measure execution time of sync code block
  static double measureMsSync(void Function() fn) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  }

  static int _utf8ByteLength(String? value) =>
      value == null ? 0 : utf8.encode(value).length;

  static int _bigIntToInt(BigInt value) => value.toInt();

  static frb.Int64List _toInt64List(List<int> values) {
    final result = frb.Int64List(values.length);
    for (var i = 0; i < values.length; i++) {
      result[i] = values[i];
    }
    return result;
  }

  /// Run multiple iterations and measure avg/min/max
  static Future<BenchmarkResult> benchmark(
    String name,
    Future<void> Function() fn, {
    int iterations = 10,
    required BenchmarkCategory category,
  }) async {
    final times = <double>[];

    // Warmup (exclude first run)
    await fn();

    for (var i = 0; i < iterations; i++) {
      final ms = await measureMs(fn);
      times.add(ms);
    }

    times.sort();
    final avg = times.reduce((a, b) => a + b) / times.length;

    return BenchmarkResult(
      name: name,
      avgMs: avg,
      minMs: times.first,
      maxMs: times.last,
      iterations: iterations,
      category: category,
    );
  }

  /// Tokenization benchmark (Rust-powered)
  static Future<BenchmarkResult> benchmarkTokenize(
    String text, {
    int iterations = 50,
  }) async {
    return benchmark(
      'Tokenize (${text.length} chars)',
      () async {
        tokenize(text: text);
      },
      iterations: iterations,
      category: BenchmarkCategory.rust,
    );
  }

  /// Embedding generation benchmark (ONNX-powered)
  static Future<BenchmarkResult> benchmarkEmbed(
    String text, {
    int iterations = 10,
  }) async {
    return benchmark(
      'Embed (${text.length} chars)',
      () async {
        await EmbeddingService.embed(text);
      },
      iterations: iterations,
      category: BenchmarkCategory.onnx,
    );
  }

  /// Search benchmark (Rust HNSW-powered)
  static Future<BenchmarkResult> benchmarkSearch(
    String dbPath,
    List<double> queryEmbedding,
    int docCount, {
    int iterations = 20,
  }) async {
    return benchmark(
      'HNSW Search ($docCount docs)',
      () async {
        await searchSimilar(queryEmbedding: queryEmbedding, topK: 3);
      },
      iterations: iterations,
      category: BenchmarkCategory.rust,
    );
  }

  /// Hybrid Search benchmark
  static Future<BenchmarkResult> benchmarkHybridSearch(
    String dbPath,
    String queryText,
    List<double> queryEmbedding,
    int docCount, {
    int iterations = 20,
  }) async {
    return benchmark(
      'Hybrid Search ($docCount docs)',
      () async {
        await searchHybridSimple(
          queryText: queryText,
          queryEmbedding: queryEmbedding,
          topK: 3,
        );
      },
      iterations: iterations,
      category: BenchmarkCategory.rust,
    );
  }

  static QueryPayloadVariantStats _variantStatsFromNative({
    required String label,
    required double elapsedMs,
    required int hitCount,
    int metaBytes = 0,
    int contextBytes = 0,
    int fullChunkBytes = 0,
    int previewBytes = 0,
    query_metrics.QueryContentReadStats? nativeReadStats,
  }) {
    return QueryPayloadVariantStats(
      label: label,
      elapsedMs: elapsedMs,
      hitCount: hitCount,
      metaBytes: metaBytes,
      contextBytes: contextBytes,
      fullChunkBytes: fullChunkBytes,
      previewBytes: previewBytes,
      nativeHybridResultRows: _bigIntToInt(
        nativeReadStats?.hybridResultRows ?? BigInt.zero,
      ),
      nativeHybridResultContentBytes: _bigIntToInt(
        nativeReadStats?.hybridResultContentBytes ?? BigInt.zero,
      ),
      nativeFullHydrateRows: _bigIntToInt(
        nativeReadStats?.fullHydrateRows ?? BigInt.zero,
      ),
      nativeFullHydrateContentBytes: _bigIntToInt(
        nativeReadStats?.fullHydrateContentBytes ?? BigInt.zero,
      ),
      nativePreviewRows: _bigIntToInt(
        nativeReadStats?.previewRows ?? BigInt.zero,
      ),
      nativePreviewContentBytes: _bigIntToInt(
        nativeReadStats?.previewContentBytes ?? BigInt.zero,
      ),
      nativeAssemblyRows: _bigIntToInt(
        nativeReadStats?.assemblyRows ?? BigInt.zero,
      ),
      nativeAssemblyContentBytes: _bigIntToInt(
        nativeReadStats?.assemblyContentBytes ?? BigInt.zero,
      ),
      nativeUnclassifiedRows: _bigIntToInt(
        nativeReadStats?.unclassifiedRows ?? BigInt.zero,
      ),
      nativeUnclassifiedContentBytes: _bigIntToInt(
        nativeReadStats?.unclassifiedContentBytes ?? BigInt.zero,
      ),
      nativeScopedExactScanRows: _bigIntToInt(
        nativeReadStats?.scopedExactScanRows ?? BigInt.zero,
      ),
      nativeScopedExactScanContentBytes: _bigIntToInt(
        nativeReadStats?.scopedExactScanContentBytes ?? BigInt.zero,
      ),
      nativeScopedExactScanTokenizedRows: _bigIntToInt(
        nativeReadStats?.scopedExactScanTokenizedRows ?? BigInt.zero,
      ),
      nativeScopedExactScanTokenizedContentBytes: _bigIntToInt(
        nativeReadStats?.scopedExactScanTokenizedContentBytes ?? BigInt.zero,
      ),
      nativeScopedExactScanTokens: _bigIntToInt(
        nativeReadStats?.scopedExactScanTokens ?? BigInt.zero,
      ),
      nativeScopedExactScanTokenizationNanos: _bigIntToInt(
        nativeReadStats?.scopedExactScanTokenizationNanos ?? BigInt.zero,
      ),
    );
  }

  /// Measure current query/search payload shape without changing runtime
  /// behavior.
  ///
  /// The benchmark seeds a deterministic collection with precomputed stub
  /// embeddings, then compares:
  /// - legacy `searchHybrid` full-result payload,
  /// - `SearchHandle` + full hydration,
  /// - `SearchHandle` + preview excerpts,
  /// - `SearchHandle` + context-only assembly.
  ///
  /// This intentionally measures string bytes surfaced to Dart, not internal
  /// Rust allocations. It is the pre-optimization baseline for moving the query
  /// path toward body-less retrieval.
  ///
  /// The result also includes native lower-bound counters for content rows read
  /// by legacy hybrid materialization and shared SearchHandle hydration.
  static Future<QueryPayloadBenchResult> benchmarkQueryPayload({
    int topK = 4,
    int adjacentChunks = 1,
    int previewMaxBytes = 24,
    int tokenBudget = 4000,
    String? restoreDbPath,
    String? dbPathOverride,
  }) async {
    const collectionId = 'bench-query-payload';
    const queryText = 'install checksum smoke';
    final queryEmbedding = Float32List.fromList([1.0, 0.0, 0.0, 0.0]);
    final benchDbPath =
        dbPathOverride ??
        "${(await getApplicationDocumentsDirectory()).path}/query_payload_bench.sqlite";
    final benchFile = File(benchDbPath);
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    final tokenizerFile = File('$benchDbPath.tokenizer.json');
    if (await tokenizerFile.exists()) {
      await tokenizerFile.delete();
    }

    await initDbPool(dbPath: benchDbPath, maxSize: 4);
    await initDb();
    await source_rag.initSourceDb();
    await tokenizerFile.writeAsString(
      '{"version":"1.0","truncation":null,"padding":null,'
      '"added_tokens":[],"normalizer":null,'
      '"pre_tokenizer":{"type":"Whitespace"},"post_processor":null,'
      '"decoder":null,"model":{"type":"WordLevel",'
      '"vocab":{"[UNK]":0,"install":1,"checksum":2,"smoke":3},'
      '"unk_token":"[UNK]"}}',
      flush: true,
    );
    await initTokenizer(tokenizerPath: tokenizerFile.path);

    Future<void> seedSource({
      required String name,
      required String? metadata,
      required List<String> chunks,
      required List<Float32List> embeddings,
    }) async {
      final source = await source_rag.addSourceInCollection(
        collectionId: collectionId,
        content: chunks.join('\n'),
        metadata: metadata,
        name: name,
      );
      await source_rag.updateSourceStatus(
        sourceId: source.sourceId,
        status: 'completed',
      );

      var cursor = 0;
      final chunkData = <source_rag.ChunkData>[];
      for (var i = 0; i < chunks.length; i++) {
        final content = chunks[i];
        chunkData.add(
          source_rag.ChunkData(
            content: content,
            chunkIndex: i,
            startPos: cursor,
            endPos: cursor + content.length,
            chunkType: i == 0 && name == 'guide'
                ? 'text|Guide > Setup'
                : 'general',
            embedding: embeddings[i],
          ),
        );
        cursor += content.length + 1;
      }

      await source_rag.addChunks(sourceId: source.sourceId, chunks: chunkData);
    }

    await seedSource(
      name: 'guide',
      metadata: '{"source":"guide"}',
      chunks: [
        'Install the package from the signed release archive before running the app.',
        'Verify the checksum and compare it with the release manifest.',
        'Configure the local model path after the package is installed.',
      ],
      embeddings: [
        Float32List.fromList([1.0, 0.0, 0.0, 0.0]),
        Float32List.fromList([0.95, 0.05, 0.0, 0.0]),
        Float32List.fromList([0.75, 0.15, 0.0, 0.0]),
      ],
    );
    await seedSource(
      name: 'smoke',
      metadata: '{"source":"smoke"}',
      chunks: [
        'Run the smoke test after installation and inspect the first query.',
        'Record the startup timing and search payload size for regression checks.',
        'Archive the debug log only when the test reports a failure.',
      ],
      embeddings: [
        Float32List.fromList([0.82, 0.18, 0.0, 0.0]),
        Float32List.fromList([0.68, 0.32, 0.0, 0.0]),
        Float32List.fromList([0.2, 0.8, 0.0, 0.0]),
      ],
    );

    await source_rag.rebuildChunkHnswIndexForCollection(
      collectionId: collectionId,
    );
    await source_rag.rebuildChunkBm25IndexForCollection(
      collectionId: collectionId,
    );

    QueryPayloadVariantStats variantStats({
      required String label,
      required double elapsedMs,
      required int hitCount,
      int metaBytes = 0,
      int contextBytes = 0,
      int fullChunkBytes = 0,
      int previewBytes = 0,
      query_metrics.QueryContentReadStats? nativeReadStats,
    }) {
      return _variantStatsFromNative(
        label: label,
        elapsedMs: elapsedMs,
        hitCount: hitCount,
        metaBytes: metaBytes,
        contextBytes: contextBytes,
        fullChunkBytes: fullChunkBytes,
        previewBytes: previewBytes,
        nativeReadStats: nativeReadStats,
      );
    }

    Future<QueryPayloadVariantStats> runLegacy() async {
      query_metrics.resetQueryContentReadStats();
      final sw = Stopwatch()..start();
      final results = await searchHybrid(
        queryText: queryText,
        queryEmbedding: queryEmbedding,
        topK: topK,
        config: const RrfConfig(k: 60, vectorWeight: 1.0, bm25Weight: 0.0),
        filter: const SearchFilter(collectionId: collectionId),
      );
      sw.stop();
      final nativeReadStats = query_metrics.takeQueryContentReadStats();

      final fullChunkBytes = results.fold<int>(
        0,
        (sum, result) =>
            sum +
            _utf8ByteLength(result.content) +
            _utf8ByteLength(result.metadata),
      );

      return variantStats(
        label: 'legacy searchHybrid',
        elapsedMs: sw.elapsedMicroseconds / 1000.0,
        hitCount: results.length,
        fullChunkBytes: fullChunkBytes,
        nativeReadStats: nativeReadStats,
      );
    }

    Future<QueryPayloadVariantStats> runHandleVariant(
      _QueryPayloadHydration hydration,
    ) async {
      source_rag.SearchHandle? handle;
      query_metrics.resetQueryContentReadStats();
      final sw = Stopwatch()..start();
      try {
        handle = await source_rag.searchMetaHybrid(
          collectionId: collectionId,
          queryText: queryText,
          queryEmbedding: queryEmbedding,
          options: source_rag.SearchMetaHybridOptions(
            topK: topK,
            vectorWeight: 1.0,
            bm25Weight: 0.0,
            adjacentChunks: adjacentChunks,
          ),
        );
        final hits = await handle.hitMeta();
        final metaBytes = hits.fold<int>(
          0,
          (sum, hit) =>
              sum +
              _utf8ByteLength(hit.rawType) +
              _utf8ByteLength(hit.headerPathPreview),
        );

        final assembled = await handle.assembleContext(
          options: source_rag.AssembleContextOptions(
            tokenBudget: tokenBudget,
            strategy: source_rag.ContextAssemblyStrategy.relevanceFirst,
            separator: '\n\n---\n\n',
            singleSourceMode: false,
          ),
        );
        final contextBytes = _utf8ByteLength(assembled.text);
        final hitIds = _toInt64List(
          hits.map((hit) => hit.chunkId.toInt()).toList(growable: false),
        );

        var fullChunkBytes = 0;
        var previewBytes = 0;
        switch (hydration) {
          case _QueryPayloadHydration.full:
            final chunks = await handle.hydrateChunks(chunkIds: hitIds);
            fullChunkBytes = chunks.fold<int>(
              0,
              (sum, chunk) =>
                  sum +
                  _utf8ByteLength(chunk.content) +
                  _utf8ByteLength(chunk.chunkType) +
                  _utf8ByteLength(chunk.metadata),
            );
            break;
          case _QueryPayloadHydration.preview:
            final excerpts = await handle.getChunkExcerpts(
              chunkIds: hitIds,
              maxBytes: previewMaxBytes,
            );
            previewBytes = excerpts.fold<int>(
              0,
              (sum, excerpt) =>
                  sum +
                  _utf8ByteLength(excerpt.rawType) +
                  _utf8ByteLength(excerpt.headerPathPreview) +
                  _utf8ByteLength(excerpt.excerpt),
            );
            break;
          case _QueryPayloadHydration.contextOnly:
            break;
        }
        sw.stop();
        final nativeReadStats = query_metrics.takeQueryContentReadStats();

        return variantStats(
          label: switch (hydration) {
            _QueryPayloadHydration.full => 'handle + full hydrate',
            _QueryPayloadHydration.preview => 'handle + preview excerpts',
            _QueryPayloadHydration.contextOnly => 'handle + context only',
          },
          elapsedMs: sw.elapsedMicroseconds / 1000.0,
          hitCount: hits.length,
          metaBytes: metaBytes,
          contextBytes: contextBytes,
          fullChunkBytes: fullChunkBytes,
          previewBytes: previewBytes,
          nativeReadStats: nativeReadStats,
        );
      } finally {
        if (handle != null) {
          await handle.dispose();
        }
      }
    }

    try {
      return QueryPayloadBenchResult(
        topK: topK,
        adjacentChunks: adjacentChunks,
        previewMaxBytes: previewMaxBytes,
        legacySearchHybrid: await runLegacy(),
        handleFull: await runHandleVariant(_QueryPayloadHydration.full),
        handlePreview: await runHandleVariant(_QueryPayloadHydration.preview),
        handleContextOnly: await runHandleVariant(
          _QueryPayloadHydration.contextOnly,
        ),
      );
    } finally {
      query_metrics.resetQueryContentReadStats();
      await closeDbPool();
      if (await benchFile.exists()) {
        await benchFile.delete();
      }
      if (await tokenizerFile.exists()) {
        await tokenizerFile.delete();
      }
      if (restoreDbPath != null) {
        await initDbPool(dbPath: restoreDbPath, maxSize: 4);
      }
    }
  }

  /// Measure the scoped exact-scan branch of `searchMetaHybrid`.
  ///
  /// Seeds one scoped source with [scopedChunkCount] chunks (each ~256 ASCII
  /// bytes) plus a distractor source so the post-filter path has work to do,
  /// then runs `searchMetaHybrid` with `sourceIds=[scopedSourceId]` across the
  /// supplied [bm25Weights]. Each variant captures `query_metrics`
  /// `scoped_exact_scan_*` counters before disposing the handle, so the caller
  /// can verify that scoped BM25 ranks are served from the active term index
  /// without query-time chunk-body reads or tokenization.
  ///
  /// Intentionally meta-only — no hydration, no assemble — so the recorded
  /// scoped-scan bytes are not blurred with `full_hydrate_*` materialization.
  static Future<ScopedExactScanBenchResult> benchmarkScopedExactScan({
    int scopedChunkCount = 50,
    int distractorChunkCount = 10,
    int topK = 4,
    int chunkContentChars = 256,
    List<double> bm25Weights = const [0.0, 0.5],
    String? restoreDbPath,
    String? dbPathOverride,
  }) async {
    const collectionId = 'bench-scoped-exact-scan';
    const queryText = 'install checksum smoke';
    final queryEmbedding = Float32List.fromList([1.0, 0.0, 0.0, 0.0]);

    final benchDbPath =
        dbPathOverride ??
        "${(await getApplicationDocumentsDirectory()).path}/scoped_exact_scan_bench.sqlite";
    final benchFile = File(benchDbPath);
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    final tokenizerFile = File('$benchDbPath.tokenizer.json');
    if (await tokenizerFile.exists()) {
      await tokenizerFile.delete();
    }

    await initDbPool(dbPath: benchDbPath, maxSize: 4);
    await initDb();
    await source_rag.initSourceDb();
    await tokenizerFile.writeAsString(
      '{"version":"1.0","truncation":null,"padding":null,'
      '"added_tokens":[],"normalizer":null,'
      '"pre_tokenizer":{"type":"Whitespace"},"post_processor":null,'
      '"decoder":null,"model":{"type":"WordLevel",'
      '"vocab":{"[UNK]":0,"install":1,"checksum":2,"smoke":3,"setup":4},'
      '"unk_token":"[UNK]"}}',
      flush: true,
    );
    await initTokenizer(tokenizerPath: tokenizerFile.path);

    String makeChunkContent(int seed) {
      const words = [
        'install',
        'checksum',
        'smoke',
        'setup',
        'verify',
        'archive',
        'manifest',
        'release',
        'config',
        'package',
      ];
      final buffer = StringBuffer();
      var i = seed;
      while (buffer.length < chunkContentChars) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(words[i % words.length]);
        i++;
      }
      return buffer.toString().substring(0, chunkContentChars);
    }

    Future<int> seedSource({
      required String name,
      required int chunkCount,
      required int seedBase,
    }) async {
      final source = await source_rag.addSourceInCollection(
        collectionId: collectionId,
        content: 'bench source $name',
        metadata: '{"source":"$name"}',
        name: name,
      );
      await source_rag.updateSourceStatus(
        sourceId: source.sourceId,
        status: 'completed',
      );
      var cursor = 0;
      final chunkData = <source_rag.ChunkData>[];
      for (var i = 0; i < chunkCount; i++) {
        final content = makeChunkContent(seedBase + i);
        chunkData.add(
          source_rag.ChunkData(
            content: content,
            chunkIndex: i,
            startPos: cursor,
            endPos: cursor + content.length,
            chunkType: 'general',
            embedding: Float32List.fromList([
              1.0 - (i % 16) * 0.01,
              (i % 16) * 0.01,
              0.0,
              0.0,
            ]),
          ),
        );
        cursor += content.length + 1;
      }
      await source_rag.addChunks(sourceId: source.sourceId, chunks: chunkData);
      return source.sourceId;
    }

    try {
      final scopedSourceId = await seedSource(
        name: 'scoped',
        chunkCount: scopedChunkCount,
        seedBase: 0,
      );
      await seedSource(
        name: 'distractor',
        chunkCount: distractorChunkCount,
        seedBase: 7,
      );
      await source_rag.rebuildChunkHnswIndexForCollection(
        collectionId: collectionId,
      );
      await source_rag.rebuildChunkBm25IndexForCollection(
        collectionId: collectionId,
      );

      final variants = <QueryPayloadVariantStats>[];
      for (final bm25Weight in bm25Weights) {
        source_rag.SearchHandle? handle;
        query_metrics.resetQueryContentReadStats();
        final sw = Stopwatch()..start();
        try {
          handle = await source_rag.searchMetaHybrid(
            collectionId: collectionId,
            queryText: queryText,
            queryEmbedding: queryEmbedding,
            options: source_rag.SearchMetaHybridOptions(
              topK: topK,
              vectorWeight: 1.0 - bm25Weight,
              bm25Weight: bm25Weight,
              sourceIds: _toInt64List([scopedSourceId]),
              adjacentChunks: 0,
            ),
          );
          final hits = await handle.hitMeta();
          sw.stop();
          final nativeReadStats = query_metrics.takeQueryContentReadStats();

          variants.add(
            _variantStatsFromNative(
              label:
                  'scoped exact scan (chunks=$scopedChunkCount, bm25=${bm25Weight.toStringAsFixed(2)})',
              elapsedMs: sw.elapsedMicroseconds / 1000.0,
              hitCount: hits.length,
              nativeReadStats: nativeReadStats,
            ),
          );
        } finally {
          if (handle != null) {
            await handle.dispose();
          }
        }
      }

      return ScopedExactScanBenchResult(
        scopedChunkCount: scopedChunkCount,
        distractorChunkCount: distractorChunkCount,
        chunkContentBytes: chunkContentChars,
        topK: topK,
        bm25Weights: List.unmodifiable(bm25Weights),
        variants: List.unmodifiable(variants),
      );
    } finally {
      query_metrics.resetQueryContentReadStats();
      await closeDbPool();
      if (await benchFile.exists()) {
        await benchFile.delete();
      }
      if (await tokenizerFile.exists()) {
        await tokenizerFile.delete();
      }
      if (restoreDbPath != null) {
        await initDbPool(dbPath: restoreDbPath, maxSize: 4);
      }
    }
  }

  /// Run full benchmark suite
  static Future<List<BenchmarkResult>> runFullBenchmark({
    required String dbPath,
    Function(String)? onProgress,
  }) async {
    final results = <BenchmarkResult>[];

    // Test data - English samples
    final shortText = "Apple is delicious";
    final mediumText =
        "Apples are red fruits rich in vitamins. Eating them daily is good for health.";
    final longText =
        "Apples belong to the rose family and are one of the most widely cultivated fruits in the world. "
        "They are rich in vitamin C and dietary fiber with many varieties. "
        "The skin contains many antioxidants, so eating with skin is recommended.";

    onProgress?.call("Starting tokenization benchmark...");

    // 1. Tokenization benchmark
    results.add(await benchmarkTokenize(shortText));
    results.add(await benchmarkTokenize(mediumText));
    results.add(await benchmarkTokenize(longText));

    onProgress?.call("Starting embedding benchmark...");

    // 2. Embedding benchmark
    results.add(await benchmarkEmbed(shortText));
    results.add(await benchmarkEmbed(mediumText));
    results.add(await benchmarkEmbed(longText));

    onProgress?.call("Batch embedding benchmark...");

    // 2.5 Batch embedding benchmark
    final batchTexts = [
      shortText,
      mediumText,
      longText,
      "Dogs are cute and loyal",
      "Cats are agile hunters",
      "Cars are fast vehicles",
      "Computers are convenient tools",
      "Paris is the capital of France",
      "The ocean is vast and blue",
      "Mountains are tall and majestic",
    ];

    // Sequential embedding (for comparison)
    results.add(
      await benchmark(
        'Sequential Embed (10 texts)',
        () async {
          for (final text in batchTexts) {
            await EmbeddingService.embed(text);
          }
        },
        iterations: 3,
        category: BenchmarkCategory.onnx,
      ),
    );

    // Batch embedding
    results.add(
      await benchmark(
        'Batch Embed (10 texts)',
        () async {
          await EmbeddingService.embedBatch(batchTexts, concurrency: 4);
        },
        iterations: 3,
        category: BenchmarkCategory.onnx,
      ),
    );

    onProgress?.call("Preparing search benchmark...");

    // 3. Search benchmark data preparation
    final testDbPath =
        "${(await getApplicationDocumentsDirectory()).path}/benchmark_db.sqlite";

    // Initialize pool with test DB
    await initDbPool(dbPath: testDbPath, maxSize: 5);
    await initDb();

    // Sample documents (20 texts x 5 = 100 documents)
    final sampleTexts = [
      "Apple is delicious",
      "Banana is yellow",
      "Orange is round",
      "Grape is sweet",
      "Watermelon is big",
      "Dog is cute",
      "Cat is agile",
      "Rabbit is fast",
      "Turtle is slow",
      "Monkey is smart",
      "Car is fast",
      "Bicycle is healthy",
      "Airplane flies in the sky",
      "Ship crosses the ocean",
      "Train arrives on time",
      "Computer is convenient",
      "Smartphone is essential",
      "Tablet is light",
      "Laptop is portable",
      "Desktop is powerful",
    ];

    // Create 100 documents (20 texts x 5 repeats)
    for (var i = 0; i < 5; i++) {
      for (final text in sampleTexts) {
        final emb = await EmbeddingService.embed(text);
        await addDocument(content: "$text ($i)", embedding: emb);
      }
    }

    // Rebuild HNSW index after adding documents
    await rebuildHnswIndex();

    onProgress?.call("Running search benchmark...");

    final queryEmb = await EmbeddingService.embed("fruit");

    // Search benchmark (100 documents)
    results.add(await benchmarkSearch(testDbPath, queryEmb, 100));

    // Hybrid Search benchmark
    results.add(
      await benchmarkHybridSearch(testDbPath, "fruit", queryEmb, 100),
    );

    // Cleanup
    await closeDbPool();
    await File(testDbPath).delete();

    // RESTORE main DB connection (Critical fix)
    // Re-initialize the global pool with the original app database path
    await initDbPool(dbPath: dbPath, maxSize: 4);

    onProgress?.call("Benchmark complete!");

    return results;
  }

  /// Measure FFI text-byte traffic for an `addDocument` ingest, comparing the
  /// legacy chain (addSourceInCollection + chunker + addChunks) against the
  /// IngestSession chain (prepareSourceIngestion + take_embedding_batch +
  /// commit_embeddings) on a deterministic document.
  ///
  /// Self-contained: spins up an isolated temp DB, runs both pipelines with
  /// stub embeddings (zeroed Float32List of [embeddingDim]) to keep the
  /// measurement focused on FFI text traffic (no ONNX cost, no GC noise),
  /// and tears everything down before returning.
  ///
  /// The caller is responsible for preserving whatever pool/DB state was
  /// active on entry — on success this function restores the original pool
  /// configuration; on failure the caller should reinitialise the pool.
  static Future<IngestFfiBenchResult> benchmarkIngestFfiTraffic({
    int targetBytes = 1 * 1024 * 1024,
    int embeddingDim = 384,
    int maxChunkChars = 1500,
    int overlapChars = 100,
    int batchSize = 16,
    String? restoreDbPath,
    String? dbPathOverride,
  }) async {
    final content = _generateBenchDoc(targetBytes);
    // ASCII-only doc generator → 1 byte per code unit, so length == UTF-8
    // byte count. If we ever switch to multilingual content, use utf8.encode.
    final docUtf8Bytes = content.length;

    final benchDbPath =
        dbPathOverride ??
        "${(await getApplicationDocumentsDirectory()).path}/ingest_ffi_bench.sqlite";
    final benchFile = File(benchDbPath);
    if (await benchFile.exists()) {
      await benchFile.delete();
    }

    await initDbPool(dbPath: benchDbPath, maxSize: 4);
    await initDb();
    await source_rag.initSourceDb();

    final stubEmbedding = Float32List(embeddingDim);

    // ---- Legacy chain ----------------------------------------------------
    ingest_metrics.resetIngestTrafficStats();
    final legacyEntry = await source_rag.addSourceInCollection(
      collectionId: 'bench-legacy',
      content: content,
      metadata: null,
      name: 'bench-legacy',
    );
    final legacySourceId = legacyEntry.sourceId;
    await source_rag.claimSourceForIngestion(sourceId: legacySourceId);
    final legacyChunks = semantic_chunker.semanticChunkWithOverlap(
      text: content,
      maxChars: maxChunkChars,
      overlapChars: overlapChars,
    );
    final legacyChunkData = legacyChunks
        .map(
          (c) => source_rag.ChunkData(
            content: c.content,
            chunkIndex: c.index,
            startPos: c.startPos,
            endPos: c.endPos,
            chunkType: c.chunkType,
            embedding: stubEmbedding,
          ),
        )
        .toList(growable: false);
    for (var offset = 0; offset < legacyChunkData.length; offset += batchSize) {
      final end = math.min(offset + batchSize, legacyChunkData.length);
      await source_rag.addChunks(
        sourceId: legacySourceId,
        chunks: legacyChunkData.sublist(offset, end),
      );
    }
    final legacyStats = ingest_metrics.ingestTrafficStats();
    await source_rag.deleteSourceInCollection(
      collectionId: 'bench-legacy',
      sourceId: legacySourceId,
    );

    // ---- IngestSession chain --------------------------------------------
    ingest_metrics.resetIngestTrafficStats();
    final prepared = await ingest_session.prepareSourceIngestion(
      collectionId: 'bench-session',
      content: content,
      metadata: null,
      name: 'bench-session',
      strategy: ingest_session.IngestStrategy.recursive,
      maxChars: maxChunkChars,
      overlapChars: overlapChars,
    );
    final session = prepared.session;
    if (session == null) {
      throw StateError(
        'benchmarkIngestFfiTraffic: prepareSourceIngestion returned no session '
        '(state=${prepared.state}); benchmark requires a fresh DB.',
      );
    }
    try {
      var saved = 0;
      while (saved < prepared.totalChunks) {
        final batch = await session.takeEmbeddingBatch(batchSize: batchSize);
        if (batch.isEmpty) break;
        final embeddings = batch
            .map(
              (req) => ingest_session.ChunkEmbedding(
                chunkIndex: req.chunkIndex,
                embedding: stubEmbedding,
              ),
            )
            .toList(growable: false);
        saved += await session.commitEmbeddings(embeddings: embeddings);
      }
      await session.finalize();
    } finally {
      await session.dispose();
    }
    final sessionStats = ingest_metrics.ingestTrafficStats();
    await source_rag.deleteSourceInCollection(
      collectionId: 'bench-session',
      sourceId: prepared.sourceId,
    );

    // ---- Teardown --------------------------------------------------------
    await closeDbPool();
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    if (restoreDbPath != null) {
      await initDbPool(dbPath: restoreDbPath, maxSize: 4);
    }

    return IngestFfiBenchResult(
      docBytes: docUtf8Bytes,
      chunkCount: legacyChunks.length,
      legacy: legacyStats,
      session: sessionStats,
    );
  }

  /// Measure FFI text-byte traffic across the three IngestSession entrypoints
  /// on a deterministic document: the canonical `prepareSourceIngestion`
  /// (Dart String), `prepareSourceIngestionFromUtf8` (bytes), and
  /// `prepareSourceIngestionFromFile` (path-only). Stub embeddings keep the
  /// measurement focused on FFI byte traffic.
  ///
  /// The body bytes never round-trip back through Dart on the file variant,
  /// so `session_prepare_content_in_bytes` should be 0 for it.
  static Future<IngestFfiEntrypointBenchResult> benchmarkIngestFfiEntrypoints({
    int targetBytes = 1 * 1024 * 1024,
    int embeddingDim = 384,
    int maxChunkChars = 1500,
    int overlapChars = 100,
    int batchSize = 16,
    String? restoreDbPath,
    String? dbPathOverride,
  }) async {
    final content = _generateBenchDoc(targetBytes);
    // ASCII-only doc: String length == UTF-8 byte count.
    final docUtf8Bytes = content.length;

    final benchDbPath =
        dbPathOverride ??
        "${(await getApplicationDocumentsDirectory()).path}/ingest_ffi_entrypoints_bench.sqlite";
    final benchFile = File(benchDbPath);
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    final benchTextFile = File('$benchDbPath.txt');
    if (await benchTextFile.exists()) {
      await benchTextFile.delete();
    }
    await benchTextFile.writeAsString(content, flush: true);

    await initDbPool(dbPath: benchDbPath, maxSize: 4);
    await initDb();
    await source_rag.initSourceDb();

    final stubEmbedding = Float32List(embeddingDim);

    Future<ingest_metrics.IngestTrafficStats> runOne(
      Future<ingest_session.PreparedIngestion> Function() prepare,
      String collectionId,
    ) async {
      ingest_metrics.resetIngestTrafficStats();
      final prepared = await prepare();
      final session = prepared.session;
      if (session == null) {
        throw StateError(
          'benchmarkIngestFfiEntrypoints: prepare returned no session '
          '(state=${prepared.state}); benchmark requires a fresh collection.',
        );
      }
      try {
        var saved = 0;
        while (saved < prepared.totalChunks) {
          final batch = await session.takeEmbeddingBatch(batchSize: batchSize);
          if (batch.isEmpty) break;
          final embeddings = batch
              .map(
                (req) => ingest_session.ChunkEmbedding(
                  chunkIndex: req.chunkIndex,
                  embedding: stubEmbedding,
                ),
              )
              .toList(growable: false);
          saved += await session.commitEmbeddings(embeddings: embeddings);
        }
        await session.finalize();
      } finally {
        await session.dispose();
      }
      final stats = ingest_metrics.ingestTrafficStats();
      await source_rag.deleteSourceInCollection(
        collectionId: collectionId,
        sourceId: prepared.sourceId,
      );
      return stats;
    }

    final stringStats = await runOne(
      () => ingest_session.prepareSourceIngestion(
        collectionId: 'bench-string',
        content: content,
        metadata: null,
        name: 'bench-string',
        strategy: ingest_session.IngestStrategy.recursive,
        maxChars: maxChunkChars,
        overlapChars: overlapChars,
      ),
      'bench-string',
    );

    final utf8Bytes = Uint8List.fromList(content.codeUnits);
    final utf8Stats = await runOne(
      () => ingest_session.prepareSourceIngestionFromUtf8(
        collectionId: 'bench-utf8',
        contentBytes: utf8Bytes,
        metadata: null,
        name: 'bench-utf8',
        strategy: ingest_session.IngestStrategy.recursive,
        maxChars: maxChunkChars,
        overlapChars: overlapChars,
      ),
      'bench-utf8',
    );

    final fileStats = await runOne(
      () => ingest_session.prepareSourceIngestionFromFile(
        collectionId: 'bench-file',
        filePath: benchTextFile.path,
        metadata: null,
        name: 'bench-file',
        strategyHint: ingest_session.IngestStrategy.recursive,
        maxChars: maxChunkChars,
        overlapChars: overlapChars,
      ),
      'bench-file',
    );

    await closeDbPool();
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    if (await benchTextFile.exists()) {
      await benchTextFile.delete();
    }
    if (restoreDbPath != null) {
      await initDbPool(dbPath: restoreDbPath, maxSize: 4);
    }

    return IngestFfiEntrypointBenchResult(
      docBytes: docUtf8Bytes,
      stringPath: stringStats,
      utf8Path: utf8Stats,
      filePath: fileStats,
    );
  }

  /// Measure peak process RSS during each ingest entrypoint variant on the
  /// realistic caller pattern:
  ///
  ///   - String path: caller does `readAsBytes` → `utf8.decode` → `addDocument`.
  ///   - UTF-8 path:  caller does `readAsBytes`              → `addDocumentUtf8`.
  ///   - File path:   caller passes the path only            → `addDocumentFromFile`.
  ///
  /// Each variant runs in isolation with a fresh DB collection. A 5 ms RSS
  /// sampler runs in parallel and tracks the peak observed during the
  /// operation. Reports `peak - baseline` per variant.
  ///
  /// Returns -1 deltas if [ProcessInfo.currentRss] is unsupported on the
  /// current platform.
  static Future<IngestHeapBenchResult> benchmarkIngestHeap({
    int targetBytes = 4 * 1024 * 1024,
    int embeddingDim = 384,
    int maxChunkChars = 1500,
    int overlapChars = 0,
    int batchSize = 16,
    String? restoreDbPath,
    String? dbPathOverride,
  }) async {
    if (ProcessInfo.currentRss < 0) {
      throw StateError(
        'benchmarkIngestHeap: ProcessInfo.currentRss is unsupported on this platform',
      );
    }

    final content = _generateBenchDoc(targetBytes);
    final docUtf8Bytes = content.length;

    final benchDbPath =
        dbPathOverride ??
        "${(await getApplicationDocumentsDirectory()).path}/ingest_heap_bench.sqlite";
    final benchFile = File(benchDbPath);
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    final benchTextFile = File('$benchDbPath.txt');
    if (await benchTextFile.exists()) {
      await benchTextFile.delete();
    }
    await benchTextFile.writeAsString(content, flush: true);

    await initDbPool(dbPath: benchDbPath, maxSize: 4);
    await initDb();
    await source_rag.initSourceDb();

    final stubEmbedding = Float32List(embeddingDim);

    Future<int> drainAndDelete(
      ingest_session.PreparedIngestion prepared,
      String collectionId,
    ) async {
      final session = prepared.session;
      if (session == null) {
        throw StateError(
          'benchmarkIngestHeap: prepare returned no session '
          '(state=${prepared.state}); benchmark requires a fresh collection.',
        );
      }
      try {
        var saved = 0;
        while (saved < prepared.totalChunks) {
          final batch = await session.takeEmbeddingBatch(batchSize: batchSize);
          if (batch.isEmpty) break;
          final embeddings = batch
              .map(
                (req) => ingest_session.ChunkEmbedding(
                  chunkIndex: req.chunkIndex,
                  embedding: stubEmbedding,
                ),
              )
              .toList(growable: false);
          saved += await session.commitEmbeddings(embeddings: embeddings);
        }
        await session.finalize();
      } finally {
        await session.dispose();
      }
      await source_rag.deleteSourceInCollection(
        collectionId: collectionId,
        sourceId: prepared.sourceId,
      );
      return prepared.totalChunks;
    }

    Future<int> measureVariant(Future<void> Function() runVariant) async {
      // Two-phase: baseline (let any prior GC settle), then sample peak
      // during the variant. 5 ms cadence is fast enough to catch the
      // body-allocation spike for a multi-MB doc.
      await Future.delayed(const Duration(milliseconds: 50));
      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      final stopwatch = Stopwatch()..start();
      final sampler = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final r = ProcessInfo.currentRss;
        if (r > peak) peak = r;
      });
      try {
        await runVariant();
      } finally {
        sampler.cancel();
        stopwatch.stop();
        final r = ProcessInfo.currentRss;
        if (r > peak) peak = r;
      }
      return peak - baseline;
    }

    final stringDelta = await measureVariant(() async {
      final bytes = await benchTextFile.readAsBytes();
      // Caller-side String materialization — this is what from_utf8 / from_file avoid.
      final s = utf8.decode(bytes);
      final prepared = await ingest_session.prepareSourceIngestion(
        collectionId: 'bench-heap-string',
        content: s,
        metadata: null,
        name: 'bench-heap-string',
        strategy: ingest_session.IngestStrategy.recursive,
        maxChars: maxChunkChars,
        overlapChars: overlapChars,
      );
      await drainAndDelete(prepared, 'bench-heap-string');
    });

    final utf8Delta = await measureVariant(() async {
      final bytes = await benchTextFile.readAsBytes();
      final prepared = await ingest_session.prepareSourceIngestionFromUtf8(
        collectionId: 'bench-heap-utf8',
        contentBytes: bytes,
        metadata: null,
        name: 'bench-heap-utf8',
        strategy: ingest_session.IngestStrategy.recursive,
        maxChars: maxChunkChars,
        overlapChars: overlapChars,
      );
      await drainAndDelete(prepared, 'bench-heap-utf8');
    });

    final fileDelta = await measureVariant(() async {
      final prepared = await ingest_session.prepareSourceIngestionFromFile(
        collectionId: 'bench-heap-file',
        filePath: benchTextFile.path,
        metadata: null,
        name: 'bench-heap-file',
        strategyHint: ingest_session.IngestStrategy.recursive,
        maxChars: maxChunkChars,
        overlapChars: overlapChars,
      );
      await drainAndDelete(prepared, 'bench-heap-file');
    });

    await closeDbPool();
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    if (await benchTextFile.exists()) {
      await benchTextFile.delete();
    }
    if (restoreDbPath != null) {
      await initDbPool(dbPath: restoreDbPath, maxSize: 4);
    }

    return IngestHeapBenchResult(
      docBytes: docUtf8Bytes,
      stringPathPeakDeltaBytes: stringDelta,
      utf8PathPeakDeltaBytes: utf8Delta,
      filePathPeakDeltaBytes: fileDelta,
    );
  }

  /// Measure wall-clock latency of the full prepare → drain → finalize →
  /// delete cycle across the three ingest entrypoint variants. Stub
  /// embeddings (zeroed [Float32List]) keep the measurement focused on the
  /// FFI + Rust pipeline cost rather than ONNX inference time.
  ///
  /// Each variant runs [warmupRuns] warmup iterations followed by
  /// [measuredRuns] measured iterations. Reports p50 / p95 / mean / stdev
  /// in milliseconds per variant.
  static Future<IngestLatencyBenchResult> benchmarkIngestLatency({
    int targetBytes = 1 * 1024 * 1024,
    int embeddingDim = 384,
    int maxChunkChars = 1500,
    int overlapChars = 0,
    int batchSize = 16,
    int warmupRuns = 2,
    int measuredRuns = 5,
    String? restoreDbPath,
    String? dbPathOverride,
  }) async {
    final content = _generateBenchDoc(targetBytes);
    final docUtf8Bytes = content.length;

    final benchDbPath =
        dbPathOverride ??
        "${(await getApplicationDocumentsDirectory()).path}/ingest_latency_bench.sqlite";
    final benchFile = File(benchDbPath);
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    final benchTextFile = File('$benchDbPath.txt');
    if (await benchTextFile.exists()) {
      await benchTextFile.delete();
    }
    await benchTextFile.writeAsString(content, flush: true);

    await initDbPool(dbPath: benchDbPath, maxSize: 4);
    await initDb();
    await source_rag.initSourceDb();

    final stubEmbedding = Float32List(embeddingDim);
    final contentBytes = Uint8List.fromList(content.codeUnits);

    Future<double> runOnce(_LatencyVariant variant, int iteration) async {
      final collectionId = 'bench-latency-${variant.name}-$iteration';
      final sw = Stopwatch()..start();
      late ingest_session.PreparedIngestion prepared;
      switch (variant) {
        case _LatencyVariant.string:
          prepared = await ingest_session.prepareSourceIngestion(
            collectionId: collectionId,
            content: content,
            metadata: null,
            name: collectionId,
            strategy: ingest_session.IngestStrategy.recursive,
            maxChars: maxChunkChars,
            overlapChars: overlapChars,
          );
          break;
        case _LatencyVariant.utf8:
          prepared = await ingest_session.prepareSourceIngestionFromUtf8(
            collectionId: collectionId,
            contentBytes: contentBytes,
            metadata: null,
            name: collectionId,
            strategy: ingest_session.IngestStrategy.recursive,
            maxChars: maxChunkChars,
            overlapChars: overlapChars,
          );
          break;
        case _LatencyVariant.file:
          prepared = await ingest_session.prepareSourceIngestionFromFile(
            collectionId: collectionId,
            filePath: benchTextFile.path,
            metadata: null,
            name: collectionId,
            strategyHint: ingest_session.IngestStrategy.recursive,
            maxChars: maxChunkChars,
            overlapChars: overlapChars,
          );
          break;
      }
      final session = prepared.session;
      if (session == null) {
        throw StateError(
          'benchmarkIngestLatency: prepare returned no session for variant '
          '${variant.name} (state=${prepared.state}).',
        );
      }
      try {
        var saved = 0;
        while (saved < prepared.totalChunks) {
          final batch = await session.takeEmbeddingBatch(batchSize: batchSize);
          if (batch.isEmpty) break;
          final embeddings = batch
              .map(
                (req) => ingest_session.ChunkEmbedding(
                  chunkIndex: req.chunkIndex,
                  embedding: stubEmbedding,
                ),
              )
              .toList(growable: false);
          saved += await session.commitEmbeddings(embeddings: embeddings);
        }
        await session.finalize();
      } finally {
        await session.dispose();
      }
      sw.stop();
      await source_rag.deleteSourceInCollection(
        collectionId: collectionId,
        sourceId: prepared.sourceId,
      );
      return sw.elapsedMicroseconds / 1000.0;
    }

    Future<IngestLatencyStats> measureVariant(_LatencyVariant variant) async {
      for (var i = 0; i < warmupRuns; i++) {
        await runOnce(variant, -1 - i);
      }
      final samples = <double>[];
      for (var i = 0; i < measuredRuns; i++) {
        samples.add(await runOnce(variant, i));
      }
      samples.sort();
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      return IngestLatencyStats(
        p50Ms: _percentileFromSorted(samples, 0.5),
        p95Ms: _percentileFromSorted(samples, 0.95),
        meanMs: mean,
        stdevMs: _stdDev(samples, mean),
        samples: List.unmodifiable(samples),
      );
    }

    final stringStats = await measureVariant(_LatencyVariant.string);
    final utf8Stats = await measureVariant(_LatencyVariant.utf8);
    final fileStats = await measureVariant(_LatencyVariant.file);

    await closeDbPool();
    if (await benchFile.exists()) {
      await benchFile.delete();
    }
    if (await benchTextFile.exists()) {
      await benchTextFile.delete();
    }
    if (restoreDbPath != null) {
      await initDbPool(dbPath: restoreDbPath, maxSize: 4);
    }

    return IngestLatencyBenchResult(
      docBytes: docUtf8Bytes,
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      stringPath: stringStats,
      utf8Path: utf8Stats,
      filePath: fileStats,
    );
  }

  /// Builds a deterministic ASCII document of roughly [targetBytes] bytes by
  /// repeating a paragraph fixture. ASCII-only so `String.length` == UTF-8
  /// byte count.
  static String _generateBenchDoc(int targetBytes) {
    const fixture =
        'The quick brown fox jumps over the lazy dog. Pack my box with five '
        'dozen liquor jugs. How vexingly quick daft zebras jump! Sphinx of '
        'black quartz, judge my vow. The five boxing wizards jump quickly.\n\n';
    final buffer = StringBuffer();
    while (buffer.length < targetBytes) {
      buffer.write(fixture);
    }
    return buffer.toString();
  }
}

/// Result of [BenchmarkService.benchmarkIngestFfiTraffic].
///
/// Each entry in [legacy] and [session] is a cumulative byte/call count from
/// the corresponding Rust counter. The two `*TextTraffic` totals are the
/// sum of all text-body FFI traffic across the chain (excluding embedding
/// vector traffic, which is tracked separately for transparency).
class IngestFfiBenchResult {
  /// Document size in UTF-8 bytes.
  final int docBytes;

  /// Number of chunks the document was split into.
  final int chunkCount;

  /// Counter snapshot taken immediately after the legacy chain finished.
  final ingest_metrics.IngestTrafficStats legacy;

  /// Counter snapshot taken immediately after the IngestSession chain finished.
  final ingest_metrics.IngestTrafficStats session;

  const IngestFfiBenchResult({
    required this.docBytes,
    required this.chunkCount,
    required this.legacy,
    required this.session,
  });

  int get legacyTextTrafficBytes =>
      (legacy.legacyAddSourceInBytes +
              legacy.legacyChunkerTextInBytes +
              legacy.legacyChunkerChunksOutBytes +
              legacy.legacyAddChunksInBytes)
          .toInt();

  int get sessionTextTrafficBytes =>
      (session.sessionPrepareContentInBytes +
              session.sessionEmbeddingTextOutBytes)
          .toInt();

  double get legacyMultiple => legacyTextTrafficBytes / docBytes;
  double get sessionMultiple => sessionTextTrafficBytes / docBytes;
  double get reductionRatio => sessionTextTrafficBytes / legacyTextTrafficBytes;

  /// Pretty-print a single-block summary of the comparison.
  String renderSummary() {
    String fmt(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';
    return [
      'Ingest FFI traffic ($docBytes B doc → $chunkCount chunks):',
      '  Legacy chain:  ${fmt(legacyTextTrafficBytes)}'
          ' (${legacyMultiple.toStringAsFixed(2)}× document)',
      '    add_source_in_collection:    ${fmt(legacy.legacyAddSourceInBytes.toInt())}',
      '    chunker text in:             ${fmt(legacy.legacyChunkerTextInBytes.toInt())}',
      '    chunker chunks out:          ${fmt(legacy.legacyChunkerChunksOutBytes.toInt())}',
      '    add_chunks:                  ${fmt(legacy.legacyAddChunksInBytes.toInt())}',
      '  IngestSession chain: ${fmt(sessionTextTrafficBytes)}'
          ' (${sessionMultiple.toStringAsFixed(2)}× document)',
      '    prepare content in:          ${fmt(session.sessionPrepareContentInBytes.toInt())}',
      '    take_embedding_batch out:    ${fmt(session.sessionEmbeddingTextOutBytes.toInt())}',
      '  Reduction: ${((1 - reductionRatio) * 100).toStringAsFixed(1)}%'
          ' (session / legacy = ${reductionRatio.toStringAsFixed(2)})',
    ].join('\n');
  }
}

/// Result of [BenchmarkService.benchmarkIngestFfiEntrypoints].
///
/// Each `*Path` field is the counter snapshot taken immediately after that
/// entrypoint variant ran. Tests compare per-variant
/// `session_prepare_content_in_bytes` against `docBytes` to verify the
/// pass-through claim of [ingest_session.prepareSourceIngestionFromUtf8] and
/// [ingest_session.prepareSourceIngestionFromFile].
class IngestFfiEntrypointBenchResult {
  /// Document size in UTF-8 bytes.
  final int docBytes;

  /// Counter snapshot for the canonical String entrypoint.
  final ingest_metrics.IngestTrafficStats stringPath;

  /// Counter snapshot for the UTF-8 bytes entrypoint.
  final ingest_metrics.IngestTrafficStats utf8Path;

  /// Counter snapshot for the file-path entrypoint.
  final ingest_metrics.IngestTrafficStats filePath;

  const IngestFfiEntrypointBenchResult({
    required this.docBytes,
    required this.stringPath,
    required this.utf8Path,
    required this.filePath,
  });

  int get stringPrepareInBytes =>
      stringPath.sessionPrepareContentInBytes.toInt();
  int get utf8PrepareInBytes => utf8Path.sessionPrepareContentInBytes.toInt();
  int get filePrepareInBytes => filePath.sessionPrepareContentInBytes.toInt();

  String renderSummary() {
    String fmt(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';
    return [
      'Ingest FFI entrypoint comparison ($docBytes B doc):',
      '  prepareSourceIngestion(String):   prepare_in=${fmt(stringPrepareInBytes)}',
      '  prepareSourceIngestionFromUtf8:   prepare_in=${fmt(utf8PrepareInBytes)}',
      '  prepareSourceIngestionFromFile:   prepare_in=${fmt(filePrepareInBytes)}',
    ].join('\n');
  }
}

/// Result of [BenchmarkService.benchmarkIngestHeap].
///
/// Each `*PeakDeltaBytes` field is `peak_rss - baseline_rss` in bytes
/// observed during that variant's run, with a 5 ms sampler. Useful for
/// confirming the empirical "from_file holds no Dart-side body" claim.
///
/// Caveats: full-process RSS is noisy and includes Rust + ONNX + framework
/// allocations. Use the relative ordering and approximate magnitude, not
/// absolute numbers.
class IngestHeapBenchResult {
  /// Document size in UTF-8 bytes.
  final int docBytes;

  /// peak_rss − baseline_rss for `prepareSourceIngestion(String)` path (the
  /// caller reads bytes then `utf8.decode`s into a Dart `String`).
  final int stringPathPeakDeltaBytes;

  /// peak_rss − baseline_rss for `prepareSourceIngestionFromUtf8`.
  final int utf8PathPeakDeltaBytes;

  /// peak_rss − baseline_rss for `prepareSourceIngestionFromFile`. The
  /// caller never holds the body; the only Dart-side memory it pays for is
  /// the path string.
  final int filePathPeakDeltaBytes;

  const IngestHeapBenchResult({
    required this.docBytes,
    required this.stringPathPeakDeltaBytes,
    required this.utf8PathPeakDeltaBytes,
    required this.filePathPeakDeltaBytes,
  });

  String renderSummary() {
    String fmt(int bytes) {
      final kb = bytes / 1024;
      if (kb.abs() >= 1024) {
        return '${(kb / 1024).toStringAsFixed(2)} MB';
      }
      return '${kb.toStringAsFixed(1)} KB';
    }

    return [
      'Ingest peak-RSS delta ($docBytes B doc, baseline-subtracted):',
      '  prepareSourceIngestion(String):   peak_delta=${fmt(stringPathPeakDeltaBytes)}',
      '  prepareSourceIngestionFromUtf8:   peak_delta=${fmt(utf8PathPeakDeltaBytes)}',
      '  prepareSourceIngestionFromFile:   peak_delta=${fmt(filePathPeakDeltaBytes)}',
    ].join('\n');
  }
}

enum _LatencyVariant { string, utf8, file }

class IngestLatencyStats {
  final double p50Ms;
  final double p95Ms;
  final double meanMs;
  final double stdevMs;
  final List<double> samples;
  const IngestLatencyStats({
    required this.p50Ms,
    required this.p95Ms,
    required this.meanMs,
    required this.stdevMs,
    required this.samples,
  });
}

/// Result of [BenchmarkService.benchmarkIngestLatency].
///
/// Wall-clock ms for the full prepare → drain → finalize → delete cycle of
/// each variant. Stub embeddings (zeroed [Float32List]) keep the
/// measurement focused on FFI + Rust pipeline cost rather than ONNX time.
class IngestLatencyBenchResult {
  /// Document size in UTF-8 bytes.
  final int docBytes;

  /// Number of warmup iterations excluded from stats.
  final int warmupRuns;

  /// Number of measured iterations that fed the stats.
  final int measuredRuns;

  final IngestLatencyStats stringPath;
  final IngestLatencyStats utf8Path;
  final IngestLatencyStats filePath;

  const IngestLatencyBenchResult({
    required this.docBytes,
    required this.warmupRuns,
    required this.measuredRuns,
    required this.stringPath,
    required this.utf8Path,
    required this.filePath,
  });

  double get stringP50Ms => stringPath.p50Ms;
  double get utf8P50Ms => utf8Path.p50Ms;
  double get fileP50Ms => filePath.p50Ms;

  double get stringP95Ms => stringPath.p95Ms;
  double get utf8P95Ms => utf8Path.p95Ms;
  double get fileP95Ms => filePath.p95Ms;

  String renderSummary() {
    String row(String label, IngestLatencyStats s) =>
        '  $label  p50=${s.p50Ms.toStringAsFixed(2)}ms  '
        'p95=${s.p95Ms.toStringAsFixed(2)}ms  '
        'mean=${s.meanMs.toStringAsFixed(2)}ms  '
        '±${s.stdevMs.toStringAsFixed(2)}ms';
    return [
      'Ingest latency ($docBytes B doc, warmup=$warmupRuns, measured=$measuredRuns):',
      row('prepareSourceIngestion(String):  ', stringPath),
      row('prepareSourceIngestionFromUtf8:  ', utf8Path),
      row('prepareSourceIngestionFromFile:  ', filePath),
    ].join('\n');
  }
}

enum _QueryPayloadHydration { full, preview, contextOnly }

/// Result of [BenchmarkService.benchmarkScopedExactScan].
///
/// Captures the scoped exact-scan branch of `searchMetaHybrid`: whether
/// `source_ids` queries read or tokenize chunk bodies while preserving BM25
/// ranks from the active term index across the supplied `bm25Weights`.
class ScopedExactScanBenchResult {
  /// Number of chunks under the scoped `source_ids` filter.
  final int scopedChunkCount;

  /// Number of chunks on a distractor source kept outside the filter — exists
  /// purely so the scoped filter has something to exclude.
  final int distractorChunkCount;

  /// Approximate UTF-8 byte length of each chunk body.
  final int chunkContentBytes;

  /// `topK` requested per variant.
  final int topK;

  /// BM25 weights iterated, one entry per [variants].
  final List<double> bm25Weights;

  /// Captured stats per BM25 weight (aligned with [bm25Weights]).
  final List<QueryPayloadVariantStats> variants;

  const ScopedExactScanBenchResult({
    required this.scopedChunkCount,
    required this.distractorChunkCount,
    required this.chunkContentBytes,
    required this.topK,
    required this.bm25Weights,
    required this.variants,
  });

  String renderSummary() {
    return [
      'Scoped exact-scan indexed-BM25 check (scoped_chunks=$scopedChunkCount, '
          'distractor=$distractorChunkCount, '
          'chunk_body≈${chunkContentBytes}B, topK=$topK):',
      for (final v in variants) v.renderSummary(),
    ].join('\n');
  }
}

/// Result of [BenchmarkService.benchmarkQueryPayload].
///
/// This is a query-path baseline: it counts UTF-8 bytes of strings surfaced to
/// Dart by each search shape, plus native lower-bound content rows/bytes read
/// by the current query path. It does not try to account for allocator copies
/// or FFI serialization overhead.
class QueryPayloadBenchResult {
  final int topK;
  final int adjacentChunks;
  final int previewMaxBytes;
  final QueryPayloadVariantStats legacySearchHybrid;
  final QueryPayloadVariantStats handleFull;
  final QueryPayloadVariantStats handlePreview;
  final QueryPayloadVariantStats handleContextOnly;

  const QueryPayloadBenchResult({
    required this.topK,
    required this.adjacentChunks,
    required this.previewMaxBytes,
    required this.legacySearchHybrid,
    required this.handleFull,
    required this.handlePreview,
    required this.handleContextOnly,
  });

  String renderSummary() {
    return [
      'Query payload baseline (topK=$topK, adjacent=$adjacentChunks, previewMaxBytes=$previewMaxBytes):',
      legacySearchHybrid.renderSummary(),
      handleFull.renderSummary(),
      handlePreview.renderSummary(),
      handleContextOnly.renderSummary(),
    ].join('\n');
  }
}

class QueryPayloadVariantStats {
  final String label;
  final double elapsedMs;
  final int hitCount;

  /// Metadata-style strings surfaced to Dart, such as chunk type, header
  /// preview, or source metadata.
  final int metaBytes;

  /// Assembled LLM context text surfaced to Dart.
  final int contextBytes;

  /// Full chunk body strings surfaced to Dart.
  final int fullChunkBytes;

  /// Preview/excerpt strings surfaced to Dart instead of full chunk bodies.
  final int previewBytes;

  /// Native content rows/bytes read while materializing legacy
  /// `HybridSearchResult.content`.
  final int nativeHybridResultRows;
  final int nativeHybridResultContentBytes;

  /// Native content rows/bytes read by `SearchHandle.hydrateChunks`.
  final int nativeFullHydrateRows;
  final int nativeFullHydrateContentBytes;

  /// Native content rows/bytes read by `SearchHandle.getChunkExcerpts`.
  final int nativePreviewRows;
  final int nativePreviewContentBytes;

  /// Native content rows/bytes read while assembling context.
  final int nativeAssemblyRows;
  final int nativeAssemblyContentBytes;

  /// Native hydration reads that escaped phase classification.
  final int nativeUnclassifiedRows;
  final int nativeUnclassifiedContentBytes;

  /// Native rows/bytes the hybrid-search scoped exact-scan path read while
  /// walking the full scoped chunk set (source_ids / metadata_like branch).
  /// Disjoint from the materialization counters above — counts backend scan
  /// work, not result hydration.
  final int nativeScopedExactScanRows;
  final int nativeScopedExactScanContentBytes;
  final int nativeScopedExactScanTokenizedRows;
  final int nativeScopedExactScanTokenizedContentBytes;
  final int nativeScopedExactScanTokens;
  final int nativeScopedExactScanTokenizationNanos;

  const QueryPayloadVariantStats({
    required this.label,
    required this.elapsedMs,
    required this.hitCount,
    required this.metaBytes,
    required this.contextBytes,
    required this.fullChunkBytes,
    required this.previewBytes,
    required this.nativeHybridResultRows,
    required this.nativeHybridResultContentBytes,
    required this.nativeFullHydrateRows,
    required this.nativeFullHydrateContentBytes,
    required this.nativePreviewRows,
    required this.nativePreviewContentBytes,
    required this.nativeAssemblyRows,
    required this.nativeAssemblyContentBytes,
    required this.nativeUnclassifiedRows,
    required this.nativeUnclassifiedContentBytes,
    required this.nativeScopedExactScanRows,
    required this.nativeScopedExactScanContentBytes,
    required this.nativeScopedExactScanTokenizedRows,
    required this.nativeScopedExactScanTokenizedContentBytes,
    required this.nativeScopedExactScanTokens,
    required this.nativeScopedExactScanTokenizationNanos,
  });

  int get totalStringBytes =>
      metaBytes + contextBytes + fullChunkBytes + previewBytes;

  int get bodyLikeBytes => contextBytes + fullChunkBytes + previewBytes;

  int get nativeRowsRead =>
      nativeHybridResultRows +
      nativeFullHydrateRows +
      nativePreviewRows +
      nativeAssemblyRows +
      nativeUnclassifiedRows;

  int get nativeContentBytesRead =>
      nativeHybridResultContentBytes +
      nativeFullHydrateContentBytes +
      nativePreviewContentBytes +
      nativeAssemblyContentBytes +
      nativeUnclassifiedContentBytes;

  double get nativeScopedExactScanTokenizationMs =>
      nativeScopedExactScanTokenizationNanos / 1000000.0;

  String renderSummary() {
    String fmt(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';
    return [
      '  $label: hits=$hitCount elapsed=${elapsedMs.toStringAsFixed(2)}ms '
          'total=${fmt(totalStringBytes)} body_like=${fmt(bodyLikeBytes)}',
      '    meta=${fmt(metaBytes)} context=${fmt(contextBytes)} '
          'full_chunks=${fmt(fullChunkBytes)} preview=${fmt(previewBytes)}',
      '    native_read rows=$nativeRowsRead bytes=${fmt(nativeContentBytesRead)} '
          'hybrid=${fmt(nativeHybridResultContentBytes)} '
          'assembly=${fmt(nativeAssemblyContentBytes)} '
          'full=${fmt(nativeFullHydrateContentBytes)} '
          'preview=${fmt(nativePreviewContentBytes)} '
          'unclassified=${fmt(nativeUnclassifiedContentBytes)}',
      '    scoped_exact_scan rows=$nativeScopedExactScanRows '
          'bytes=${fmt(nativeScopedExactScanContentBytes)} '
          'tokenized_rows=$nativeScopedExactScanTokenizedRows '
          'tokenized_bytes=${fmt(nativeScopedExactScanTokenizedContentBytes)} '
          'tokens=$nativeScopedExactScanTokens '
          'tokenize=${nativeScopedExactScanTokenizationMs.toStringAsFixed(3)}ms',
    ].join('\n');
  }
}
