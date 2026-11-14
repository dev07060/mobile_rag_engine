/// Main entry point for Mobile RAG Engine.
///
/// Provides a singleton pattern for easy access throughout your app.
/// Initialize once in main(), use anywhere via [MobileRag.instance].
///
/// ## Quick Start
///
/// ```dart
/// import 'package:mobile_rag_engine/mobile_rag_engine.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   await MobileRag.initialize(
///     tokenizerAsset: 'assets/tokenizer.json',
///     modelAsset: 'assets/model.onnx',
///   );
///
///   runApp(const MyApp());
/// }
///
/// // Later, anywhere in your app:
/// final result = await MobileRag.instance.search('What is Flutter?');
/// ```
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/src/internal/defaults.dart';
import 'package:mobile_rag_engine/src/internal/validation.dart';
import 'package:mobile_rag_engine/services/rag_config.dart';
import 'package:mobile_rag_engine/services/rag_engine.dart';
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/model_pack.dart';
import 'package:mobile_rag_engine/src/model_pack/model_pack_resolver.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/services/ask.dart';
import 'package:mobile_rag_engine/services/llm_tool.dart';
// Explicitly import SourceEntry so it can be used in types
import 'package:mobile_rag_engine/src/rust/api/migration_meta.dart'
    show MigrationAxes;
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart'
    show
        ChunkSearchResult,
        SourceEntry,
        SourceStats,
        SearchHandle,
        ChunkExcerptResult,
        AssembledContextV2;
import 'package:mobile_rag_engine/src/rust/api/hybrid_search.dart' as hybrid;

// Export types for consumers
export 'package:mobile_rag_engine/src/internal/embedding_fingerprint.dart'
    show
        ClearAndRestartConfirmation,
        RagEmbeddingFingerprintLock,
        RagReembedProgress;
export 'package:mobile_rag_engine/src/rust/api/migration_meta.dart'
    show MigrationAxes;
export 'package:mobile_rag_engine/src/rust/api/source_rag.dart'
    show
        ChunkSearchResult,
        SourceStats,
        AddSourceResult,
        ChunkData,
        SourceEntry,
        SearchHandle,
        SearchHitMeta,
        ChunkExcerptResult,
        AssembledContextV2;
export 'package:mobile_rag_engine/services/source_rag_service.dart'
    show
        SearchMetaResult,
        RagSearchResult,
        ChunkingStrategy,
        SearchHydrationMode;
export 'package:mobile_rag_engine/services/context_builder.dart'
    show ContextStrategy, AssembledContext;

export 'package:mobile_rag_engine/services/text_chunker.dart';

/// Singleton facade for Mobile RAG Engine.
///
/// Use [MobileRag.initialize] to set up the engine, then access it
/// via [MobileRag.instance] anywhere in your app.
class MobileRag {
  static MobileRag? _instance;
  static RagEngine? _engine;

  MobileRag._();

