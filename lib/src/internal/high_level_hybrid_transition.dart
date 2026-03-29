library;

import '../../services/context_builder.dart';
import '../rust/api/source_rag.dart';

class HybridSearchParitySnapshot {
  final List<ChunkSearchResult> chunks;
  final AssembledContext context;

  const HybridSearchParitySnapshot({
    required this.chunks,
    required this.context,
  });
}

class HybridSearchParityMismatch {
  final String fieldPath;
  final int? index;
  final Object? expected;
  final Object? actual;

  const HybridSearchParityMismatch({
    required this.fieldPath,
    this.index,
    required this.expected,
    required this.actual,
  });

  @override
  String toString() {
    final location = index == null ? fieldPath : '$fieldPath[$index]';
    return '$location expected=$expected actual=$actual';
  }
}

class HybridSearchParityReport {
  final List<HybridSearchParityMismatch> mismatches;

  const HybridSearchParityReport({required this.mismatches});

  bool get isMatch => mismatches.isEmpty;

  String describe() {
    if (mismatches.isEmpty) {
      return 'No parity mismatches.';
    }
    return mismatches.map((mismatch) => mismatch.toString()).join('\n');
  }
}

List<int> missingChunkIds({
  required Iterable<int> orderedChunkIds,
  required List<ChunkSearchResult> hydratedChunks,
}) {
  final hydratedIds =
      hydratedChunks.map((chunk) => chunk.chunkId.toInt()).toSet();
  return orderedChunkIds
      .where((chunkId) => !hydratedIds.contains(chunkId))
      .toList();
}

List<ChunkSearchResult> orderHydratedChunksByIds({
  required Iterable<int> orderedChunkIds,
  required List<ChunkSearchResult> hydratedChunks,
}) {
  final chunksById = <int, ChunkSearchResult>{
    for (final chunk in hydratedChunks) chunk.chunkId.toInt(): chunk,
  };

  return orderedChunkIds
      .map((chunkId) => chunksById[chunkId])
      .whereType<ChunkSearchResult>()
      .toList(growable: false);
}

AssembledContext buildLegacyCompatibleContextFromLowLevel({
  required AssembledContextV2 lowLevelContext,
  required List<ChunkSearchResult> hydratedChunks,
}) {
  final includedChunks = orderHydratedChunksByIds(
    orderedChunkIds:
        lowLevelContext.includedChunkIds.map((chunkId) => chunkId.toInt()),
    hydratedChunks: hydratedChunks,
  );

  return AssembledContext(
    text: lowLevelContext.text,
    includedChunks: includedChunks,
    estimatedTokens: lowLevelContext.exactTokens,
    remainingBudget: lowLevelContext.remainingBudget,
  );
}

HybridSearchParityReport compareHybridSearchParity({
  required HybridSearchParitySnapshot expected,
  required HybridSearchParitySnapshot actual,
}) {
  final mismatches = <HybridSearchParityMismatch>[];

  _compareChunkLists(
    fieldPath: 'chunks',
    expected: expected.chunks,
    actual: actual.chunks,
    mismatches: mismatches,
  );
  _compareValues(
    fieldPath: 'context.text',
    expected: expected.context.text,
    actual: actual.context.text,
    mismatches: mismatches,
  );
  _compareValues(
    fieldPath: 'context.estimatedTokens',
    expected: expected.context.estimatedTokens,
    actual: actual.context.estimatedTokens,
    mismatches: mismatches,
  );
  _compareValues(
    fieldPath: 'context.remainingBudget',
    expected: expected.context.remainingBudget,
    actual: actual.context.remainingBudget,
    mismatches: mismatches,
  );
  _compareChunkLists(
    fieldPath: 'context.includedChunks',
    expected: expected.context.includedChunks,
    actual: actual.context.includedChunks,
    mismatches: mismatches,
  );

  return HybridSearchParityReport(mismatches: mismatches);
}

List<int> candidateChunkIdsForSelectedSource({
  required Iterable<SearchHitMeta> hits,
  required int? selectedSourceId,
}) {
  final candidateHits = selectedSourceId == null
      ? hits
      : hits.where((hit) => hit.sourceId.toInt() == selectedSourceId);
  return candidateHits
      .map((hit) => hit.chunkId.toInt())
      .toList(growable: false);
}

void _compareChunkLists({
  required String fieldPath,
  required List<ChunkSearchResult> expected,
  required List<ChunkSearchResult> actual,
  required List<HybridSearchParityMismatch> mismatches,
}) {
  _compareValues(
    fieldPath: '$fieldPath.length',
    expected: expected.length,
    actual: actual.length,
    mismatches: mismatches,
  );

  final sharedLength =
      expected.length < actual.length ? expected.length : actual.length;
  for (var index = 0; index < sharedLength; index++) {
    final expectedChunk = expected[index];
    final actualChunk = actual[index];
    _compareValues(
      fieldPath: '$fieldPath.chunkId',
      index: index,
      expected: expectedChunk.chunkId.toInt(),
      actual: actualChunk.chunkId.toInt(),
      mismatches: mismatches,
    );
    _compareValues(
      fieldPath: '$fieldPath.sourceId',
      index: index,
      expected: expectedChunk.sourceId.toInt(),
      actual: actualChunk.sourceId.toInt(),
      mismatches: mismatches,
    );
    _compareValues(
      fieldPath: '$fieldPath.chunkIndex',
      index: index,
      expected: expectedChunk.chunkIndex,
      actual: actualChunk.chunkIndex,
      mismatches: mismatches,
    );
    _compareValues(
      fieldPath: '$fieldPath.content',
      index: index,
      expected: expectedChunk.content,
      actual: actualChunk.content,
      mismatches: mismatches,
    );
    _compareValues(
      fieldPath: '$fieldPath.chunkType',
      index: index,
      expected: expectedChunk.chunkType,
      actual: actualChunk.chunkType,
      mismatches: mismatches,
    );
    _compareValues(
      fieldPath: '$fieldPath.similarity',
      index: index,
      expected: expectedChunk.similarity,
      actual: actualChunk.similarity,
      mismatches: mismatches,
    );
    _compareValues(
      fieldPath: '$fieldPath.metadata',
      index: index,
      expected: expectedChunk.metadata,
      actual: actualChunk.metadata,
      mismatches: mismatches,
    );
  }
}

void _compareValues({
  required String fieldPath,
  int? index,
  required Object? expected,
  required Object? actual,
  required List<HybridSearchParityMismatch> mismatches,
}) {
  if (expected == actual) {
    return;
  }

  mismatches.add(
    HybridSearchParityMismatch(
      fieldPath: fieldPath,
      index: index,
      expected: expected,
      actual: actual,
    ),
  );
}
