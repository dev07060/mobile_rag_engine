// Real-engine checks for milestones S1 and W1 (docs/milestones.md):
//   A. a short document stored next to a large PDF is found by vector search;
//   B. after clearAndRestart() the same documents can be added again;
//   W1. `prepareAsk` with its default arguments (README example 3) puts the
//       short document among its five passages.
//
// Runs against real models, so it needs an app with these assets (paths can
// be changed with --dart-define):
//   S1_MODEL_PACK         assets/mobile_rag/model-pack.json
//                         (`dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en`)
//   S1_SECOND_MODEL_PACK  assets/koen/model-pack.json
//                         (KoEn-E5-Tiny, docs/guides/model_setup.md; phase swapB only)
//   S1_PDF_ASSET          assets/sample_data/sample_eng.pdf
//                         (example/assets/sample_data/sample_eng.pdf, 1820 chunks)
//
// Phases (--dart-define=S1_PHASE=...):
//   repro     short document + PDF in both orders, and six short documents
//   upgradeA  index a short document and the PDF, then exit. Run it with the
//             last published release so the files on disk come from it.
//   upgradeB  reopen the same database with this branch and search
//   swapA     index five documents with the first model
//   swapB     open them with the second model, clearAndRestart(), add the
//             same five documents again
//
// flutter test integration_test/short_document_recall_test.dart -d macos \
//   --dart-define=S1_PHASE=repro
//
// Every result line starts with "S1 " so a run can be grepped.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';

const _phase = String.fromEnvironment('S1_PHASE', defaultValue: 'repro');
const _modelPack = String.fromEnvironment(
  'S1_MODEL_PACK',
  defaultValue: 'assets/mobile_rag/model-pack.json',
);
const _secondModelPack = String.fromEnvironment(
  'S1_SECOND_MODEL_PACK',
  defaultValue: 'assets/koen/model-pack.json',
);
const _pdfAsset = String.fromEnvironment(
  'S1_PDF_ASSET',
  defaultValue: 'assets/sample_data/sample_eng.pdf',
);

const _refundDoc = 'Refunds are accepted within 14 days of purchase.';
const _refundQuery = 'How long is the refund period?';

/// Five short documents and, for each, a question and a phrase of its answer.
const _shortDocs = <String, (String, String, String)>{
  'refund.txt': (
    'Refunds are accepted within 14 days of purchase. Items must be unused '
        'and returned in the original packaging together with the receipt.',
    _refundQuery,
    '14 days',
  ),
  'shipping.txt': (
    'Standard shipping takes three to five business days. Express shipping '
        'arrives the next business day for orders placed before noon.',
    'How long does standard shipping take?',
    'three to five business days',
  ),
  'warranty.txt': (
    'The warranty covers manufacturing defects for two years from the date '
        'of delivery. Damage caused by water or drops is not covered.',
    'What does the warranty cover?',
    'manufacturing defects',
  ),
  'flutter.txt': (
    'Flutter is an open source UI toolkit from Google for building natively '
        'compiled applications for mobile, web and desktop from one codebase.',
    'What is Flutter?',
    'UI toolkit',
  ),
  'hnsw.txt': (
    'Hierarchical navigable small world graphs are an approximate nearest '
        'neighbor index used for vector search over embeddings.',
    'What is an HNSW graph used for?',
    'navigable small world',
  ),
};

// ignore: avoid_print
void _log(String line) => print('S1 $line');

Future<Directory> _dir() => getApplicationDocumentsDirectory();

Future<void> _wipe(String stem) async {
  await for (final entry in (await _dir()).list()) {
    if (entry is File && entry.uri.pathSegments.last.startsWith(stem)) {
      await entry.delete();
    }
  }
}

