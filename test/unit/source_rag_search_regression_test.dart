import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';

ChunkSearchResult _chunk({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required String content,
  required String chunkType,
  required double similarity,
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

void main() {
  group('SourceRagService search regressions', () {
    test('markdown embedding text preserves header path across re-embedding', () {
      const content = 'Install dependencies before starting the server.';
      const chunkType = 'text|Guide > Setup';

      final embeddingText = buildChunkEmbeddingText(
        content: content,
        chunkType: chunkType,
      );

      expect(
        embeddingText,
        'Header Path: Guide > Setup\nInstall dependencies before starting the server.',
      );
    });

    test('plain chunk embedding text remains raw content', () {
      const content = 'Plain chunk body';

      final embeddingText = buildChunkEmbeddingText(
        content: content,
        chunkType: 'general',
      );

      expect(embeddingText, content);
    });

    test(
      'mergeCanonicalChunkSearchResult restores markdown chunk metadata without dropping hybrid score',
      () {
        final fallback = _chunk(
          chunkId: 10,
          sourceId: 7,
          chunkIndex: 3,
          content: 'Install dependencies.',
          chunkType: 'general',
          similarity: 0.83,
          metadata: '{"source":"hybrid"}',
        );
        final canonical = _chunk(
          chunkId: 10,
          sourceId: 7,
          chunkIndex: 3,
          content: 'Install dependencies.',
          chunkType: 'text|Guide > Setup',
          similarity: 0.0,
          metadata: '{"source":"canonical"}',
        );

        final merged = mergeCanonicalChunkSearchResult(
          fallback: fallback,
          canonical: canonical,
        );

        expect(merged.chunkType, 'text|Guide > Setup');
        expect(merged.content, 'Install dependencies.');
        expect(merged.similarity, 0.83);
        expect(merged.metadata, '{"source":"canonical"}');
      },
    );

    test('mergeCanonicalChunkSearchResult falls back cleanly when missing', () {
      final fallback = _chunk(
        chunkId: 11,
        sourceId: 8,
        chunkIndex: 0,
        content: 'Raw chunk',
        chunkType: 'general',
        similarity: 0.51,
      );

      final merged = mergeCanonicalChunkSearchResult(fallback: fallback);

      expect(merged, same(fallback));
    });
  });
}
