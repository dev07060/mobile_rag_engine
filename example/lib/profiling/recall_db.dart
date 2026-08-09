import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'recall_math.dart';

/// Read every chunk's original f32 embedding for one collection straight from
/// the engine SQLite file (`chunks.embedding`). Opens read-only so the recall
/// profiler never writes to, or migrates, the engine database.
Map<int, Float32List> fetchChunkEmbeddingsF32({
  required String dbPath,
  required String collectionId,
}) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT id, embedding FROM chunks WHERE collection_id = ? ORDER BY id',
      [collectionId],
    );
    final out = <int, Float32List>{};
    for (final row in rows) {
      final id = row['id'] as int;
      final blob = row['embedding'] as Uint8List;
      final decoded = decodeF32Blob(blob);
      if (decoded != null) {
        out[id] = decoded;
      }
    }
    return out;
  } finally {
    db.dispose();
  }
}

/// Read test-fixture chunk identities without interpreting persisted vector
/// bytes. Production `chunks.embedding` is a Q8_0 or VABQ blob, so it must
/// never be used as the f32 ground-truth corpus for a quantization evaluation.
///
/// The profiler fixture creates one short chunk per source. If a future fixture
/// produces multiple chunks, the first chunk by `chunk_index` is retained and
/// the integration test's cardinality assertion fails closed.
Map<int, int> fetchChunkIdsBySource({
  required String dbPath,
  required String collectionId,
}) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT id, source_id FROM chunks '
      'WHERE collection_id = ? ORDER BY source_id, chunk_index, id',
      [collectionId],
    );
    final out = <int, int>{};
    for (final row in rows) {
      out.putIfAbsent(row['source_id'] as int, () => row['id'] as int);
    }
    return out;
  } finally {
    db.dispose();
  }
}
