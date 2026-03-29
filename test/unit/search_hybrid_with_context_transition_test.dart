import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/internal/defaults.dart';
import 'package:mobile_rag_engine/src/rust/api/error.dart';
import 'package:mobile_rag_engine/src/rust/api/hybrid_search.dart' as hybrid;
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;

frb.Int64List _toInt64List(List<int> values) {
  final result = frb.Int64List(values.length);
  for (var i = 0; i < values.length; i++) {
    result[i] = values[i];
  }
  return result;
}

rust_rag.ChunkSearchResult _chunk({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required String content,
  required String chunkType,
  required double similarity,
  String? metadata,
}) {
  return rust_rag.ChunkSearchResult(
    chunkId: chunkId,
    sourceId: sourceId,
    chunkIndex: chunkIndex,
    content: content,
    chunkType: chunkType,
    similarity: similarity,
    metadata: metadata,
  );
}

hybrid.HybridSearchResult _hybrid({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required String content,
  required double score,
  String? metadata,
}) {
  return hybrid.HybridSearchResult(
    docId: chunkId,
    content: content,
    score: score,
    vectorRank: 0,
    bm25Rank: 0,
    sourceId: sourceId,
    metadata: metadata,
    chunkIndex: chunkIndex,
  );
}

rust_rag.SearchHitMeta _hit({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required double similarity,
  required String rawType,
  String? headerPathPreview,
}) {
  return rust_rag.SearchHitMeta(
    chunkId: chunkId,
    sourceId: sourceId,
    chunkIndex: chunkIndex,
    similarity: similarity,
    rawType: rawType,
    headerPathPreview: headerPathPreview,
  );
}

rust_rag.ChunkExcerptResult _excerpt({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required String rawType,
  String? headerPathPreview,
  required String excerpt,
}) {
  return rust_rag.ChunkExcerptResult(
    chunkId: chunkId,
    sourceId: sourceId,
    chunkIndex: chunkIndex,
    rawType: rawType,
    headerPathPreview: headerPathPreview,
    excerpt: excerpt,
  );
}

class FakeSearchHandle implements rust_rag.SearchHandle {
  FakeSearchHandle({
    required this.hits,
    Iterable<Object>? assembleResponses,
    Iterable<Object>? hydrateResponses,
    Iterable<Object>? excerptResponses,
  })  : _assembleResponses =
            ListQueue<Object>.from(assembleResponses ?? const []),
        _hydrateResponses =
            ListQueue<Object>.from(hydrateResponses ?? const []),
        _excerptResponses =
            ListQueue<Object>.from(excerptResponses ?? const []);

  final List<rust_rag.SearchHitMeta> hits;
  final ListQueue<Object> _assembleResponses;
  final ListQueue<Object> _hydrateResponses;
  final ListQueue<Object> _excerptResponses;

  int disposeCount = 0;
  int hydrateCallCount = 0;
  int excerptCallCount = 0;

  @override
  bool isDisposed = false;

  @override
  Future<rust_rag.AssembledContextV2> assembleContext({
    required rust_rag.AssembleContextOptions options,
  }) async {
    if (_assembleResponses.isEmpty) {
      throw StateError('missing assemble response');
    }
    final next = _assembleResponses.removeFirst();
    if (next is RagError) {
      throw next;
    }
    return next as rust_rag.AssembledContextV2;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    disposeCount++;
  }

  @override
  Future<List<rust_rag.ChunkExcerptResult>> getChunkExcerpts({
    required frb.Int64List chunkIds,
    required int maxBytes,
  }) async {
    excerptCallCount++;
    if (_excerptResponses.isEmpty) {
      throw StateError('missing excerpt response');
    }
    final next = _excerptResponses.removeFirst();
    if (next is RagError) {
      throw next;
    }
    return next as List<rust_rag.ChunkExcerptResult>;
  }

  @override
  Future<List<rust_rag.SearchHitMeta>> hitMeta() async => hits;

