// Phase B of the upgrade harness, run against the PR head in the same app
// (same data container) that phase A left behind. Each check prints an
// H1_CHECK line that run.sh compares with the known-failing list.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
// Counts tokens with the engine's loaded tokenizer.
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/tokenizer.dart' show countTokens;

import 'h1_common.dart';

/// Passage budget for the contract tool. Five corpus chunks overflow it.
const contractTokenBudget = 300;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phase B $scenario', (tester) async {
    final passed = switch (scenario) {
      'p0' => await _dataContainerKept(),
      's1' => await _sameModel(),
      's2' => await _preparedFileSwapped(),
      's3' => await _legacyAssetSwapped(),
      's4' => await _modelPackSwapped(),
      'contract' => await _toolContract(),
      'r1' => await _clearAndRestartThenReAdd(),
      'c1' => await _searchAfterCollectionSwitch(),
      't1' => await _textIndexedByRelease(),
      _ => fail('Unknown phase B scenario "$scenario"'),
    };
    expect(passed, isTrue, reason: 'see the H1_CHECK lines above');
  });
}

Future<Map<String, Object?>> _phaseA(String id) async =>
    jsonDecode(await (await phaseAMarker(id)).readAsString())
        as Map<String, Object?>;

Future<bool> _dataContainerKept() async {
  final missing = [
    for (final id in ['s1', 's2', 's3', 's4', 'r1', 'c1', 't1'])
      if (!await (await phaseAMarker(id)).exists()) id,
  ];
  return report(
    'p0',
    missing.isEmpty,
    missing.isEmpty
        ? 'phase A files found in ${(await documentsDirectory()).path}'
        : 'phase A files missing for $missing: the data container was reset',
  );
}

/// Phase A indexed with MiniLM; phase B loads the same Model Pack.
Future<bool> _sameModel() async {
  final before = await _phaseA('s1');
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset(miniLmPack),
    databaseName: databaseName('s1'),
  );
  final rag = MobileRag.instance;
  final lock = rag.embeddingFingerprintLock;
  final fingerprint = (await rag.migrationState).embeddingFingerprint;
  final chunks = (await rag.getStats()).chunkCount.toInt();
  final result = lock == null
      ? await rag.search('What does hot reload do?', tokenBudget: 500)
      : null;
  final found =
      result?.chunks.any((c) => c.content.contains('Hot reload')) ?? false;
  await MobileRag.dispose();
  // 0.22.x stored no model identity, so the upgrade appends it; 0.23.0
  // already stored it, so it stays as it is.
  final fingerprintKept = baseStoresModelIdentity
      ? fingerprint == before['fingerprint']
      : fingerprint.startsWith('${before['fingerprint']}|');
  return report(
    's1',
    lock == null && fingerprintKept && chunks == before['chunks'] && found,
    'lock=${lock != null} stored_before=${before['fingerprint']} '
        'stored_after=$fingerprint chunks ${before['chunks']}->$chunks '
        'search_found=$found',
  );
}

/// The app replaces the `model.onnx` it manages with KoEn while upgrading.
Future<bool> _preparedFileSwapped() async {
  final before = await _phaseA('s2');
  final prepared = await preparedDirectory();
  final model = File('${prepared.path}/model.onnx');
  final tokenizer = File('${prepared.path}/tokenizer.json');
  await copyAsset(koEnModel, model);
  await copyAsset(koEnTokenizer, tokenizer);
  final engine = await RagEngine.initialize(
    config: RagConfig.fromPreparedFiles(
      tokenizerPath: tokenizer.path,
      modelPath: model.path,
      expectedEmbeddingDimension: 384,
      databaseName: databaseName('s2'),
    ),
  );
  final passed = await _expectLock('s2', before, engine);
  await RagEngine.dispose();
  return passed;
}

/// The app points `modelAsset`/`tokenizerAsset` at KoEn while upgrading.
/// Both copies land on the same `model.onnx`/`tokenizer.json` paths.
Future<bool> _legacyAssetSwapped() async {
  final before = await _phaseA('s3');
  await MobileRag.initialize(
    tokenizerAsset: koEnTokenizer,
    modelAsset: koEnModel,
    databaseName: databaseName('s3'),
  );
  final passed = await _expectLock('s3', before, MobileRag.instance.engine);
  await MobileRag.dispose();
  return passed;
}

