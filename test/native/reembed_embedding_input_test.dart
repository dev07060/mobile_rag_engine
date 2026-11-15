// Q3 B2 (docs/milestones.md): `reembedAll` must embed the same text that
// ingestion embedded. For markdown chunks that is the "Header Path: ..." line
// followed by the chunk, not the chunk alone. Embeddings come from a fake
// worker whose vector is a hash of the input text, so a chunk is its own
// exact match (similarity 1.0) only when it was embedded from the same text.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/services/rag_engine.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

import '../support/fake_embedding_workers.dart';
import 'native_test_support.dart';

/// Korean, Japanese, Chinese, NFD Hangul, full-width, emoji and decimals
/// (Q0 test text rule).
const _guide =
    '# 사용 설명서\n\n'
    '## 설치 インストール\n\n'
    '환불은 구매 후 14일 이내에 가능합니다. 東京は大きい。北京是中国的首都。\n'
    '한글 ＲＡＧ 🚀 버전 3.14.\n\n'
    '## 문제 해결\n\n'
    '앱을 다시 시작하세요. 가격 ３,５００원.\n';

const _wordLevelTokenizerJson =
    '{"version":"1.0","truncation":null,"padding":null,"added_tokens":[],'
    '"normalizer":null,"pre_tokenizer":{"type":"Whitespace"},'
    '"post_processor":null,"decoder":null,'
    '"model":{"type":"WordLevel","vocab":{"[UNK]":0},"unk_token":"[UNK]"}}';

const _modelA = 'model-a.onnx|384|f32|sha256:aaaa+vabq:none';
const _modelB = 'model-b.onnx|384|f32|sha256:bbbb+vabq:none';

Future<RagEngine> _engine(String dbPath, String fingerprint) =>
    RagEngine.initializeForTest(
      dbPath: dbPath,
      embeddingDimension: fakeEmbeddingDimension,
      embeddingFingerprint: fingerprint,
    );

/// Cosine similarity of each chunk to a query made of its own embedding
/// input. Vector search without `sourceIds` reports cosine similarity (with
/// `sourceIds` it is a fused rank score).
Future<Map<String, double>> _selfSimilarities(RagEngine engine) async {
  final all = await engine.search('설치', topK: 50);
  final out = <String, double>{};
  for (final chunk in all.chunks) {
    final input = renderContextText(
      content: chunk.content,
      chunkType: chunk.chunkType,
    );
    final hits = await engine.search(input, topK: 50);
    out[input] = hits.chunks
        .firstWhere((hit) => hit.chunkId == chunk.chunkId)
        .similarity;
  }
  return out;
}

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(() async {
    if (!RustLib.instance.initialized) await RustLib.init();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mobile_rag_q3_reembed_');
    dbPath = '${dir.path}/q3.sqlite';
    // Search assembles context with the tokenizer: a word-level one that
    // maps every word to [UNK] is enough here.
    final tokenizer = File('${dir.path}/tokenizer.json');
    await tokenizer.writeAsString(_wordLevelTokenizerJson);
    await initTokenizer(tokenizerPath: tokenizer.path);
  });

  tearDown(() async {
    await RagEngine.dispose();
    await releaseNativeFilesAndDelete(dir);
  });

  test('reembedAll embeds markdown chunks with their header path, as '
      'ingestion does', () async {
    await EmbeddingService.startWorkerForTest(answeringWorker);
    var engine = await _engine(dbPath, _modelA);
    final added = await engine.addDocument(
      _guide,
      name: 'guide.md',
      strategy: ChunkingStrategy.markdown,
    );
    expect(added.chunkCount, greaterThan(1));

    final before = await _selfSimilarities(engine);
    expect(
      before.keys.where((input) => input.startsWith('Header Path: ')),
      isNotEmpty,
    );
    for (final entry in before.entries) {
      expect(entry.value, closeTo(1.0, 1e-4), reason: entry.key);
    }

    await RagEngine.dispose();
    await EmbeddingService.startWorkerForTest(answeringWorker);
    engine = await _engine(dbPath, _modelB);
    expect(engine.embeddingFingerprintLock, isNotNull);
    await engine.reembedAll();
    expect(engine.embeddingFingerprintLock, isNull);

    final after = await _selfSimilarities(engine);
    expect(after.keys, unorderedEquals(before.keys));
    for (final entry in after.entries) {
      expect(entry.value, closeTo(1.0, 1e-4), reason: entry.key);
    }
  });

  // Q3: `.MD` and `.Markdown` are markdown files too. The file path ingest
  // already ignored case; `addDocument(filePath:)` did not.
  for (final fileName in ['GUIDE.MD', 'guide.Markdown', 'guide.md']) {
    test('addDocument(filePath: "$fileName") uses markdown chunking', () async {
      await EmbeddingService.startWorkerForTest(answeringWorker);
      final engine = await _engine(dbPath, _modelA);
      final added = await engine.addDocument(
        _guide,
        filePath: '${dir.path}/$fileName',
      );
      expect(added.chunkCount, greaterThan(1));
      final chunks = await engine.search('설치', topK: 50);
      expect(
        chunks.chunks.map((c) => c.chunkType),
        contains(startsWith('text|사용 설명서 > 설치 インストール')),
      );
    });
  }
}