  @override
  Future<List<rust_rag.ChunkSearchResult>> hydrateChunks({
    required frb.Int64List chunkIds,
  }) async {
    hydrateCallCount++;
    if (_hydrateResponses.isEmpty) {
      throw StateError('missing hydrate response');
    }
    final next = _hydrateResponses.removeFirst();
    if (next is RagError) {
      throw next;
    }
    return next as List<rust_rag.ChunkSearchResult>;
  }
}

class FakeSourceRagService extends SourceRagService {
  FakeSourceRagService({
    required this.hybridResults,
    required this.canonicalChunks,
  }) : super(
          dbPath: '/tmp/fake-rag.sqlite',
          collectionId: 'test',
        );

  final ListQueue<SearchMetaResult> searchMetaResponses =
      ListQueue<SearchMetaResult>();
  final List<hybrid.HybridSearchResult> hybridResults;
  final List<rust_rag.ChunkSearchResult> canonicalChunks;

  @override
  Future<SearchMetaResult> searchMeta(
    String query, {
    int topK = 10,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
    int adjacentChunks = 0,
  }) async {
    if (searchMetaResponses.isEmpty) {
      throw StateError('missing searchMeta response');
    }
    return searchMetaResponses.removeFirst();
  }

  @override
  Future<List<hybrid.HybridSearchResult>> searchHybrid(
    String query, {
    int topK = 10,
    double vectorWeight = kDefaultVectorWeight,
    double bm25Weight = kDefaultBm25Weight,
    List<int>? sourceIds,
  }) async {
    return hybridResults;
  }

  @override
  Future<List<rust_rag.ChunkSearchResult>> getAdjacentChunks({
    required int sourceId,
    required int minIndex,
    required int maxIndex,
  }) async {
    return canonicalChunks
        .where((chunk) => chunk.sourceId.toInt() == sourceId)
        .where((chunk) => chunk.chunkIndex >= minIndex)
        .where((chunk) => chunk.chunkIndex <= maxIndex)
        .toList(growable: false);
  }
}