  /// Initialize the RAG engine. Call once in main().
  ///
  /// This will:
  /// 1. Initialize the Rust library (FFI)
  /// 2. Load the tokenizer from assets
  /// 3. Load the ONNX embedding model
  /// 4. Initialize the SQLite database
  ///
  /// **Parameters:**
  ///
  /// - [tokenizerAsset] - Path to tokenizer.json in assets (e.g., `'assets/tokenizer.json'`)
  /// - [modelAsset] - Path to ONNX model file in assets (e.g., `'assets/model.onnx'`)
  /// - [modelPack] - A verified Model Pack ([RagModelPack.asset]) instead of
  ///   [tokenizerAsset]/[modelAsset]
  /// - [tokenizerPath], [modelPath] - Files your app already placed on disk,
  ///   for example a model downloaded on first launch so it is not in the app
  ///   bundle. They are loaded where they are, without an asset copy. Pass both,
  ///   and none of the asset or Model Pack options. The embedding fingerprint
  ///   includes the model's file name and a hash of the file, so any change to
  ///   either locks search until `reembedAll()` or `clearAndRestart()`.
  /// - [databaseName] - SQLite database file name (default: `'rag.sqlite'`)
  /// - [maxChunkChars] - Maximum characters per chunk (default: [kDefaultMaxChunkChars])
  /// - [overlapChars] - Overlap between chunks for context continuity (default: [kDefaultOverlapChars])
  /// - [embeddingIntraOpNumThreads] - Precise thread count for ONNX (e.g., `1` for minimal CPU).
  ///   **Mutually exclusive with [threadLevel].**
  /// - [threadLevel] - High-level thread usage: `low` (~20%), `medium` (~40%), `high` (~80%).
  ///   **Mutually exclusive with [embeddingIntraOpNumThreads].**
  /// - [deferIndexWarmup] - If true, returns before BM25/HNSW warmup completes.
  ///   Use [isIndexReady] or [warmupFuture] to gate search quality.
  /// - [defaultVectorWeight], [defaultBm25Weight] - Weights for hybrid search
  ///   ([searchHybrid], [searchHybridWithContext], [searchMeta], [ask],
  ///   [prepareAsk], [CollectionRag] and `RagSearchTool.fromMobileRag`) when a
  ///   call does not pass `vectorWeight` / `bm25Weight`. Default 0.2 / 0.8,
  ///   which suits the English-only default model. With a multilingual model
  ///   such as KoEn-E5-Tiny, more vector weight finds answers that share few
  ///   words with the question; the KoEn-E5-Tiny recipe in
  ///   `docs/guides/model_setup.md` uses 0.5 / 0.5 for Korean and English
  ///   documents. Each must be between 0.0
  ///   and 1.0, and not both 0.0.
  /// - [onProgress] - Callback for initialization progress updates
  ///
  /// **Thread Configuration:**
  ///
  /// Choose ONE of the following:
  /// - `threadLevel: ThreadUseLevel.medium` - Simple, recommended for most apps
  /// - `embeddingIntraOpNumThreads: 2` - Fine-grained control
  ///
  /// ⚠️ If both are set:
  /// - Debug builds: throws an [AssertionError]
  /// - Release builds: [threadLevel] takes precedence and a warning is logged
  ///
  /// Example:
  /// ```dart
  /// await MobileRag.initialize(
  ///   tokenizerAsset: 'assets/tokenizer.json',
  ///   modelAsset: 'assets/model.onnx',
  ///   threadLevel: ThreadUseLevel.medium, // Recommended
  ///   onProgress: (status) => print(status),
  /// );
  /// ```
  static Future<void> initialize({
    String? tokenizerAsset,
    String? modelAsset,
    RagModelPack? modelPack,
    String? tokenizerPath,
    String? modelPath,
    String? databaseName,
    int maxChunkChars = kDefaultMaxChunkChars,
    int overlapChars = kDefaultOverlapChars,
    int? embeddingIntraOpNumThreads,
    ThreadUseLevel? threadLevel,
    bool deferIndexWarmup = false,
    double defaultVectorWeight = kDefaultVectorWeight,
    double defaultBm25Weight = kDefaultBm25Weight,
    void Function(String status)? onProgress,
  }) async {
    if (_instance != null) {
      onProgress?.call('Already initialized');
      return;
    }
    validateDefaultHybridWeights(
      vectorWeight: defaultVectorWeight,
      bm25Weight: defaultBm25Weight,
    );

    final hasLegacyAssets = tokenizerAsset != null || modelAsset != null;
    final hasFilePaths = tokenizerPath != null || modelPath != null;
    final sourceCount =
        (modelPack != null ? 1 : 0) +
        (hasLegacyAssets ? 1 : 0) +
        (hasFilePaths ? 1 : 0);
    if (sourceCount > 1) {
      throw ArgumentError(
        'Specify only one of modelPack, tokenizerAsset/modelAsset, or '
        'tokenizerPath/modelPath.',
      );
    }
    if (sourceCount == 0) {
      throw ArgumentError(
        'Specify modelPack, both tokenizerAsset and modelAsset, or both '
        'tokenizerPath and modelPath.',
      );
    }
    if (hasLegacyAssets && (tokenizerAsset == null || modelAsset == null)) {
      throw ArgumentError('Specify both tokenizerAsset and modelAsset.');
    }
    if (hasFilePaths && (tokenizerPath == null || modelPath == null)) {
      throw ArgumentError('Specify both tokenizerPath and modelPath.');
    }
    final RagConfig config;
    if (hasFilePaths) {
      for (final (name, path) in [
        ('tokenizerPath', tokenizerPath!),
        ('modelPath', modelPath!),
      ]) {
        if (!await File(path).exists()) {
          throw ArgumentError.value(path, name, 'File does not exist');
        }
      }
      config = RagConfig(
        tokenizerAsset: '',
        modelAsset: '',
        preparedTokenizerPath: tokenizerPath,
        preparedModelPath: modelPath,
        databaseName: databaseName,
        maxChunkChars: maxChunkChars,
        overlapChars: overlapChars,
        embeddingIntraOpNumThreads: embeddingIntraOpNumThreads,
        threadLevel: threadLevel,
        deferIndexWarmup: deferIndexWarmup,
        defaultVectorWeight: defaultVectorWeight,
        defaultBm25Weight: defaultBm25Weight,
      );
    } else if (modelPack != null) {
      final resolved = await const RagModelPackResolver().resolve(modelPack);
      config = RagConfig.fromPreparedFiles(
        tokenizerPath: resolved.tokenizerPath,
        modelPath: resolved.modelPath,
        expectedEmbeddingDimension: resolved.manifest.embeddingDimension,
        databaseName: databaseName,
        maxChunkChars: maxChunkChars,
        overlapChars: overlapChars,
        embeddingIntraOpNumThreads: embeddingIntraOpNumThreads,
        threadLevel: threadLevel,
        deferIndexWarmup: deferIndexWarmup,
        defaultVectorWeight: defaultVectorWeight,
        defaultBm25Weight: defaultBm25Weight,
      );
    } else {
      config = RagConfig.fromAssets(
        tokenizerAsset: tokenizerAsset!,
        modelAsset: modelAsset!,
        databaseName: databaseName,
        maxChunkChars: maxChunkChars,
        overlapChars: overlapChars,
        embeddingIntraOpNumThreads: embeddingIntraOpNumThreads,
        threadLevel: threadLevel,
        deferIndexWarmup: deferIndexWarmup,
        defaultVectorWeight: defaultVectorWeight,
        defaultBm25Weight: defaultBm25Weight,
      );
    }
    _engine = await RagEngine.initialize(
      config: config,
      onProgress: onProgress,
    );
    _instance = MobileRag._();
  }

