import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/error.dart';
import 'package:mobile_rag_engine/src/rust/api/migration_meta.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as source_rag;
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> _ensureRustLoaded() async {
  if (!RustLib.instance.initialized) {
    await RustLib.init();
  }
}

Future<Directory> _freshDir() =>
    Directory.systemTemp.createTemp('mobile_rag_fingerprint_gate_');

/// Insert a chunk row directly, bypassing the ingest pipeline.
///
/// The test needs control over the chunk's `embedding_fingerprint` tag and
/// the embedding bytes don't matter for the gate flow, so a raw INSERT keeps
/// the test focused on the migration_meta surface under exercise.
void _seedChunk({
  required Database db,
  required int sourceId,
  required int chunkIndex,
  required String content,
  required String fingerprint,
}) {
  final fakeEmbedding = Uint8List(4 * 8); // 8 floats, zeroed.
  db.execute(
    "INSERT INTO chunks (source_id, collection_id, chunk_index, content, "
    "start_pos, end_pos, chunk_type, embedding, embedding_fingerprint) "
    "VALUES (?, '__default__', ?, ?, 0, ?, 'general', ?, ?)",
    [sourceId, chunkIndex, content, content.length, fakeEmbedding, fingerprint],
  );
}

void _seedSource({required Database db, required int id, required String content}) {
  db.execute(
    "INSERT INTO sources (id, content, content_hash, status, collection_id) "
    "VALUES (?, ?, ?, 'completed', '__default__')",
    [id, content, 'hash-$id'],
  );
}

int _chunkCountInDb(String dbPath) {
  final db = sqlite3.open(dbPath);
  try {
    final result = db.select('SELECT COUNT(*) AS n FROM chunks');
    return result.first['n'] as int;
  } finally {
    db.dispose();
  }
}

