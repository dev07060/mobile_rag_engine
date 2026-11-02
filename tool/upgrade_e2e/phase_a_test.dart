// Phase A of the upgrade harness, run against the last published release.
// Indexes the corpus with MiniLM the way each scenario's app would, then
// exits, leaving the database and model files phase B upgrades from.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'h1_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phase A $scenario', (tester) async {
    final database = databaseName(scenario);
    final RagEngine engine;
    switch (scenario) {
      case 's1' || 's4':
        await MobileRag.initialize(
          modelPack: const RagModelPack.asset(miniLmPack),
          databaseName: database,
        );
        engine = MobileRag.instance.engine;
      case 's2':
        final prepared = await preparedDirectory();
        final model = File('${prepared.path}/model.onnx');
        final tokenizer = File('${prepared.path}/tokenizer.json');
        await copyAsset(miniLmModel, model);
        await copyAsset(miniLmTokenizer, tokenizer);
        engine = await RagEngine.initialize(
          config: RagConfig.fromPreparedFiles(
            tokenizerPath: tokenizer.path,
            modelPath: model.path,
            expectedEmbeddingDimension: 384,
            databaseName: database,
          ),
        );
      case 's3':
        await MobileRag.initialize(
          tokenizerAsset: miniLmTokenizer,
          modelAsset: miniLmModel,
          databaseName: database,
        );
        engine = MobileRag.instance.engine;
      default:
        fail('Unknown phase A scenario "$scenario"');
    }

    for (final MapEntry(key: name, value: text) in corpus.entries) {
      await engine.addDocument(text, name: name);
    }
    await engine.rebuildIndex();
    final fingerprint = (await engine.migrationState).embeddingFingerprint;
    final chunks = (await engine.getStats()).chunkCount.toInt();
    await (await phaseAMarker(scenario)).writeAsString(
      jsonEncode({'fingerprint': fingerprint, 'chunks': chunks}),
    );
    print('H1_PHASE_A $scenario fingerprint=$fingerprint chunks=$chunks');

    if (scenario == 's2') {
      await RagEngine.dispose();
    } else {
      await MobileRag.dispose();
    }
    // Releases before the model identity store three components.
    expect(fingerprint.split('|'), hasLength(3));
    expect(chunks, greaterThan(0));
  });
}
