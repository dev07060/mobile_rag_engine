/// Unified RAG engine with simplified initialization.
///
/// This class combines tokenizer, embedding model, and RAG service
/// initialization into a single `initialize()` call.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:mobile_rag_engine/mobile_rag_engine.dart';
///
/// // NOTE: For most apps, use [MobileRag] singleton instead.
/// // It wraps this class and handles global access.
///
/// // If you need a standalone engine instance:
/// final rag = await RagEngine.initialize(
///   config: RagConfig.fromAssets(
///     tokenizerAsset: 'assets/tokenizer.json',
///     modelAsset: 'assets/model.onnx',
///   ),
/// );
///
/// // Use the engine
/// await rag.addDocument('Your document text here');
/// await rag.rebuildIndex();
/// final result = await rag.search('query', tokenBudget: 2000);
/// ```
library;

import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/tokenizer.dart';
import '../src/rust/api/source_rag.dart'
    show
        ChunkSearchResult,
        SourceStats,
        SourceEntry,
        SearchHandle,
        ChunkExcerptResult,
        AssembledContextV2;
import '../src/rust/api/db_pool.dart';
import '../src/internal/defaults.dart';
import '../src/internal/validation.dart';
import 'embedding_service.dart';
import 'rag_config.dart';
import 'source_rag_service.dart';
import 'context_builder.dart';
import '../src/rust/api/hybrid_search.dart' as hybrid;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import '../src/rust/frb_generated.dart';

/// Unified RAG engine with simplified initialization.
///
/// Wraps [SourceRagService] with automatic dependency initialization.
class RagEngine {
  static bool _isRustInitialized = false;

