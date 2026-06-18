import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import '../src/rust/api/db_pool.dart' as db_pool;
import '../src/rust/api/source_rag.dart' as source_rag;
import '../src/rust/frb_generated.dart';

/// LLM-agnostic vector-store facade backed by mobile_rag_engine's source/chunk
/// storage.
///
/// This is intended for integration packages that already have embeddings from
/// another runtime, such as an on-device LLM package. It maps each external
/// document to one source row with one chunk, while keeping the lower-level
/// Rust APIs private to this package.
class MobileRagVectorStore {
  MobileRagVectorStore({
    this.collectionId = 'mobile_rag_vector_store',
    this.maxPoolSize = 2,
    this.enableHnsw = true,
  });

  static bool _rustInitialized = false;

  final String collectionId;
  final int maxPoolSize;
  bool enableHnsw;

  var _initialized = false;
  var _indexDirty = false;
  var _vectorDimension = 0;

  bool get isInitialized => _initialized;

  Future<void> initialize(String databasePath) async {
    if (_initialized) return;

    await _ensureRustInitialized();
    await Directory(File(databasePath).parent.path).create(recursive: true);
    await db_pool.initDbPool(dbPath: databasePath, maxSize: maxPoolSize);
    await source_rag.initSourceDb();

    if (enableHnsw) {
      await source_rag.rebuildChunkHnswIndexForCollection(
        collectionId: collectionId,
      );
    }

    _initialized = true;
    _indexDirty = false;
  }

  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    _ensureInitialized();
    _validateEmbeddingDimension(embedding);

    await removeDocument(id: id);

    final source = await source_rag.addSourceInCollection(
      collectionId: collectionId,
      content: content,
      metadata: metadata,
      name: id,
    );

    await source_rag.addChunks(
      sourceId: source.sourceId,
      chunks: [
        source_rag.ChunkData(
          content: content,
          chunkIndex: 0,
          startPos: 0,
          endPos: content.length,
          chunkType: 'document',
          embedding: Float32List.fromList(embedding),
        ),
      ],
    );

    await source_rag.updateSourceStatus(
      sourceId: source.sourceId,
      status: 'completed',
    );
    _indexDirty = true;
  }

  Future<void> removeDocument({required String id}) async {
    _ensureInitialized();
    final sources = await source_rag.listSourcesInCollection(
      collectionId: collectionId,
    );

    for (final source in sources.where((source) => source.name == id)) {
      await source_rag.deleteSourceInCollection(
        collectionId: collectionId,
        sourceId: source.id,
      );
      _indexDirty = true;
    }
  }

  Future<List<MobileRagVectorSearchResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async {
    _ensureInitialized();
    _validateQueryDimension(queryEmbedding);
    await _ensureSearchIndex();

    final hits = enableHnsw
        ? await source_rag.searchChunksInCollection(
            collectionId: collectionId,
            queryEmbedding: queryEmbedding,
            topK: topK,
          )
        : await source_rag.benchmarkSearchChunksLinearInCollection(
            collectionId: collectionId,
            queryEmbedding: queryEmbedding,
            topK: topK,
          );

    final sourceNames = await _sourceNamesById();
    return hits
        .where((hit) => hit.similarity >= threshold)
        .map(
          (hit) => MobileRagVectorSearchResult(
            id: sourceNames[hit.sourceId.toString()] ?? hit.chunkId.toString(),
            content: hit.content,
            similarity: hit.similarity,
            metadata: hit.metadata,
          ),
        )
        .toList(growable: false);
  }

  Future<MobileRagVectorStoreStats> getStats() async {
    _ensureInitialized();
    final stats = await source_rag.getSourceStatsInCollection(
      collectionId: collectionId,
    );
    return MobileRagVectorStoreStats(
      documentCount: stats.sourceCount.toInt(),
      vectorDimension: _vectorDimension,
    );
  }

  Future<void> clear() async {
    _ensureInitialized();
    final sources = await source_rag.listSourcesInCollection(
      collectionId: collectionId,
    );
    for (final source in sources) {
      await source_rag.deleteSourceInCollection(
        collectionId: collectionId,
        sourceId: source.id,
      );
    }
    _vectorDimension = 0;
    _indexDirty = true;
  }

  Future<void> close() async {
    if (!_initialized) return;
    await db_pool.closeDbPool();
    _initialized = false;
    _indexDirty = false;
  }

  Future<Map<String, String>> _sourceNamesById() async {
    final sources = await source_rag.listSourcesInCollection(
      collectionId: collectionId,
    );
    return {
      for (final source in sources)
        if (source.name != null) source.id.toString(): source.name!,
    };
  }

  Future<void> _ensureSearchIndex() async {
    if (!enableHnsw || !_indexDirty) return;
    await source_rag.rebuildChunkHnswIndexForCollection(
      collectionId: collectionId,
    );
    _indexDirty = false;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MobileRagVectorStore is not initialized.');
    }
  }

  void _validateEmbeddingDimension(List<double> embedding) {
    if (embedding.isEmpty) {
      throw ArgumentError.value(embedding, 'embedding', 'Must not be empty.');
    }
    if (_vectorDimension == 0) {
      _vectorDimension = embedding.length;
      return;
    }
    if (embedding.length != _vectorDimension) {
      throw ArgumentError(
        'Embedding dimension mismatch: expected $_vectorDimension, '
        'got ${embedding.length}.',
      );
    }
  }

  void _validateQueryDimension(List<double> queryEmbedding) {
    if (_vectorDimension == 0) return;
    if (queryEmbedding.length != _vectorDimension) {
      throw ArgumentError(
        'Query embedding dimension mismatch: expected $_vectorDimension, '
        'got ${queryEmbedding.length}.',
      );
    }
  }

  static Future<void> _ensureRustInitialized() async {
    if (_rustInitialized || RustLib.instance.initialized) {
      _rustInitialized = true;
      return;
    }

    try {
      await RustLib.init();
    } catch (_) {
      if (!Platform.isMacOS || RustLib.instance.initialized) rethrow;
      await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
      );
    }
    _rustInitialized = true;
  }
}

class MobileRagVectorSearchResult {
  const MobileRagVectorSearchResult({
    required this.id,
    required this.content,
    required this.similarity,
    this.metadata,
  });

  final String id;
  final String content;
  final double similarity;
  final String? metadata;
}

class MobileRagVectorStoreStats {
  const MobileRagVectorStoreStats({
    required this.documentCount,
    required this.vectorDimension,
  });

  final int documentCount;
  final int vectorDimension;
}