  /// **(FOR TESTING ONLY)** Inject a custom instance for mocking.
  ///
  /// This allows you to provide a mock implementation or a pre-configured
  /// engine instance in unit tests.
  @visibleForTesting
  static void setMockInstance(MobileRag? mock) {
    _instance = mock;
    if (mock != null && mock.engine != _engine) {
      _engine = mock.engine;
    }
  }

  /// **(FOR TESTING ONLY)** Makes the real facade use [engine], for example a
  /// mock, without loading the native library. Undo it with
  /// `setMockInstance(null)`.
  @visibleForTesting
  static MobileRag useEngineForTest(RagEngine engine) {
    _engine = engine;
    return _instance = MobileRag._();
  }

  /// Check if the engine is initialized.
  static bool get isInitialized => _instance != null;

  /// Get the singleton instance.
  ///
  /// Throws [StateError] if [initialize] has not been called.
  static MobileRag get instance {
    if (_instance == null) {
      throw StateError(
        'MobileRag not initialized. Call MobileRag.initialize() first.',
      );
    }
    return _instance!;
  }

  /// Access the underlying [RagEngine] for advanced operations.
  RagEngine get engine => _engine!;

  /// Path to the SQLite database.
  String get dbPath => _engine!.dbPath;

  /// Vocabulary size of the loaded tokenizer.
  int get vocabSize => _engine!.vocabSize;

  /// Whether all retrieval indexes are ready for full-quality search.
  bool get isIndexReady => _engine!.isIndexReady;