  /// Ensures RustLib is initialized (safe to call multiple times).
  static Future<void> _ensureRustInitialized() async {
    if (_isRustInitialized) return;

    if (Platform.isMacOS) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
      );
    } else {
      await RustLib.init();
    }
    _isRustInitialized = true;
  }

  final SourceRagService _ragService;
  final Map<String, SourceRagService> _collectionServices;
  final Set<String> _initializedCollections;
  final Map<String, Future<void>> _collectionInitInFlight;

  /// Path to the SQLite database.
  final String dbPath;

  /// Vocabulary size of the loaded tokenizer.
  final int vocabSize;
  final bool _deferIndexWarmup;

  RagEngine._({
    required SourceRagService ragService,
    required this.dbPath,
    required this.vocabSize,
    required bool deferIndexWarmup,
  })  : _ragService = ragService,
        _deferIndexWarmup = deferIndexWarmup,
        _collectionServices = {
          SourceRagService.defaultCollectionId: ragService
        },
        _initializedCollections = {SourceRagService.defaultCollectionId},
        _collectionInitInFlight = {};

  String _normalizeCollectionId(String? collectionId) {
    final trimmed = collectionId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return SourceRagService.defaultCollectionId;
    }
    return trimmed;
  }

  Future<SourceRagService> _serviceForCollection(String? collectionId) async {
    final normalized = _normalizeCollectionId(collectionId);
    final service = _collectionServices.putIfAbsent(
      normalized,
      () => _ragService.inCollection(normalized),
    );

    await _ensureCollectionInitialized(normalized, service);
    return service;
  }

  Future<void> _ensureCollectionInitialized(
    String collectionId,
    SourceRagService service,
  ) async {
    if (_initializedCollections.contains(collectionId)) {
      return;
    }

    final inFlight = _collectionInitInFlight[collectionId];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final initFuture = () async {
      await service.init(deferIndexWarmup: _deferIndexWarmup);
      _initializedCollections.add(collectionId);
    }();

    _collectionInitInFlight[collectionId] = initFuture;
    try {
      await initFuture;
    } finally {
      if (identical(_collectionInitInFlight[collectionId], initFuture)) {
        _collectionInitInFlight.remove(collectionId);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Auto-Indexing Strategy (Active Tracking + Debounce + Flush-on-Search)
  // ─────────────────────────────────────────────────────────────────────────

  Timer? _indexDebounceTimer;
  static const _debounceDuration = Duration(milliseconds: 500);

  /// Tracks the number of active long-running operations (Add/Remove).
  /// We ONLY schedule a debounce timer when this count drops to zero.
  int _activeOperations = 0;

  /// Start a long-running operation.
  /// Cancels any pending timer to prevent premature indexing.
  void _startOperation() {
    _activeOperations++;
    _indexDebounceTimer?.cancel();
    _indexDebounceTimer = null;
  }

  /// End a long-running operation.
  /// If no more operations are active, schedule the debounce timer.
  void _endOperation() {
    _activeOperations--;
    if (_activeOperations <= 0) {
      _activeOperations = 0; // Safety clamp
      _scheduleIndexRebuild();
    }
  }

  /// Schedules an index rebuild with a debounce delay.
  /// Only runs if no operations are currently active.
  void _scheduleIndexRebuild() {
    if (_activeOperations > 0) return; // Don't schedule if busy

    _indexDebounceTimer?.cancel();
    _indexDebounceTimer = Timer(_debounceDuration, () {
      if (_activeOperations > 0) return; // double-check
      debugPrint('[RagEngine] Auto-rebuilding index (Debounce)...');
      rebuildIndex();
      _indexDebounceTimer = null;
    });
  }

  /// Flushes any pending index rebuilds properly BEFORE a search.
  /// checks both the timer AND active operations.
  Future<void> _flushIndex({String? collectionId}) async {
    final normalized = _normalizeCollectionId(collectionId);
    if (normalized != SourceRagService.defaultCollectionId) {
      final service = await _serviceForCollection(normalized);
      await service.rebuildIndex();
      return;
    }

    // If timer is pending, cancel and run immediately
    if (_indexDebounceTimer != null && _indexDebounceTimer!.isActive) {
      debugPrint('[RagEngine] Flushing pending index rebuild before search...');
      _indexDebounceTimer!.cancel();
      _indexDebounceTimer = null;
      await rebuildIndex();
    }
  }

  /// Initialize RagEngine with all dependencies.
  ///
  /// This method handles:
  /// 1. Copying tokenizer asset to documents directory
  /// 2. Initializing the tokenizer
  /// 3. Loading the ONNX embedding model
  /// 4. Initializing the RAG database
  ///
  /// [config] - Configuration containing asset paths and options.
  /// [onProgress] - Optional callback for initialization status updates.
  ///
  /// Example:
  /// ```dart
  /// final rag = await RagEngine.initialize(
  ///   config: RagConfig.fromAssets(
  ///     tokenizerAsset: 'assets/tokenizer.json',
  ///     modelAsset: 'assets/model.onnx',
  ///   ),
  ///   onProgress: (status) => setState(() => _status = status),
  /// );
  /// ```
  static Future<RagEngine> initialize({
    required RagConfig config,
    void Function(String status)? onProgress,
  }) async {
    // 0. Auto-initialize Rust library (safe to call multiple times)
    await _ensureRustInitialized();

    // 1. Get app documents directory
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = "${dir.path}/${config.databaseName ?? 'rag.sqlite'}";
    final tokenizerPath = "${dir.path}/tokenizer.json";
    final modelPath = "${dir.path}/${config.modelAsset.split('/').last}";

    // 2. Copy and initialize tokenizer
    onProgress?.call('Initializing tokenizer...');
    await _copyAssetToFile(config.tokenizerAsset, tokenizerPath);
    await initTokenizer(tokenizerPath: tokenizerPath);
    final vocabSize = getVocabSize();

    // 3. Prepare ONNX embedding model (Copy logic)
    onProgress?.call('Preparing embedding model...');
    // Copy model asset to file (optimized for memory)
    await _copyAssetToFile(config.modelAsset, modelPath);

    final normalizedMaxChunkChars = normalizeMaxChunkChars(
      config.maxChunkChars,
      context: 'RagEngine.initialize',
    );
    final normalizedOverlapChars = normalizeOverlapChars(
      config.overlapChars,
      context: 'RagEngine.initialize',
    );
    warnThreadConfigConflict(
      threadLevel: config.threadLevel,
      embeddingIntraOpNumThreads: config.embeddingIntraOpNumThreads,
      context: 'RagEngine.initialize',
    );

    // Default to half the cores if not specified to prevent full CPU usage
    // Calculate threads based on configuration
    int threads;
    final totalCores = Platform.numberOfProcessors;

    if (config.threadLevel != null) {
      // 1. Thread Level (Percentage based)
      switch (config.threadLevel!) {
        case ThreadUseLevel.low:
          threads = (totalCores * 0.2).ceil();
          break;
        case ThreadUseLevel.medium:
          threads = (totalCores * 0.4).ceil();
          break;
        case ThreadUseLevel.high:
          threads = (totalCores * 0.8).ceil();
          break;
      }
    } else if (config.embeddingIntraOpNumThreads != null) {
      // 2. Manual Count
      threads = config.embeddingIntraOpNumThreads!;
    } else {
      // 3. Priority: Default (50% safe fallback)
      threads = (totalCores > 1 ? (totalCores / 2).ceil() : 1);
    }

    // Ensure at least 1 thread
    if (threads < 1) threads = 1;

    debugPrint(
      '[RagEngine] Configured ONNX embedding threads: $threads (Total Cores: $totalCores)',
    );

    // Init EmbeddingService on a background worker isolate.
    // Thread config is passed as a raw int; the worker creates
    // OrtSessionOptions internally (native objects can't cross isolate
    // boundaries).
    onProgress?.call('Loading embedding model...');
    await EmbeddingService.init(
      modelPath: modelPath,
      intraOpNumThreads: threads,
    );

    // 4. Initialize database connection pool
    onProgress?.call('Initializing connection pool...');
    await initDbPool(dbPath: dbPath, maxSize: 4);

    // 5. Initialize RAG service
    onProgress?.call('Initializing database...');
    final ragService = SourceRagService(
      dbPath: dbPath,
      modelPath: modelPath,
      maxChunkChars: normalizedMaxChunkChars,
      overlapChars: normalizedOverlapChars,
    );
    await ragService.init(deferIndexWarmup: config.deferIndexWarmup);

    onProgress?.call('Ready!');
    return RagEngine._(
      ragService: ragService,
      dbPath: dbPath,
      vocabSize: vocabSize,
      deferIndexWarmup: config.deferIndexWarmup,
    );
  }

  /// Copy asset file to filesystem if it doesn't exist.
  static Future<void> _copyAssetToFile(
    String assetPath,
    String filePath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
  }

  static String _stripDbExtension(String path) {
    const knownDbExtensions = ['.sqlite3', '.sqlite', '.db'];
    final lower = path.toLowerCase();
    for (final ext in knownDbExtensions) {
      if (lower.endsWith(ext)) {
        return path.substring(0, path.length - ext.length);
      }
    }
    return path;
  }

  /// Whether all retrieval indexes are ready for full-quality search.
  bool get isIndexReady => _ragService.isIndexReady;

  /// Completes when the latest index warmup/rebuild task has finished.
  Future<void> get warmupFuture => _ragService.warmupFuture;

  /// Whether a specific collection index is ready for full-quality search.
  bool isCollectionIndexReady(String collectionId) {
    final normalized = _normalizeCollectionId(collectionId);
    final service = _collectionServices[normalized];
    if (service == null) return false;
    return service.isIndexReady;
  }

  /// Completes when a specific collection warmup/rebuild task has finished.
  Future<void> collectionWarmupFuture(String collectionId) async {
    final service = await _serviceForCollection(collectionId);
    await service.warmupFuture;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Delegated methods from SourceRagService
  // ─────────────────────────────────────────────────────────────────────────

  /// Add a document with automatic chunking and embedding.
  ///
  /// The document is:
  /// 1. Split into chunks based on file type (auto-detected from [filePath])
  /// 2. Each chunk is embedded using the loaded model
  /// 3. Source and chunks are stored in the database
  ///
  /// Remember to call [rebuildIndex] after adding documents for optimal
  /// search performance.
  Future<SourceAddResult> addDocument(
    String content, {
    String? metadata,
    String? name,
    String? filePath,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
    String? collectionId,
  }) async {
    final normalized = _normalizeCollectionId(collectionId);
    final service = await _serviceForCollection(normalized);

    if (normalized == SourceRagService.defaultCollectionId) {
      _startOperation(); // Start tracking
    }
    try {
      final result = await service.addSourceWithChunking(
        content,
        metadata: metadata,
        name: name,
        filePath: filePath,
        strategy: strategy,
        chunkDelay: chunkDelay,
        onProgress: onProgress,
      );
      return result;
    } finally {
      if (normalized == SourceRagService.defaultCollectionId) {
        _endOperation(); // End tracking -> Schedule debounce
      }
    }
  }

  /// Add a UTF-8 document payload without requiring the caller to inflate a Dart String first.
  Future<SourceAddResult> addDocumentUtf8(
    Uint8List bytes, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
    String? collectionId,
  }) async {
    final normalized = _normalizeCollectionId(collectionId);
    final service = await _serviceForCollection(normalized);

    if (normalized == SourceRagService.defaultCollectionId) {
      _startOperation();
    }
    try {
      return await service.addSourceUtf8WithChunking(
        bytes,
        metadata: metadata,
        name: name,
        strategy: strategy,
        chunkDelay: chunkDelay,
        onProgress: onProgress,
      );
    } finally {
      if (normalized == SourceRagService.defaultCollectionId) {
        _endOperation();
      }
    }
  }

  /// Add a document from a file path using Rust-side file reading/parsing.
  Future<SourceAddResult> addDocumentFromFile(
    String filePath, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
    String? collectionId,
  }) async {
    final normalized = _normalizeCollectionId(collectionId);
    final service = await _serviceForCollection(normalized);

    if (normalized == SourceRagService.defaultCollectionId) {
      _startOperation();
    }
    try {
      return await service.addSourceFromFileWithChunking(
        filePath,
        metadata: metadata,
        name: name,
        strategy: strategy,
        chunkDelay: chunkDelay,
        onProgress: onProgress,
      );
    } finally {
      if (normalized == SourceRagService.defaultCollectionId) {
        _endOperation();
      }
    }
  }

  /// Search for relevant chunks and assemble context for LLM.
  ///
  /// [query] - The search query text.
  /// [topK] - Number of top results to return (default: 10).
  /// [tokenBudget] - Maximum tokens for assembled context (default: 2000).
  /// [strategy] - Context assembly strategy (default: relevanceFirst).
  /// [adjacentChunks] - Include N chunks before/after matches (default: 0).
  /// [singleSourceMode] - Only include chunks from most relevant source.
  Future<RagSearchResult> search(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
    List<int>? sourceIds,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    await _flushIndex(
      collectionId: collectionId,
    ); // Ensure index is up-to-date before searching
    return service.search(
      query,
      topK: topK,
      tokenBudget: tokenBudget,
      strategy: strategy,
      adjacentChunks: adjacentChunks,
      singleSourceMode: singleSourceMode,
      sourceIds: sourceIds,
    );
  }

  /// Additive metadata-first low-level search lane.
  Future<SearchMetaResult> searchMeta(
    String query, {
    int topK = 10,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    await _flushIndex(collectionId: collectionId);
    return service.searchMeta(
      query,
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: sourceIds,
      adjacentChunks: adjacentChunks,
    );
  }

  Future<AssembledContextV2> assembleContext({
    required SearchHandle searchHandle,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    String separator = '\n\n---\n\n',
    bool singleSourceMode = false,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    return service.assembleContext(
      searchHandle: searchHandle,
      tokenBudget: tokenBudget,
      strategy: strategy,
      separator: separator,
      singleSourceMode: singleSourceMode,
    );
  }

  Future<List<ChunkSearchResult>> hydrateChunks({
    required SearchHandle searchHandle,
    required List<int> chunkIds,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    return service.hydrateChunks(
      searchHandle: searchHandle,
      chunkIds: chunkIds,
    );
  }

  Future<List<ChunkExcerptResult>> getChunkExcerpts({
    required SearchHandle searchHandle,
    required List<int> chunkIds,
    required int maxBytes,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    return service.getChunkExcerpts(
      searchHandle: searchHandle,
      chunkIds: chunkIds,
      maxBytes: maxBytes,
    );
  }

  Future<int> deriveContextBudgetForPromptV2({
    required int fullPromptBudget,
    required String query,
    String? systemInstruction,
    bool useStrictMode = true,
    int safetyMarginTokens = 0,
    int? fixedPromptOverheadTokens,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    return service.deriveContextBudgetForPromptV2(
      fullPromptBudget: fullPromptBudget,
      query: query,
      systemInstruction: systemInstruction,
      useStrictMode: useStrictMode,
      safetyMarginTokens: safetyMarginTokens,
      fixedPromptOverheadTokens: fixedPromptOverheadTokens,
    );
  }

  /// Hybrid search combining vector and keyword (BM25) search.
  ///
  /// Uses Reciprocal Rank Fusion (RRF) to combine semantic and keyword results.
  Future<List<hybrid.HybridSearchResult>> searchHybrid(
    String query, {
    int topK = 10,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    await _flushIndex(
      collectionId: collectionId,
    ); // Ensure index is up-to-date before searching
    return service.searchHybrid(
      query,
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: sourceIds,
    );
  }

  /// Hybrid search with context assembly for LLM.
  ///
  /// [adjacentChunks] - Include N chunks before/after matches (default: 0).
  /// [singleSourceMode] - Only include chunks from most relevant source.
  Future<RagSearchResult> searchHybridWithContext(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    await _flushIndex(
      collectionId: collectionId,
    ); // Ensure index is up-to-date before searching
    return service.searchHybridWithContext(
      query,
      topK: topK,
      tokenBudget: tokenBudget,
      strategy: strategy,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: sourceIds,
      adjacentChunks: adjacentChunks,
      singleSourceMode: singleSourceMode,
    );
  }

  /// Rebuild the HNSW index after adding documents.
  ///
  /// Call this after adding one or more documents for optimal search
  /// performance. The index enables fast approximate nearest neighbor search.
  /// [force] - If true, rebuilds even if no changes were detected (default: false).
  Future<void> rebuildIndex({bool force = false, String? collectionId}) async {
    final normalized = _normalizeCollectionId(collectionId);
    final service = await _serviceForCollection(normalized);

    if (normalized == SourceRagService.defaultCollectionId) {
      _indexDebounceTimer
          ?.cancel(); // Cancel any pending auto-rebuild since we are doing it now
      _indexDebounceTimer = null;
    }

    return service.rebuildIndex(force: force); // Service handles dirty check
  }

  /// Try to load a cached HNSW index from disk.
  ///
  /// Returns true if a previously built index exists.
  Future<bool> tryLoadCachedIndex({String? collectionId}) async {
    final service = await _serviceForCollection(collectionId);
    return service.tryLoadCachedIndex();
  }

  /// Save the HNSW index marker to disk.
  Future<void> saveIndex({String? collectionId}) async {
    final service = await _serviceForCollection(collectionId);
    return service.saveIndex();
  }

  /// Get statistics about stored sources and chunks.
  Future<SourceStats> getStats({String? collectionId}) async {
    final service = await _serviceForCollection(collectionId);
    return service.getStats();
  }

  /// Remove a source and all its chunks from the database.
  Future<void> removeSource(int sourceId, {String? collectionId}) async {
    final normalized = _normalizeCollectionId(collectionId);
    final service = await _serviceForCollection(normalized);
    if (normalized == SourceRagService.defaultCollectionId) {
      _startOperation();
    }
    try {
      await service.removeSource(sourceId);
    } finally {
      if (normalized == SourceRagService.defaultCollectionId) {
        _endOperation();
      }
    }
  }

  /// Get a list of all stored sources.
  Future<List<SourceEntry>> listSources({String? collectionId}) async {
    final service = await _serviceForCollection(collectionId);
    return service.listSources();
  }

  /// Get all chunk texts for a specific source.
  ///
  /// Returns the raw text content of each chunk in order.
  /// Useful for displaying full document content reconstructed from chunks.
  Future<List<String>> getSourceChunks(int sourceId) =>
      _ragService.getSourceChunks(sourceId: sourceId);

  /// Get adjacent chunks around a given chunk range.
  ///
  /// Useful for "Read More" or context expansion features.
  Future<List<ChunkSearchResult>> getAdjacentChunks({
    required int sourceId,
    required int minIndex,
    required int maxIndex,
  }) =>
      _ragService.getAdjacentChunks(
        sourceId: sourceId,
        minIndex: minIndex,
        maxIndex: maxIndex,
      );

  /// Get the number of chunks for a specific source.
  ///
  /// Useful for pagination, progress tracking, and batch processing.
  Future<int> getSourceChunkCount(int sourceId) =>
      _ragService.getSourceChunkCount(sourceId: sourceId);

  /// Get the original source document content by ID.
  ///
  /// Returns null if the source doesn't exist.
  Future<String?> getSourceDocument(int sourceId) =>
      _ragService.getSourceDocument(sourceId: sourceId);

  /// Format search results as an LLM prompt.
  String formatPrompt(String query, RagSearchResult result) =>
      _ragService.formatPrompt(query, result);

  /// Regenerate embeddings for all existing chunks.
  ///
  /// Use this when the embedding model has been updated.
  Future<void> regenerateAllEmbeddings({
    void Function(int done, int total)? onProgress,
    String? collectionId,
  }) async {
    final service = await _serviceForCollection(collectionId);
    return service.regenerateAllEmbeddings(onProgress: onProgress);
  }

  /// Clear all data (database and index files) and reset the engine.
  ///
  /// This is a destructive operation that:
  /// 1. Closes the database connection
  /// 2. Deletes the SQLite database file
  /// 3. Deletes the HNSW index file
  /// 4. Re-initializes the database and service
  Future<void> clearAllData() async {
    debugPrint('[RagEngine] clearAllData: Starting...');
    // 1. Close DB pool
    debugPrint('[RagEngine] clearAllData: Closing DB pool...');
    await closeDbPool();
    debugPrint('[RagEngine] clearAllData: DB pool closed.');

    // 2. Delete DB file
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      debugPrint('[RagEngine] clearAllData: Deleting DB file at $dbPath...');
      await dbFile.delete();
      debugPrint('[RagEngine] clearAllData: DB file deleted.');
    } else {
      debugPrint('[RagEngine] clearAllData: DB file not found.');
    }

    // 3. Delete index artifacts (new and legacy naming patterns)
    final baseNoExt = _stripDbExtension(dbPath);
    final indexStems = <String>{baseNoExt, '${baseNoExt}_hnsw'};
    final indexCandidates = <String>{
      for (final stem in indexStems) stem,
      for (final stem in indexStems) '$stem.pbin',
      for (final stem in indexStems) '$stem.hnsw.data',
      for (final stem in indexStems) '$stem.hnsw.graph',
    };

    for (final path in indexCandidates) {
      final file = File(path);
      if (await file.exists()) {
        debugPrint('[RagEngine] clearAllData: Deleting index artifact: $path');
        await file.delete();
      }
    }

    // 4. Re-initialize DB pool
    debugPrint('[RagEngine] clearAllData: Re-initializing DB pool...');
    await initDbPool(dbPath: dbPath, maxSize: 4);
    debugPrint('[RagEngine] clearAllData: DB pool initialized.');

    // 5. Re-initialize service
    debugPrint('[RagEngine] clearAllData: Re-initializing service...');
    await _ragService.init(deferIndexWarmup: _deferIndexWarmup);
    _collectionServices
      ..clear()
      ..[SourceRagService.defaultCollectionId] = _ragService;
    _initializedCollections
      ..clear()
      ..add(SourceRagService.defaultCollectionId);
    _collectionInitInFlight.clear();
    debugPrint('[RagEngine] clearAllData: Service initialized. Done.');
  }

  /// Access to the underlying [SourceRagService] for advanced operations.
  SourceRagService get service => _ragService;

  /// Dispose of resources.
  ///
  /// Call this when done using the engine to release resources.
  static Future<void> dispose() async {
    await EmbeddingService.disposeAsync();
    await closeDbPool();
  }
}
