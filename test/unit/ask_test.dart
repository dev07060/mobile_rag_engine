import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

ChunkSearchResult _chunk(int chunkId, int sourceId, String content) =>
    ChunkSearchResult(
      chunkId: chunkId,
      sourceId: sourceId,
      chunkIndex: 0,
      content: content,
      chunkType: 'general',
      similarity: 0.5,
    );

RagSearchResult _result(List<ChunkSearchResult> included) => RagSearchResult(
  chunks: included,
  context: AssembledContext(
    text: included.map((c) => c.content).join('\n\n---\n\n'),
    includedChunks: included,
    estimatedTokens: 42,
    remainingBudget: 100,
  ),
);

SourceEntry _source(int id, String? name) =>
    SourceEntry(id: id, name: name, createdAt: 0, collectionId: 'default');

RagSearchTool _tool(
  List<ChunkSearchResult> chunks, {
  List<(String, int)>? searches,
  int topK = 5,
}) => RagSearchTool(
  search: (query, k) async {
    searches?.add((query, k));
    return _result(chunks);
  },
  listSources: () async => [_source(7, 'refund.md')],
  defaultTopK: topK,
  maxTopK: topK,
);

RagPassage _passage(String id) => RagPassage(id: id, text: 'text $id');

void main() {
  final refund = _chunk(31, 7, '환불은 구매일로부터 14일 이내에 가능하다.');
  final shipping = _chunk(12, 9, 'Shipping takes 2-3 days.');

  group('askWith', () {
    test('sends one prompt and returns the cited passages', () async {
      final searches = <(String, int)>[];
      final prompts = <String>[];
      final answer = await askWith(
        _tool([refund, shipping], searches: searches, topK: 3),
        '환불 기간은?',
        generate: (prompt) async {
          prompts.add(prompt);
          return '구매일로부터 14일 이내입니다 [1].';
        },
      );

      expect(searches, [('환불 기간은?', 3)]);
      expect(prompts, [answer.prompt]);
      expect(answer.text, '구매일로부터 14일 이내입니다 [1].');
      expect(answer.hasPassages, isTrue);
      expect([for (final p in answer.passages) p.id], ['1', '2']);
      expect([for (final p in answer.citations) p.id], ['1']);

      final cited = answer.citations.single;
      expect(cited.sourceId, 7);
      expect(cited.sourceName, 'refund.md');
      expect(cited.chunkId, 31);
      expect(cited.text, refund.content);
      expect(answer.passages[1].sourceName, isNull);
    });

    test('does not call generate when nothing is found', () async {
      var calls = 0;
      final answer = await askWith(
        _tool(const []),
        'anything',
        generate: (prompt) async {
          calls++;
          return 'made up';
        },
      );

      expect(calls, 0);
      expect(answer.hasPassages, isFalse);
      expect(answer.text, isEmpty);
      expect(answer.prompt, isEmpty);
      expect(answer.citations, isEmpty);
    });

    test('rejects an empty question before searching', () async {
      final searches = <(String, int)>[];
      await expectLater(
        askWith(
          _tool([refund], searches: searches),
          '  ',
          generate: (prompt) async => '',
        ),
        throwsArgumentError,
      );
      expect(searches, isEmpty);
    });

    test('propagates generate failures', () async {
      await expectLater(
        askWith(
          _tool([refund]),
          'q',
          generate: (prompt) async => throw StateError('offline'),
        ),
        throwsStateError,
      );
    });

    test('uses a custom prompt builder', () async {
      final answer = await askWith(
        _tool([refund, shipping]),
        'q',
        generate: (prompt) async => prompt,
        buildPrompt: (question, passages) =>
            '$question:${passages.map((p) => p.id).join(',')}',
      );
      expect(answer.text, 'q:1,2');
    });
  });

  group('prepareAskWith', () {
    test('numbers passages from 1 for every question', () async {
      final tool = _tool([refund, shipping]);
      final first = await prepareAskWith(tool, 'a');
      final second = await prepareAskWith(_tool([refund, shipping]), 'b');
      expect([for (final p in first.passages) p.id], ['1', '2']);
      expect([for (final p in second.passages) p.id], ['1', '2']);
    });

    test('answer() pairs a streamed answer with its citations', () async {
      final prepared = await prepareAskWith(_tool([refund, shipping]), 'q');
      final answer = prepared.answer('Both [2] and [1].');
      expect([for (final p in answer.citations) p.id], ['2', '1']);
      expect(answer.prompt, prepared.prompt);
    });
  });

  group('defaultAskPrompt', () {
    test('lists each passage once with its id and source name', () {
      final prompt = defaultAskPrompt(' 환불 기간은? ', [
        RagPassage(id: '1', text: refund.content, sourceName: 'refund.md'),
        RagPassage(id: '2', text: shipping.content),
      ]);

      expect(prompt, contains('[1] refund.md\n${refund.content}\n'));
      expect(prompt, contains('[2]\n${shipping.content}\n'));
      expect(prompt, endsWith('Question: 환불 기간은?'));
      expect(prompt, contains('like [1]'));
      expect(
        RegExp(RegExp.escape(refund.content)).allMatches(prompt),
        hasLength(1),
      );
      expect(prompt, isNot(contains('source_id')));
    });
  });

  group('citedPassages', () {
    final passages = [_passage('1'), _passage('2'), _passage('3')];

    List<String> ids(String text) => [
      for (final p in citedPassages(text, passages)) p.id,
    ];

    test('reads single, grouped and adjacent citations', () {
      expect(ids('A [2]. B [1, 3].'), ['2', '1', '3']);
      expect(ids('A [3][1]'), ['3', '1']);
      expect(ids('A [1,2]'), ['1', '2']);
    });

    test('keeps the first citation of each passage', () {
      expect(ids('[2] then [1] then [2] again [1]'), ['2', '1']);
    });

    test('leaves out ids that were not given to the model', () {
      expect(ids('Invented [9] and real [3], [0]'), ['3']);
    });

    test('ignores brackets that are not citations', () {
      expect(ids('No citations [a] [1a] [ ] [-1] here'), isEmpty);
    });
  });
}
