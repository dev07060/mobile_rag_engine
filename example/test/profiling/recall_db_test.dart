import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/recall_db.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('fetchChunkEmbeddingsF32 reads only target collection f32 blobs', () {
    final dir = Directory.systemTemp.createTempSync('recall_db_test');
    try {
      final path = '${dir.path}/test.sqlite';
      final db = sqlite3.open(path);
      db.execute('''
        CREATE TABLE chunks (
          id INTEGER PRIMARY KEY,
          source_id INTEGER NOT NULL,
          collection_id TEXT NOT NULL,
          chunk_index INTEGER NOT NULL,
          content TEXT NOT NULL,
          start_pos INTEGER NOT NULL,
          end_pos INTEGER NOT NULL,
          chunk_type TEXT,
          embedding BLOB NOT NULL,
          embedding_i8 BLOB,
          embedding_scale REAL
        );
      ''');

      Uint8List blob(List<double> values) =>
          Float32List.fromList(values).buffer.asUint8List();

      final stmt = db.prepare(
        'INSERT INTO chunks('
        'id, source_id, collection_id, chunk_index, content, start_pos, '
        'end_pos, embedding) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        stmt.execute([1, 1, 'A', 0, 'x', 0, 1, blob([1.0, 2.0])]);
        stmt.execute([2, 1, 'A', 1, 'y', 0, 1, blob([3.0, 4.0])]);
        stmt.execute([3, 9, 'B', 0, 'z', 0, 1, blob([9.0, 9.0])]);
      } finally {
        stmt.dispose();
        db.dispose();
      }

      final got = fetchChunkEmbeddingsF32(dbPath: path, collectionId: 'A');
      expect(got.keys.toSet(), {1, 2});
      expect(got[1], [1.0, 2.0]);
      expect(got[2], [3.0, 4.0]);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