/// The app ships a KoEn Model Pack instead of MiniLM while upgrading.
Future<bool> _modelPackSwapped() async {
  final before = await _phaseA('s4');
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset(koEnPack),
    databaseName: databaseName('s4'),
  );
  final passed = await _expectLock('s4', before, MobileRag.instance.engine);
  await MobileRag.dispose();
  return passed;
}

/// Vectors from MiniLM must not be searched with KoEn queries.
Future<bool> _expectLock(
  String id,
  Map<String, Object?> before,
  RagEngine engine,
) async {
  final lock = engine.embeddingFingerprintLock;
  final fingerprint = (await engine.migrationState).embeddingFingerprint;
  return report(
    id,
    lock != null,
    lock != null
        ? 'locked: stored=${lock.stored} current=${lock.current} '
              'remaining=${lock.remainingChunks}'
        : 'NOT locked: MiniLM vectors are now searched with KoEn. '
              'stored_before=${before['fingerprint']} '
              'stored_after=$fingerprint',
  );
}

/// Q2 r1: the documented way out of a model swap. The KoEn pack locks a
/// MiniLM database; `clearAndRestart()` drops the embeddings and keeps the
/// sources, and adding the same documents again must index them. Before S1
/// (#134) the re-add returned "Source ingestion already in progress" with no
/// chunks.
Future<bool> _clearAndRestartThenReAdd() async {
  final before = await _phaseA('r1');
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset(koEnPack),
    databaseName: databaseName('r1'),
  );
  final rag = MobileRag.instance;
  final locked = rag.embeddingFingerprintLock != null;
  if (locked) {
    await rag.clearAndRestart(
      confirm: ClearAndRestartConfirmation
          .iUnderstandThisDeletesAllOnDeviceEmbeddings,
    );
  }
  final cleared = (await rag.getStats()).chunkCount.toInt();
  final added = <String, int>{};
  for (final MapEntry(key: name, value: text) in corpus.entries) {
    added[name] = (await rag.addDocument(text, name: name)).chunkCount;
  }
  final stats = await rag.getStats();
  final result = await rag.search('What does hot reload do?', topK: 3);
  final found = result.chunks.any((c) => c.content.contains('Hot reload'));
  await MobileRag.dispose();
  final empty = [
    for (final MapEntry(key: name, value: count) in added.entries)
      if (count == 0) name,
  ];
  return report(
    'r1',
    locked &&
        cleared == 0 &&
        empty.isEmpty &&
        stats.sourceCount.toInt() == corpus.length &&
        found,
    'locked=$locked chunks before=${before['chunks']} after_clear=$cleared '
        'readded=${added.values.fold(0, (a, b) => a + b)} '
        'sources=${stats.sourceCount} no_chunks=$empty search_found=$found',
  );
}

/// Q2 c1 (A4): hybrid search in one collection maps that collection's HNSW
/// file. A plain `search()` in another collection then has to search its
/// own vectors. Before Q2 it searched the mapped graph of the first one, and
/// the collection filter dropped every hit.
Future<bool> _searchAfterCollectionSwitch() async {
  final before = await _phaseA('c1');
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset(miniLmPack),
    databaseName: databaseName('c1'),
  );
  final rag = MobileRag.instance;
  final docs = rag.inCollection(docsCollection);
  final notes = rag.inCollection(notesCollection);
  final notesChunks = (await notes.getStats()).chunkCount.toInt();
  final hybrid = await docs.searchHybrid('What does hot reload do?', topK: 3);
  final result = await notes.search(
    'How does a tokenizer split text into subword units?',
    topK: 3,
  );
  final back = await docs.search('What does hot reload do?', topK: 3);
  await MobileRag.dispose();
  final found = result.chunks.any((c) => c.content.contains('subword units'));
  final foundBack = back.chunks.any((c) => c.content.contains('Hot reload'));
  return report(
    'c1',
    hybrid.isNotEmpty && found && foundBack,
    'chunks before=${before['chunks']} notes=$notesChunks '
        'docs_hybrid=${hybrid.length} notes_search=${result.chunks.length} '
        'notes_found=$found docs_search_after=${back.chunks.length} '
        'docs_found=$foundBack',
  );
}

