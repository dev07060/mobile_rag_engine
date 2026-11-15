// Q2 (docs/milestones.md): engine lifecycle bugs that only show once an app
// disposes, re-initializes or resets the engine in the same process.
// Embeddings come from a fake worker, so these run without ONNX.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/services/rag_engine.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

import '../support/fake_embedding_workers.dart';
import 'native_test_support.dart';

/// Korean, Japanese, Chinese, NFD Hangul, full-width, emoji and decimals
/// (Q0 test text rule).
const _mixedText =
    '환불은 구매 후 14일 이내에 가능합니다. 東京は大きい。大阪も大きい。'
    '北京是中国的首都。한국어 '
    'ＲＡＧ ガイド 🚀 버전 3.14 가격 ３,５００원.';

/// About 40 chunks at the default chunk size.
String _longDocument(String tag) =>
    List.generate(40, (i) => '[$tag 단락 $i] $_mixedText ' * 6).join('\n\n');

Future<RagEngine> _engine(String dbPath) => RagEngine.initializeForTest(
  dbPath: dbPath,
  embeddingDimension: fakeEmbeddingDimension,
);

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(() async {
    if (!RustLib.instance.initialized) await RustLib.init();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mobile_rag_q2_lifecycle_');
    dbPath = '${dir.path}/q2.sqlite';
  });

  tearDown(() async {
    await RagEngine.dispose();
    await releaseNativeFilesAndDelete(dir);
  });

  // B5: the ingest waited forever for an embedding the disposed worker never
  // sent. Its source stayed `processing`, and re-initializing in the same
  // process skips crash recovery, so the document could not be added again
  // until the app restarted.
  test('dispose during an ingest ends it, and the document can be re-added '
      'in the same process', () async {
    await EmbeddingService.startWorkerForTest(silentWorker);
    var engine = await _engine(dbPath);
    final ingest = engine.addDocument(_mixedText, name: 'refund.txt');
    final failed = expectLater(
      ingest.timeout(const Duration(seconds: 20)),
      throwsA(isA<StateError>()),
    );
    await pumpEventQueue(times: 50);
    await RagEngine.dispose().timeout(const Duration(seconds: 20));
    await failed;

    await EmbeddingService.startWorkerForTest(answeringWorker);
    engine = await _engine(dbPath);
    final again = await engine
        .addDocument(_mixedText, name: 'refund.txt')
        .timeout(const Duration(seconds: 20));
    expect(again.chunkCount, greaterThan(0), reason: again.message);
    expect((await engine.getStats()).chunkCount.toInt(), again.chunkCount);
  });

  // B6: the 500 ms auto-rebuild timer belongs to the instance and the static
  // dispose could not cancel it. It fired on a closed database and threw an
  // unhandled error (the test zone reports it).
  test('dispose cancels the pending automatic index rebuild', () async {
    await EmbeddingService.startWorkerForTest(answeringWorker);
    final engine = await _engine(dbPath);
    await engine.addDocument(_mixedText, name: 'mixed.txt');
    await RagEngine.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await expectLater(
      engine.addDocument('北京', name: 'late.txt'),
      throwsStateError,
    );
  });

  // B7: clearAllData waited only for the default collection's warmup. An
  // ingest in another collection kept running into the closed pool or the
  // recreated database.
  test('clearAllData waits for an ingest in another collection', () async {
    await EmbeddingService.startWorkerForTest(slowWorker);
    final engine = await _engine(dbPath);
    final started = Completer<void>();
    final ingest = engine.addDocument(
      _longDocument('other'),
      name: 'other.txt',
      collectionId: 'other',
      onProgress: (done, total) {
        if (!started.isCompleted) started.complete();
      },
    );
    await started.future.timeout(const Duration(seconds: 30));

    await engine.clearAllData().timeout(const Duration(seconds: 60));
    final added = await ingest.timeout(const Duration(seconds: 5));
    expect(added.chunkCount, greaterThan(1));

    final other = await engine.getStats(collectionId: 'other');
    expect(other.sourceCount.toInt(), 0);
    expect(other.chunkCount.toInt(), 0);
    expect((await engine.getStats()).chunkCount.toInt(), 0);
  });

  test(
    'a write that starts during clearAllData lands in the new database',
    () async {
      await EmbeddingService.startWorkerForTest(answeringWorker);
      final engine = await _engine(dbPath);
      await engine.addDocument('old 東京', name: 'old.txt', collectionId: 'b');

      final clearing = engine.clearAllData();
      final added = engine.addDocument(
        _mixedText,
        name: 'new.txt',
        collectionId: 'b',
      );
      await clearing;
      final result = await added;
      expect(result.isDuplicate, isFalse);
      final stats = await engine.getStats(collectionId: 'b');
      expect(stats.sourceCount.toInt(), 1);
      expect(stats.chunkCount.toInt(), result.chunkCount);
    },
  );
}
