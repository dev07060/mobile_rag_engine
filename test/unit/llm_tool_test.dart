import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mocktail/mocktail.dart';

class MockMobileRag extends Mock implements MobileRag {}

class MockCollectionRag extends Mock implements CollectionRag {}

class MockRagEngine extends Mock implements RagEngine {}

ChunkSearchResult _chunk(
  int chunkId,
  int sourceId,
  String content, {
  double similarity = 0.5,
}) => ChunkSearchResult(
  chunkId: chunkId,
  sourceId: sourceId,
  chunkIndex: chunkId % 10,
  content: content,
  chunkType: 'general',
  similarity: similarity,
);

RagSearchResult _result(
  List<ChunkSearchResult> included, {
  List<ChunkSearchResult> extra = const [],
}) => RagSearchResult(
  chunks: [...included, ...extra],
  context: AssembledContext(
    text: included.map((c) => c.content).join('\n\n---\n\n'),
    includedChunks: included,
    estimatedTokens: 42,
    remainingBudget: 100,
  ),
);

SourceEntry _source(int id, String? name) =>
    SourceEntry(id: id, name: name, createdAt: 0, collectionId: 'default');

void main() {
  group('RagSearchResult.toLlmJson', () {
    test('labels included chunks and keeps ids for mapping back', () {
      final json = _result(
        [
          _chunk(31, 7, '환불은 14일 이내', similarity: 0.83456),
          _chunk(12, 9, 'Shipping takes 2-3 days'),
        ],
        // Retrieved but over the token budget: not part of the context.
        extra: [_chunk(99, 7, 'over budget')],
      ).toLlmJson(sourceNames: {7: 'refund.md'});

      expect(json.keys, ['results']);
      expect(json['results'], [
        {
          'id': '1',
          'source_id': 7,
          'source_name': 'refund.md',
          'chunk_id': 31,
          'chunk_index': 1,
          'score': 1.0,
          'text': '환불은 14일 이내',
        },
        {
          'id': '2',
          'source_id': 9,
          'chunk_id': 12,
          'chunk_index': 2,
          'score': 0.599,
          'text': 'Shipping takes 2-3 days',
        },
      ]);
    });

    test('keeps hybrid (RRF) scores apart', () {
      // Hybrid similarity is 1/(60+rank)-based: about 0.016 at best.
      final json = _result([
        _chunk(1, 1, 'a', similarity: 0.01639),
        _chunk(2, 1, 'b', similarity: 0.01613),
        _chunk(3, 1, 'c', similarity: 0.01587),
      ]).toLlmJson();

      expect(
        [for (final r in json['results'] as List) r['score']],
        [1.0, 0.984, 0.968],
      );
    });

    test('numbers citation ids from firstId', () {
      final json = _result([
        _chunk(1, 1, 'a'),
        _chunk(2, 1, 'b'),
      ]).toLlmJson(firstId: 4);

      expect([for (final r in json['results'] as List) r['id']], ['4', '5']);
    });

    test('turns context-only results into one passage', () {
      final json = RagSearchResult(
        chunks: const [],
        context: AssembledContext(
          text: '<document id="7">...</document>',
          includedChunks: const [],
          estimatedTokens: 5,
          remainingBudget: 0,
        ),
      ).toLlmJson(firstId: 3);

      expect(json, {
        'results': [
          {'id': '3', 'text': '<document id="7">...</document>'},
        ],
      });
    });

    test('is encodable as JSON', () {
      final json = _result([_chunk(1, 1, 'a "quoted" text')]).toLlmJson();
      expect(jsonDecode(jsonEncode(json)), json);
    });
  });

  group('RagSearchTool', () {
    late List<(String, int)> calls;
    late RagSearchTool tool;

    setUp(() {
      calls = [];
      tool = RagSearchTool(
        search: (query, topK) async {
          calls.add((query, topK));
          return _result([_chunk(31, 7, '환불은 14일 이내')]);
        },
        listSources: () async => [_source(7, 'refund.md'), _source(9, null)],
      );
    });

    test('definition is a provider-neutral JSON Schema tool', () {
      final definition = tool.definition;
      expect(definition['name'], 'search_documents');
      expect(definition['description'], contains('cite'));
      expect(definition['parameters'], {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': isA<String>()},
          'top_k': {
            'type': 'integer',
            'description': isA<String>(),
            'minimum': 1,
            'maximum': 10,
          },
        },
        'required': ['query'],
      });
      // Registers with an SDK as plain JSON.
      expect(jsonDecode(jsonEncode(definition)), isA<Map<String, dynamic>>());
    });

    test(
      'round-trips a tool call from raw JSON to a JSON tool result',
      () async {
        final output = await tool.callJson('{"query": " 환불 기간 ", "top_k": 3}');

        expect(calls, [('환불 기간', 3)]);
        final decoded = jsonDecode(output) as Map<String, dynamic>;
        expect(decoded.keys, ['results']);
        expect(decoded['results'], [
          {
            'id': '1',
            'source_id': 7,
            'source_name': 'refund.md',
            'chunk_id': 31,
            'chunk_index': 1,
            'score': 1.0,
            'text': '환불은 14일 이내',
          },
        ]);
      },
    );

    test('continues citation ids across calls', () async {
      final ids = <Object?>[];
      final twoHits = RagSearchTool(
        search: (query, topK) async =>
            _result([_chunk(31, 7, 'a'), _chunk(12, 9, 'b')]),
      );
      for (final query in ['first', 'second']) {
        final output = await twoHits.call({'query': query});
        ids.addAll([for (final r in output['results'] as List) r['id']]);
      }

      expect(ids, ['1', '2', '3', '4']);
    });

    test(
      'uses defaultTopK, clamps top_k and accepts integral doubles',
      () async {
        await tool.call({'query': 'a'});
        await tool.call({'query': 'a', 'top_k': 50});
        await tool.call({'query': 'a', 'top_k': 0});
        await tool.call({'query': 'a', 'top_k': 4.0});

        expect(calls.map((c) => c.$2), [5, 10, 1, 4]);
      },
    );

    test('returns errors for invalid arguments without searching', () async {
      final outputs = [
        await tool.call({}),
        await tool.call({'query': '   '}),
        await tool.call({'query': 1}),
        await tool.call({'query': 'a', 'top_k': 2.5}),
        await tool.call({'query': 'a', 'top_k': '3'}),
        jsonDecode(await tool.callJson('not json')),
        jsonDecode(await tool.callJson('["query"]')),
        jsonDecode(await tool.callJson('')),
      ];

      for (final output in outputs) {
        expect(output, {'error': isA<String>()});
      }
      expect(calls, isEmpty);
    });

    test('skips the source lookup when nothing was found', () async {
      var lookups = 0;
      final empty = RagSearchTool(
        search: (query, topK) async => _result(const []),
        listSources: () async {
          lookups++;
          return const [];
        },
      );

      expect(await empty.call({'query': 'a'}), {'results': <Object?>[]});
      expect(lookups, 0);
    });

    test('propagates engine failures', () async {
      final failing = RagSearchTool(
        search: (query, topK) async => throw StateError('engine down'),
      );

      await expectLater(failing.call({'query': 'a'}), throwsStateError);
    });

    test('rejects a defaultTopK outside 1..maxTopK', () {
      expect(
        () => RagSearchTool(
          search: (query, topK) async => _result(const []),
          defaultTopK: 11,
        ),
        throwsArgumentError,
      );
    });

    test('fromMobileRag searches hybrid within the token budget', () async {
      final rag = MockMobileRag();
      when(
        () => rag.searchHybridWithContext(
          any(),
          topK: any(named: 'topK'),
          tokenBudget: any(named: 'tokenBudget'),
        ),
      ).thenAnswer((_) async => _result([_chunk(31, 7, 'x')]));
      when(rag.listSources).thenAnswer((_) async => [_source(7, 'refund.md')]);

      final output = await RagSearchTool.fromMobileRag(
        rag,
        tokenBudget: 800,
      ).call({'query': 'q', 'top_k': 2});

      verify(
        () => rag.searchHybridWithContext('q', topK: 2, tokenBudget: 800),
      ).called(1);
      expect(
        (output['results'] as List).single,
        containsPair('source_name', 'refund.md'),
      );
    });

    test('fromCollection looks the collection up on every call', () async {
      final rag = MockMobileRag();
      final collection = MockCollectionRag();
      when(() => rag.engine).thenReturn(MockRagEngine());
      MobileRag.setMockInstance(rag);
      addTearDown(() => MobileRag.setMockInstance(null));
      when(() => rag.inCollection('manuals')).thenReturn(collection);
      when(
        () => collection.searchHybridWithContext(
          any(),
          topK: any(named: 'topK'),
          tokenBudget: any(named: 'tokenBudget'),
        ),
      ).thenAnswer((_) async => _result([_chunk(31, 7, 'x')]));
      when(collection.listSources).thenAnswer((_) async => const []);

      final tool = RagSearchTool.fromCollection('manuals');
      await tool.call({'query': 'q'});
      await tool.call({'query': 'q'});

      verify(
        () =>
            collection.searchHybridWithContext('q', topK: 5, tokenBudget: 1500),
      ).called(2);
      verify(() => rag.inCollection('manuals')).called(4);
    });
  });
}
