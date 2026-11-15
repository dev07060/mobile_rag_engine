// Q2 B5: an embed() that the worker never answers used to wait forever once
// the worker was disposed, so the ingest calling it never ended.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/embedding_service.dart';

import '../support/fake_embedding_workers.dart';

void main() {
  tearDown(EmbeddingService.disposeAsync);

  test('embed() fails when the worker is disposed before answering', () async {
    await EmbeddingService.startWorkerForTest(silentWorker);
    final pending = EmbeddingService.embed('환불은 14일 이내 東京 北京 ＲＡＧ 😀 3.14');
    final outcome = expectLater(
      pending.timeout(const Duration(seconds: 10)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('disposed'),
        ),
      ),
    );
    await EmbeddingService.disposeAsync();
    await outcome;
  });

  test(
    'embed() fails when a new worker replaces the one it waits for',
    () async {
      await EmbeddingService.startWorkerForTest(silentWorker);
      final pending = EmbeddingService.embed('가격은 ３,５００원');
      final outcome = expectLater(
        pending.timeout(const Duration(seconds: 10)),
        throwsA(isA<StateError>()),
      );
      await EmbeddingService.startWorkerForTest(answeringWorker);
      await outcome;
      expect(
        await EmbeddingService.embed('가격은 ３,５００원'),
        hasLength(fakeEmbeddingDimension),
      );
    },
  );

  test('answered embeds are unaffected', () async {
    await EmbeddingService.startWorkerForTest(answeringWorker);
    final vectors = await Future.wait([
      for (final text in ['東京は大きい。', '한', 'ＲＡＧ 😀 3.14'])
        EmbeddingService.embed(text),
    ]);
    expect(vectors.map((v) => v.length), everyElement(fakeEmbeddingDimension));
  });
}
