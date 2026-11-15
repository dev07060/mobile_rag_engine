// Q4 output contract (docs/milestones.md): the score unit of `search` (B10)
// and the order of results when adjacent chunks are added (B11).
//
// Chunks are stored with the fake worker's vector for their own text, so a
// query made of a chunk's text matches that chunk exactly (cosine 1.0).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/services/rag_engine.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

import '../support/fake_embedding_workers.dart';
import 'native_test_support.dart';

/// Every word is one [UNK] token.
const _wordLevelTokenizerJson =
    '{"version":"1.0","truncation":null,"padding":null,"added_tokens":[],'
    '"normalizer":null,"pre_tokenizer":{"type":"Whitespace"},'
    '"post_processor":null,"decoder":null,'
    '"model":{"type":"WordLevel","vocab":{"[UNK]":0},"unk_token":"[UNK]"}}';

/// Korean, Japanese, Chinese, NFD Hangul, full-width, emoji and decimals
/// (Q0 test text rule). Source "manual" is added first, so it has the lower
/// source id and sorts first by source.
const _manual = [
  '설치 안내 インストール 手順 첫 번째 단계 ３,５００원 버전 3.14',
  '東京は大きい。北京是中国的首都。 두 번째 단계 🚀 설정',
  '앱을 다시 시작하세요 세 번째 단계 ＲＡＧ 1.5배',
  '마지막 단계 문제 해결 版本 2.0 끝',
];
const _refund = [
  '환불 정책 소개 返金 退款 개요 0.5',
  // The chunk the queries look for. "환불" is NFD here.
  '\u1112\u116a\u11ab\u1107\u116e\u11af 은 구매 후 14일 이내 가능 返金は14日以内 退款需在14天内 🚀 ２.５',
  '환불 예외 사항 例外 例外情况 3.0',
];

Future<int> _addSource(String name, List<String> chunks) async {
  final source = await addSourceInCollection(
    collectionId: SourceRagService.defaultCollectionId,
    content: chunks.join('\n'),
    name: name,
  );
  await updateSourceStatus(sourceId: source.sourceId, status: 'completed');
  var offset = 0;
  await addChunks(
    sourceId: source.sourceId,
    chunks: [
      for (var i = 0; i < chunks.length; i++)
        ChunkData(
          content: chunks[i],
          chunkIndex: i,
          startPos: offset,
          endPos: offset += chunks[i].length,
          chunkType: 'general',
          embedding: fakeEmbedding(chunks[i]),
        ),
    ],
  );
  return source.sourceId.toInt();
}

/// Tokens of [chunk] alone in a document block, as context assembly renders
/// it: the budget that fits exactly one such chunk.
Future<int> _oneChunkBudget(int sourceId, String chunk) async {
  final block =
      '<document id="$sourceId">\n  <content>\n$chunk\n  </content>\n'
      '</document>\n';
  return countTokens(text: block);
}

void main() {
  late Directory dir;
  late RagEngine engine;
  late int manualId;
  late int refundId;
  final target = _refund[1];

  setUpAll(() async {
    if (!RustLib.instance.initialized) await RustLib.init();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mobile_rag_q4_contract_');
    final tokenizer = File('${dir.path}/tokenizer.json');
    await tokenizer.writeAsString(_wordLevelTokenizerJson);
    await initTokenizer(tokenizerPath: tokenizer.path);
    await EmbeddingService.startWorkerForTest(answeringWorker);
    engine = await RagEngine.initializeForTest(
      dbPath: '${dir.path}/q4.sqlite',
      embeddingDimension: fakeEmbeddingDimension,
    );
    manualId = await _addSource('manual', _manual);
    refundId = await _addSource('refund', _refund);
    await engine.rebuildIndex(force: true);
  });

  tearDown(() async {
    await RagEngine.dispose();
    await releaseNativeFilesAndDelete(dir);
  });

  group('B10 search similarity', () {
    test('is cosine similarity with and without sourceIds', () async {
      final all = await engine.search(target, topK: 3);
      final scoped = await engine.search(
        target,
        topK: 3,
        sourceIds: [refundId],
      );

      expect(all.chunks.first.content, target);
      expect(scoped.chunks.first.content, target);
      expect(all.chunks.first.similarity, closeTo(1.0, 1e-3));
      expect(scoped.chunks.first.similarity, closeTo(1.0, 1e-3));
      for (final chunk in scoped.chunks) {
        final same = all.chunks.where((c) => c.chunkId == chunk.chunkId);
        if (same.isEmpty) continue;
        expect(chunk.similarity, closeTo(same.single.similarity, 1e-3));
      }
      expect(scoped.chunks.every((c) => c.sourceId.toInt() == refundId), isTrue);
    });
  });

  group('B11 adjacent chunks keep relevance order', () {
    test('searchHybridWithContext: the best hit comes first and fits '
        'a one-chunk budget', () async {
      final budget = await _oneChunkBudget(refundId, target);
      final result = await engine.searchHybridWithContext(
        target,
        topK: 1,
        tokenBudget: budget,
        adjacentChunks: 1,
      );

      expect(result.context.includedChunks.map((c) => c.content), [target]);
    });

    test('searchHybridWithContext: hits come before their neighbors in '
        'included chunks and in LLM JSON', () async {
      final result = await engine.searchHybridWithContext(
        target,
        topK: 1,
        tokenBudget: 4000,
        adjacentChunks: 1,
      );

      final included = result.context.includedChunks;
      expect(included.first.content, target);
      expect(included.map((c) => c.content).toSet(), _refund.toSet());
      final json = result.toLlmJson();
      final first = (json['results'] as List).first as Map;
      expect(first['text'], target);
      expect(first['score'], 1.0);
    });

    test('search (vector): the best hit comes first and fits a one-chunk '
        'budget', () async {
      final budget = await _oneChunkBudget(refundId, target);
      final result = await engine.search(
        target,
        topK: 1,
        tokenBudget: budget,
        adjacentChunks: 1,
      );

      expect(result.chunks.first.content, target);
      expect(result.context.includedChunks.map((c) => c.content), [target]);
    });

    test('several hits: every hit comes before any neighbor', () async {
      final result = await engine.searchHybridWithContext(
        target,
        topK: 2,
        tokenBudget: 4000,
        adjacentChunks: 1,
        vectorWeight: 1.0,
        bm25Weight: 0.0,
      );
      final hits = await engine.searchHybrid(
        target,
        topK: 2,
        vectorWeight: 1.0,
        bm25Weight: 0.0,
      );

      final included = result.context.includedChunks;
      expect(
        included.take(2).map((c) => c.chunkId),
        hits.map((h) => h.docId),
      );
      expect(included.skip(2).every((c) => c.similarity == 0.0), isTrue);
    });

    test('chronological still orders by source and chunk index', () async {
      final result = await engine.searchHybridWithContext(
        target,
        topK: 1,
        tokenBudget: 4000,
        adjacentChunks: 1,
        strategy: ContextStrategy.chronological,
      );

      expect(result.context.includedChunks.map((c) => c.content), _refund);
      expect(manualId, lessThan(refundId));
    });
  });
}