  /// Read-only snapshot of every on-device data migration axis
  /// (`sql_schema_version`, `hnsw_format_version`, `bm25_stats_version`,
  /// `embedding_fingerprint`, `embedding_fingerprint_pending`) plus the last
  /// engine version recorded at boot. Backed by the `migration_meta` row
  /// provisioned during `initialize()`.
  Future<MigrationAxes> get migrationState => _engine!.migrationState;

  /// Fingerprint computed from the currently loaded embedding model
  /// (`{modelBasename}|{dim}|{quant}|{modelIdentity}`, where the identity is a
  /// hash of the model file's content). Stable across reboots as long as the
  /// host app keeps loading the same model file.
  String get currentEmbeddingFingerprint =>
      _engine!.currentEmbeddingFingerprint;

  /// Non-null when boot detected an embedding fingerprint mismatch — i.e.
  /// the stored on-device embeddings were produced by a different model than
  /// the one currently loaded. While set, all search and ingest entry points
  /// throw `RagError.embeddingFingerprintMismatch`. Resolve by calling either
  /// [reembedAll] (preserves data) or [clearAndRestart] (discards embeddings
  /// after explicit confirmation).
  RagEmbeddingFingerprintLock? get embeddingFingerprintLock =>
      _engine!.embeddingFingerprintLock;

  /// Whether boot detected an embedding fingerprint mismatch.
  bool get isEmbeddingFingerprintLocked =>
      _engine!.isEmbeddingFingerprintLocked;

  /// Re-embed every stored chunk with the currently loaded model and clear
  /// the [embeddingFingerprintLock]. Resumable across app restarts — progress
  /// is persisted per chunk on the Rust side, so an interrupted run picks up
  /// where it left off on the next call.
  ///
  /// [onProgress] is invoked once per chunk with the cumulative
  /// (done, total) snapshot for the current run.
  ///
  /// Throws [StateError] when no mismatch is active.
  Future<void> reembedAll({
    void Function(RagReembedProgress progress)? onProgress,
    int batchSize = 32,
  }) => _engine!.reembedAll(onProgress: onProgress, batchSize: batchSize);

  /// Discard every on-device embedding (chunks table) and rotate the
  /// fingerprint baseline to the currently loaded model.
  ///
  /// `confirm` is required and only accepts
  /// [ClearAndRestartConfirmation.iUnderstandThisDeletesAllOnDeviceEmbeddings]
  /// — the parameter exists solely to keep the destructive choice visible at
  /// every call site. The `sources` table is preserved so the original
  /// documents can be re-ingested through `addDocument`.
  ///
  /// Throws [StateError] when no mismatch is active.
  Future<void> clearAndRestart({
    required ClearAndRestartConfirmation confirm,
  }) => _engine!.clearAndRestart(confirm: confirm);

  /// Up-to-date count of chunks still tagged with a non-current fingerprint.
  /// Safe to call while [reembedAll] is running.
  Future<int> reembedRemaining() => _engine!.reembedRemaining();

  /// Completes when BM25/HNSW warmup has finished.
  Future<void> get warmupFuture => _engine!.warmupFuture;

  /// Get a collection-scoped facade.
  CollectionRag inCollection(String collectionId) =>
      CollectionRag._(_engine!, collectionId);

  // ─────────────────────────────────────────────────────────────────────────
  // Convenience instance methods (delegate to RagEngine)
  // ─────────────────────────────────────────────────────────────────────────

