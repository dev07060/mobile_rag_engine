import 'dart:io';

import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/hnsw_index.dart';

/// Releases every native handle on a test database, then deletes [dir].
///
/// Windows refuses to delete files that are still open or memory-mapped, so
/// close the DB pool (which also drops the mmap vector store) and unmap the
/// HNSW index before removing a test's temporary database directory.
Future<void> releaseNativeFilesAndDelete(Directory dir) async {
  await closeDbPool();
  await clearHnswIndex();
  await dir.delete(recursive: true);
}
