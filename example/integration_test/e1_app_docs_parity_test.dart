// E1 (docs/milestones.md): the example app's "App docs" path gives the same
// answers as the evaluation harness.
//
// Runs the app's own code (lib/e1/app_docs_bundle.dart, lib/example_model.dart)
// on a fresh database: ingests the E1 bundle, asks all 120 questions with each
// weight preset, and writes the top-5 source keys and gold hits per question
// to Documents/e1_app_parity_<model>.json. scripts/e1/compare_app_parity.py
// compares that file with the harness dump of the same model.
//
// It also checks that "App default" (no weights passed) returns the same top 5
// as the model's recipe weights passed explicitly (repeating the pair when
// BM25 ties make one call differ).
//
//   flutter drive --profile -d macos --driver=test_driver/integration_test.dart \
//     --target=integration_test/e1_app_docs_parity_test.dart \
//     --dart-define=EXAMPLE_MODEL=koen

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine_example/e1/app_docs_bundle.dart';
import 'package:mobile_rag_engine_example/example_model.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'E1 app path matches the harness',
    (tester) async {
      final model = resolveExampleModel();
      final docs = await getApplicationDocumentsDirectory();
      final dbName =
          'e1_app_parity_${DateTime.now().millisecondsSinceEpoch}.sqlite';
      await model.initialize(databaseName: dbName);
      final bundle = await E1Bundle.load();
      final added = await bundle.ingest();
      expect(added, bundle.sources.length);
      await bundle.collection.warmupFuture;

      final (rv, rb) = model.effectiveWeights;
      final rows = <Map<String, Object?>>[];
      final hitsByPreset = <String, int>{};
      var answerable = 0;
      var defaultMismatch = 0;
      var tieRetries = 0;
      for (final q in bundle.questions) {
        if (q.hasAnswer) answerable++;
        final row = <String, Object?>{
          'item_id': q.id,
          'has_answer': q.hasAnswer,
        };
        for (final w in e1WeightPresets) {
          final hits = await bundle.search(
            q.query,
            weights: w,
            goldPassage: q.goldPassage,
          );
          final found = hits.any((h) => h.isGold);
          row[w.label] = {
            'sources': [for (final h in hits) h.sourceKey],
            'gold_rank': hits.indexWhere((h) => h.isGold) + 1,
          };
          if (q.hasAnswer && found) {
            hitsByPreset[w.label] = (hitsByPreset[w.label] ?? 0) + 1;
          }
        }
        // The engine orders BM25 score ties through a HashMap, so two calls with
        // the same weights can differ in tied chunks. Count a difference only
        // if no repeat of the two calls ever agrees.
        final recipe = E1Weights('recipe', rv, rb);
        final implicitWeights = e1WeightPresets.first;
        var agreed = false;
        for (var attempt = 0; attempt < 5 && !agreed; attempt++) {
          final a = await bundle.search(q.query, weights: implicitWeights);
          final e = await bundle.search(q.query, weights: recipe);
          agreed =
              jsonEncode([for (final h in a) h.text]) ==
              jsonEncode([for (final h in e) h.text]);
          if (!agreed && attempt == 0) tieRetries++;
        }
        if (!agreed) {
          defaultMismatch++;
          row['default_vs_recipe_mismatch'] = true;
        }
        rows.add(row);
      }

      final out = File('${docs.path}/e1_app_parity_${model.id}.json');
      await out.writeAsString(
        const JsonEncoder.withIndent(' ').convert({
          'model': model.id,
          'recipe_weights': [rv, rb],
          'sources': bundle.sources.length,
          'answerable': answerable,
          'hits': hitsByPreset,
          'default_vs_recipe_mismatch': defaultMismatch,
          'differed_on_first_try': tieRetries,
          'rows': rows,
        }),
      );
      // ignore: avoid_print
      print(
        'E1_APP_PARITY model=${model.id} answerable=$answerable '
        'hits=${jsonEncode(hitsByPreset)} default_vs_recipe_mismatch=$defaultMismatch '
        'differed_on_first_try=$tieRetries '
        'out=${out.path}',
      );
      expect(defaultMismatch, 0);
      await MobileRag.dispose();
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
