// lib/models/benchmark_models.dart

/// Benchmark category for grouping results
enum BenchmarkCategory {
  /// Rust-powered operations (tokenization, HNSW search)
  rust,

  /// ONNX Runtime operations (embedding generation)
  onnx,
}

/// Benchmark result data class
class BenchmarkResult {
  final String name;
  final double avgMs;
  final double minMs;
  final double maxMs;
  final int iterations;
  final BenchmarkCategory category;

  BenchmarkResult({
    required this.name,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.iterations,
    required this.category,
  });

  @override
  String toString() =>
      '$name: avg=${avgMs.toStringAsFixed(2)}ms, '
      'min=${minMs.toStringAsFixed(2)}ms, max=${maxMs.toStringAsFixed(2)}ms '
      '($iterations runs)';
}

/// Detailed benchmark statistics for reproducible validation.
class DetailedBenchmarkStats {
  final int warmupIterations;
  final int measuredIterations;
  final List<double> samplesMs;
  final double avgMs;
  final double minMs;
  final double maxMs;
  final double p50Ms;
  final double p95Ms;
  final double stdDevMs;

  DetailedBenchmarkStats({
    required this.warmupIterations,
    required this.measuredIterations,
    required this.samplesMs,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.stdDevMs,
  });

  Map<String, dynamic> toJson() => {
    'warmup_iterations': warmupIterations,
    'measured_iterations': measuredIterations,
    'samples_ms': samplesMs,
    'avg_ms': avgMs,
    'min_ms': minMs,
    'max_ms': maxMs,
    'p50_ms': p50Ms,
    'p95_ms': p95Ms,
    'stddev_ms': stdDevMs,
  };
}
