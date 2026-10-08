import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/rag_engine.dart';

void main() {
  group('RagEngine.isDatabaseArtifact', () {
    bool owned(String name, {String db = 'rag.sqlite'}) =>
        RagEngine.isDatabaseArtifact(db, name);

    test('covers the database, its SQLite sidecars and the vector store', () {
      for (final name in [
        'rag.sqlite',
        'rag.sqlite-wal',
        'rag.sqlite-shm',
        'rag.sqlite-journal',
        'rag.vec',
      ]) {
        expect(owned(name), isTrue, reason: name);
      }
    });

    test('covers HNSW indexes of every collection, current and legacy', () {
      for (final name in [
        'rag_hnsw.hnsw',
        'rag_hnsw.hnsw.tmp',
        'rag_hnsw_0a1b2c3d.hnsw',
        'rag_hnsw_0a1b2c3d.hnsw.tmp',
        'rag_hnsw.hnsw.data',
        'rag_hnsw.hnsw.graph',
        'rag_hnsw_0a1b2c3d.hnsw.graph',
        'rag.hnsw.data',
        'rag.pbin',
        'rag_hnsw.pbin',
        'rag_hnsw',
        'rag',
      ]) {
        expect(owned(name), isTrue, reason: name);
      }
    });

    test('covers dirty markers of every collection', () {
      expect(owned('rag.dirty'), isTrue);
      expect(owned('rag.0a1b2c3d.dirty'), isTrue);
    });

    test('leaves unrelated files alone', () {
      for (final name in [
        'rag_notes.txt',
        'rag.sqlite.bak',
        'ragged.sqlite',
        'rag_hnsw_backup.hnsw',
        'rag_hnsw_0A1B2C3D.hnsw',
        'other.vec',
        'rag.json',
        'mobile_rag_model_packs',
      ]) {
        expect(owned(name), isFalse, reason: name);
      }
    });

    test('derives the vector store name like the native side', () {
      // Rust uses Path::with_extension("vec"), replacing any last extension.
      expect(owned('notes.vec', db: 'notes.custom'), isTrue);
      expect(owned('store.vec', db: 'store'), isTrue);
      expect(owned('notes.custom.vec', db: 'notes.custom'), isFalse);
    });
  });
}
