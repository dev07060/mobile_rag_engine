/// High-level RAG service for managing sources and chunks.
///
/// This service provides a convenient API that combines:
/// - Rust plain-text and markdown chunking for document splitting
/// - EmbeddingService for vector generation
/// - Rust source_rag APIs for storage and search
/// - ContextBuilder for LLM context assembly
/// - Hybrid search combining vector and BM25 keyword search
library;

import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../src/rust/api/error.dart';
import '../src/rust/api/source_rag.dart' as rust_rag;
import '../src/rust/api/source_rag.dart'
    show SourceStats, ChunkSearchResult, SourceEntry;
import '../src/rust/api/ingest_session.dart' as rust_ingest;
import '../src/rust/api/hybrid_search.dart' as hybrid;
import 'context_builder.dart';
import 'embedding_service.dart';
import '../src/internal/defaults.dart';
import '../src/internal/validation.dart';
import '../utils/error_utils.dart';
import '../src/rust/api/logger.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'dart:async';

extension RagErrorMessage on RagError {
  String get message => when(
        databaseError: (msg) => msg,
        ioError: (msg) => msg,
        modelLoadError: (msg) => msg,
        invalidInput: (msg) => msg,
        staleSearchHandle: (msg) => msg,
        concurrentMutation: (msg) => msg,
        internalError: (msg) => msg,
        unsupportedMigrationVersion: (axis, stored, supported) =>
            "Unsupported migration axis '$axis': stored=$stored, supported=$supported",
        unknown: (msg) => msg,
      );
}

/// Chunking strategy for document processing.
enum ChunkingStrategy {
  /// Default plain-text chunking with paragraph/line planning and tokenizer guard
  recursive,

  /// Markdown-aware chunking (preserves headers, code blocks, tables)
  markdown,
}

enum DuplicateSourceIngestionDecision {
  skipCompleted,
  alreadyInProgress,
  resetAndResume,
}

@visibleForTesting
DuplicateSourceIngestionDecision decideDuplicateSourceIngestion({
  required String? status,
  required int chunkCount,
}) {
  final normalizedStatus = status ?? 'completed';
  switch (normalizedStatus) {
    case 'completed':
      return chunkCount > 0
          ? DuplicateSourceIngestionDecision.skipCompleted
          : DuplicateSourceIngestionDecision.resetAndResume;
    case 'pending':
    case 'processing':
      return DuplicateSourceIngestionDecision.alreadyInProgress;
    case 'failed':
      return DuplicateSourceIngestionDecision.resetAndResume;
    default:
      // Backward-compat fallback for unknown status values.
      return chunkCount > 0
          ? DuplicateSourceIngestionDecision.skipCompleted
          : DuplicateSourceIngestionDecision.resetAndResume;
  }
}

String _chunkLookupKey(int sourceId, int chunkIndex) => '$sourceId:$chunkIndex';

// TODO(metadata-breaking): replace this compatibility encoding with dedicated
// chunkType/contextualPath fields in the next breaking schema/API cleanup.
String _encodeStructuredChunkType(String chunkType, {String? headerPath}) {
  final normalizedHeaderPath = headerPath?.trim();
  if (normalizedHeaderPath == null || normalizedHeaderPath.isEmpty) {
    return chunkType;
  }

  return '$chunkType|$normalizedHeaderPath';
}

@visibleForTesting
String buildChunkEmbeddingText({
  required String content,
  required String chunkType,
}) {
  return renderContextText(content: content, chunkType: chunkType);
}

ChunkSearchResult _chunkSearchResultFromHybrid(
  hybrid.HybridSearchResult result,
) {
  return ChunkSearchResult(
    chunkId: result.docId,
    sourceId: result.sourceId,
    chunkIndex: result.chunkIndex,
    content: result.content,
    chunkType: 'general',
    similarity: result.score,
    metadata: result.metadata,
  );
}

@visibleForTesting
ChunkSearchResult mergeCanonicalChunkSearchResult({
  required ChunkSearchResult fallback,
  ChunkSearchResult? canonical,
}) {
  if (canonical == null) {
    return fallback;
  }

  return ChunkSearchResult(
    chunkId: fallback.chunkId,
    sourceId: fallback.sourceId,
    chunkIndex: fallback.chunkIndex,
    content: canonical.content,
    chunkType: canonical.chunkType,
    similarity: fallback.similarity,
    metadata: canonical.metadata ?? fallback.metadata,
  );
}

/// Result of adding a source document with automatic chunking.
class SourceAddResult {
  final int sourceId;
  final bool isDuplicate;
  final int chunkCount;
  final String message;

  /// UTF-8 byte length of the text body after file parsing / decoding.
  final int? bodyByteLength;

  /// Text length as Dart `String.length` would report it (UTF-16 code units).
  ///
  /// This lets file-path ingest callers display the same "extracted text
  /// length" style UI without materializing the full body in Dart.
  final int? bodyCharLength;

  SourceAddResult({
    required this.sourceId,
    required this.isDuplicate,
    required this.chunkCount,
    required this.message,
    this.bodyByteLength,
    this.bodyCharLength,
  });
}

/// Search result with assembled context.
class RagSearchResult {
  /// Individual chunk results.
  final List<ChunkSearchResult> chunks;

  /// Assembled context for LLM.
  final AssembledContext context;

  RagSearchResult({required this.chunks, required this.context});
}

/// Hydration mode for high-level hybrid search results.
enum SearchHydrationMode {
  /// Preserve the legacy full-content chunk contract.
  full,

  /// Return lightweight excerpt-based chunks for UI/debug style listing.
  preview,

  /// Return only assembled context and omit chunk payloads.
  contextOnly,
}

/// Result of the additive low-level search lane.
///
/// `hits` is a bounded metadata-only view. Use [handle] for explicit hydration
/// or Rust-side context assembly when needed.
class SearchMetaResult {
  final rust_rag.SearchHandle handle;
  final List<rust_rag.SearchHitMeta> hits;

  const SearchMetaResult({required this.handle, required this.hits});

  Future<void> dispose() => handle.dispose();
}

/// High-level service for source-based RAG operations.
class SourceRagService {
  static const String defaultCollectionId = '__default__';

  final String dbPath;

  /// Maximum characters per chunk (default: [kDefaultMaxChunkChars])
  final int maxChunkChars;

  /// Overlap characters between chunks for context continuity
  final int overlapChars;

  /// Path to the ONNX model file.
  final String? modelPath;
  final String collectionId;

  SourceRagService({
    required this.dbPath,
    this.modelPath,
    int maxChunkChars = kDefaultMaxChunkChars,
    int overlapChars = kDefaultOverlapChars,
    this.collectionId = defaultCollectionId,
  })  : maxChunkChars = normalizeMaxChunkChars(
          maxChunkChars,
          context: 'SourceRagService',
        ),
        overlapChars = normalizeOverlapChars(
          overlapChars,
          context: 'SourceRagService',
        );

  SourceRagService inCollection(String id) => SourceRagService(
        dbPath: dbPath,
        modelPath: modelPath,
        maxChunkChars: maxChunkChars,
        overlapChars: overlapChars,
        collectionId: id.trim().isEmpty ? defaultCollectionId : id.trim(),
      );

