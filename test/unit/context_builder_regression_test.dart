import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
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
    setUp(() {
      ContextBuilder.debugTokenCounterOverride =
          (text) => RegExp(r'\S+').allMatches(text).length;
      ContextBuilder.debugCompressionRunnerOverride = null;
    });

    tearDown(() {
      ContextBuilder.debugTokenCounterOverride = null;
      ContextBuilder.debugCompressionRunnerOverride = null;
    });

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

    test('token budget uses rendered XML metadata and contextual overhead', () {
      final metadata = List.filled(8, 'meta').join(' ');
      final results = <ChunkSearchResult>[
        _chunk(
          chunkId: 10,
          sourceId: 1,
          chunkIndex: 0,
          content: 'alpha beta gamma delta',
          similarity: 0.90,
          metadata: metadata,
        ),
        _chunk(
          chunkId: 11,
          sourceId: 1,
          chunkIndex: 1,
          content: 'epsilon zeta eta theta',
          similarity: 0.89,
          metadata: metadata,
        ),
      ];

      final context = ContextBuilder.build(
        searchResults: results,
        tokenBudget: 20,
        singleSourceMode: false,
      );

      expect(context.includedChunks, hasLength(1));
      expect(context.estimatedTokens <= 20, isTrue);
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

      expect(
        results.single.content,
        'Run `npm install` before starting the server.',
      );
      expect(context.text, contains('Guide > Setup'));
      expect(
        context.text,
        contains('Run `npm install` before starting the server.'),
      );
    });

    test('oversized chunk is skipped and later smaller chunks are still packed',
        () {
      final results = <ChunkSearchResult>[
        _chunk(
          chunkId: 40,
          sourceId: 1,
          chunkIndex: 0,
          content: 'alpha beta gamma delta epsilon zeta',
          similarity: 0.99,
        ),
        _chunk(
          chunkId: 41,
          sourceId: 1,
          chunkIndex: 1,
          content: 'small chunk',
          similarity: 0.80,
        ),
        _chunk(
          chunkId: 42,
          sourceId: 1,
          chunkIndex: 2,
          content: 'later fit',
          similarity: 0.70,
        ),
      ];

      final context = ContextBuilder.build(
        searchResults: results,
        tokenBudget: 5,
        separator: ' | ',
        singleSourceMode: true,
      );

      expect(
        context.includedChunks.map((chunk) => chunk.chunkId),
        orderedEquals([41, 42]),
      );
      expect(context.text, 'small chunk | later fit');
      expect(context.estimatedTokens, 5);
      expect(context.remainingBudget, 0);
    });

    test('no-overflow grouped rendering remains byte-for-byte stable', () {
      final results = <ChunkSearchResult>[
        _chunk(
          chunkId: 50,
          sourceId: 7,
          chunkIndex: 3,
          content: 'Install the package.',
          chunkType: 'text|Guide > Setup',
          similarity: 0.95,
          metadata: '{"source":"guide"}',
        ),
        _chunk(
          chunkId: 51,
          sourceId: 9,
          chunkIndex: 0,
          content: 'Run the smoke test.',
          similarity: 0.90,
        ),
      ];

      final context = ContextBuilder.build(
        searchResults: results,
        tokenBudget: 100,
        singleSourceMode: false,
      );

      expect(
        context.text,
        '<document id="7">\n'
        '  <metadata>{"source":"guide"}</metadata>\n'
        '  <content>\n'
        'Header Path: Guide > Setup\n'
        'Install the package.\n'
        '  </content>\n'
        '</document>\n'
        '\n'
        '<document id="9">\n'
        '  <content>\n'
        'Run the smoke test.\n'
        '  </content>\n'
        '</document>\n',
      );
      expect(
        context.estimatedTokens,
        RegExp(r'\S+').allMatches(context.text).length,
      );
      expect(context.remainingBudget, 100 - context.estimatedTokens);
    });

    test('renderContextText matches markdown embedding text contract', () {
      const content = 'Install dependencies before starting the server.';
      const chunkType = 'text|Guide > Setup';

      expect(
        renderContextText(content: content, chunkType: chunkType),
        buildChunkEmbeddingText(content: content, chunkType: chunkType),
      );
    });

    test('deriveContextBudgetForPrompt supports fixed overhead budgeting', () {
      final budget = ContextBuilder.deriveContextBudgetForPrompt(
        fullPromptBudget: 100,
        query: 'What changed?',
        options: const PromptBudgetOptions(
          fixedPromptOverheadTokens: 13,
          safetyMarginTokens: 7,
        ),
      );

      expect(budget, 80);
    });

    test(
      'deriveContextBudgetForPrompt can use a target prompt token counter',
      () {
        int counter(String text) => RegExp(r'\S+').allMatches(text).length;
        const query = 'Where is the guide?';
        final expectedSkeleton = 'Answer the question based ONLY on the '
            'documents below. If the information is not in the documents, '
            'say "I could not find the information in the provided documents".\n\n'
            '--- Reference Documents ---\n'
            '\n'
            '--- End of Documents ---\n\n'
            'Question: $query\n\n'
            'Answer:';

        final budget = ContextBuilder.deriveContextBudgetForPrompt(
          fullPromptBudget: 40,
          query: query,
          options: PromptBudgetOptions(
            safetyMarginTokens: 2,
            targetPromptTokenCounter: counter,
          ),
        );

        expect(
          budget,
          (40 - counter(expectedSkeleton) - 2).clamp(0, 1 << 30),
        );
      },
    );

    test(
      'buildWithCompression converges to exact token budget and keeps provenance',
      () async {
        var compressionCalls = 0;
        ContextBuilder.debugCompressionRunnerOverride =
            (renderedText, maxChars, level, language) async {
          compressionCalls++;
          if (compressionCalls == 1) {
            return 'alpha beta gamma delta epsilon';
          }
          if (compressionCalls == 2) {
            return 'alpha beta gamma';
          }
          return 'alpha beta';
        };

        final results = <ChunkSearchResult>[
          _chunk(
            chunkId: 30,
            sourceId: 2,
            chunkIndex: 0,
            content: 'alpha beta gamma delta epsilon',
            chunkType: 'text|Guide > Setup',
            similarity: 0.92,
          ),
          _chunk(
            chunkId: 31,
            sourceId: 2,
            chunkIndex: 1,
            content: 'zeta eta theta',
            chunkType: 'text|Guide > Setup',
            similarity: 0.90,
          ),
        ];

        final context = await ContextBuilder.buildWithCompression(
          searchResults: results,
          tokenBudget: 2,
          singleSourceMode: true,
        );

        expect(context.estimatedTokens, lessThanOrEqualTo(2));
        expect(context.text, 'alpha beta');
        expect(context.includedChunks, results);
        expect(context.remainingBudget, 0);
        expect(compressionCalls, greaterThanOrEqualTo(2));
      },
    );
  });
}
