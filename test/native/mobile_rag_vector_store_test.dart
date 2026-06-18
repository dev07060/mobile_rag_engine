import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() {
  test('MobileRagVectorStore stores and searches precomputed embeddings',
      () async {
    final dir = await Directory.systemTemp.createTemp(
      'mobile_rag_vector_store_',
    );
    final store = MobileRagVectorStore(collectionId: 'test-vector-store');

    try {
      await store.initialize('${dir.path}/vector_store.sqlite');

      expect(store.isInitialized, isTrue);
      expect(store.enableHnsw, isTrue);

      await store.addDocument(
        id: 'doc-1',
        content: 'mobile_rag_engine provides retrieval for Flutter apps.',
        embedding: const [1, 0, 0],
        metadata: '{"kind":"probe"}',
      );

      final hits = await store.searchSimilar(
        queryEmbedding: const [1, 0, 0],
        topK: 3,
      );

      expect(hits, isNotEmpty);
      expect(hits.first.id, 'doc-1');
      expect(hits.first.content, contains('retrieval'));
      expect(hits.first.metadata, '{"kind":"probe"}');

      final stats = await store.getStats();
      expect(stats.documentCount, 1);
      expect(stats.vectorDimension, 3);

      await store.clear();
      final cleared = await store.getStats();
      expect(cleared.documentCount, 0);
      expect(cleared.vectorDimension, 0);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
