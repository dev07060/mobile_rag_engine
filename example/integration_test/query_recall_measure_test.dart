import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/profiling/recall_db.dart';
import 'package:path_provider/path_provider.dart';

const _docs = 500;
const _dbName = 'recall_smoke.sqlite';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recall DB smoke: Dart reads engine f32 embeddings on device',
    () async {
      _assertProfileMode();

      final docsDir = await getApplicationDocumentsDirectory();
      await _deleteDbFiles('${docsDir.path}/$_dbName');

      await MobileRag.initialize(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
        databaseName: _dbName,
        deferIndexWarmup: true,
      );
      await QueryFixture.seed(docsPerCollection: _docs);

      final corpus = fetchChunkEmbeddingsF32(
        dbPath: MobileRag.instance.dbPath,
        collectionId: QueryFixture.collectionA,
      );
      expect(
        corpus,
        isNotEmpty,
        reason: 'Dart must read at least one chunk embedding from engine DB',
      );
      expect(corpus.length, _docs);
      expect(corpus.values.first.length, greaterThan(0));

      // ignore: avoid_print
      print(
        'RECALL_SMOKE chunks=${corpus.length} '
        'dim=${corpus.values.first.length}',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
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
  for (final path in [dbStem, '$dbStem-wal', '$dbStem-shm', '$dbStem-journal']) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
