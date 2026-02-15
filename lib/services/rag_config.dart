/// Configuration for RagEngine initialization.
///
/// Use [RagConfig.fromAssets] for convenient asset-based configuration:
///
/// ```dart
/// final config = RagConfig.fromAssets(
///   tokenizerAsset: 'assets/tokenizer.json',
///   modelAsset: 'assets/model.onnx',
/// );
/// ```
library;

/// Thread usage level for ONNX runtime.
///
/// Controls how many CPU threads are used for embedding operations.
/// - [low]: ~20% of cores. Good for background tasks or low power.
/// - [medium]: ~40% of cores. Balanced performance.
/// - [high]: ~80% of cores. Maximum performance for heavy tasks.
enum ThreadUseLevel { low, medium, high }

/// Configuration options for RagEngine initialization.
class RagConfig {
  /// Asset path for tokenizer JSON file.
  ///
  /// Example: `'assets/tokenizer.json'`
  final String tokenizerAsset;

  /// Asset path for ONNX embedding model.
  ///
  /// Example: `'assets/model.onnx'`
  final String modelAsset;

  /// Name of the SQLite database file.
  ///
  /// If null, defaults to `'rag.sqlite'`.
  /// The file will be created in the app's documents directory.
  ///
  /// Both `.sqlite` and `.db` extensions work (e.g., `'rag.sqlite'` or `'rag.db'`).
  final String? databaseName;

  /// Maximum characters per chunk (default: 500).
  final int maxChunkChars;

  /// Overlap characters between chunks for context continuity (default: 50).
  final int overlapChars;

  /// Maximum number of threads for intra-op parallelism in ONNX runtime.
  ///
  /// If [threadLevel] is set, this value is ignored.
  ///
  /// Set this to a small number (e.g., 1 or 2) to reduce CPU usage and heat
  /// on mobile devices, at the cost of slower embedding speed.
  /// If both are null, defaults to ~50% of available cores.
  final int? embeddingIntraOpNumThreads;

  /// High-level thread usage configuration.
  ///
  /// If specified, this takes precedence over [embeddingIntraOpNumThreads].
  final ThreadUseLevel? threadLevel;

  /// Whether to defer index warmup during initialization.
  ///
  /// If true, [RagEngine.initialize] returns after DB setup and starts
  /// BM25/HNSW warmup in background. UI can render faster on low-end devices.
  ///
  /// Search quality should be gated by [RagEngine.isIndexReady] or
  /// awaiting [RagEngine.warmupFuture].
  final bool deferIndexWarmup;

  /// Creates a RagConfig with all options.
  const RagConfig({
    required this.tokenizerAsset,
    required this.modelAsset,
    this.databaseName,
    this.maxChunkChars = 500,
    this.overlapChars = 50,
    this.embeddingIntraOpNumThreads,
    this.threadLevel,
    this.deferIndexWarmup = false,
  }) : assert(
         embeddingIntraOpNumThreads == null || threadLevel == null,
         'Cannot set both [embeddingIntraOpNumThreads] and [threadLevel]. Choose one.',
       );

  /// Convenience factory for asset-based initialization.
  ///
  /// ```dart
  /// final config = RagConfig.fromAssets(
  ///   tokenizerAsset: 'assets/tokenizer.json',
  ///   modelAsset: 'assets/model.onnx',
  ///   databaseName: 'my_rag.sqlite', // optional
  ///   threadLevel: ThreadUseLevel.medium, // optional
  /// );
  /// ```
  factory RagConfig.fromAssets({
    required String tokenizerAsset,
    required String modelAsset,
    String? databaseName,
    int maxChunkChars = 500,
    int overlapChars = 50,
    int? embeddingIntraOpNumThreads,
    ThreadUseLevel? threadLevel,
    bool deferIndexWarmup = false,
  }) => RagConfig(
    tokenizerAsset: tokenizerAsset,
    modelAsset: modelAsset,
    databaseName: databaseName,
    maxChunkChars: maxChunkChars,
    overlapChars: overlapChars,
    embeddingIntraOpNumThreads: embeddingIntraOpNumThreads,
    threadLevel: threadLevel,
    deferIndexWarmup: deferIndexWarmup,
  );
}
