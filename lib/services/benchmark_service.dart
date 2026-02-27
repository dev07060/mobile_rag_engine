// lib/services/benchmark_service.dart
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/hybrid_search.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math' as math;

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
}