/// Q3 t1 (B8, B9): the release indexed a decomposed (NFD) Korean document.
/// The BM25 index is rebuilt from the stored chunks when the engine starts,
/// so keyword search uses the new tokenizer with no migration: "RAG" finds
/// "RAG는", "앱" finds "앱을", and NFC "환불" finds the NFD text. Adding the
/// document again, in NFD or NFC, is a duplicate of the release's row, whose
/// dedup hash was taken from the raw NFD text.
Future<bool> _textIndexedByRelease() async {
  final before = await _phaseA('t1');
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset(miniLmPack),
    databaseName: databaseName('t1'),
  );
  final rag = MobileRag.instance;
  final found = <String, bool>{};
  for (final query in ['RAG', '앱', '환불', '2024']) {
    final hits = await rag.searchHybrid(query, topK: 5);
    found[query] = hits.any((h) => h.bm25Rank > 0 && h.content.contains('東京'));
  }
  final nfd = await rag.addDocument(
    toNfdHangul(t1KoreanText),
    name: t1KoreanName,
  );
  final nfc = await rag.addDocument(t1KoreanText, name: t1KoreanName);
  final sources = (await rag.getStats()).sourceCount.toInt();
  await MobileRag.dispose();
  final release = {
    for (final query in found.keys) query: before['bm25_$query'],
  };
  return report(
    't1',
    !found.containsValue(false) &&
        nfd.isDuplicate &&
        nfc.isDuplicate &&
        sources == before['sources'],
    'bm25_found=$found (release before upgrade: $release) '
        're-add nfd_duplicate=${nfd.isDuplicate} '
        'nfc_duplicate=${nfc.isDuplicate} '
        'sources ${before['sources']}->$sources',
  );
}

/// H1-b: properties of real tool output that a caller relies on.
Future<bool> _toolContract() async {
  final documents = await documentsDirectory();
  final database = databaseName('contract');
  for (final entry in documents.listSync()) {
    if (entry.uri.pathSegments.last.startsWith(database)) {
      entry.deleteSync(recursive: true);
    }
  }
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset(miniLmPack),
    databaseName: database,
  );
  final rag = MobileRag.instance;
  for (final MapEntry(key: name, value: text) in corpus.entries) {
    await rag.addDocument(text, name: name);
  }
  await rag.rebuildIndex();

  final tool = RagSearchTool.fromMobileRag(
    rag,
    tokenBudget: contractTokenBudget,
  );
  final first = await tool.callJson(
    jsonEncode({
      'query': 'How does hybrid search rank keyword and vector results?',
      'top_k': 5,
    }),
  );
  final second = await tool.callJson(
    jsonEncode({
      'query': 'How are quantized models run on mobile processors?',
      'top_k': 5,
    }),
  );
  final tokens = countTokens(text: first);
  final q4 = await _q4OutputContract(rag);
  await MobileRag.dispose();
  print('H1_TOOL_OUTPUT first=$first');
  print('H1_TOOL_OUTPUT second=$second');

  final firstJson = jsonDecode(first) as Map<String, Object?>;
  final secondJson = jsonDecode(second) as Map<String, Object?>;
  final results = _results(firstJson);
  final context = firstJson['context'] as String? ?? '';
  var passed = true;

  // b1: the scores a model sees must keep the ranking.
  final scores = [for (final r in results.take(3)) r['score']];
  passed &= report(
    'b1',
    scores.length == 3 && scores.toSet().length == scores.length,
    'top-3 scores=$scores (need 3 distinct values)',
  );

  // b2: each passage body is sent once.
  final duplicated = [
    for (final r in results)
      if (_occurrences(context, r['text'] as String) +
              results.where((o) => o['text'] == r['text']).length >
          1)
        r['id'],
  ];
  passed &= report(
    'b2',
    results.isNotEmpty && duplicated.isEmpty,
    'results=${results.length} bodies sent more than once: ids $duplicated',
  );

  // b3: citation ids from two calls in one conversation do not collide.
  final firstIds = {for (final r in results) r['id']};
  final secondIds = {for (final r in _results(secondJson)) r['id']};
  final shared = firstIds.intersection(secondIds);
  passed &= report(
    'b3',
    firstIds.isNotEmpty && secondIds.isNotEmpty && shared.isEmpty,
    'call 1 ids=$firstIds call 2 ids=$secondIds shared=$shared',
  );

  // b4: the tool result costs about one passage budget, plus a small
  // allowance per result for ids and source fields.
  final limit = contractTokenBudget + 40 * results.length + 50;
  passed &= report(
    'b4',
    tokens <= limit,
    'output tokens=$tokens limit=$limit '
        '(budget $contractTokenBudget, ${results.length} results)',
  );
  return passed && q4;
}