  /// Add a document with automatic chunking and embedding.
  ///
  /// The document is split into chunks, embedded, and stored.
  ///
  /// **Note:** Indexing is **automatic** (debounced by 500ms).
  /// You generally do NOT need to call [rebuildIndex] manually, unless you want
  /// to ensure the index is ready immediately (e.g., before a UI update).
  Future<SourceAddResult> addDocument(
    String content, {
    String? metadata,
    String? name,
    String? filePath,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) => _engine!.addDocument(
    content,
    metadata: metadata,
    name: name,
    filePath: filePath,
    strategy: strategy,
    chunkDelay: chunkDelay,
    onProgress: onProgress,
  );

  Future<SourceAddResult> addDocumentUtf8(
    Uint8List bytes, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) => _engine!.addDocumentUtf8(
    bytes,
    metadata: metadata,
    name: name,
    strategy: strategy,
    chunkDelay: chunkDelay,
    onProgress: onProgress,
  );

  Future<SourceAddResult> addDocumentFromFile(
    String filePath, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) => _engine!.addDocumentFromFile(
    filePath,
    metadata: metadata,
    name: name,
    strategy: strategy,
    chunkDelay: chunkDelay,
    onProgress: onProgress,
  );

  /// Get a list of all stored sources.
  Future<List<SourceEntry>> listSources() => _engine!.listSources();

  /// Remove a source and all its chunks.
  ///
  /// **Note:** You do NOT need to call [rebuildIndex] immediately.
  /// The engine uses lazy filtering to exclude deleted items from search results.
  /// However, if you delete a large amount of data (e.g., >50%), calling
  /// [rebuildIndex] is recommended to reclaim memory and optimize the vector graph.
  Future<void> removeSource(int sourceId) => _engine!.removeSource(sourceId);

  /// Get all chunk texts for a specific source document.
  ///
  /// Returns the raw text content of each chunk in order.
  Future<List<String>> getSourceChunks(int sourceId) =>
      _engine!.getSourceChunks(sourceId);

  /// Get adjacent chunks around a given chunk range.
  ///
  /// Useful for "Read More" or context expansion features.
  Future<List<ChunkSearchResult>> getAdjacentChunks({
    required int sourceId,
    required int minIndex,
    required int maxIndex,
  }) => _engine!.getAdjacentChunks(
    sourceId: sourceId,
    minIndex: minIndex,
    maxIndex: maxIndex,
  );

  /// Get the number of chunks for a specific source.
  Future<int> getSourceChunkCount(int sourceId) =>
      _engine!.getSourceChunkCount(sourceId);

  /// Get the original source document content.
  ///
  /// Returns null if the source doesn't exist.
  Future<String?> getSourceDocument(int sourceId) =>
      _engine!.getSourceDocument(sourceId);

  /// Search for relevant chunks and assemble context for LLM.
  Future<RagSearchResult> search(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
    List<int>? sourceIds,
  }) => _engine!.search(
    query,
    topK: topK,
    tokenBudget: tokenBudget,
    strategy: strategy,
    adjacentChunks: adjacentChunks,
    singleSourceMode: singleSourceMode,
    sourceIds: sourceIds,
  );

  Future<SearchMetaResult> searchMeta(
    String query, {
    int topK = 10,
    double? vectorWeight,
    double? bm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
  }) => _engine!.searchMeta(
    query,
    topK: topK,
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    sourceIds: sourceIds,
    adjacentChunks: adjacentChunks,
  );

  Future<AssembledContextV2> assembleContext({
    required SearchHandle searchHandle,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    String separator = '\n\n---\n\n',
    bool singleSourceMode = false,
  }) => _engine!.assembleContext(
    searchHandle: searchHandle,
    tokenBudget: tokenBudget,
    strategy: strategy,
    separator: separator,
    singleSourceMode: singleSourceMode,
  );

  Future<List<ChunkSearchResult>> hydrateChunks({
    required SearchHandle searchHandle,
    required List<int> chunkIds,
  }) => _engine!.hydrateChunks(searchHandle: searchHandle, chunkIds: chunkIds);

  Future<List<ChunkExcerptResult>> getChunkExcerpts({
    required SearchHandle searchHandle,
    required List<int> chunkIds,
    required int maxBytes,
  }) => _engine!.getChunkExcerpts(
    searchHandle: searchHandle,
    chunkIds: chunkIds,
    maxBytes: maxBytes,
  );

  Future<int> deriveContextBudgetForPromptV2({
    required int fullPromptBudget,
    required String query,
    String? systemInstruction,
    bool useStrictMode = true,
    int safetyMarginTokens = 0,
    int? fixedPromptOverheadTokens,
  }) => _engine!.deriveContextBudgetForPromptV2(
    fullPromptBudget: fullPromptBudget,
    query: query,
    systemInstruction: systemInstruction,
    useStrictMode: useStrictMode,
    safetyMarginTokens: safetyMarginTokens,
    fixedPromptOverheadTokens: fixedPromptOverheadTokens,
  );