  /// Detect the appropriate chunking strategy based on file extension.
  static ChunkingStrategy detectChunkingStrategy(String? filePath) {
    if (filePath == null) return ChunkingStrategy.recursive;

    final ext = filePath.split('.').lastOrNull?.toLowerCase() ?? '';
    return switch (ext) {
      'md' || 'markdown' => ChunkingStrategy.markdown,
      _ => ChunkingStrategy.recursive,
    };
  }

  // Shared logger stream across all collection-scoped service instances.
  static StreamSubscription<String>? _logSubscription;

  /// Helper to convert `List<int>` to the specific `Int64List` type required by FRB.
  /// We do this manually because frb.Int64List.fromList() might return a native
  /// dart:typed_data Int64List which can cause type mismatch errors if FRB
  /// expects its own wrapped type.
  frb.Int64List _toInt64List(List<int> list) {
    // Try using the constructor directly
    final result = frb.Int64List(list.length);
    for (var i = 0; i < list.length; i++) {
      result[i] = list[i];
    }
    return result;
  }

  rust_rag.ContextAssemblyStrategy _toRustAssemblyStrategy(
    ContextStrategy strategy,
  ) {
    return switch (strategy) {
      ContextStrategy.relevanceFirst =>
        rust_rag.ContextAssemblyStrategy.relevanceFirst,
      ContextStrategy.diverseSources =>
        rust_rag.ContextAssemblyStrategy.diverseSources,
      ContextStrategy.chronological =>
        rust_rag.ContextAssemblyStrategy.chronological,
    };
  }

  String get _dbPathWithoutExtension {
    const knownDbExtensions = ['.sqlite3', '.sqlite', '.db'];
    final lower = dbPath.toLowerCase();
    for (final ext in knownDbExtensions) {
      if (lower.endsWith(ext)) {
        return dbPath.substring(0, dbPath.length - ext.length);
      }
    }
    return dbPath;
  }

  bool get _isDefaultCollection => collectionId == defaultCollectionId;