void main() {
  group('searchHybridWithContext high-level transition', () {
    late List<rust_rag.ChunkSearchResult> canonicalChunks;
    late List<hybrid.HybridSearchResult> hybridResults;
    late List<rust_rag.SearchHitMeta> hitsWithAdjacent;
    late FakeSourceRagService service;

    setUp(() {
      ContextBuilder.debugTokenCounterOverride = (text) => text.length;
      canonicalChunks = [
        _chunk(
          chunkId: 101,
          sourceId: 1,
          chunkIndex: 0,
          content: 'Install the package.',
          chunkType: 'text|Guide > Setup',
          similarity: 0.91,
          metadata: '{"source":"guide"}',
        ),
        _chunk(
          chunkId: 102,
          sourceId: 1,
          chunkIndex: 1,
          content: 'Verify the checksum.',
          chunkType: 'general',
          similarity: 0.0,
          metadata: '{"source":"guide"}',
        ),
        _chunk(
          chunkId: 201,
          sourceId: 2,
          chunkIndex: 0,
          content: 'Run the smoke test.',
          chunkType: 'general',
          similarity: 0.63,
        ),
      ];

      hybridResults = [
        _hybrid(
          chunkId: 101,
          sourceId: 1,
          chunkIndex: 0,
          content: 'Install the package.',
          score: 0.91,
          metadata: '{"source":"guide"}',
        ),
        _hybrid(
          chunkId: 201,
          sourceId: 2,
          chunkIndex: 0,
          content: 'Run the smoke test.',
          score: 0.63,
        ),
      ];

      hitsWithAdjacent = [
        _hit(
          chunkId: 101,
          sourceId: 1,
          chunkIndex: 0,
          similarity: 0.91,
          rawType: 'text',
          headerPathPreview: 'Guide > Setup',
        ),
        _hit(
          chunkId: 102,
          sourceId: 1,
          chunkIndex: 1,
          similarity: 0.0,
          rawType: 'general',
        ),
        _hit(
          chunkId: 201,
          sourceId: 2,
          chunkIndex: 0,
          similarity: 0.63,
          rawType: 'general',
        ),
      ];

      service = FakeSourceRagService(
        hybridResults: hybridResults,
        canonicalChunks: canonicalChunks,
      );
    });

    tearDown(() {
      ContextBuilder.debugTokenCounterOverride = null;
    });

    test('default full mode matches legacy grouped result', () async {
      final legacy = await service.searchHybridWithContextLegacyForTest(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
      );
      final handle = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: legacy.context.text,
            exactTokens: legacy.context.estimatedTokens,
            includedChunkIds: _toInt64List(
              legacy.context.includedChunks
                  .map((chunk) => chunk.chunkId.toInt())
                  .toList(),
            ),
            remainingBudget: legacy.context.remainingBudget,
            selectedSourceId: null,
          ),
        ],
        hydrateResponses: [legacy.chunks],
      );
      service.searchMetaResponses.add(
        SearchMetaResult(handle: handle, hits: hitsWithAdjacent),
      );

      final result = await service.searchHybridWithContext(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
      );

      expect(result.chunks, legacy.chunks);
      expect(result.context.text, legacy.context.text);
      expect(result.context.estimatedTokens, legacy.context.estimatedTokens);
      expect(result.context.remainingBudget, legacy.context.remainingBudget);
      expect(
        result.context.includedChunks
            .map((chunk) => chunk.chunkId)
            .toList(growable: false),
        legacy.context.includedChunks
            .map((chunk) => chunk.chunkId)
            .toList(growable: false),
      );
      expect(handle.isDisposed, isTrue);
      expect(handle.disposeCount, 1);
    });

    test(
        'singleSourceMode full path uses low-level selectedSourceId without re-deriving from hydrated chunks',
        () async {
      final legacy = await service.searchHybridWithContextLegacyForTest(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
        singleSourceMode: true,
      );
      final handle = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: legacy.context.text,
            exactTokens: legacy.context.estimatedTokens,
            includedChunkIds: _toInt64List(
              legacy.context.includedChunks
                  .map((chunk) => chunk.chunkId.toInt())
                  .toList(),
            ),
            remainingBudget: legacy.context.remainingBudget,
            selectedSourceId: 1,
          ),
        ],
        hydrateResponses: [legacy.chunks],
      );
      service.searchMetaResponses.add(
        SearchMetaResult(handle: handle, hits: hitsWithAdjacent),
      );

      final result = await service.searchHybridWithContext(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
        singleSourceMode: true,
      );

      expect(result.chunks, legacy.chunks);
      expect(
        result.chunks.every((chunk) => chunk.sourceId.toInt() == 1),
        isTrue,
      );
      expect(handle.hydrateCallCount, 1);
      expect(handle.isDisposed, isTrue);
    });

    test('preview mode stays lossy/non-canonical while keeping context parity',
        () async {
      final legacy = await service.searchHybridWithContextLegacyForTest(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
      );
      final previewChunks = [
        _excerpt(
          chunkId: 101,
          sourceId: 1,
          chunkIndex: 0,
          rawType: 'text',
          headerPathPreview: 'Guide > Setup',
          excerpt: 'Install ',
        ),
        _excerpt(
          chunkId: 102,
          sourceId: 1,
          chunkIndex: 1,
          rawType: 'general',
          excerpt: 'Verify t',
        ),
        _excerpt(
          chunkId: 201,
          sourceId: 2,
          chunkIndex: 0,
          rawType: 'general',
          excerpt: 'Run the ',
        ),
      ];
      final handle = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: legacy.context.text,
            exactTokens: legacy.context.estimatedTokens,
            includedChunkIds: _toInt64List(
              legacy.context.includedChunks
                  .map((chunk) => chunk.chunkId.toInt())
                  .toList(),
            ),
            remainingBudget: legacy.context.remainingBudget,
            selectedSourceId: null,
          ),
        ],
        excerptResponses: [previewChunks],
      );
      service.searchMetaResponses.add(
        SearchMetaResult(handle: handle, hits: hitsWithAdjacent),
      );

      final result = await service.searchHybridWithContext(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
        hydrationMode: SearchHydrationMode.preview,
        previewMaxBytes: 8,
      );

      expect(result.context.text, legacy.context.text);
      expect(result.context.estimatedTokens, legacy.context.estimatedTokens);
      expect(result.chunks, hasLength(legacy.chunks.length));
      expect(result.chunks.every((chunk) => chunk.metadata == null), isTrue);
      expect(result.chunks.every((chunk) => chunk.content.length <= 8), isTrue);
      expect(result.chunks.first.chunkType, 'text|Guide > Setup');
      expect(
        result.context.includedChunks
            .map((chunk) => chunk.chunkId)
            .toList(growable: false),
        legacy.context.includedChunks
            .map((chunk) => chunk.chunkId)
            .toList(growable: false),
      );
      expect(handle.excerptCallCount, 1);
      expect(handle.isDisposed, isTrue);
    });

    test(
        'contextOnly mode returns empty chunk lists while preserving assembled context',
        () async {
      final legacy = await service.searchHybridWithContextLegacyForTest(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
      );
      final handle = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: legacy.context.text,
            exactTokens: legacy.context.estimatedTokens,
            includedChunkIds: _toInt64List(
              legacy.context.includedChunks
                  .map((chunk) => chunk.chunkId.toInt())
                  .toList(),
            ),
            remainingBudget: legacy.context.remainingBudget,
            selectedSourceId: null,
          ),
        ],
      );
      service.searchMetaResponses.add(
        SearchMetaResult(handle: handle, hits: hitsWithAdjacent),
      );

      final result = await service.searchHybridWithContext(
        'install',
        topK: 2,
        tokenBudget: 200,
        adjacentChunks: 1,
        hydrationMode: SearchHydrationMode.contextOnly,
      );

      expect(result.chunks, isEmpty);
      expect(result.context.includedChunks, isEmpty);
      expect(result.context.text, legacy.context.text);
      expect(result.context.estimatedTokens, legacy.context.estimatedTokens);
      expect(handle.hydrateCallCount, 0);
      expect(handle.excerptCallCount, 0);
      expect(handle.isDisposed, isTrue);
    });

    test('retries once when assemble path hits concurrent mutation', () async {
      final successChunks = canonicalChunks;
      final handle1 = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [const RagError.concurrentMutation('race')],
      );
      final handle2 = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: 'Header Path: Guide > Setup\nInstall the package.',
            exactTokens: 7,
            includedChunkIds: _toInt64List([101]),
            remainingBudget: 193,
            selectedSourceId: null,
          ),
        ],
        hydrateResponses: [successChunks],
      );
      service.searchMetaResponses
        ..add(SearchMetaResult(handle: handle1, hits: hitsWithAdjacent))
        ..add(SearchMetaResult(handle: handle2, hits: hitsWithAdjacent));

      final result = await service.searchHybridWithContext(
        'install',
        topK: 2,
        tokenBudget: 200,
      );

      expect(result.chunks, successChunks);
      expect(result.context.text,
          'Header Path: Guide > Setup\nInstall the package.');
      expect(handle1.isDisposed, isTrue);
      expect(handle2.isDisposed, isTrue);
      expect(handle2.hydrateCallCount, 1);
    });

    test('retries once when full hydration path hits stale handle', () async {
      final handle1 = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: 'ctx',
            exactTokens: 3,
            includedChunkIds: _toInt64List([101]),
            remainingBudget: 197,
            selectedSourceId: null,
          ),
        ],
        hydrateResponses: [const RagError.staleSearchHandle('stale')],
      );
      final handle2 = FakeSearchHandle(
        hits: hitsWithAdjacent,
        assembleResponses: [
          rust_rag.AssembledContextV2(
            text: 'ctx',
            exactTokens: 3,
            includedChunkIds: _toInt64List([101]),
            remainingBudget: 197,
            selectedSourceId: null,
          ),
        ],
        hydrateResponses: [
          [
            canonicalChunks.first,
          ],
        ],
      );
      service.searchMetaResponses
        ..add(SearchMetaResult(handle: handle1, hits: hitsWithAdjacent))
        ..add(SearchMetaResult(handle: handle2, hits: hitsWithAdjacent));

      final result = await service.searchHybridWithContext(
        'install',
        topK: 2,
        tokenBudget: 200,
      );

      expect(result.chunks, [canonicalChunks.first]);
      expect(handle1.isDisposed, isTrue);
      expect(handle2.isDisposed, isTrue);
    });
  });
}
