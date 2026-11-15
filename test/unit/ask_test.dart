import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine/src/internal/prompt_budget.dart';
import 'package:mocktail/mocktail.dart';

class _MockRagEngine extends Mock implements RagEngine {}

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

    test('reads CJK corner bracket citations', () {
      expect(ids('「1」에 따르면 … 「3」과 「2」'), ['1', '3', '2']);
      expect(ids('『2』によると [1]'), ['2', '1']);
      expect(ids('「1, 3」'), ['1', '3']);
    });

    test('does not read quoted words or unmatched brackets as citations', () {
      expect(ids('「결전」 전에 「공성 준비」'), isEmpty);
      expect(ids('「9」 and 「1] and [2」 and 「1』'), isEmpty);
    });

    test('ignores brackets that are not citations', () {
      expect(ids('No citations [a] [1a] [ ] [-1] here'), isEmpty);
    });

    // Q4 B12: citation forms models answering in Korean, Japanese or Chinese
    // produce, and code that is not a citation.
    test('reads full-width brackets and digits', () {
      expect(ids('返金は可能です［１］。価格は３.５ドル［２］。'), ['1', '2']);
      expect(ids('환불 가능［3］ and [２]'), ['3', '2']);
      expect(ids('「２」と『３』'), ['2', '3']);
    });

    test('reads lenticular brackets', () {
      expect(ids('北京是中国的首都【1】，人口很多【3】。'), ['1', '3']);
      expect(ids('【1，2】'), ['1', '2']);
    });

    test('reads ideographic and full-width commas', () {
      expect(ids('東京は大きい[1、2]。'), ['1', '2']);
      expect(ids('[3，1]'), ['3', '1']);
      expect(ids('【2、3】'), ['2', '3']);
    });

    test('reads ranges', () {
      expect(ids('환불은 14일 이내 🚀 [1-3]'), ['1', '2', '3']);
      expect(ids('[2–3] and [1~2]'), ['2', '3', '1']);
      expect(ids('［１－２］'), ['1', '2']);
      // Only ids that were given; reversed ranges are not citations.
      expect(ids('[2-9]'), ['2', '3']);
      expect(ids('[3-1] [2024-11]'), isEmpty);
    });

    test('does not read code as citations', () {
      expect(ids('Use `items[2]` here [1].'), ['1']);
      expect(ids('```dart\nfinal x = items[2] + list[3];\n```\nSee [1].'), [
        '1',
      ]);
      expect(ids('~~~\nrow[2]\n~~~\n'), isEmpty);
      // Text after a code span is still read.
      expect(ids('`a[1]` 그리고 「3」 3.14 [2]'), ['3', '2']);
    });
  });

  // Q4 B13: tokenBudget in the LLM's tokens when the app gives a counter.
  group('promptTokenCounter', () {
    late _MockRagEngine engine;
    late MobileRag rag;
    // 29, 22 and 16 code points.
    final ko = _chunk(31, 7, '환불은 구매일로부터 14일 이내에 가능하다 🚀 ２.５');
    final ja = _chunk(32, 7, '返金は14日以内です。東京は大きい。3.14');
    final zh = _chunk(33, 9, '\u1112\u116a\u11ab\u1107\u116e\u11af 退款需在14天内。');
    int codePoints(String text) => text.runes.length;

    setUp(() {
      engine = _MockRagEngine();
      rag = MobileRag.useEngineForTest(engine);
      when(
        () => engine.searchHybridWithContext(
          any(),
          topK: any(named: 'topK'),
          tokenBudget: any(named: 'tokenBudget'),
          vectorWeight: any(named: 'vectorWeight'),
          bm25Weight: any(named: 'bm25Weight'),
          collectionId: any(named: 'collectionId'),
        ),
      ).thenAnswer((_) async => _result([ko, ja, zh]));
      when(
        () => engine.listSources(collectionId: any(named: 'collectionId')),
      ).thenAnswer((_) async => [_source(7, 'refund.md')]);
    });
    tearDown(() => MobileRag.setMockInstance(null));

    List<int> chunkIds(RagAskPrompt p) => [
      for (final x in p.passages) x.chunkId!,
    ];

    test(
      'keeps the most relevant passages that fit, counted by the counter',
      () async {
        expect(codePoints(ko.content), 29);
        expect(codePoints(ja.content), 22);
        final one = await rag.prepareAsk(
          'q',
          tokenBudget: 50,
          promptTokenCounter: codePoints,
        );
        final two = await rag.prepareAsk(
          'q',
          tokenBudget: 51,
          promptTokenCounter: codePoints,
        );
        expect(chunkIds(one), [31]);
        expect(chunkIds(two), [31, 32]);
        expect(one.prompt, contains(ko.content));
        expect(one.prompt, isNot(contains(ja.content)));
      },
    );

    test('lets the engine keep every hit whole', () async {
      await rag.ask(
        'q',
        generate: (_) async => '［１］',
        tokenBudget: 100,
        promptTokenCounter: codePoints,
      );
      verify(
        () => engine.searchHybridWithContext(
          'q',
          topK: 5,
          tokenBudget: uncappedEngineTokenBudget,
          vectorWeight: null,
          bm25Weight: null,
        ),
      ).called(1);
    });

    test('a passage larger than the budget is left out, not cut', () async {
      final none = await rag.prepareAsk(
        'q',
        tokenBudget: 28,
        promptTokenCounter: codePoints,
      );
      expect(none.hasPassages, isFalse);
      expect(none.prompt, isEmpty);
    });

    test('works on collections and on the tool', () async {
      final scoped = await rag
          .inCollection('manuals')
          .prepareAsk('q', tokenBudget: 51, promptTokenCounter: codePoints);
      expect(chunkIds(scoped), [31, 32]);
      verify(
        () => engine.searchHybridWithContext(
          'q',
          topK: 5,
          tokenBudget: uncappedEngineTokenBudget,
          vectorWeight: null,
          bm25Weight: null,
          collectionId: 'manuals',
        ),
      ).called(1);

      final tool = RagSearchTool.fromMobileRag(
        rag,
        tokenBudget: 67,
        promptTokenCounter: codePoints,
      );
      final json = await tool.call({'query': 'q'});
      expect(
        [for (final r in json['results'] as List) (r as Map)['chunk_id']],
        [31, 32, 33],
      );
      final tight = RagSearchTool.fromMobileRag(
        rag,
        tokenBudget: 30,
        promptTokenCounter: codePoints,
      );
      final tightJson = await tight.call({'query': 'q'});
      expect(
        [for (final r in tightJson['results'] as List) (r as Map)['chunk_id']],
        [31],
      );
    });
  });

  group('MobileRag.prepareAsk / ask search weights', () {
    late _MockRagEngine engine;
    late MobileRag rag;

    setUp(() {
      engine = _MockRagEngine();
      rag = MobileRag.useEngineForTest(engine);
      when(
        () => engine.searchHybridWithContext(
          any(),
          topK: any(named: 'topK'),
          tokenBudget: any(named: 'tokenBudget'),
          vectorWeight: any(named: 'vectorWeight'),
          bm25Weight: any(named: 'bm25Weight'),
          collectionId: any(named: 'collectionId'),
        ),
      ).thenAnswer((_) async => _result([refund]));
      when(
        () => engine.listSources(collectionId: any(named: 'collectionId')),
      ).thenAnswer((_) async => [_source(7, 'refund.md')]);
    });
    tearDown(() => MobileRag.setMockInstance(null));

    test('default arguments search with 5 / 1500 and leave the weights to the '
        'engine defaults', () async {
      await rag.prepareAsk('q');
      await rag.ask('q', generate: (_) async => 'a [1]');
      await RagSearchTool.fromMobileRag(rag).call({'query': 'q'});
      verify(
        () => engine.searchHybridWithContext(
          'q',
          topK: 5,
          tokenBudget: 1500,
          vectorWeight: null,
          bm25Weight: null,
        ),
      ).called(3);
    });

    test('given weights are passed to the search', () async {
      await rag.prepareAsk('q', vectorWeight: 0.5, bm25Weight: 0.5);
      await rag.ask(
        'q',
        generate: (_) async => 'a',
        vectorWeight: 0.7,
        bm25Weight: 0.3,
      );
      await rag
          .inCollection('manuals')
          .prepareAsk('q', vectorWeight: 0.6, bm25Weight: 0.4);
      verify(
        () => engine.searchHybridWithContext(
          'q',
          topK: 5,
          tokenBudget: 1500,
          vectorWeight: 0.5,
          bm25Weight: 0.5,
        ),
      ).called(1);
      verify(
        () => engine.searchHybridWithContext(
          'q',
          topK: 5,
          tokenBudget: 1500,
          vectorWeight: 0.7,
          bm25Weight: 0.3,
        ),
      ).called(1);
      verify(
        () => engine.searchHybridWithContext(
          'q',
          topK: 5,
          tokenBudget: 1500,
          vectorWeight: 0.6,
          bm25Weight: 0.4,
          collectionId: 'manuals',
        ),
      ).called(1);
    });
  });
}