  String get _collectionFileSuffix {
    // Deterministic FNV-1a 32-bit hash for stable file names.
    var hash = 0x811C9DC5;
    for (final codeUnit in collectionId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Get the HNSW index path (derived from dbPath + collectionId)
  String get _indexPath => _isDefaultCollection
      ? '${_dbPathWithoutExtension}_hnsw'
      : '${_dbPathWithoutExtension}_hnsw_$_collectionFileSuffix';

  /// File marker to indicate if the index is dirty (needs rebuild).
  /// This persists across app restarts for crash recovery.
  File get _dirtyMarkerFile => _isDefaultCollection
      ? File('$_dbPathWithoutExtension.dirty')
      : File('$_dbPathWithoutExtension.$_collectionFileSuffix.dirty');

  /// Memory flag to track dirty state alongside the file marker.
  bool _needsRebuild = false;
  int _dirtyVersion = 0;

  /// Whether all retrieval indexes are ready for full-quality search.
  bool _isIndexReady = false;

  /// Completes when the latest index warmup/rebuild task has finished.
  Future<void> _warmupFuture = Future.value();

  /// Serializes index tasks to avoid overlapping rebuild/load operations.
  Future<void> _indexTaskQueue = Future.value();

  bool get isIndexReady => _isIndexReady;
  Future<void> get warmupFuture => _warmupFuture;

  Future<void> _enqueueIndexTask(Future<void> Function() task) {
    final queued = _indexTaskQueue.then((_) => task());
    _indexTaskQueue = queued.catchError((_) {});
    return queued;
  }

  /// Mark the index as dirty (needs rebuild).
  /// Creates a persistent marker file.
  Future<void> _markDirty() async {
    _needsRebuild = true;
    _dirtyVersion++;
    _isIndexReady = false;
    try {
      if (!await _dirtyMarkerFile.exists()) {
        await _dirtyMarkerFile.create();
      }
    } catch (e) {
      debugPrint('[SourceRagService] Failed to create dirty marker: $e');
    }
  }

  /// Mark the index as clean (rebuild complete).
  /// Deletes the persistent marker file.
  Future<void> _markClean({int? expectedVersion}) async {
    if (expectedVersion != null && expectedVersion != _dirtyVersion) {
      debugPrint(
        '[SourceRagService] Index changed during build; keeping dirty marker.',
      );
      return;
    }
    _needsRebuild = false;
    try {
      if (await _dirtyMarkerFile.exists()) {
        await _dirtyMarkerFile.delete();
      }
    } catch (e) {
      debugPrint('[SourceRagService] Failed to delete dirty marker: $e');
    }
  }

  Future<void> _runIndexWarmup() async {
    _isIndexReady = false;
    final startDirtyVersion = _dirtyVersion;

    // BM25 is currently in-memory only and fast to rebuild from SQLite
    debugPrint('[SourceRagService] init: Rebuilding BM25 index...');
    await rust_rag.rebuildChunkBm25IndexForCollection(
      collectionId: collectionId,
    );

    // HNSW can be slow to rebuild for large datasets, so we try loading from disk first
    debugPrint(
      '[SourceRagService] init: Attempting to load HNSW index from disk...',
    );
    final loaded = await tryLoadCachedIndex();

    if (loaded && !_needsRebuild) {
      debugPrint(
        '[SourceRagService] init: HNSW index loaded successfully from cache.',
      );
    } else {
      if (_needsRebuild) {
        debugPrint(
          '[SourceRagService] init: Dirty marker found, forcing HNSW rebuild.',
        );
      } else {
        debugPrint(
          '[SourceRagService] init: No cached HNSW index found, rebuilding from DB.',
        );
      }
      await rust_rag.rebuildChunkHnswIndexForCollection(
        collectionId: collectionId,
      );
      // Save the newly built index for next time
      await saveIndex();
    }

    await _markClean(expectedVersion: startDirtyVersion);
    _isIndexReady = !_needsRebuild;
  }

  /// Initialize the source database.
  Future<void> init({bool deferIndexWarmup = false}) async {
    try {
      debugPrint('[SourceRagService] init: Starting...');

      // 1-3. Initialize Logger (only if not already active)

      // Skipping re-init avoids potential deadlocks with closeLogStream/logging threads
      if (_logSubscription == null) {
        debugPrint('[SourceRagService] init: Initializing logger system...');
        await initLogger(); // Idempotent

        // Close any existing (though _logSubscription is null, be safe)
        await _cleanupLogStream();

        // Start fresh log stream
        debugPrint('[SourceRagService] init: Starting log stream...');
        _logSubscription = initLogStream().listen((log) {
          debugPrint(log);
        });
      } else {
        debugPrint(
          '[SourceRagService] init: Logger stream already active, skipping re-init.',
        );
      }

      // 4. Initialize DB
      debugPrint('[SourceRagService] init: Initializing Source DB...');
      await rust_rag.initSourceDb();

      // 4.1 Check for dirty marker (Crash Recovery)
      if (await _dirtyMarkerFile.exists()) {
        debugPrint(
          '[SourceRagService] Found dirty marker. Previous session might have crashed.',
        );
        debugPrint('[SourceRagService] Index will be rebuilt automatically.');
        if (!_needsRebuild) {
          _needsRebuild = true;
          _dirtyVersion++;
        }
      }

      // 5. Load or rebuild indexes.
      final warmup = _enqueueIndexTask(_runIndexWarmup);
      _warmupFuture = warmup;

      if (deferIndexWarmup) {
        debugPrint(
          '[SourceRagService] init: deferIndexWarmup=true, continuing while index warms up in background.',
        );
        unawaited(
          warmup.catchError((error, _) {
            debugPrint('[SourceRagService] Background warmup failed: $error');
            _isIndexReady = false;
          }),
        );
      } else {
        await warmup;
      }

      debugPrint('[SourceRagService] init: Done!');
    } on RagError catch (e) {
      // Smart Error Handling integration
      debugPrint(
        '[SmartError] ${e.userFriendlyMessage} (Tech: ${e.technicalMessage})',
      );
      rethrow;
    }
  }

  /// Clean up log stream resources (both Dart subscription and Rust sink).
  Future<void> _cleanupLogStream() async {
    await _logSubscription?.cancel();
    _logSubscription = null;
    try {
      closeLogStream(); // Close Rust-side sink
    } catch (_) {
      // Ignore errors during cleanup
    }
  }

  /// Dispose resources held by this service.
  /// Call this when the service is no longer needed.
  Future<void> dispose() async {
    await _cleanupLogStream();
  }

  /// Try to load cached HNSW index.
  ///
  /// Returns true if a previously built index exists (marker found).
  /// The actual index data is rebuilt from DB when [rebuildIndex] is called.
  ///
  /// Usage pattern:
  /// ```dart
  /// await service.init();
  /// final hasCached = await service.tryLoadCachedIndex();
  /// if (!hasCached || forceRebuild) {
  ///   await service.rebuildIndex();
  /// }
  /// ```
  Future<bool> tryLoadCachedIndex() async {
    final exists = await rust_rag.loadCollectionHnswIndex(
      collectionId: collectionId,
      basePath: _indexPath,
    );
    return exists;
  }

  /// Save HNSW index marker to disk.
  ///
  /// Call this after [rebuildIndex] to mark that an index was built.
  /// This allows faster startup detection on next app launch.
  Future<void> saveIndex() async {
    await rust_rag.saveCollectionHnswIndex(
      collectionId: collectionId,
      basePath: _indexPath,
    );
  }

  /// Add a source document with automatic chunking and embedding.
  ///
  /// The document is:
  /// 1. Split into chunks based on file type (auto-detected from [filePath])
  /// 2. Each chunk is embedded (micro-batch streaming, [kIngestionBatchSize] at a time)
  /// 3. Source and chunks are incrementally stored in DB
  ///
  /// If [filePath] is provided, chunking strategy is auto-detected:
  /// - `.md`, `.markdown` → Markdown-aware chunking (preserves headers, code blocks)
  /// - Other files → Default recursive chunking
  ///
  /// **Memory safety:** Uses streaming micro-batch pipeline instead of loading
  /// all embeddings into memory. Each batch of [kIngestionBatchSize] chunks is
  /// embedded, saved to DB, then released — keeping memory usage flat.
  ///
  /// [chunkDelay] controls the yield duration between batches (default: 10ms).
  /// This allows GC to run and prevents thermal throttling on mobile devices.
  Future<SourceAddResult> addSourceWithChunking(
    String content, {
    String? metadata,
    String? name,
    String? filePath,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) async {
    final effectiveStrategy = strategy ??
        (filePath != null &&
                (filePath.endsWith('.md') || filePath.endsWith('.markdown'))
            ? ChunkingStrategy.markdown
            : ChunkingStrategy.recursive);

    // Hand the document body to Rust exactly once. `prepareSourceIngestion`
    // performs the source-row INSERT, claim, duplicate decision, chunker run,
    // and stages chunk content in a Rust-resident IngestSession — so neither
    // the chunk content nor the full document round-trips back to Dart.
    final prepared = await rust_ingest.prepareSourceIngestion(
      collectionId: collectionId,
      content: content,
      metadata: metadata,
      name: name ?? filePath,
      strategy: _toIngestStrategy(effectiveStrategy),
      maxChars: maxChunkChars,
      overlapChars: overlapChars,
    );
    return _runPreparedIngestion(
      prepared,
      chunkDelay: chunkDelay,
      onProgress: onProgress,
    );
  }

  /// Shared drain loop for every `prepareSourceIngestion*` entrypoint.
  ///
  /// Handles duplicate-skip / duplicate-in-progress states, runs the
  /// embedding micro-batch pipeline, and finalizes / aborts / disposes the
  /// session. Keeps the public ingest entrypoints identical in behavior.
  Future<SourceAddResult> _runPreparedIngestion(
    rust_ingest.PreparedIngestion prepared, {
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) async {
    final sourceId = prepared.sourceId.toInt();

    switch (prepared.state) {
      case rust_ingest.PreparedSourceState.duplicateSkip:
        return SourceAddResult(
          sourceId: sourceId,
          isDuplicate: true,
          chunkCount: 0,
          message: prepared.message,
          bodyByteLength: prepared.bodyByteLength,
          bodyCharLength: prepared.bodyCharLength,
        );
      case rust_ingest.PreparedSourceState.duplicateInProgress:
        return SourceAddResult(
          sourceId: sourceId,
          isDuplicate: true,
          chunkCount: 0,
          message: prepared.message,
          bodyByteLength: prepared.bodyByteLength,
          bodyCharLength: prepared.bodyCharLength,
        );
      case rust_ingest.PreparedSourceState.createdReady:
      case rust_ingest.PreparedSourceState.resumeReady:
        break;
    }

    final session = prepared.session;
    if (session == null) {
      throw StateError(
        'prepareSourceIngestion returned ${prepared.state} without a session handle.',
      );
    }

    final isResume =
        prepared.state == rust_ingest.PreparedSourceState.resumeReady;
    final total = prepared.totalChunks;
    debugPrint(
      '[SourceRagService] Prepared $total chunks (resume=$isResume). Starting streaming ingestion...',
    );

    // Mark dirty only when ingestion will actually run (parity with old path).
    await _markDirty();

    final effectiveDelay = chunkDelay ?? const Duration(milliseconds: 10);
    var savedCount = 0;
    var sessionDisposed = false;

    try {
      while (savedCount < total) {
        final batch =
            await session.takeEmbeddingBatch(batchSize: kIngestionBatchSize);
        if (batch.isEmpty) break;

        final embeddings = <rust_ingest.ChunkEmbedding>[];
        for (final request in batch) {
          final embedding =
              await EmbeddingService.embed(request.embeddingText);
          embeddings.add(
            rust_ingest.ChunkEmbedding(
              chunkIndex: request.chunkIndex,
              embedding: embedding,
            ),
          );
        }

        final committed =
            await session.commitEmbeddings(embeddings: embeddings);
        savedCount += committed;
        onProgress?.call(savedCount, total);

        if (savedCount < total) {
          await Future.delayed(effectiveDelay);
        }
      }

      await session.finalize();
      return SourceAddResult(
        sourceId: sourceId,
        isDuplicate: isResume,
        chunkCount: savedCount,
        message: isResume ? 'Source resumed and completed' : prepared.message,
        bodyByteLength: prepared.bodyByteLength,
        bodyCharLength: prepared.bodyCharLength,
      );
    } catch (e) {
      try {
        await session.abort();
      } catch (_) {
        // best-effort: abort errors are surfaced via the rethrow below
      }
      rethrow;
    } finally {
      if (!sessionDisposed) {
        sessionDisposed = true;
        try {
          await session.dispose();
        } catch (_) {}
      }
    }
  }

  rust_ingest.IngestStrategy _toIngestStrategy(ChunkingStrategy strategy) {
    switch (strategy) {
      case ChunkingStrategy.markdown:
        return rust_ingest.IngestStrategy.markdown;
      case ChunkingStrategy.recursive:
        return rust_ingest.IngestStrategy.recursive;
    }
  }

  /// Add a document from UTF-8 bytes while avoiding caller-side String inflation.
  ///
  /// The bytes are handed directly to Rust, which decodes UTF-8 once and runs
  /// the ingest pipeline without round-tripping the body through a Dart
  /// `String`. For a 4 MB UTF-8 buffer this saves the ~8 MB Dart heap UTF-16
  /// allocation and one Rust→Dart→Rust traffic leg compared to the legacy
  /// `extractTextFromUtf8 → addSourceWithChunking` two-step.
  Future<SourceAddResult> addSourceUtf8WithChunking(
    List<int> bytes, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) async {
    final effectiveStrategy = strategy ?? ChunkingStrategy.recursive;
    final prepared = await rust_ingest.prepareSourceIngestionFromUtf8(
      collectionId: collectionId,
      contentBytes: bytes,
      metadata: metadata,
      name: name,
      strategy: _toIngestStrategy(effectiveStrategy),
      maxChars: maxChunkChars,
      overlapChars: overlapChars,
    );
    return _runPreparedIngestion(
      prepared,
      chunkDelay: chunkDelay,
      onProgress: onProgress,
    );
  }

  /// Add a document from a file path using a Rust-side ingest fast path.
  ///
  /// The file body never crosses the FFI boundary — Rust reads the file
  /// itself and runs the rest of the staging pipeline locally. Only the path
  /// string is sent Dart→Rust. Strategy is auto-detected from the extension
  /// when [strategy] is `null` (`.md` / `.markdown` → Markdown, else
  /// Recursive). Text-like extensions (`.txt`, `.md`, `.markdown`) are
  /// decoded as UTF-8; everything else falls through to the magic-byte
  /// document extractor (PDF / DOCX).
  Future<SourceAddResult> addSourceFromFileWithChunking(
    String filePath, {
    String? metadata,
    String? name,
    ChunkingStrategy? strategy,
    Duration? chunkDelay,
    void Function(int done, int total)? onProgress,
  }) async {
    final prepared = await rust_ingest.prepareSourceIngestionFromFile(
      collectionId: collectionId,
      filePath: filePath,
      metadata: metadata,
      name: name ?? filePath,
      strategyHint: strategy == null ? null : _toIngestStrategy(strategy),
      maxChars: maxChunkChars,
      overlapChars: overlapChars,
    );
    return _runPreparedIngestion(
      prepared,
      chunkDelay: chunkDelay,
      onProgress: onProgress,
    );
  }

  /// Rebuild the HNSW and BM25 indexes after adding sources.
  /// [force] - If true, rebuilds even if no changes were detected (default: false).
  Future<void> rebuildIndex({bool force = false}) {
    if (!force && !_needsRebuild) {
      debugPrint(
        '[SourceRagService] Index is already up to date. Skipping rebuild.',
      );
      return _warmupFuture;
    }
    _isIndexReady = false;
    final startDirtyVersion = _dirtyVersion;

    final rebuildFuture = _enqueueIndexTask(() async {
      try {
        // Rebuild HNSW for vector search
        await rust_rag.rebuildChunkHnswIndexForCollection(
          collectionId: collectionId,
        );
        await saveIndex(); // Persist to disk immediately

        // Rebuild BM25 for keyword search (critical for hybrid search!)
        await rust_rag.rebuildChunkBm25IndexForCollection(
          collectionId: collectionId,
        );

        await _markClean(
          expectedVersion: startDirtyVersion,
        ); // Mark index as clean (Persistent)
        _isIndexReady = !_needsRebuild;
      } on RagError catch (e) {
        _isIndexReady = false;
        e.when(
          databaseError: (msg) =>
              debugPrint('[SmartError] DB error rebuilding index: $msg'),
          ioError: (msg) =>
              debugPrint('[SmartError] IO error rebuilding index: $msg'),
          modelLoadError: (_) {},
          invalidInput: (_) {},
          staleSearchHandle: (_) {},
          concurrentMutation: (_) {},
          internalError: (msg) => debugPrint(
            '[SmartError] Internal error rebuilding indexes: $msg',
          ),
          unsupportedMigrationVersion: (axis, stored, supported) => debugPrint(
            '[SmartError] Unsupported migration axis $axis '
            '(stored=$stored, supported=$supported) while rebuilding indexes',
          ),
          unknown: (_) {},
        );
        rethrow;
      }
    });

    _warmupFuture = rebuildFuture;
    return rebuildFuture;
  }

  /// Regenerate embeddings for all existing chunks using the current model.
  /// This is needed when the embedding model or tokenizer has been updated.
  Future<void> regenerateAllEmbeddings({
    void Function(int done, int total)? onProgress,
  }) async {
    // 1. Get total stats for progress tracking
    final stats = await rust_rag.getSourceStatsInCollection(
      collectionId: collectionId,
    );
    final totalChunks = stats.chunkCount.toInt();

    debugPrint(
      '[regenerateAllEmbeddings] Found $totalChunks chunks to re-embed (Safe Batch Mode)',
    );

    // 2. Iterate by Source to ensure memory safety
    // Instead of loading all chunks (which could be huge), we process source by source
    final sources = await rust_rag.listSourcesInCollection(
      collectionId: collectionId,
    );
    int processedCount = 0;

    for (final source in sources) {
      final sourceId = source.id.toInt();
      final chunkCount = await rust_rag.getSourceChunkCount(
        sourceId: source.id,
      );

      // Process chunks for this source in batches
      const batchSize = 50;
      for (var offset = 0; offset < chunkCount; offset += batchSize) {
        // Fetch batch of chunks
        // We use getAdjacentChunks to fetch specific ranges safely
        // minIndex = offset, maxIndex = offset + batchSize - 1
        List<ChunkSearchResult> batch;
        try {
          batch = await rust_rag.getAdjacentChunks(
            sourceId: source.id,
            minIndex: offset,
            maxIndex: offset + batchSize - 1, // Inclusive
          );
        } catch (e) {
          debugPrint(
            '[regenerateAllEmbeddings] Failed to fetch batch for source $sourceId: $e',
          );
          continue;
        }

        // Re-embed and update each chunk
        for (final chunk in batch) {
          try {
            final embeddingText = buildChunkEmbeddingText(
              content: chunk.content,
              chunkType: chunk.chunkType,
            );
            final embedding = await EmbeddingService.embed(embeddingText);
            await rust_rag.updateChunkEmbedding(
              chunkId: chunk.chunkId,
              embedding: embedding,
            );
          } catch (e) {
            debugPrint(
              '[regenerateAllEmbeddings] Failed to update chunk ${chunk.chunkId}: $e',
            );
          }
        }

        processedCount += batch.length;
        onProgress?.call(processedCount, totalChunks);

        // Yield to event loop to prevent UI jank
        await Future.delayed(Duration.zero);
      }
    }

    debugPrint('[regenerateAllEmbeddings] Completed. Rebuilding HNSW index...');

    // 3. Rebuild HNSW index
    await rebuildIndex(force: true);

    debugPrint('[regenerateAllEmbeddings] Done!');
  }

  /// Fetch adjacent chunks for a given source and index range.
  ///
  /// Useful for "Show More" or "Read Previous/Next" features.
  Future<List<ChunkSearchResult>> getAdjacentChunks({
    required int sourceId,
    required int minIndex,
    required int maxIndex,
  }) {
    return rust_rag.getAdjacentChunks(
      sourceId: sourceId,
      minIndex: minIndex,
      maxIndex: maxIndex,
    );
  }

  /// Low-level metadata-first hybrid search lane.
  ///
  /// Returns a generation-pinned [SearchMetaResult]. The returned handle must
  /// be disposed when no longer needed.
  Future<SearchMetaResult> searchMeta(
    String query, {
    int topK = 10,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
  }) async {
    final normalizedWeights = normalizeHybridWeights(
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      context: 'SourceRagService.searchMeta',
    );

    final queryEmbedding = await EmbeddingService.embed(query);
    await rust_rag.activateCollectionForHybridSearch(
      collectionId: collectionId,
      basePath: _indexPath,
    );

    try {
      final handle = await rust_rag.searchMetaHybrid(
        collectionId: collectionId,
        queryText: query,
        queryEmbedding: queryEmbedding,
        options: rust_rag.SearchMetaHybridOptions(
          topK: topK,
          vectorWeight: normalizedWeights.vectorWeight,
          bm25Weight: normalizedWeights.bm25Weight,
          sourceIds: sourceIds != null ? _toInt64List(sourceIds) : null,
          adjacentChunks: adjacentChunks,
        ),
      );
      final hits = await handle.hitMeta();
      return SearchMetaResult(handle: handle, hits: hits);
    } on RagError catch (e) {
      e.when(
        databaseError: (msg) =>
            debugPrint('[SmartError] searchMeta DB error: $msg'),
        ioError: (msg) => debugPrint('[SmartError] searchMeta IO error: $msg'),
        modelLoadError: (_) {},
        invalidInput: (msg) =>
            debugPrint('[SmartError] searchMeta invalid input: $msg'),
        staleSearchHandle: (msg) =>
            debugPrint('[SmartError] searchMeta stale handle: $msg'),
        concurrentMutation: (msg) => debugPrint(
          '[SmartError] searchMeta concurrent mutation: $msg',
        ),
        internalError: (msg) =>
            debugPrint('[SmartError] searchMeta internal error: $msg'),
        unsupportedMigrationVersion: (axis, stored, supported) => debugPrint(
          '[SmartError] searchMeta blocked by unsupported migration axis '
          '$axis (stored=$stored, supported=$supported)',
        ),
        unknown: (msg) => debugPrint('[SmartError] searchMeta unknown: $msg'),
      );
      rethrow;
    }
  }

  Future<rust_rag.AssembledContextV2> assembleContext({
    required rust_rag.SearchHandle searchHandle,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    String separator = '\n\n---\n\n',
    bool singleSourceMode = false,
  }) {
    return searchHandle.assembleContext(
      options: rust_rag.AssembleContextOptions(
        tokenBudget: tokenBudget,
        strategy: _toRustAssemblyStrategy(strategy),
        separator: separator,
        singleSourceMode: singleSourceMode,
      ),
    );
  }

  Future<List<ChunkSearchResult>> hydrateChunks({
    required rust_rag.SearchHandle searchHandle,
    required List<int> chunkIds,
  }) {
    return searchHandle.hydrateChunks(chunkIds: _toInt64List(chunkIds));
  }

  Future<List<rust_rag.ChunkExcerptResult>> getChunkExcerpts({
    required rust_rag.SearchHandle searchHandle,
    required List<int> chunkIds,
    required int maxBytes,
  }) {
    return searchHandle.getChunkExcerpts(
      chunkIds: _toInt64List(chunkIds),
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
  }) {
    return rust_rag.deriveContextBudgetForPromptV2(
      fullPromptBudget: fullPromptBudget,
      query: query,
      systemInstruction: systemInstruction,
      useStrictMode: useStrictMode,
      safetyMarginTokens: safetyMarginTokens,
      fixedPromptOverheadTokens: fixedPromptOverheadTokens,
    );
  }

  /// Search for relevant chunks and assemble context for LLM.
  ///
  /// [adjacentChunks] - Number of adjacent chunks to include before/after each
  /// matched chunk (default: 0). Setting this to 1 will include the chunk
  /// before and after each matched chunk, helping with long articles.
  /// [singleSourceMode] - If true, only include chunks from the most relevant source.
  Future<RagSearchResult> search(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
    List<int>? sourceIds,
  }) async {
    // 1. Generate query embedding
    final queryEmbedding = await EmbeddingService.embed(query);

    // DEBUG: Log embedding stats
    final embNorm = queryEmbedding.fold<double>(0, (sum, v) => sum + v * v);
    debugPrint('[DEBUG] Query: "$query"');
    debugPrint(
      '[DEBUG] Embedding norm: ${embNorm.toStringAsFixed(4)}, dims: ${queryEmbedding.length}',
    );
    debugPrint(
      '[DEBUG] First 5 values: ${queryEmbedding.take(5).map((v) => v.toStringAsFixed(4)).toList()}',
    );

    // 2. Search chunks
    late List<ChunkSearchResult> chunks;
    try {
      if (sourceIds != null && sourceIds.isNotEmpty) {
        // Use hybrid search with filter for vector search capability is limited in filters
        // For strictly vector search with filters, we'd need HNSW filtering which is more complex.
        // For now, we'll use hybrid search with 1.0 vector weight if sourceIds are provided.
        final hybridResults = await searchHybrid(
          query,
          topK: topK,
          vectorWeight: 1.0,
          bm25Weight: 0.0,
          sourceIds: sourceIds,
        );
        chunks = await _hydrateCanonicalChunkResults(
          hybridResults.map(_chunkSearchResultFromHybrid).toList(),
        );
      } else {
        chunks = await rust_rag.searchChunksInCollection(
          collectionId: collectionId,
          queryEmbedding: queryEmbedding,
          topK: topK,
        );
      }
    } on RagError catch (e) {
      e.when(
        databaseError: (msg) =>
            debugPrint('[SmartError] Search failed (database): $msg'),
        ioError: (msg) => debugPrint('[SmartError] Search IO error: $msg'),
        modelLoadError: (_) {},
        invalidInput: (msg) =>
            debugPrint('[SmartError] Invalid search parameters: $msg'),
        staleSearchHandle: (msg) =>
            debugPrint('[SmartError] Search stale handle: $msg'),
        concurrentMutation: (msg) =>
            debugPrint('[SmartError] Search concurrent mutation: $msg'),
        internalError: (msg) =>
            debugPrint('[SmartError] Search engine failure: $msg'),
        unsupportedMigrationVersion: (axis, stored, supported) => debugPrint(
          '[SmartError] Search blocked by unsupported migration axis '
          '$axis (stored=$stored, supported=$supported)',
        ),
        unknown: (msg) => debugPrint('[SmartError] Unknown search error: $msg'),
      );
      rethrow;
    }

    // 3. Filter to single source FIRST (before adjacent expansion)
    // Pass the original query for text matching
    if (singleSourceMode && chunks.isNotEmpty) {
      chunks = _filterToMostRelevantSource(chunks, query);
    }

    // 4. Expand with adjacent chunks (only for the selected source)
    if (adjacentChunks > 0 && chunks.isNotEmpty) {
      chunks = await _expandWithAdjacentChunks(chunks, adjacentChunks);
    }

    // 5. Assemble context (pass singleSourceMode to skip headers when single source)
    final context = ContextBuilder.build(
      searchResults: chunks,
      tokenBudget: tokenBudget,
      strategy: strategy,
      singleSourceMode: singleSourceMode, // Pass through to skip headers
    );

    return RagSearchResult(chunks: chunks, context: context);
  }

  /// Filter to only chunks from the most relevant source.
  /// Prioritizes sources that contain exact text from the query.
  List<ChunkSearchResult> _filterToMostRelevantSource(
    List<ChunkSearchResult> results,
    String query,
  ) {
    if (results.isEmpty) return results;

    // Extract key phrases from query
    final queryLower = query.toLowerCase();

    // First: Try to find source that contains the exact query text
    final sourceTextMatches = <int, int>{}; // sourceId -> match count

    for (final chunk in results) {
      final sourceId = chunk.sourceId.toInt();
      final contentLower = chunk.content.toLowerCase();

      // Check if chunk contains significant part of query
      // Split query into meaningful segments and check for matches
      final queryWords = _extractSignificantQueryTerms(query);
      int matchCount = 0;
      for (final word in queryWords) {
        if (contentLower.contains(word.toLowerCase())) {
          matchCount++;
        }
      }

      // Bonus for exact phrase match
      if (contentLower.contains(queryLower) || chunk.content.contains(query)) {
        matchCount += 100; // Strong bonus for exact match
      }

      sourceTextMatches[sourceId] =
          (sourceTextMatches[sourceId] ?? 0) + matchCount;
    }

    // Find source with highest text match count
    int? bestSourceByText;
    int bestTextMatchCount = 0;
    for (final entry in sourceTextMatches.entries) {
      if (entry.value > bestTextMatchCount) {
        bestTextMatchCount = entry.value;
        bestSourceByText = entry.key;
      }
    }

    // If we have a source with good text matches, use it
    if (bestSourceByText != null && bestTextMatchCount > 0) {
      return results
          .where((c) => c.sourceId.toInt() == bestSourceByText)
          .toList();
    }

    // Fallback: Sum similarity scores by source
    final sourceScores = <int, double>{};
    for (final chunk in results) {
      final sourceId = chunk.sourceId.toInt();
      sourceScores[sourceId] = (sourceScores[sourceId] ?? 0) + chunk.similarity;
    }

    // Find source with highest total score
    int? bestSourceId;
    double bestScore = -1;
    for (final entry in sourceScores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestSourceId = entry.key;
      }
    }

    if (bestSourceId == null) return results;

    // Filter to only that source
    return results.where((c) => c.sourceId.toInt() == bestSourceId).toList();
  }

  static List<String> _extractSignificantQueryTerms(String query) {
    final splitter = RegExp(r'[\s\(\)\[\]\{\},.!?:;/|_\-]+');
    return query
        .split(splitter)
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .where((w) => _containsCjkOrHangul(w) || w.length >= 2)
        .map((w) => w.toLowerCase())
        .toSet()
        .toList();
  }

  static bool _containsCjkOrHangul(String text) {
    return RegExp(
      r'[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7A3]',
    ).hasMatch(text);
  }

  /// Expand search results with adjacent chunks from the same source.
  Future<List<ChunkSearchResult>> _expandWithAdjacentChunks(
    List<ChunkSearchResult> chunks,
    int adjacentCount,
  ) async {
    final expandedMap = <String, ChunkSearchResult>{};

    // Add original chunks first (keyed by sourceId:chunkIndex)
    for (final chunk in chunks) {
      final key = '${chunk.sourceId}:${chunk.chunkIndex}';
      expandedMap[key] = chunk;
    }

    // Fetch adjacent chunks for each matched chunk
    for (final chunk in chunks) {
      final minIndex = (chunk.chunkIndex - adjacentCount).clamp(0, 999999);
      final maxIndex = chunk.chunkIndex + adjacentCount;

      List<ChunkSearchResult> adjacent = [];
      try {
        adjacent = await getAdjacentChunks(
          sourceId: chunk.sourceId,
          minIndex: minIndex,
          maxIndex: maxIndex,
        );
      } on RagError catch (e) {
        debugPrint(
          '[SmartError] Failed to fetch adjacent chunks: ${e.message}',
        );
        // Non-critical, just continue without expansion
        continue;
      }

      for (final adj in adjacent) {
        final key = '${adj.sourceId}:${adj.chunkIndex}';
        if (!expandedMap.containsKey(key)) {
          expandedMap[key] = adj;
        }
      }
    }

    // Sort by sourceId then chunkIndex for coherent reading order
    final result = expandedMap.values.toList();
    result.sort((a, b) {
      final sourceCompare = a.sourceId.compareTo(b.sourceId);
      if (sourceCompare != 0) return sourceCompare;
      return a.chunkIndex.compareTo(b.chunkIndex);
    });

    return result;
  }

  Future<List<ChunkSearchResult>> _hydrateCanonicalChunkResults(
    List<ChunkSearchResult> chunks,
  ) async {
    if (chunks.isEmpty) {
      return chunks;
    }

    final rangesBySource = <int, ({int minIndex, int maxIndex})>{};
    for (final chunk in chunks) {
      final sourceId = chunk.sourceId.toInt();
      final existing = rangesBySource[sourceId];
      rangesBySource[sourceId] = existing == null
          ? (minIndex: chunk.chunkIndex, maxIndex: chunk.chunkIndex)
          : (
              minIndex: existing.minIndex < chunk.chunkIndex
                  ? existing.minIndex
                  : chunk.chunkIndex,
              maxIndex: existing.maxIndex > chunk.chunkIndex
                  ? existing.maxIndex
                  : chunk.chunkIndex,
            );
    }

    final canonicalByKey = <String, ChunkSearchResult>{};
    for (final entry in rangesBySource.entries) {
      try {
        final canonicalChunks = await getAdjacentChunks(
          sourceId: entry.key,
          minIndex: entry.value.minIndex,
          maxIndex: entry.value.maxIndex,
        );
        for (final canonical in canonicalChunks) {
          canonicalByKey[_chunkLookupKey(
            canonical.sourceId.toInt(),
            canonical.chunkIndex,
          )] = canonical;
        }
      } on RagError catch (e) {
        debugPrint(
          '[SmartError] Failed to hydrate canonical chunk metadata: ${e.message}',
        );
      }
    }

    return chunks
        .map(
          (chunk) => mergeCanonicalChunkSearchResult(
            fallback: chunk,
            canonical: canonicalByKey[_chunkLookupKey(
              chunk.sourceId.toInt(),
              chunk.chunkIndex,
            )],
          ),
        )
        .toList();
  }

  /// Get all chunk texts for a specific source.
  ///
  /// Returns the raw text content of each chunk in order.
  /// Useful for displaying full document content reconstructed from chunks.
  Future<List<String>> getSourceChunks({required int sourceId}) async {
    return await rust_rag.getSourceChunks(sourceId: sourceId);
  }

  /// Get the total number of chunks for a specific source.
  ///
  /// Useful for pagination, progress tracking, and batch processing.
  Future<int> getSourceChunkCount({required int sourceId}) async {
    return await rust_rag.getSourceChunkCount(sourceId: sourceId);
  }

  /// Get the original source document content by source ID.
  ///
  /// Returns null if the source doesn't exist.
  Future<String?> getSourceDocument({required int sourceId}) async {
    return await rust_rag.getSource(sourceId: sourceId);
  }

  /// Get the original source document for a chunk.
  Future<String?> getSourceForChunk(ChunkSearchResult chunk) async {
    return await rust_rag.getSource(sourceId: chunk.sourceId);
  }

  /// Get statistics about stored sources and chunks.
  Future<SourceStats> getStats() async {
    return await rust_rag.getSourceStatsInCollection(
      collectionId: collectionId,
    );
  }

  /// Format search results as an LLM prompt.
  String formatPrompt(String query, RagSearchResult result) {
    return ContextBuilder.formatForPrompt(
      query: query,
      context: result.context,
    );
  }

  /// Get a list of all stored sources.
  Future<List<SourceEntry>> listSources() async {
    return await rust_rag.listSourcesInCollection(collectionId: collectionId);
  }

  /// Remove a source and all its chunks from the database.
  Future<void> removeSource(int sourceId) async {
    try {
      await rust_rag.deleteSourceInCollection(
        collectionId: collectionId,
        sourceId: sourceId,
      );
      await _markDirty(); // Mark index as dirty (Persistent)
    } on RagError catch (e) {
      debugPrint(
        '[SmartError] Failed to remove source $sourceId: ${e.message}',
      );
      rethrow;
    }
    // Note: HNSW index is not automatically updated.
    // It's recommended to call rebuildIndex() if many sources are deleted.
  }

  /// Hybrid search combining vector and keyword (BM25) search.
  ///
  /// This method uses Reciprocal Rank Fusion (RRF) to combine:
  /// - Vector search: semantic similarity using embeddings
  /// - BM25 search: keyword matching for exact terms
  ///
  /// Use this for better results when searching for:
  /// - Proper nouns (names, product models)
  /// - Technical terms or code snippets
  /// - Exact keyword matches
  ///
  /// Parameters:
  /// - [query]: The search query text
  /// - [topK]: Number of results to return (default: 10)
  /// - [vectorWeight]: Weight for vector search (0.0-1.0, default: [kDefaultVectorWeight])
  /// - [bm25Weight]: Weight for BM25 search (0.0-1.0, default: [kDefaultBm25Weight])
  Future<List<hybrid.HybridSearchResult>> searchHybrid(
    String query, {
    int topK = 10,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
  }) async {
    final normalizedWeights = normalizeHybridWeights(
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      context: 'SourceRagService.searchHybrid',
    );

    // 1. Generate query embedding
    final queryEmbedding = await EmbeddingService.embed(query);

    // 2. Ensure hybrid indexes are switched to this collection.
    await rust_rag.activateCollectionForHybridSearch(
      collectionId: collectionId,
      basePath: _indexPath,
    );

    // 3. Perform hybrid search with RRF fusion
    late List<hybrid.HybridSearchResult> results;
    try {
      // Improve post-filtering recall:
      // If filtering by source, fetch more candidates internally to avoid
      // the dominant source occupying all top-k slots before filtering.
      final effectiveTopK =
          sourceIds != null ? (topK * 10).clamp(50, 200) : topK;

      results = await hybrid.searchHybrid(
        queryText: query,
        queryEmbedding: queryEmbedding,
        topK: effectiveTopK,
        config: hybrid.RrfConfig(
          k: 60,
          vectorWeight: normalizedWeights.vectorWeight,
          bm25Weight: normalizedWeights.bm25Weight,
        ),
        filter: hybrid.SearchFilter(
          sourceIds: sourceIds != null ? _toInt64List(sourceIds) : null,
          collectionId: collectionId,
        ),
      );
    } on RagError catch (e) {
      e.when(
        databaseError: (msg) =>
            debugPrint('[SmartError] Hybrid search DB error: $msg'),
        ioError: (_) {},
        modelLoadError: (_) {},
        invalidInput: (_) {},
        staleSearchHandle: (msg) =>
            log('[SmartError] Hybrid search stale handle: $msg'),
        concurrentMutation: (msg) =>
            log('[SmartError] Hybrid search concurrent mutation: $msg'),
        internalError: (msg) =>
            log('[SmartError] Hybrid search engine error: $msg'),
        unsupportedMigrationVersion: (axis, stored, supported) => log(
          '[SmartError] Hybrid search blocked by unsupported migration axis '
          '$axis (stored=$stored, supported=$supported)',
        ),
        unknown: (msg) => log('[SmartError] Hybrid search unknown error: $msg'),
      );
      rethrow;
    }

    return results.take(topK).toList();
  }

  /// Hybrid search with context assembly for LLM.
  ///
  /// Similar to [search] but uses hybrid (vector + BM25) search.
  ///
  /// [adjacentChunks] - Number of adjacent chunks to include before/after each
  /// matched chunk (default: 0). Setting this to 1 will include the chunk
  /// before and after each matched chunk, helping with long articles.
  /// [singleSourceMode] - If true, only include chunks from the most relevant source.
  /// [hydrationMode] - Controls whether returned chunks are fully hydrated,
  /// preview-only, or omitted entirely while still returning assembled context.
  /// [previewMaxBytes] - Maximum UTF-8 byte length per preview chunk when
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
  }) async {
    RagError? lastRetryableError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _searchHybridWithContextViaHandle(
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
      } on RagError catch (e) {
        final isRetryable = e.when(
          databaseError: (_) => false,
          ioError: (_) => false,
          modelLoadError: (_) => false,
          invalidInput: (_) => false,
          staleSearchHandle: (_) => true,
          concurrentMutation: (_) => true,
          internalError: (_) => false,
          unsupportedMigrationVersion: (_, __, ___) => false,
          unknown: (_) => false,
        );
        if (!isRetryable || attempt == 1) {
          rethrow;
        }
        lastRetryableError = e;
        debugPrint(
          '[SmartError] Retrying searchHybridWithContext after transient handle invalidation: ${e.message}',
        );
      }
    }

