import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:mobile_rag_engine/services/context_builder.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/error.dart';
import 'package:mobile_rag_engine/src/internal/high_level_hybrid_transition.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

import '../support/high_level_hybrid_legacy_oracle.dart';

frb.Int64List _toInt64List(List<int> values) {
  final result = frb.Int64List(values.length);
  for (var i = 0; i < values.length; i++) {
    result[i] = values[i];
  }
  return result;
}

Future<Directory> _initTempDb(String name) async {
  final dir = await Directory.systemTemp.createTemp('mobile_rag_engine_');
  final dbPath = '${dir.path}/$name.sqlite';
  await initDbPool(dbPath: dbPath, maxSize: 4);
  await initSourceDb();
  return dir;
}

Future<void> _seedCollection(String collectionId) async {
  final guide = await addSourceInCollection(
    collectionId: collectionId,
    content: 'Install the package.\nVerify the checksum.',
    metadata: '{"source":"guide"}',
    name: 'guide',
  );
  await updateSourceStatus(sourceId: guide.sourceId, status: 'completed');
  await addChunks(
    sourceId: guide.sourceId,
    chunks: [
      ChunkData(
        content: 'Install the package.',
        chunkIndex: 0,
        startPos: 0,
        endPos: 20,
        chunkType: 'text|Guide > Setup',
        embedding: Float32List.fromList([1.0, 0.0, 0.0, 0.0]),
      ),
      ChunkData(
        content: 'Verify the checksum.',
        chunkIndex: 1,
        startPos: 21,
        endPos: 41,
        chunkType: 'text|Guide > Setup',
        embedding: Float32List.fromList([0.95, 0.0, 0.0, 0.0]),
      ),
    ],
  );

  final smoke = await addSourceInCollection(
    collectionId: collectionId,
    content: 'Run the smoke test.',
    name: 'smoke',
  );
  await updateSourceStatus(sourceId: smoke.sourceId, status: 'completed');
  await addChunks(
    sourceId: smoke.sourceId,
    chunks: [
      ChunkData(
        content: 'Run the smoke test.',
        chunkIndex: 0,
        startPos: 0,
        endPos: 19,
        chunkType: 'general',
        embedding: Float32List.fromList([0.6, 0.0, 0.0, 0.0]),
      ),
    ],
  );

  await rebuildChunkHnswIndexForCollection(collectionId: collectionId);
  await rebuildChunkBm25IndexForCollection(collectionId: collectionId);
}

void main() {
  setUpAll(() async {
    if (Platform.isMacOS) {
      await RustLib.init(
        externalLibrary: frb.ExternalLibrary.process(
          iKnowHowToUseIt: true,
        ),
      );
    } else {
      await RustLib.init();
    }
  });

  tearDown(() async {
    try {
      await closeDbPool();
    } catch (_) {}
  });

  test('low-level search lane hydrates batches and assembles context',
      () async {
    final dir = await _initTempDb('low_level_lane_hydrate');
    addTearDown(() async {
      await dir.delete(recursive: true);
    });

    const collectionId = 'dart-low-level-lane';
    await _seedCollection(collectionId);

    final handle = await searchMetaHybrid(
      collectionId: collectionId,
      queryText: 'install',
      queryEmbedding: [1.0, 0.0, 0.0, 0.0],
      options: const SearchMetaHybridOptions(
        topK: 2,
        vectorWeight: 1.0,
        bm25Weight: 0.0,
        adjacentChunks: 0,
      ),
    );
    addTearDown(() async {
      await handle.dispose();
    });

    final hits = await handle.hitMeta();
    expect(hits, hasLength(2));
    expect(
      hits.any(
        (hit) =>
            hit.rawType == 'text' && hit.headerPathPreview == 'Guide > Setup',
      ),
      isTrue,
    );

    final chunkIds = _toInt64List(hits.map((hit) => hit.chunkId).toList());
    final hydrated = await handle.hydrateChunks(chunkIds: chunkIds);
    expect(hydrated, hasLength(2));
    final guideHit = hits.firstWhere((hit) => hit.rawType == 'text');
    final hydratedById = {
      for (final chunk in hydrated) chunk.chunkId: chunk,
    };
    expect(
      hydratedById[guideHit.chunkId]?.content,
      'Install the package.',
    );
    expect(
      hydratedById[guideHit.chunkId]?.metadata,
      '{"source":"guide"}',
    );

    final excerpts = await handle.getChunkExcerpts(
      chunkIds: chunkIds,
      maxBytes: 10,
    );
    expect(excerpts, hasLength(2));
    final excerptById = {
      for (final excerpt in excerpts) excerpt.chunkId: excerpt,
    };
    expect(excerptById[guideHit.chunkId]?.excerpt, 'Install th');
  });

  test('stale search handle is rejected after collection mutation', () async {
    final dir = await _initTempDb('low_level_lane_stale');
    addTearDown(() async {
      await dir.delete(recursive: true);
    });

    const collectionId = 'dart-low-level-stale';
    await _seedCollection(collectionId);

    final handle = await searchMetaHybrid(
      collectionId: collectionId,
      queryText: 'install',
      queryEmbedding: [1.0, 0.0, 0.0, 0.0],
      options: const SearchMetaHybridOptions(
        topK: 2,
        vectorWeight: 1.0,
        bm25Weight: 0.0,
        adjacentChunks: 0,
      ),
    );
    addTearDown(() async {
      await handle.dispose();
    });

    await addSourceInCollection(
      collectionId: collectionId,
      content: 'mutation',
      name: 'mutation',
    );

    try {
      await handle.hitMeta();
      fail('expected stale handle error');
    } on RagError catch (e) {
      expect(e, isA<RagError_StaleSearchHandle>());
    }
  });

  test('low-level full assembly matches legacy parity oracle', () async {
    final dir = await _initTempDb('low_level_lane_parity');
    addTearDown(() async {
      await dir.delete(recursive: true);
    });

    const collectionId = 'dart-low-level-parity';
    await _seedCollection(collectionId);

    final lowLevelSnapshot = await buildLowLevelHybridParitySnapshot(
      collectionId: collectionId,
      queryText: 'install',
      queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
      topK: 2,
      tokenBudget: 32,
      vectorWeight: 1.0,
      bm25Weight: 0.0,
      adjacentChunks: 1,
      strategy: ContextStrategy.relevanceFirst,
    );
    final legacySnapshot = await buildLegacyHybridParitySnapshot(
      collectionId: collectionId,
      queryText: 'install',
      queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
      topK: 2,
      tokenBudget: 32,
      vectorWeight: 1.0,
      bm25Weight: 0.0,
      adjacentChunks: 1,
      strategy: ContextStrategy.relevanceFirst,
    );

    final report = compareHybridSearchParity(
      expected: legacySnapshot,
      actual: lowLevelSnapshot,
    );

    expect(report.isMatch, isTrue, reason: report.describe());
  });
}
