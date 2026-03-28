import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/src/internal/high_level_hybrid_transition.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

ChunkSearchResult _chunk({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required String content,
  required double similarity,
  String chunkType = 'general',
  String? metadata,
}) {
  return ChunkSearchResult(
    chunkId: chunkId,
    sourceId: sourceId,
    chunkIndex: chunkIndex,
    content: content,
    chunkType: chunkType,
    similarity: similarity,
    metadata: metadata,
  );
}

frb.Int64List _toInt64List(List<int> values) {
  final result = frb.Int64List(values.length);
  for (var i = 0; i < values.length; i++) {
    result[i] = values[i];
  }
  return result;
}

void main() {
  group('high-level hybrid transition helpers', () {
    test(
        'buildLegacyCompatibleContextFromLowLevel preserves id order and exact tokens',
        () {
      final hydratedChunks = [
        _chunk(
          chunkId: 10,
          sourceId: 7,
          chunkIndex: 0,
          content: 'Install the package.',
          similarity: 0.9,
        ),
        _chunk(
          chunkId: 11,
          sourceId: 7,
          chunkIndex: 1,
          content: 'Verify the checksum.',
          similarity: 0.8,
        ),
      ];

      final context = buildLegacyCompatibleContextFromLowLevel(
        lowLevelContext: AssembledContextV2(
          text: 'Verify the checksum.\nInstall the package.',
          exactTokens: 7,
          includedChunkIds: _toInt64List([11, 10]),
          remainingBudget: 3,
        ),
        hydratedChunks: hydratedChunks,
      );

      expect(context.text, 'Verify the checksum.\nInstall the package.');
      expect(
        context.includedChunks.map((chunk) => chunk.chunkId.toInt()),
        orderedEquals([11, 10]),
      );
      expect(context.estimatedTokens, 7);
      expect(context.remainingBudget, 3);
    });

    test(
        'compareHybridSearchParity reports stable field path and index details',
        () {
      final expected = HybridSearchParitySnapshot(
        chunks: [
          _chunk(
            chunkId: 10,
            sourceId: 7,
            chunkIndex: 0,
            content: 'Install the package.',
            similarity: 0.9,
          ),
        ],
        context: AssembledContext(
          text: 'Install the package.',
          includedChunks: [
            _chunk(
              chunkId: 10,
              sourceId: 7,
              chunkIndex: 0,
              content: 'Install the package.',
              similarity: 0.9,
            ),
          ],
          estimatedTokens: 3,
          remainingBudget: 9,
        ),
      );
      final actual = HybridSearchParitySnapshot(
        chunks: [
          _chunk(
            chunkId: 10,
            sourceId: 7,
            chunkIndex: 0,
            content: 'Install the package now.',
            similarity: 0.85,
          ),
        ],
        context: AssembledContext(
          text: 'Install the package now.',
          includedChunks: [
            _chunk(
              chunkId: 10,
              sourceId: 7,
              chunkIndex: 0,
              content: 'Install the package now.',
              similarity: 0.85,
            ),
          ],
          estimatedTokens: 4,
          remainingBudget: 8,
        ),
      );

      final report = compareHybridSearchParity(
        expected: expected,
        actual: actual,
      );

      expect(report.isMatch, isFalse);
      expect(
        report.mismatches.any(
          (mismatch) =>
              mismatch.fieldPath == 'chunks.content' &&
              mismatch.index == 0 &&
              mismatch.expected == 'Install the package.' &&
              mismatch.actual == 'Install the package now.',
        ),
        isTrue,
      );
      expect(
        report.mismatches.any(
          (mismatch) =>
              mismatch.fieldPath == 'context.estimatedTokens' &&
              mismatch.index == null &&
              mismatch.expected == 3 &&
              mismatch.actual == 4,
        ),
        isTrue,
      );
      expect(
        report.describe(),
        contains(
            'chunks.content[0] expected=Install the package. actual=Install the package now.'),
      );
    });
  });
}
