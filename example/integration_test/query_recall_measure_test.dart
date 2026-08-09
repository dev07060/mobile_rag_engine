import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/profiling/query_profiler.dart';
import 'package:mobile_rag_engine_example/profiling/recall_db.dart';
import 'package:mobile_rag_engine_example/profiling/recall_math.dart';
import 'package:mobile_rag_engine_example/profiling/recall_report.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine_example/profiling/vabq_measurement_config.dart';

const _docsPerCollection = int.fromEnvironment(
  'DOCS_PER_COLLECTION',
  defaultValue: 500,
);
const _vabqProfileWire = String.fromEnvironment(
  'VABQ_PROFILE',
  defaultValue: 'none',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'e2e hybrid recall@10: GT(f32) vs shipped i8-HNSW+BM25 RRF',
    () async {
      _assertProfileMode();
      final measurement = VabqMeasurementConfig.fromWire(
        profileWire: _vabqProfileWire,
        docsPerCollection: _docsPerCollection,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final dbName = 'recall_${measurement.profileWire}.sqlite';
      await _deleteDbFiles('${docsDir.path}/$dbName');

      await MobileRag.initialize(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
        vabqProfile: measurement.vabqProfile,
        databaseName: dbName,
        deferIndexWarmup: true,
      );
      await MobileRag.instance.warmupFuture;
      final seeded = await QueryFixture.seed(
        docsPerCollection: measurement.docsPerCollection,
      );
      expect(
        seeded[QueryFixture.collectionA],
        hasLength(measurement.docsPerCollection),
      );
      expect(
        seeded[QueryFixture.collectionB],
        hasLength(measurement.docsPerCollection),
      );

      const collection = QueryFixture.collectionA;
      final profiler = QueryProfiler(dbPath: MobileRag.instance.dbPath);
      await profiler.deleteOnDiskIndex(collection);
      await profiler.activateOnly(collection);

      // Production SQLite stores quantized Q8_0/VABQ blobs. It is only used
      // here to map the deterministic fixture source IDs to production chunk
      // IDs; f32 ground truth stays entirely in this test fixture.
      final chunkIdsBySource = fetchChunkIdsBySource(
        dbPath: MobileRag.instance.dbPath,
        collectionId: collection,
      );
      final sourceIds = seeded[collection]!;
      final docs = QueryFixture.docs(collection, measurement.docsPerCollection);
      expect(chunkIdsBySource.length, measurement.docsPerCollection);
      expect(sourceIds, hasLength(docs.length));

      final corpus = <int, List<double>>{};
      for (var i = 0; i < docs.length; i++) {
        final chunkId = chunkIdsBySource[sourceIds[i]];
        expect(chunkId, isNotNull,
            reason: 'missing chunk for source ${sourceIds[i]}');
        corpus[chunkId!] = await EmbeddingService.embed(docs[i]);
      }
      expect(corpus.values.first.length, greaterThan(0));

      const k = 10;
      final queries = QueryFixture.unfilteredQueries;
      final results = <RecallQueryResult>[];

      for (var qi = 0; qi < queries.length; qi++) {
        final query = queries[qi];
        final queryEmbedding = await EmbeddingService.embed(query);
        final gt = groundTruthTopK(
          query: queryEmbedding,
          corpus: corpus,
          k: k,
        );

        final vectorOnly = await _prodTopK(
          collection,
          query,
          queryEmbedding,
          topK: k,
          vectorWeight: 1.0,
          bm25Weight: 0.0,
        );
        final hybrid = await _prodTopK(
          collection,
          query,
          queryEmbedding,
          topK: k,
          vectorWeight: 0.2,
          bm25Weight: 0.8,
        );

        expect(gt, hasLength(k));
        expect(vectorOnly, isNotEmpty);
        expect(hybrid, isNotEmpty);

        results.add(
          RecallQueryResult(
            queryIndex: qi,
            query: query,
            recallVectorOnly: recallAtK(gt: gt, prod: vectorOnly, k: k),
            recallHybrid: recallAtK(gt: gt, prod: hybrid, k: k),
          ),
        );
      }

      final report = RecallReport(
        results: results,
        meta: {
          'k': k,
          'collection': collection,
          ...measurement.toJson(),
          'query_count': queries.length,
          'build_mode':
              kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
          'features': 'vector_faer,vector_quant_i8',
          'embedding_dim': corpus.values.first.length,
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'gt': 'test_fixture_reembedded_f32_brute_force_cosine',
          'default_warmup': 'awaited_before_collection_seed',
          'note':
              'recall_vectoronly isolates i8-HNSW graph+quant error vs f32 GT; '
                  'recall_hybrid reflects BM25 RRF reorder vs pure-vector GT.',
        },
      );

      final tsTag = DateTime.now().millisecondsSinceEpoch.toString();
      await RecallExport.write(report, tsTag: tsTag);
      // ignore: avoid_print
      print('RECALL_MEAN vectoronly=${report.meanVectorOnly} '
          'hybrid=${report.meanHybrid}');
    },
    timeout: const Timeout(
      Duration(
        minutes: int.fromEnvironment(
          'MEASUREMENT_TIMEOUT_MINUTES',
          defaultValue: 15,
        ),
      ),
    ),
    skip: kDebugMode
        ? 'Measurement requires flutter drive --profile; flutter test is debug.'
        : false,
  );
}

void _assertProfileMode() {
  if (kDebugMode) {
    fail(
      'Query recall profiler must run in PROFILE/RELEASE via flutter drive.\n'
      'Debug builds use the cargokit debug profile = fallback Rust backend '
      '(no vector_faer / vector_quant_i8), so the recall number would be '
      'invalid. Aborting to avoid a fake-green quality baseline. '
      '(detected: kDebugMode=$kDebugMode, kProfileMode=$kProfileMode, '
      'kReleaseMode=$kReleaseMode)',
    );
  }
}

Future<void> _deleteDbFiles(String dbStem) async {
  for (final path in [
    dbStem,
    '$dbStem-wal',
    '$dbStem-shm',
    '$dbStem-journal'
  ]) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<List<int>> _prodTopK(
  String collection,
  String query,
  List<double> queryEmbedding, {
  required int topK,
  required double vectorWeight,
  required double bm25Weight,
}) async {
  final handle = await rust_rag.searchMetaHybrid(
    collectionId: collection,
    queryText: query,
    queryEmbedding: queryEmbedding,
    options: rust_rag.SearchMetaHybridOptions(
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: null,
      adjacentChunks: 0,
    ),
  );
  try {
    final hits = await handle.hitMeta();
    return <int>[for (final hit in hits) hit.chunkId];
  } finally {
    await handle.dispose();
  }
}