/// Q4: a document long enough for several chunks, in Korean, Japanese and
/// Chinese with NFD Hangul, full-width text, emoji and decimals. Each
/// paragraph is about one subject, so a question finds one chunk in the
/// middle and its neighbors are different chunks.
const q4LongName = 'q4_manual.txt';
final q4LongText = [
  '설치 안내. 앱을 처음 실행하면 모델 파일을 기기에 복사합니다. 복사는 한 번만 '
          '하며 약 23MB를 씁니다. 東京のユーザーも同じ手順でインストールします。'
          '安装需要大约三十秒。 버전 3.14 이상에서 이 순서를 따릅니다. 🚀 ' *
      3,
  // NFD "환불" (decomposed Hangul, as some PDFs and macOS file names give it).
  '\u1112\u116a\u11ab\u1107\u116e\u11af 정책. 구매 후 14일 이내에는 전액을 '
          '돌려받을 수 있고, 30일까지는 ２.５달러 수수료를 뺀 금액을 돌려받습니다. '
          '返金は購入から14日以内なら全額です。退款在十四天内全额退还。 ' *
      3,
  '배터리 절약. 백그라운드 색인은 충전 중에만 돌고, 화면이 꺼져 있으면 스레드를 '
          '하나만 씁니다. バッテリーが少ないときは索引を止めます。电量低于百分之二十时暂停。 ' *
      3,
  '문제 해결. 검색 결과가 비어 있으면 rebuildIndex를 한 번 호출하세요. ＲＡＧ '
          '로그는 설정 화면에서 내보낼 수 있습니다. ログは設定から書き出せます。日志可以导出。 ' *
      3,
].join('\n\n');

const q4RefundQuestion = '구매 후 며칠 안에 환불을 받을 수 있나요?';