  /// Hybrid search combining vector and keyword (BM25) search.
  Future<List<hybrid.HybridSearchResult>> searchHybrid(
    String query, {
    int topK = 10,
    double? vectorWeight,
    double? bm25Weight,
    List<int>? sourceIds,
  }) => _engine!.searchHybrid(
    query,
    topK: topK,
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    sourceIds: sourceIds,
  );

  /// Hybrid search with context assembly for LLM.
  Future<RagSearchResult> searchHybridWithContext(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    double? vectorWeight,
    double? bm25Weight,
    bool singleSourceMode = false,
    List<int>? sourceIds,
    SearchHydrationMode hydrationMode = SearchHydrationMode.full,
    int previewMaxBytes = 512,
  }) => _engine!.searchHybridWithContext(
    query,
    topK: topK,
    tokenBudget: tokenBudget,
    strategy: strategy,
    adjacentChunks: adjacentChunks,
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    singleSourceMode: singleSourceMode,
    sourceIds: sourceIds,
    hydrationMode: hydrationMode,
    previewMaxBytes: previewMaxBytes,
  );

  /// Rebuild the HNSW index.
  ///
  /// **When to use:**
  /// - **Automatic:** The engine automatically rebuilds 500ms after the last operation.
  /// - **Manual:** Call this if you want to **force** an immediate rebuild (e.g., to guarantee consistency before a critical search).
  /// - **Not needed:** After `clearAllData()` (which resets everything).
  ///
  /// This operation can be slow for large datasets.
  Future<void> rebuildIndex() => _engine!.rebuildIndex();

  /// Try to load a cached HNSW index.
  ///
  /// Use this at startup to skip the expensive [rebuildIndex] step.
  /// Returns `true` if an index was successfully loaded from disk.
  Future<bool> tryLoadCachedIndex() => _engine!.tryLoadCachedIndex();

  /// Save the HNSW index marker to disk.
  ///
  /// This is handled automatically by [rebuildIndex], but can be called manually
  /// if you are doing custom index management.
  Future<void> saveIndex() => _engine!.saveIndex();

  /// Get statistics about stored sources and chunks.
  Future<SourceStats> getStats() => _engine!.getStats();

  /// Format search results as an LLM prompt.
  String formatPrompt(String query, RagSearchResult result) =>
      _engine!.formatPrompt(query, result);

  /// Searches for [question] and builds the prompt for an LLM, without calling
  /// one. Use it to stream the answer with your own SDK, then pass the
  /// complete answer to [RagAskPrompt.answer].
  ///
  /// Searches like [searchHybridWithContext] for [topK] passages within
  /// [tokenBudget] engine tokens, with the same [vectorWeight] / [bm25Weight]
  /// as [searchHybrid]. Citation ids start at 1 for every question.
  /// The prompt is empty when nothing was found.
  Future<RagAskPrompt> prepareAsk(
    String question, {
    int topK = 5,
    int tokenBudget = 1500,
    double? vectorWeight,
    double? bm25Weight,
    RagPromptBuilder buildPrompt = defaultAskPrompt,
  }) => prepareAskWith(
    _askTool(topK, tokenBudget, vectorWeight, bm25Weight),
    question,
    buildPrompt: buildPrompt,
  );

  /// Answers [question] from the stored documents with your LLM.
  ///
  /// Runs [prepareAsk], sends the prompt to [generate], and returns the answer
  /// with the passages it cites. [generate] is not called when nothing was
  /// found; the answer then has no passages and empty text.
  Future<RagAnswer> ask(
    String question, {
    required RagGenerate generate,
    int topK = 5,
    int tokenBudget = 1500,
    double? vectorWeight,
    double? bm25Weight,
    RagPromptBuilder buildPrompt = defaultAskPrompt,
  }) => askWith(
    _askTool(topK, tokenBudget, vectorWeight, bm25Weight),
    question,
    generate: generate,
    buildPrompt: buildPrompt,
  );

  RagSearchTool _askTool(
    int topK,
    int tokenBudget,
    double? vectorWeight,
    double? bm25Weight,
  ) => RagSearchTool(
    search: (query, k) => _engine!.searchHybridWithContext(
      query,
      topK: k,
      tokenBudget: tokenBudget,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
    ),
    listSources: listSources,
    defaultTopK: topK,
    maxTopK: topK,
  );

  /// Clear all data (database and index files) and reset the engine.
  ///
  /// This is a destructive operation!
  Future<void> clearAllData() => _engine!.clearAllData();

  /// Dispose of resources.
  ///
  /// Call when completely done with the engine.
  static Future<void> dispose() async {
    await RagEngine.dispose();
    _engine = null;
    _instance = null;
  }
}