    throw lastRetryableError ??
        RagError.unknown('searchHybridWithContext retry loop exhausted');
  }

  @visibleForTesting
  Future<RagSearchResult> searchHybridWithContextLegacyForTest(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
  }) {
    return _searchHybridWithContextLegacy(
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

  Future<RagSearchResult> _searchHybridWithContextViaHandle(
    String query, {
    required int topK,
    required int tokenBudget,
    required ContextStrategy strategy,
    required double vectorWeight,
    required double bm25Weight,
    required List<int>? sourceIds,
    required int adjacentChunks,
    required bool singleSourceMode,
    required SearchHydrationMode hydrationMode,
    required int previewMaxBytes,
  }) async {
    final metaResult = await searchMeta(
      query,
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: sourceIds,
      adjacentChunks: adjacentChunks,
    );

    try {
      final assembled = await assembleContext(
        searchHandle: metaResult.handle,
        tokenBudget: tokenBudget,
        strategy: strategy,
        singleSourceMode: singleSourceMode,
      );

      final candidateHits = _candidateHitsForAssembly(
        metaResult.hits,
        selectedSourceId: assembled.selectedSourceId?.toInt(),
      );
      final candidateChunkIds = candidateHits
          .map((hit) => hit.chunkId.toInt())
          .toList(growable: false);

      final chunks = switch (hydrationMode) {
        SearchHydrationMode.full => await hydrateChunks(
            searchHandle: metaResult.handle,
            chunkIds: candidateChunkIds,
          ),
        SearchHydrationMode.preview => await _hydratePreviewChunks(
            searchHandle: metaResult.handle,
            candidateHits: candidateHits,
            maxBytes: previewMaxBytes,
          ),
        SearchHydrationMode.contextOnly => const <ChunkSearchResult>[],
      };

      final context = _legacyContextFromAssembledContext(
        assembled,
        chunks,
        clearIncludedChunks: hydrationMode == SearchHydrationMode.contextOnly,
      );

      return RagSearchResult(chunks: chunks, context: context);
    } finally {
      await metaResult.dispose();
    }
  }

  Future<List<ChunkSearchResult>> _hydratePreviewChunks({
    required rust_rag.SearchHandle searchHandle,
    required List<rust_rag.SearchHitMeta> candidateHits,
    required int maxBytes,
  }) async {
    if (candidateHits.isEmpty) {
      return const <ChunkSearchResult>[];
    }

    final excerpts = await getChunkExcerpts(
      searchHandle: searchHandle,
      chunkIds: candidateHits.map((hit) => hit.chunkId.toInt()).toList(),
      maxBytes: maxBytes,
    );
    final hitsById = {
      for (final hit in candidateHits) hit.chunkId.toInt(): hit,
    };
    return excerpts.map((excerpt) {
      final hit = hitsById[excerpt.chunkId.toInt()];
      return ChunkSearchResult(
        chunkId: excerpt.chunkId,
        sourceId: excerpt.sourceId,
        chunkIndex: excerpt.chunkIndex,
        content: excerpt.excerpt,
        chunkType: _encodeStructuredChunkType(
          excerpt.rawType,
          headerPath: excerpt.headerPathPreview,
        ),
        similarity: hit?.similarity ?? 0.0,
        metadata: null,
      );
    }).toList(growable: false);
  }

  List<rust_rag.SearchHitMeta> _candidateHitsForAssembly(
    List<rust_rag.SearchHitMeta> hits, {
    int? selectedSourceId,
  }) {
    if (selectedSourceId == null) {
      return List<rust_rag.SearchHitMeta>.from(hits, growable: false);
    }

    return hits
        .where((hit) => hit.sourceId.toInt() == selectedSourceId)
        .toList(growable: false);
  }

  AssembledContext _legacyContextFromAssembledContext(
    rust_rag.AssembledContextV2 assembled,
    List<ChunkSearchResult> hydratedChunks, {
    bool clearIncludedChunks = false,
  }) {
    final includedChunks = clearIncludedChunks
        ? const <ChunkSearchResult>[]
        : _resolveIncludedChunks(
            assembled.includedChunkIds,
            hydratedChunks,
          );

    return AssembledContext(
      text: assembled.text,
      includedChunks: includedChunks,
      estimatedTokens: assembled.exactTokens,
      remainingBudget: assembled.remainingBudget,
    );
  }

  List<ChunkSearchResult> _resolveIncludedChunks(
    frb.Int64List includedChunkIds,
    List<ChunkSearchResult> hydratedChunks,
  ) {
    if (includedChunkIds.isEmpty || hydratedChunks.isEmpty) {
      return const <ChunkSearchResult>[];
    }

    final chunksById = {
      for (final chunk in hydratedChunks) chunk.chunkId.toInt(): chunk,
    };
    return includedChunkIds
        .map((chunkId) => chunksById[chunkId.toInt()])
        .whereType<ChunkSearchResult>()
        .toList(growable: false);
  }

  Future<RagSearchResult> _searchHybridWithContextLegacy(
    String query, {
    required int topK,
    required int tokenBudget,
    required ContextStrategy strategy,
    required double vectorWeight,
    required double bm25Weight,
    required List<int>? sourceIds,
    required int adjacentChunks,
    required bool singleSourceMode,
  }) async {
    // 1. Get hybrid search results
    final hybridResults = await searchHybrid(
      query,
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: sourceIds,
    );

    // 2. Rehydrate canonical chunk rows so markdown chunk_type metadata survives
    // hybrid search's lightweight result shape.
    var chunks = await _hydrateCanonicalChunkResults(
      hybridResults.map(_chunkSearchResultFromHybrid).toList(),
    );

    // 3. Filter to single source FIRST (before adjacent expansion)
    if (singleSourceMode && chunks.isNotEmpty) {
      chunks = _filterToMostRelevantSource(chunks, query);
    }

    // 4. Expand with adjacent chunks (only for the selected source)
    if (adjacentChunks > 0 && chunks.isNotEmpty) {
      chunks = await _expandWithAdjacentChunks(chunks, adjacentChunks);
    }

    // 5. Assemble context (pass singleSourceMode to skip headers when single source)
    final context = ContextBuilder.build(
      searchResults: chunks,
      tokenBudget: tokenBudget,
      strategy: strategy,
      singleSourceMode: singleSourceMode, // Pass through to skip headers
    );

    return RagSearchResult(chunks: chunks, context: context);
  }
}