Future<String> _pdfPath() async {
  final data = await rootBundle.load(_pdfAsset);
  final file = File('${(await _dir()).path}/s1_sample_eng.pdf');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

/// Format version byte of each `<stem>*.hnsw` file (byte 4 of the header).
Future<String> _hnswVersions(String stem) async {
  final out = <String>[];
  await for (final entry in (await _dir()).list()) {
    final name = entry.uri.pathSegments.last;
    if (entry is File && name.startsWith(stem) && name.endsWith('.hnsw')) {
      final bytes = await entry.openRead(0, 5).expand((b) => b).toList();
      out.add('$name=v${bytes.length == 5 ? bytes[4] : '?'}');
    }
  }
  out.sort();
  return out.isEmpty ? 'none' : out.join(',');
}

Future<void> _open(String db, {String pack = _modelPack}) =>
    MobileRag.initialize(
      modelPack: RagModelPack.asset(pack),
      databaseName: '$db.sqlite',
    );

/// Rank of the first chunk containing [phrase] (top 50) in vector search,
/// hybrid search with the default weights, and hybrid search with equal
/// weights; -1 when it is missing.
Future<(int, int, int)> _ranks(
  String label,
  String query,
  String phrase,
) async {
  final rag = MobileRag.instance;
  final vector = await rag.search(query, topK: 50);
  final vectorRank = vector.chunks.indexWhere(
    (c) => c.content.contains(phrase),
  );
  final hybrid = await rag.searchHybrid(query, topK: 50);
  final hybridRank = hybrid.indexWhere((c) => c.content.contains(phrase));
  final equal = await rag.searchHybrid(
    query,
    topK: 50,
    vectorWeight: 0.5,
    bm25Weight: 0.5,
  );
  final equalRank = equal.indexWhere((c) => c.content.contains(phrase));
  final stats = await rag.getStats();
  final similarity = vectorRank >= 0
      ? 'sim=${vector.chunks[vectorRank].similarity.toStringAsFixed(4)}'
      : 'topSim=${vector.chunks.isEmpty ? '-' : vector.chunks.first.similarity.toStringAsFixed(4)}';
  _log(
    '$label chunks=${stats.chunkCount} "$query" vectorRank=$vectorRank '
    '$similarity hybridRank(0.2/0.8)=$hybridRank hybridRank(0.5/0.5)=$equalRank',
  );
  return (vectorRank, hybridRank, equalRank);
}

/// Vector search must find the chunk, and so must hybrid search with equal
/// weights (the vector candidate reaches the fusion step). The default
/// weights (vector 0.2, BM25 0.8) are checked through `prepareAsk` in
/// [_expectInAsk] (milestone W1).
Future<void> _expectFound(String label, String query, String phrase) async {
  final (vectorRank, _, equalRank) = await _ranks(label, query, phrase);
  expect(vectorRank, isNot(-1), reason: '$label: vector search missed it');
  expect(equalRank, isNot(-1), reason: '$label: hybrid (0.5/0.5) missed it');
}

/// Milestone W1: `prepareAsk` with its default arguments (topK 5, default
/// hybrid weights) is what README example 3 (`rag.ask`) sends to the LLM, so
/// the passage holding [phrase] must be among those five.
///
/// Also logs the chunk's vector and BM25 ranks in `searchHybrid(topK: 300)`;
/// a BM25 rank of 0 means the question shares no BM25 token with it
/// ("refund" vs "Refunds").
Future<void> _expectInAsk(String label, String query, String phrase) async {
  final rag = MobileRag.instance;
  final prepared = await rag.prepareAsk(query);
  final index = prepared.passages.indexWhere((p) => p.text.contains(phrase));
  // bm25Rank is 0 when the chunk matched no BM25 token of the question.
  final hybrid = await rag.searchHybrid(query, topK: 300);
  final hit = hybrid.where((c) => c.content.contains(phrase)).firstOrNull;
  final bm25Hits = hybrid.where((c) => c.bm25Rank > 0).length;
  String head(String text) => text.length > 30 ? text.substring(0, 30) : text;
  _log(
    '$label prepareAsk "$query" passage=$index of ${prepared.passages.length} '
    'chunk vectorRank=${hit?.vectorRank} bm25Rank=${hit?.bm25Rank} '
    'bm25Hits(top300)=$bm25Hits '
    'passages=${prepared.passages.map((p) => '"${head(p.text)}"').join(' | ')}',
  );
  // Collected and checked at the end of the phase so one run logs every case.
  if (index == -1) _askMisses.add(label);
}

final _askMisses = <String>[];

const _paraphraseQuery = 'How many days do I have to return an item?';

/// Milestone W1, known limit (logged, not checked): a question that shares no
/// word with the short document, so BM25 cannot help it. Also logs the
/// workaround in docs/guides/ask.md: the short document in its own
/// collection, asked separately.
Future<void> _paraphraseProbe(String pdf) async {
  await _wipe('s1_w1_paraphrase');
  await _open('s1_w1_paraphrase');
  final rag = MobileRag.instance;
  // Default collection: the sentence next to the PDF, as in the README.
  await rag.addDocument(_refundDoc);
  await rag.addDocumentFromFile(pdf);
  // Collection "faq": the same sentence on its own.
  await rag.inCollection('faq').addDocument(_refundDoc, name: 'refund.txt');
  int at(RagAskPrompt p) =>
      p.passages.indexWhere((x) => x.text.contains('14 days'));
  for (final query in [_refundQuery, _paraphraseQuery]) {
    final vector = await rag.search(query, topK: 50);
    final mixed = await rag.prepareAsk(query);
    final equal = await rag.prepareAsk(
      query,
      vectorWeight: 0.5,
      bm25Weight: 0.5,
    );
    final faq = await rag.inCollection('faq').prepareAsk(query);
    final vectorRank = vector.chunks.indexWhere(
      (c) => c.content.contains('14 days'),
    );
    _log(
      'W1 probe "$query" vectorRank=$vectorRank '
      'prepareAsk(default)=${at(mixed)} of ${mixed.passages.length} '
      'prepareAsk(0.5/0.5)=${at(equal)} of ${equal.passages.length} '
      'inCollection(faq).prepareAsk=${at(faq)} of ${faq.passages.length}',
    );
  }
  await MobileRag.dispose();
}

Future<void> _reproPhase() async {
  final pdf = await _pdfPath();

  // README order: the short document, then the PDF.
  await _wipe('s1_short_then_pdf');
  await _open('s1_short_then_pdf');
  await MobileRag.instance.addDocument(_refundDoc);
  await MobileRag.instance.addDocumentFromFile(pdf);
  await _expectFound('short->pdf', _refundQuery, '14 days');
  await _expectInAsk('short->pdf', _refundQuery, '14 days');
  await MobileRag.dispose();
  // Reopen: the index comes from the saved .hnsw file this time.
  await _open('s1_short_then_pdf');
  await _expectFound('short->pdf reopened', _refundQuery, '14 days');
  _log('short->pdf files ${await _hnswVersions('s1_short_then_pdf')}');
  await MobileRag.dispose();

  await _wipe('s1_pdf_then_short');
  await _open('s1_pdf_then_short');
  await MobileRag.instance.addDocumentFromFile(pdf);
  await MobileRag.instance.addDocument(_refundDoc);
  await _expectFound('pdf->short', _refundQuery, '14 days');
  await _expectInAsk('pdf->short', _refundQuery, '14 days');
  await MobileRag.dispose();

  // Six short documents next to the PDF; each must be found by its question.
  await _wipe('s1_six_short');
  await _open('s1_six_short');
  await MobileRag.instance.addDocument(_refundDoc);
  for (final entry in _shortDocs.entries) {
    await MobileRag.instance.addDocument(entry.value.$1, name: entry.key);
  }
  await MobileRag.instance.addDocumentFromFile(pdf);
  for (final entry in _shortDocs.entries) {
    await _expectFound(
      'six short+pdf ${entry.key}',
      entry.value.$2,
      entry.value.$3,
    );
    await _expectInAsk(
      'six short+pdf ${entry.key}',
      entry.value.$2,
      entry.value.$3,
    );
  }
  await MobileRag.dispose();
  await _paraphraseProbe(pdf);
  expect(
    _askMisses,
    isEmpty,
    reason: 'prepareAsk (topK 5, default weights) missed these passages',
  );
}

Future<void> _upgradeAPhase() async {
  await _wipe('s1_upgrade');
  await _open('s1_upgrade');
  await MobileRag.instance.addDocument(_refundDoc);
  await MobileRag.instance.addDocumentFromFile(await _pdfPath());
  // Logged, not asserted: this phase runs on the published release.
  await _ranks('upgradeA', _refundQuery, '14 days');
  await MobileRag.dispose();
  _log('upgradeA files ${await _hnswVersions('s1_upgrade')}');
}

Future<void> _upgradeBPhase() async {
  _log('upgradeB files before ${await _hnswVersions('s1_upgrade')}');
  await _open('s1_upgrade');
  final stats = await MobileRag.instance.getStats();
  _log(
    'upgradeB reopened sources=${stats.sourceCount} chunks=${stats.chunkCount}',
  );
  expect(stats.chunkCount, greaterThan(1000), reason: 'phase A data missing');
  await _expectFound('upgradeB first search', _refundQuery, '14 days');
  await MobileRag.dispose();
  final after = await _hnswVersions('s1_upgrade');
  _log('upgradeB files after $after');
  expect(after, isNot(contains('=v1')));
}

Future<void> _swapAPhase() async {
  await _wipe('s1_swap');
  await _open('s1_swap');
  for (final entry in _shortDocs.entries) {
    await MobileRag.instance.addDocument(entry.value.$1, name: entry.key);
  }
  final stats = await MobileRag.instance.getStats();
  _log(
    'swapA sources=${stats.sourceCount} chunks=${stats.chunkCount} '
    'fp=${MobileRag.instance.currentEmbeddingFingerprint}',
  );
  await MobileRag.dispose();
}

Future<void> _swapBPhase() async {
  await _open('s1_swap', pack: _secondModelPack);
  final rag = MobileRag.instance;
  _log(
    'swapB locked=${rag.isEmbeddingFingerprintLocked} '
    'remaining=${rag.embeddingFingerprintLock?.remainingChunks}',
  );
  expect(rag.isEmbeddingFingerprintLocked, isTrue);
  await rag.clearAndRestart(
    confirm:
        ClearAndRestartConfirmation.iUnderstandThisDeletesAllOnDeviceEmbeddings,
  );
  final cleared = await rag.getStats();
  _log(
    'swapB after clearAndRestart locked=${rag.isEmbeddingFingerprintLocked} '
    'sources=${cleared.sourceCount} chunks=${cleared.chunkCount}',
  );
  for (final entry in _shortDocs.entries) {
    final result = await rag.addDocument(entry.value.$1, name: entry.key);
    _log(
      'swapB re-add ${entry.key} isDuplicate=${result.isDuplicate} '
      'chunks=${result.chunkCount} sourceId=${result.sourceId} '
      'message=${result.message}',
    );
    // The kept source row is reused, so this is reported like a resumed
    // ingestion (isDuplicate: true) but with new chunks. Before S1 it came
    // back with 0 chunks and "Source ingestion already in progress".
    expect(result.chunkCount, greaterThan(0));
    expect(result.message, 'Source resumed and completed');
  }
  for (final entry in _shortDocs.entries) {
    final hits = await rag.search(entry.value.$2, topK: 3);
    final top = hits.chunks.isEmpty ? '' : hits.chunks.first.content;
    _log(
      'swapB "${entry.value.$2}" top="${top.length > 40 ? top.substring(0, 40) : top}"',
    );
    expect(top, contains(entry.value.$3));
  }
  final stats = await rag.getStats();
  _log('swapB done sources=${stats.sourceCount} chunks=${stats.chunkCount}');
  await MobileRag.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S1 $_phase', (tester) async {
    switch (_phase) {
      case 'repro':
        await _reproPhase();
      case 'upgradeA':
        await _upgradeAPhase();
      case 'upgradeB':
        await _upgradeBPhase();
      case 'swapA':
        await _swapAPhase();
      case 'swapB':
        await _swapBPhase();
      default:
        fail('unknown S1_PHASE "$_phase"');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
