// lib/services/benchmark_service.dart
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/hybrid_search.dart';
import 'package:mobile_rag_engine/src/rust/api/ingest_metrics.dart' as ingest_metrics;
import 'package:mobile_rag_engine/src/rust/api/ingest_session.dart' as ingest_session;
import 'package:mobile_rag_engine/src/rust/api/semantic_chunker.dart' as semantic_chunker;
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as source_rag;
import 'package:path_provider/path_provider.dart';
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

    final benchDbPath = dbPathOverride ??
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
  static Future<IngestFfiEntrypointBenchResult>
      benchmarkIngestFfiEntrypoints({
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

    final benchDbPath = dbPathOverride ??
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