/// Collection-scoped facade for Multi-Collection workflows.
class CollectionRag {
  final RagEngine _engine;
  final String _collectionId;

  CollectionRag._(this._engine, String collectionId)
    : _collectionId = collectionId.trim().isEmpty
          ? SourceRagService.defaultCollectionId
          : collectionId.trim();

  String get collectionId => _collectionId;

  bool get isIndexReady => _engine.isCollectionIndexReady(_collectionId);
  Future<void> get warmupFuture =>
      _engine.collectionWarmupFuture(_collectionId);

  Future<SourceAddResult> addDocument(
    String content, {
    String? metadata,
    String? name,
    String? filePath,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) => _engine.addDocument(
    content,
    metadata: metadata,
    name: name,
    filePath: filePath,
    strategy: strategy,
    chunkDelay: chunkDelay,
    onProgress: onProgress,
    collectionId: _collectionId,
  );

  Future<SourceAddResult> addDocumentUtf8(
    Uint8List bytes, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) => _engine.addDocumentUtf8(
    bytes,
    metadata: metadata,
    name: name,
    strategy: strategy,
    chunkDelay: chunkDelay,
    onProgress: onProgress,
    collectionId: _collectionId,
  );

  Future<SourceAddResult> addDocumentFromFile(
    String filePath, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) => _engine.addDocumentFromFile(
    filePath,
    metadata: metadata,
    name: name,
    strategy: strategy,
    chunkDelay: chunkDelay,
    onProgress: onProgress,
    collectionId: _collectionId,
  );

  Future<List<SourceEntry>> listSources() =>
      _engine.listSources(collectionId: _collectionId);

  Future<void> removeSource(int sourceId) =>
      _engine.removeSource(sourceId, collectionId: _collectionId);

  Future<RagSearchResult> search(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
    List<int>? sourceIds,
  }) => _engine.search(
    query,
    topK: topK,
    tokenBudget: tokenBudget,
    strategy: strategy,
    adjacentChunks: adjacentChunks,
    singleSourceMode: singleSourceMode,
    sourceIds: sourceIds,
    collectionId: _collectionId,
  );

  Future<SearchMetaResult> searchMeta(
    String query, {
    int topK = 10,
    double? vectorWeight,
    double? bm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
  }) => _engine.searchMeta(
    query,
    topK: topK,
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    sourceIds: sourceIds,
    adjacentChunks: adjacentChunks,
    collectionId: _collectionId,
  );

  Future<AssembledContextV2> assembleContext({
    required SearchHandle searchHandle,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    String separator = '\n\n---\n\n',
    bool singleSourceMode = false,
  }) => _engine.assembleContext(
    searchHandle: searchHandle,
    tokenBudget: tokenBudget,
    strategy: strategy,
    separator: separator,
    singleSourceMode: singleSourceMode,
    collectionId: _collectionId,
  );

  Future<List<ChunkSearchResult>> hydrateChunks({
    required SearchHandle searchHandle,
    required List<int> chunkIds,
  }) => _engine.hydrateChunks(
    searchHandle: searchHandle,
    chunkIds: chunkIds,
    collectionId: _collectionId,
  );

  Future<List<ChunkExcerptResult>> getChunkExcerpts({
    required SearchHandle searchHandle,
    required List<int> chunkIds,
    required int maxBytes,
  }) => _engine.getChunkExcerpts(
    searchHandle: searchHandle,
    chunkIds: chunkIds,
    maxBytes: maxBytes,
    collectionId: _collectionId,
  );