/// Q4 output contract on the real engine (Model Pack, ONNX, tokenizer).
/// b5: `search` gives cosine similarity with and without `sourceIds` (B10).
/// b6: adjacent chunks do not move the best hit out of a tight budget
/// (B11). b7: citations in full-width, lenticular, ideographic-comma and
/// range forms are read from an answer, and code is not (B12). b8:
/// `promptTokenCounter` budgets passages in the counter's tokens (B13).
Future<bool> _q4OutputContract(MobileRag rag) async {
  final added = await rag.addDocument(q4LongText, name: q4LongName);
  await rag.rebuildIndex();
  var passed = true;

  // b5: the same chunk has the same similarity with and without sourceIds,
  // and it is a cosine value, not a fused rank score (at most 1/61).
  final scoped = await rag.search(
    q4RefundQuestion,
    topK: 3,
    sourceIds: [added.sourceId],
  );
  final all = await rag.search(q4RefundQuestion, topK: 20);
  final allById = {for (final c in all.chunks) c.chunkId: c.similarity};
  final pairs = [
    for (final c in scoped.chunks)
      if (allById[c.chunkId] case final unscoped?) (c.similarity, unscoped),
  ];
  print(
    'H1_Q4 b5 scoped=${[for (final c in scoped.chunks) '${c.chunkId}:${c.similarity.toStringAsFixed(4)}']} '
    'unscoped=${[for (final c in all.chunks.take(5)) '${c.chunkId}:${c.similarity.toStringAsFixed(4)}']}',
  );
  passed &= report(
    'b5',
    scoped.chunks.isNotEmpty &&
        scoped.chunks.every((c) => c.sourceId.toInt() == added.sourceId) &&
        scoped.chunks.first.similarity > 2 / 61 &&
        pairs.isNotEmpty &&
        pairs.every((p) => (p.$1 - p.$2).abs() < 0.02),
    'scoped top=${scoped.chunks.isEmpty ? '-' : scoped.chunks.first.similarity} '
        'pairs (scoped, unscoped)=$pairs',
  );

  // b6: budget = the engine's own token count for the best hit alone.
  final alone = await rag.searchHybridWithContext(
    q4RefundQuestion,
    topK: 1,
    tokenBudget: 4000,
  );
  final best = alone.context.includedChunks.single;
  final tight = await rag.searchHybridWithContext(
    q4RefundQuestion,
    topK: 1,
    tokenBudget: alone.context.estimatedTokens,
    adjacentChunks: 1,
  );
  final wide = await rag.searchHybridWithContext(
    q4RefundQuestion,
    topK: 3,
    tokenBudget: 8000,
    adjacentChunks: 1,
  );
  final hits = await rag.searchHybrid(q4RefundQuestion, topK: 3);
  final wideIds = [for (final c in wide.context.includedChunks) c.chunkId];
  final hitIds = [for (final h in hits) h.docId];
  print(
    'H1_Q4 b6 chunks=${added.chunkCount} best=${best.chunkId} '
    'idx=${best.chunkIndex} tight=${[for (final c in tight.context.includedChunks) '${c.chunkId}@${c.chunkIndex}']} '
    'wide=${[for (final c in wide.context.includedChunks) '${c.chunkId}@${c.chunkIndex}:${c.similarity.toStringAsFixed(4)}']} '
    'hits=$hitIds',
  );
  passed &= report(
    'b6',
    added.chunkCount >= 3 &&
        tight.context.includedChunks
                .map((c) => c.chunkId)
                .toList()
                .toString() ==
            [best.chunkId].toString() &&
        wideIds.length > hitIds.length &&
        wideIds.take(hitIds.length).toList().toString() == hitIds.toString(),
    'chunks=${added.chunkCount} tight budget ${alone.context.estimatedTokens}: '
        'included=${[for (final c in tight.context.includedChunks) c.chunkId]} '
        'best=${best.chunkId}; wide=$wideIds hits first=$hitIds',
  );

  // b7: a canned answer over the real passages of `ask`.
  late String prompt;
  final answer = await rag.ask(
    q4RefundQuestion,
    topK: 3,
    tokenBudget: 8000,
    generate: (p) async {
      prompt = p;
      return '14일 이내 전액 환불［１］. 30일까지는 수수료 ２.５달러【2】. '
          '두 조건 모두 [1、2], 정리하면 [1-2]. 코드 예: `items[3]` 🚀';
    },
  );
  final cited = [for (final p in answer.citations) p.id];
  print(
    'H1_Q4 b7 passages=${answer.passages.length} cited=$cited '
    'prompt_tokens=${countTokens(text: prompt)}',
  );
  passed &= report(
    'b7',
    answer.passages.length >= 3 && cited.toString() == ['1', '2'].toString(),
    'passages=${answer.passages.length} cited=$cited (want [1, 2]; '
        '`items[3]` is code)',
  );

  // b8: with a counter (code points but spaces, standing in for an LLM
  // tokenizer), the budget counts passage texts in its units.
  int counter(String text) =>
      text.runes.where((r) => r != 0x20 && r != 0x0A).length;
  final full = await rag.prepareAsk(
    q4RefundQuestion,
    topK: 3,
    tokenBudget: 1000000,
    promptTokenCounter: counter,
  );
  final counts = [for (final p in full.passages) counter(p.text)];
  final engineTokens = [
    for (final p in full.passages) countTokens(text: p.text),
  ];
  final budget = counts.length < 2 ? 0 : counts[0] + counts[1] - 1;
  final fitted = await rag.prepareAsk(
    q4RefundQuestion,
    topK: 3,
    tokenBudget: budget,
    promptTokenCounter: counter,
  );
  print(
    'H1_Q4 b8 counter=$counts engine_tokens=$engineTokens budget=$budget '
    'fitted=${[for (final p in fitted.passages) p.chunkId]}',
  );
  passed &= report(
    'b8',
    full.passages.length >= 2 &&
        fitted.passages.length == 1 &&
        fitted.passages.single.chunkId == full.passages.first.chunkId,
    'counts=$counts budget=$budget '
        'fitted=${[for (final p in fitted.passages) p.chunkId]} '
        'want [${full.passages.isEmpty ? '-' : full.passages.first.chunkId}]',
  );
  return passed;
}

List<Map<String, Object?>> _results(Map<String, Object?> json) => [
  for (final r in json['results'] as List? ?? const [])
    r as Map<String, Object?>,
];

int _occurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  for (var i = haystack.indexOf(needle); i >= 0;) {
    count++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return count;
}
