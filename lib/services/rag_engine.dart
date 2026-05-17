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
import '../src/rust/api/error.dart';
import '../src/rust/api/migration_meta.dart' as migration_meta
    show
        EmbeddingFingerprintGate_Mismatch,
        EmbeddingFingerprintGate_Ok,
        EmbeddingFingerprintGate_RequiresInitialBaseline,
        MigrationAxes,
        acknowledgeAndClearEmbeddings,
        beginEmbeddingReembed,
        countChunksNeedingReembed,
        detectEmbeddingFingerprintGate,
        finalizeEmbeddingReembed,
        readMigrationAxes,
        writeEmbeddingFingerprint;
import '../src/rust/api/source_rag.dart' as rust_rag
    show listChunksNeedingReembed, updateChunkReembedded;
import '../src/internal/defaults.dart';
import '../src/internal/embedding_fingerprint.dart';
import '../src/internal/validation.dart';

export '../src/internal/embedding_fingerprint.dart'
    show
        ClearAndRestartConfirmation,
        RagEmbeddingFingerprintLock,
        RagReembedProgress;
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

  /// Fingerprint of the currently loaded embedding model.
  /// Captured during [initialize] via a one-shot probe embed.
  final String currentEmbeddingFingerprint;

  /// Non-null when boot detected an embedding fingerprint mismatch.
  /// All search and ingest entry points must throw
  /// `RagError.embeddingFingerprintMismatch` until the host app resolves it
  /// via [reembedAll] or [clearAndRestart].
  RagEmbeddingFingerprintLock? _fingerprintLock;

  RagEngine._({
    required SourceRagService ragService,
    required this.dbPath,
    required this.vocabSize,
    required this.currentEmbeddingFingerprint,
    required RagEmbeddingFingerprintLock? initialLock,
    required bool deferIndexWarmup,
  })  : _ragService = ragService,
        _deferIndexWarmup = deferIndexWarmup,
        _fingerprintLock = initialLock,
        _collectionServices = {
          SourceRagService.defaultCollectionId: ragService
        },
        _initializedCollections = {SourceRagService.defaultCollectionId},
        _collectionInitInFlight = {};

  /// Snapshot of the active embedding fingerprint lock (null when unlocked).
  ///
  /// Search and ingest entry points throw
  /// `RagError.embeddingFingerprintMismatch` while this is non-null. Use
  /// [reembedAll] to recover without losing data or [clearAndRestart] to
  /// discard embeddings after explicit confirmation.
  RagEmbeddingFingerprintLock? get embeddingFingerprintLock => _fingerprintLock;

  /// Whether boot detected an embedding fingerprint mismatch.
  bool get isEmbeddingFingerprintLocked => _fingerprintLock != null;

  void _ensureEmbeddingFingerprintUnlocked() {
    final lock = _fingerprintLock;
    if (lock != null) {
      throw RagError.embeddingFingerprintMismatch(
        lock.stored,
        lock.current,
        lock.remainingChunks,
      );
    }
  }

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

    // 6. Resolve the embedding fingerprint gate. The probe is a single
    //    one-shot embed used purely to read the model's output dimension;
    //    the result is discarded. Must happen AFTER migration_meta exists
    //    (created by ragService.init via init_source_db).
    onProgress?.call('Validating embedding fingerprint...');
    final probe = await EmbeddingService.embed(_kFingerprintProbeText);
    final currentFingerprint = computeEmbeddingFingerprint(
      modelBasename: embeddingModelBasename(modelPath),
      dim: probe.length,
      quant: kDefaultEmbeddingQuant,
    );
    final initialLock = await _resolveFingerprintGate(currentFingerprint);
    if (initialLock != null) {
      debugPrint(
        '[RagEngine] Embedding fingerprint mismatch detected: '
        'stored="${initialLock.stored}", current="$currentFingerprint", '
        'remaining=${initialLock.remainingChunks}, '
        'resume=${initialLock.resumeInProgress}. '
        'Search/ingest will be locked until reembedAll() or clearAndRestart().',
      );
    }

    onProgress?.call('Ready!');
    return RagEngine._(
      ragService: ragService,
      dbPath: dbPath,
      vocabSize: vocabSize,
      currentEmbeddingFingerprint: currentFingerprint,
      initialLock: initialLock,
      deferIndexWarmup: config.deferIndexWarmup,
    );
  }

  /// One-shot probe text used solely to read the model's output dimension.
  /// The embedding is thrown away; only `length` matters.
  static const String _kFingerprintProbeText = '__mobile_rag_engine_probe__';

  static Future<RagEmbeddingFingerprintLock?> _resolveFingerprintGate(
    String currentFingerprint,
  ) async {
    final gate = await migration_meta.detectEmbeddingFingerprintGate(
      currentFingerprint: currentFingerprint,
    );
    switch (gate) {
      case migration_meta.EmbeddingFingerprintGate_RequiresInitialBaseline():
        await migration_meta.writeEmbeddingFingerprint(
          fingerprint: currentFingerprint,
        );
        return null;
      case migration_meta.EmbeddingFingerprintGate_Ok():
        return null;
      case migration_meta.EmbeddingFingerprintGate_Mismatch(
          stored: final stored,
          current: final current,
          remainingChunks: final remaining,
          resumeInProgress: final resume,
        ):
        return RagEmbeddingFingerprintLock(
          stored: stored,
          current: current,
          remainingChunks: remaining,
          resumeInProgress: resume,
        );
    }
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

  /// Read-only snapshot of all on-device data migration axes.
  ///
  /// Reflects the `migration_meta` row written by `init_source_db`:
  /// `sql_schema_version`, `hnsw_format_version`, `bm25_stats_version`,
  /// `embedding_fingerprint`, `embedding_fingerprint_pending`, plus the last
  /// engine version recorded at boot. Later phases gate behavior on the
  /// integer axes; the fingerprint axes feed the P0-2 mismatch gate exposed
  /// via [embeddingFingerprintLock].
  Future<migration_meta.MigrationAxes> get migrationState =>
      migration_meta.readMigrationAxes();

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
    _ensureEmbeddingFingerprintUnlocked();
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

  /// Add a UTF-8 document payload while reducing input-side Dart String materialization.
  Future<SourceAddResult> addDocumentUtf8(
    Uint8List bytes, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
    String? collectionId,
  }) async {
    _ensureEmbeddingFingerprintUnlocked();
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

  /// Add a document from a file path using a Rust-side ingest fast path.
  Future<SourceAddResult> addDocumentFromFile(
    String filePath, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
    String? collectionId,
  }) async {
    _ensureEmbeddingFingerprintUnlocked();
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
    _ensureEmbeddingFingerprintUnlocked();
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
    _ensureEmbeddingFingerprintUnlocked();
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
    _ensureEmbeddingFingerprintUnlocked();
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
  /// [hydrationMode] - Controls whether high-level chunk payloads are returned
  /// as full content, lightweight previews, or omitted entirely.
  /// [previewMaxBytes] - Maximum UTF-8 bytes per chunk preview when
  /// [hydrationMode] is [SearchHydrationMode.preview].
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
    SearchHydrationMode hydrationMode = SearchHydrationMode.full,
    int previewMaxBytes = 512,
    String? collectionId,
  }) async {
    _ensureEmbeddingFingerprintUnlocked();
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
      hydrationMode: hydrationMode,
      previewMaxBytes: previewMaxBytes,
    );
  }

  /// Rebuild the HNSW index after adding documents.
  ///
  /// Call this after adding one or more documents for optimal search
  /// performance. The index enables fast approximate nearest neighbor search.
  /// [force] - If true, rebuilds even if no changes were detected (default: false).
  Future<void> rebuildIndex({bool force = false, String? collectionId}) async {
    _ensureEmbeddingFingerprintUnlocked();
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

  // ─────────────────────────────────────────────────────────────────────────
  // Embedding fingerprint recovery (P0-2)
  // ─────────────────────────────────────────────────────────────────────────

  /// Resolve an [embeddingFingerprintLock] by re-embedding every chunk with
  /// the currently loaded model.
  ///
  /// The flow is **resumable**: progress is persisted per chunk on the Rust
  /// side, so killing the app mid-stream and restarting will let a subsequent
  /// `reembedAll()` pick up where this one left off without re-doing finished
  /// chunks. `onProgress` is invoked once per chunk with the cumulative
  /// (done, total) snapshot for the current run.
  ///
  /// On success the lock is cleared and the HNSW index is rebuilt with the
  /// new embeddings. Throws [StateError] if no mismatch is active.
  ///
  /// Cold-start latency budget for this call is "background, minutes-scale"
  /// — host apps SHOULD surface progress UI.
  Future<void> reembedAll({
    void Function(RagReembedProgress progress)? onProgress,
    int batchSize = 32,
  }) async {
    final lock = _fingerprintLock;
    if (lock == null) {
      throw StateError(
        'reembedAll() called but no embedding fingerprint mismatch is active.',
      );
    }
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }
    final target = currentEmbeddingFingerprint;
    final initialRemaining = await migration_meta.beginEmbeddingReembed(
      targetFingerprint: target,
    );
    final total = initialRemaining;
    var done = 0;
    onProgress?.call(RagReembedProgress(done: done, total: total));

    while (true) {
      final batch = await rust_rag.listChunksNeedingReembed(
        targetFingerprint: target,
        limit: batchSize,
      );
      if (batch.isEmpty) break;
      for (final chunk in batch) {
        final embedding = await EmbeddingService.embed(chunk.content);
        await rust_rag.updateChunkReembedded(
          chunkId: chunk.chunkId,
          embedding: embedding,
          targetFingerprint: target,
        );
        done += 1;
        onProgress?.call(RagReembedProgress(done: done, total: total));
        // Yield so the embed loop never starves the event queue (e.g. so
        // host-app UI updates can land between chunks).
        await Future<void>.delayed(Duration.zero);
      }
    }

    await migration_meta.finalizeEmbeddingReembed(targetFingerprint: target);
    _fingerprintLock = null;
    debugPrint(
      '[RagEngine] reembedAll: completed $done/$total chunks; '
      'fingerprint now "$target". Rebuilding HNSW index...',
    );
    // The chunk embeddings just got rotated; force a rebuild so vector search
    // is consistent with the new fingerprint before we hand control back.
    await _ragService.rebuildIndex(force: true);
  }

  /// Resolve an [embeddingFingerprintLock] by discarding every on-device
  /// embedding (chunks table) and rotating the fingerprint baseline.
  ///
  /// `confirm` MUST be
  /// [ClearAndRestartConfirmation.iUnderstandThisDeletesAllOnDeviceEmbeddings];
  /// the parameter exists solely to make the destructive choice visible at
  /// every call site. The `sources` table is preserved so the host app can
  /// re-ingest the original documents through the normal `addDocument` flow.
  ///
  /// Throws [StateError] if no mismatch is active.
  Future<void> clearAndRestart({
    required ClearAndRestartConfirmation confirm,
  }) async {
    // Reference the parameter so static analysis confirms the caller passed
    // an explicit value (typing out the sentinel name is the consent).
    identical(
      confirm,
      ClearAndRestartConfirmation.iUnderstandThisDeletesAllOnDeviceEmbeddings,
    );
    if (_fingerprintLock == null) {
      throw StateError(
        'clearAndRestart() called but no embedding fingerprint mismatch is active.',
      );
    }
    final target = currentEmbeddingFingerprint;
    final deleted = await migration_meta.acknowledgeAndClearEmbeddings(
      confirmation: kEmbeddingClearConfirmationToken,
      newFingerprint: target,
    );
    _fingerprintLock = null;
    debugPrint(
      '[RagEngine] clearAndRestart: deleted $deleted chunks; '
      'fingerprint reset to "$target". Rebuilding empty HNSW index...',
    );
    await _ragService.rebuildIndex(force: true);
  }

  /// Up-to-date count of chunks still tagged with a non-current fingerprint.
  ///
  /// Safe to call while reembed is running — uses a read-only SELECT.
  Future<int> reembedRemaining() async {
    final count = await migration_meta.countChunksNeedingReembed(
      targetFingerprint: currentEmbeddingFingerprint,
    );
    return count;
  }

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
