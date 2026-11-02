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
    for (final id in ['s1', 's2', 's3', 's4'])
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
  return report(
    's1',
    lock == null &&
        fingerprint.startsWith('${before['fingerprint']}|') &&
        chunks == before['chunks'] &&
        found,
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