void main() {
  setUpAll(() async {
    await _ensureRustLoaded();
  });

  tearDown(() async {
    await closeDbPool();
  });

  test(
    'model swap surfaces EmbeddingFingerprintGate.mismatch with remaining count',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/model_swap.sqlite';
        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();

        // Establish baseline fingerprint "modelA|384|f32" and tag chunks.
        await writeEmbeddingFingerprint(fingerprint: 'modelA|384|f32');
        final seed = sqlite3.open(dbPath);
        try {
          _seedSource(db: seed, id: 1, content: 'doc-1');
          _seedChunk(
            db: seed,
            sourceId: 1,
            chunkIndex: 0,
            content: 'chunk-1',
            fingerprint: 'modelA|384|f32',
          );
          _seedChunk(
            db: seed,
            sourceId: 1,
            chunkIndex: 1,
            content: 'chunk-2',
            fingerprint: 'modelA|384|f32',
          );
        } finally {
          seed.dispose();
        }

        final gate = await detectEmbeddingFingerprintGate(
          currentFingerprint: 'modelB|384|f32',
        );
        switch (gate) {
          case EmbeddingFingerprintGate_Mismatch(
              :final stored,
              :final current,
              :final remainingChunks,
              :final resumeInProgress,
            ):
            expect(stored, 'modelA|384|f32');
            expect(current, 'modelB|384|f32');
            expect(remainingChunks, 2);
            expect(resumeInProgress, isFalse,
                reason: 'no reembed has been started yet');
          default:
            fail('Expected Mismatch, got $gate');
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'reembed resumes across simulated app restart and finalize commits',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/resume.sqlite';
        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();
        await writeEmbeddingFingerprint(fingerprint: 'old');

        final seed = sqlite3.open(dbPath);
        try {
          _seedSource(db: seed, id: 1, content: 'doc-1');
          for (var i = 0; i < 4; i++) {
            _seedChunk(
              db: seed,
              sourceId: 1,
              chunkIndex: i,
              content: 'chunk-$i',
              fingerprint: 'old',
            );
          }
        } finally {
          seed.dispose();
        }

        // Start the reembed and finish half of the chunks.
        final remainingAtStart = await beginEmbeddingReembed(
          targetFingerprint: 'new',
        );
        expect(remainingAtStart, 4);
        final firstBatch = await source_rag.listChunksNeedingReembed(
          targetFingerprint: 'new',
          limit: 2,
        );
        expect(firstBatch.length, 2);
        for (final chunk in firstBatch) {
          await source_rag.updateChunkReembedded(
            chunkId: chunk.chunkId,
            embedding: Float32List.fromList(List<double>.filled(4, 0.1)),
            targetFingerprint: 'new',
          );
        }
        expect(
          await countChunksNeedingReembed(targetFingerprint: 'new'),
          2,
          reason: 'half-done state must persist',
        );

        // Simulate an app restart — close the pool, re-open the same file.
        await closeDbPool();
        await initDbPool(dbPath: dbPath, maxSize: 2);

        // Gate detection should now signal resume_in_progress = true.
        final gate = await detectEmbeddingFingerprintGate(
          currentFingerprint: 'new',
        );
        switch (gate) {
          case EmbeddingFingerprintGate_Mismatch(
              :final remainingChunks,
              :final resumeInProgress,
            ):
            expect(remainingChunks, 2);
            expect(resumeInProgress, isTrue,
                reason: 'pending axis still records the in-flight target');
          default:
            fail('Expected Mismatch with resume, got $gate');
        }

        // Resume — finalize once every chunk is tagged.
        final secondBatch = await source_rag.listChunksNeedingReembed(
          targetFingerprint: 'new',
          limit: 10,
        );
        expect(secondBatch.length, 2);
        for (final chunk in secondBatch) {
          await source_rag.updateChunkReembedded(
            chunkId: chunk.chunkId,
            embedding: Float32List.fromList(List<double>.filled(4, 0.2)),
            targetFingerprint: 'new',
          );
        }

        await finalizeEmbeddingReembed(targetFingerprint: 'new');

        final axes = await readMigrationAxes();
        expect(axes.embeddingFingerprint, 'new');
        expect(axes.embeddingFingerprintPending, '',
            reason: 'pending must clear on finalize');

        final closedGate = await detectEmbeddingFingerprintGate(
          currentFingerprint: 'new',
        );
        expect(closedGate, isA<EmbeddingFingerprintGate_Ok>());
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'clearAndRestart refuses to delete embeddings without the confirmation token',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/clear_guard.sqlite';
        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();
        await writeEmbeddingFingerprint(fingerprint: 'old');

        final seed = sqlite3.open(dbPath);
        try {
          _seedSource(db: seed, id: 1, content: 'doc-1');
          _seedChunk(
            db: seed,
            sourceId: 1,
            chunkIndex: 0,
            content: 'keep-me',
            fingerprint: 'old',
          );
        } finally {
          seed.dispose();
        }

        await expectLater(
          acknowledgeAndClearEmbeddings(
            confirmation: 'totally not the token',
            newFingerprint: 'new',
          ),
          throwsA(
            isA<RagError_InvalidInput>().having(
              (e) => e.field0,
              'message',
              contains('confirmation'),
            ),
          ),
        );

        expect(_chunkCountInDb(dbPath), 1,
            reason: 'chunk must survive a refused clear');
        final axes = await readMigrationAxes();
        expect(axes.embeddingFingerprint, 'old',
            reason: 'axis must not rotate without consent');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'clearAndRestart with confirmation drops chunks and rotates the fingerprint',
    () async {
      final dir = await _freshDir();
      try {
        final dbPath = '${dir.path}/clear_apply.sqlite';
        await initDbPool(dbPath: dbPath, maxSize: 2);
        await source_rag.initSourceDb();
        await writeEmbeddingFingerprint(fingerprint: 'old');

        final seed = sqlite3.open(dbPath);
        try {
          _seedSource(db: seed, id: 1, content: 'doc-1');
          _seedSource(db: seed, id: 2, content: 'doc-2');
          _seedChunk(
            db: seed,
            sourceId: 1,
            chunkIndex: 0,
            content: 'c1',
            fingerprint: 'old',
          );
          _seedChunk(
            db: seed,
            sourceId: 2,
            chunkIndex: 0,
            content: 'c2',
            fingerprint: 'old',
          );
        } finally {
          seed.dispose();
        }

        final deleted = await acknowledgeAndClearEmbeddings(
          confirmation:
              'I_UNDERSTAND_THIS_DELETES_ALL_ON_DEVICE_EMBEDDINGS',
          newFingerprint: 'new',
        );
        expect(deleted, 2);
        expect(_chunkCountInDb(dbPath), 0);

        // Sources are intentionally preserved so the host app can re-ingest.
        final sourceCount = sqlite3.open(dbPath);
        try {
          final result =
              sourceCount.select('SELECT COUNT(*) AS n FROM sources');
          expect(result.first['n'], 2,
              reason: 'sources must survive clearAndRestart');
        } finally {
          sourceCount.dispose();
        }

        final axes = await readMigrationAxes();
        expect(axes.embeddingFingerprint, 'new');
        expect(axes.embeddingFingerprintPending, '');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
