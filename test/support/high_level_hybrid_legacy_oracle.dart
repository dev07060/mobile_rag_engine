import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/src/internal/high_level_hybrid_transition.dart';
import 'package:mobile_rag_engine/src/internal/validation.dart';
import 'package:mobile_rag_engine/src/rust/api/hybrid_search.dart' as hybrid;
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';

frb.Int64List _toInt64List(List<int> values) {
  final result = frb.Int64List(values.length);
  for (var i = 0; i < values.length; i++) {
    result[i] = values[i];
  }
  return result;
}

ChunkSearchResult _chunkSearchResultFromHybrid(
    hybrid.HybridSearchResult result) {
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

ChunkSearchResult _mergeCanonicalChunkSearchResult({
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

String _chunkLookupKey(int sourceId, int chunkIndex) => '$sourceId:$chunkIndex';

List<ChunkSearchResult> _filterToMostRelevantSource(
  List<ChunkSearchResult> results,
  String query,
) {
  if (results.isEmpty) {
    return results;
  }

  final queryLower = query.toLowerCase();
  final sourceTextMatches = <int, int>{};
  for (final chunk in results) {
    final sourceId = chunk.sourceId.toInt();
    final contentLower = chunk.content.toLowerCase();
    final queryWords = _extractSignificantQueryTerms(query);
    var matchCount = 0;
    for (final word in queryWords) {
      if (contentLower.contains(word)) {
        matchCount++;
      }
    }
    if (contentLower.contains(queryLower) || chunk.content.contains(query)) {
      matchCount += 100;
    }
    sourceTextMatches[sourceId] =
        (sourceTextMatches[sourceId] ?? 0) + matchCount;
  }

  int? bestSourceByText;
  var bestTextMatchCount = 0;
  for (final entry in sourceTextMatches.entries) {
    if (entry.value > bestTextMatchCount) {
      bestTextMatchCount = entry.value;
      bestSourceByText = entry.key;
    }
  }

  if (bestSourceByText != null && bestTextMatchCount > 0) {
    return results
        .where((chunk) => chunk.sourceId.toInt() == bestSourceByText)
        .toList();
  }

  final sourceScores = <int, double>{};
  for (final chunk in results) {
    final sourceId = chunk.sourceId.toInt();
    sourceScores[sourceId] = (sourceScores[sourceId] ?? 0) + chunk.similarity;
  }

  int? bestSourceId;
  var bestScore = double.negativeInfinity;
  for (final entry in sourceScores.entries) {
    if (entry.value > bestScore) {
      bestScore = entry.value;
      bestSourceId = entry.key;
    }
  }

  if (bestSourceId == null) {
    return results;
  }

  return results
      .where((chunk) => chunk.sourceId.toInt() == bestSourceId)
      .toList();
}

List<String> _extractSignificantQueryTerms(String query) {
  final splitter = RegExp(r'[\s\(\)\[\]\{\},.!?:;/|_\-]+');
  return query
      .split(splitter)
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .where((word) => _containsCjkOrHangul(word) || word.length >= 2)
      .map((word) => word.toLowerCase())
      .toSet()
      .toList();
}

bool _containsCjkOrHangul(String text) {
  return RegExp(
    r'[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7A3]',
  ).hasMatch(text);
}

Future<List<ChunkSearchResult>> _expandWithAdjacentChunks(
  List<ChunkSearchResult> chunks,
  int adjacentCount,
) async {
  final expandedMap = <String, ChunkSearchResult>{};

  for (final chunk in chunks) {
    expandedMap[_chunkLookupKey(chunk.sourceId.toInt(), chunk.chunkIndex)] =
        chunk;
  }

  for (final chunk in chunks) {
    final minIndex = (chunk.chunkIndex - adjacentCount).clamp(0, 999999);
    final maxIndex = chunk.chunkIndex + adjacentCount;
    final adjacent = await getAdjacentChunks(
      sourceId: chunk.sourceId,
      minIndex: minIndex,
      maxIndex: maxIndex,
    );
    for (final candidate in adjacent) {
      expandedMap[_chunkLookupKey(
          candidate.sourceId.toInt(), candidate.chunkIndex)] = candidate;
    }
  }

  final expanded = expandedMap.values.toList();
  expanded.sort((left, right) {
    final sourceCompare = left.sourceId.compareTo(right.sourceId);
    if (sourceCompare != 0) {
      return sourceCompare;
    }
    return left.chunkIndex.compareTo(right.chunkIndex);
  });
  return expanded;
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
    final canonicalChunks = await getAdjacentChunks(
      sourceId: entry.key,
      minIndex: entry.value.minIndex,
      maxIndex: entry.value.maxIndex,
    );
    for (final canonical in canonicalChunks) {
      canonicalByKey[_chunkLookupKey(
          canonical.sourceId.toInt(), canonical.chunkIndex)] = canonical;
    }
  }

  return chunks
      .map(
        (chunk) => _mergeCanonicalChunkSearchResult(
          fallback: chunk,
          canonical: canonicalByKey[
              _chunkLookupKey(chunk.sourceId.toInt(), chunk.chunkIndex)],
        ),
      )
      .toList();
}

Future<HybridSearchParitySnapshot> buildLegacyHybridParitySnapshot({
  required String collectionId,
  required String queryText,
  required List<double> queryEmbedding,
  required int topK,
  required int tokenBudget,
  required double vectorWeight,
  required double bm25Weight,
  List<int>? sourceIds,
  int adjacentChunks = 0,
  ContextStrategy strategy = ContextStrategy.relevanceFirst,
  bool singleSourceMode = false,
}) async {
  final normalizedWeights = normalizeHybridWeights(
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    context: 'legacy-oracle',
  );

  final effectiveTopK = sourceIds != null ? (topK * 10).clamp(50, 200) : topK;
  final hybridResults = await hybrid.searchHybrid(
    queryText: queryText,
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

  var chunks = await _hydrateCanonicalChunkResults(
    hybridResults.take(topK).map(_chunkSearchResultFromHybrid).toList(),
  );

  if (singleSourceMode && chunks.isNotEmpty) {
    chunks = _filterToMostRelevantSource(chunks, queryText);
  }
  if (adjacentChunks > 0 && chunks.isNotEmpty) {
    chunks = await _expandWithAdjacentChunks(chunks, adjacentChunks);
  }

  final context = ContextBuilder.build(
    searchResults: chunks,
    tokenBudget: tokenBudget,
    strategy: strategy,
    singleSourceMode: singleSourceMode,
  );

  return HybridSearchParitySnapshot(chunks: chunks, context: context);
}

Future<HybridSearchParitySnapshot> buildLowLevelHybridParitySnapshot({
  required String collectionId,
  required String queryText,
  required List<double> queryEmbedding,
  required int topK,
  required int tokenBudget,
  required double vectorWeight,
  required double bm25Weight,
  List<int>? sourceIds,
  int adjacentChunks = 0,
  ContextStrategy strategy = ContextStrategy.relevanceFirst,
  bool singleSourceMode = false,
}) async {
  final normalizedWeights = normalizeHybridWeights(
    vectorWeight: vectorWeight,
    bm25Weight: bm25Weight,
    context: 'low-level-oracle',
  );

  final handle = await searchMetaHybrid(
    collectionId: collectionId,
    queryText: queryText,
    queryEmbedding: queryEmbedding,
    options: SearchMetaHybridOptions(
      topK: topK,
      vectorWeight: normalizedWeights.vectorWeight,
      bm25Weight: normalizedWeights.bm25Weight,
      sourceIds: sourceIds != null ? _toInt64List(sourceIds) : null,
      adjacentChunks: adjacentChunks,
    ),
  );

  try {
    final hits = await handle.hitMeta();
    final lowLevelContext = await handle.assembleContext(
      options: AssembleContextOptions(
        tokenBudget: tokenBudget,
        strategy: switch (strategy) {
          ContextStrategy.relevanceFirst =>
            ContextAssemblyStrategy.relevanceFirst,
          ContextStrategy.diverseSources =>
            ContextAssemblyStrategy.diverseSources,
          ContextStrategy.chronological =>
            ContextAssemblyStrategy.chronological,
        },
        separator: '\n\n---\n\n',
        singleSourceMode: singleSourceMode,
      ),
    );

    final hitChunkIds = hits.map((hit) => hit.chunkId.toInt()).toList();
    var hydratedChunks = hitChunkIds.isEmpty
        ? const <ChunkSearchResult>[]
        : orderHydratedChunksByIds(
            orderedChunkIds: hitChunkIds,
            hydratedChunks: await handle.hydrateChunks(
              chunkIds: _toInt64List(hitChunkIds),
            ),
          );

    final missingIncludedIds = missingChunkIds(
      orderedChunkIds:
          lowLevelContext.includedChunkIds.map((chunkId) => chunkId.toInt()),
      hydratedChunks: hydratedChunks,
    );
    if (missingIncludedIds.isNotEmpty) {
      hydratedChunks = [
        ...hydratedChunks,
        ...await handle.hydrateChunks(
            chunkIds: _toInt64List(missingIncludedIds)),
      ];
    }

    final context = buildLegacyCompatibleContextFromLowLevel(
      lowLevelContext: lowLevelContext,
      hydratedChunks: hydratedChunks,
    );

    var chunks = orderHydratedChunksByIds(
      orderedChunkIds: hitChunkIds,
      hydratedChunks: hydratedChunks,
    );
    if (singleSourceMode && chunks.isNotEmpty) {
      chunks = _filterToMostRelevantSource(chunks, queryText);
    }

    return HybridSearchParitySnapshot(chunks: chunks, context: context);
  } finally {
    await handle.dispose();
  }
}
