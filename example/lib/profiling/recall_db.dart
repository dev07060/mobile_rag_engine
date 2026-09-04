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
