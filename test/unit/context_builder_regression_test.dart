import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';

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

void main() {
  group('ContextBuilder regression', () {
    test('singleSourceMode strips document headers and metadata wrappers', () {
      final results = <ChunkSearchResult>[
        _chunk(
          chunkId: 1,
          sourceId: 1,
          chunkIndex: 0,
          content: 'first',
          similarity: 0.90,
          metadata: '{"source":"a"}',
        ),
        _chunk(
          chunkId: 2,
          sourceId: 1,
          chunkIndex: 1,
          content: 'second',
          similarity: 0.85,
          metadata: '{"source":"a"}',
        ),
        _chunk(
          chunkId: 3,
          sourceId: 2,
          chunkIndex: 0,
          content: 'third',
          similarity: 0.30,
          metadata: '{"source":"b"}',
        ),
      ];

      final context = ContextBuilder.build(
        searchResults: results,
        tokenBudget: 500,
        separator: ' | ',
        singleSourceMode: true,
      );

      expect(context.includedChunks, hasLength(2));
      expect(
        context.includedChunks.every((chunk) => chunk.sourceId == 1),
        isTrue,
      );
      expect(context.text, equals('first | second'));
      expect(context.text.contains('<document'), isFalse);
      expect(context.text.contains('<metadata>'), isFalse);
    });

    test('token budget estimation includes rendered XML/metadata overhead', () {
      final metadata = 'm' * 60;
      final results = <ChunkSearchResult>[
        _chunk(
          chunkId: 10,
          sourceId: 1,
          chunkIndex: 0,
          content: 'a' * 40,
          similarity: 0.90,
          metadata: metadata,
        ),
        _chunk(
          chunkId: 11,
          sourceId: 1,
          chunkIndex: 1,
          content: 'b' * 40,
          similarity: 0.89,
          metadata: metadata,
        ),
      ];

      final context = ContextBuilder.build(
        searchResults: results,
        tokenBudget: 45,
        singleSourceMode: false,
      );

      expect(context.includedChunks, hasLength(1));
      expect(context.estimatedTokens <= 45, isTrue);
      expect(context.text.contains('<document id="1">'), isTrue);
      expect(context.text.contains('<metadata>$metadata</metadata>'), isTrue);
    });

    test('markdown header path is preserved in rendered context text', () {
      final results = <ChunkSearchResult>[
        _chunk(
          chunkId: 20,
          sourceId: 7,
          chunkIndex: 0,
          content: 'Run `npm install` before starting the server.',
          chunkType: 'text|Guide > Setup',
          similarity: 0.91,
        ),
      ];

      final context = ContextBuilder.build(
        searchResults: results,
        tokenBudget: 200,
        singleSourceMode: true,
      );

      expect(results.single.content,
          'Run `npm install` before starting the server.');
      expect(context.text, contains('Guide > Setup'));
      expect(
        context.text,
        contains('Run `npm install` before starting the server.'),
      );
    });
  });
}