  Future<int> deriveContextBudgetForPromptV2({
    required int fullPromptBudget,
    required String query,
    String? systemInstruction,
    bool useStrictMode = true,
    int safetyMarginTokens = 0,
    int? fixedPromptOverheadTokens,
  }) => _engine.deriveContextBudgetForPromptV2(
    fullPromptBudget: fullPromptBudget,
    query: query,
    systemInstruction: systemInstruction,
    useStrictMode: useStrictMode,
    safetyMarginTokens: safetyMarginTokens,
    fixedPromptOverheadTokens: fixedPromptOverheadTokens,
    collectionId: _collectionId,
  );

  Future<List<hybrid.HybridSearchResult>> searchHybrid(
    String query, {
    int topK = 10,
    double? vectorWeight,
    double? bm25Weight,
    List<int>? sourceIds,
  }) => _engine.searchHybrid(
    query,
    topK: topK,
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    sourceIds: sourceIds,
    collectionId: _collectionId,
  );

  Future<RagSearchResult> searchHybridWithContext(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    double? vectorWeight,
    double? bm25Weight,
    bool singleSourceMode = false,
    List<int>? sourceIds,
    SearchHydrationMode hydrationMode = SearchHydrationMode.full,
    int previewMaxBytes = 512,
  }) => _engine.searchHybridWithContext(
    query,
    topK: topK,
    tokenBudget: tokenBudget,
    strategy: strategy,
    adjacentChunks: adjacentChunks,
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    singleSourceMode: singleSourceMode,
    sourceIds: sourceIds,
    hydrationMode: hydrationMode,
    previewMaxBytes: previewMaxBytes,
    collectionId: _collectionId,
  );

  Future<void> rebuildIndex({bool force = false}) =>
      _engine.rebuildIndex(force: force, collectionId: _collectionId);

  Future<SourceStats> getStats() =>
      _engine.getStats(collectionId: _collectionId);

  String formatPrompt(String query, RagSearchResult result) =>
      _engine.formatPrompt(query, result);

  /// Searches for [question] and builds the prompt for an LLM, without calling
  /// one. Use it to stream the answer with your own SDK, then pass the
  /// complete answer to [RagAskPrompt.answer].
  ///
  /// Searches like [searchHybridWithContext] for [topK] passages within
  /// [tokenBudget] engine tokens, with the same [vectorWeight] / [bm25Weight]
  /// as [searchHybrid]. Citation ids start at 1 for every question.
  /// The prompt is empty when nothing was found.
  Future<RagAskPrompt> prepareAsk(
    String question, {
    int topK = 5,
    int tokenBudget = 1500,
    double? vectorWeight,
    double? bm25Weight,
    RagPromptBuilder buildPrompt = defaultAskPrompt,
  }) => prepareAskWith(
    _askTool(topK, tokenBudget, vectorWeight, bm25Weight),
    question,
    buildPrompt: buildPrompt,
  );

  /// Answers [question] from the stored documents with your LLM.
  ///
  /// Runs [prepareAsk], sends the prompt to [generate], and returns the answer
  /// with the passages it cites. [generate] is not called when nothing was
  /// found; the answer then has no passages and empty text.
  Future<RagAnswer> ask(
    String question, {
    required RagGenerate generate,
    int topK = 5,
    int tokenBudget = 1500,
    double? vectorWeight,
    double? bm25Weight,
    RagPromptBuilder buildPrompt = defaultAskPrompt,
  }) => askWith(
    _askTool(topK, tokenBudget, vectorWeight, bm25Weight),
    question,
    generate: generate,
    buildPrompt: buildPrompt,
  );

  RagSearchTool _askTool(
    int topK,
    int tokenBudget,
    double? vectorWeight,
    double? bm25Weight,
  ) => RagSearchTool(
    search: (query, k) => _engine.searchHybridWithContext(
      query,
      topK: k,
      tokenBudget: tokenBudget,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      collectionId: _collectionId,
    ),
    listSources: listSources,
    defaultTopK: topK,
    maxTopK: topK,
  );
}
