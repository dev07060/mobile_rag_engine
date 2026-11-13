import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/relevance_evalset.dart';
import 'package:mobile_rag_engine_example/profiling/relevance_metrics.dart';

const _manifestJson = '''
{
  "dataset_id": "unit_dataset",
  "schema_version": 1,
  "sources": [
    {"source_key": "src_a", "file_path": "assets/a.md", "language": "ko"},
    {"source_key": "src_b", "file_path": "assets/b.md", "language": "en"},
    {"source_key": "src_c", "file_path": "assets/c.md", "language": "en"}
  ]
}
''';

const _evalsetJsonl = '''
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"시장 추세","language":"ko","query_type":"positive","expected_source_key":"src_a","hard_negative_source_keys":["src_b"],"tags":["class:lexical","finance"],"collected_at":"2026-02-22"}
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q2","query":"customer perception","language":"en","query_type":"paraphrase","expected_source_key":"src_b","hard_negative_source_keys":[]}
''';

const _chunkGoldJsonl = '''
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"시장 추세","language":"ko","query_type":"positive","gold_source_key":"src_a","gold_passage":"시장 추세는 가격 방향성이다.","hard_negative_passages":[{"source_key":"src_b","passage":"부동산신탁 설명"}],"tags":["class:lexical"],"collected_at":"2026-06-09"}
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q2","query":"customer perception","language":"en","query_type":"paraphrase","gold_source_key":"src_b","gold_passage":"Customer experience includes perceptions.","hard_negative_passages":[]}
''';

void main() {
  group('RelevanceSourceManifest', () {
    test('parses source manifest JSON', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);

      expect(manifest.datasetId, 'unit_dataset');
      expect(manifest.schemaVersion, 1);
      expect(manifest.sources, hasLength(3));
      expect(manifest.sourceKeys, containsAll(['src_a', 'src_b', 'src_c']));
    });
  });

  group('RelevanceEvalset', () {
    test('parses JSONL and preserves grouping fields', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);
      final evalset = RelevanceEvalset.parseJsonl(_evalsetJsonl);

      evalset.validateAgainst(manifest);

      expect(evalset.items, hasLength(2));
      expect(evalset.items.first.language, 'ko');
      expect(evalset.items.first.queryType, 'positive');
      expect(evalset.items.first.queryClass, 'lexical');
      expect(evalset.items.first.tags, ['class:lexical', 'finance']);
      expect(evalset.items[1].tags, isEmpty);
      expect(evalset.items[1].queryClass, 'paraphrase');
    });

    test('unknown expected source keys fail validation', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);
      final evalset = RelevanceEvalset.parseJsonl('''
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"x","language":"ko","query_type":"positive","expected_source_key":"src_missing","hard_negative_source_keys":[]}
''');

      expect(
        () => evalset.validateAgainst(manifest),
        throwsA(predicate((e) => e.toString().contains('src_missing'))),
      );
    });

    test('unknown hard-negative source keys fail validation', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);
      final evalset = RelevanceEvalset.parseJsonl('''
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"x","language":"ko","query_type":"hard_negative","expected_source_key":"src_a","hard_negative_source_keys":["src_missing"]}
''');

      expect(
        () => evalset.validateAgainst(manifest),
        throwsA(predicate((e) => e.toString().contains('src_missing'))),
      );
    });

    test('duplicate item_id fails validation', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);
      final evalset = RelevanceEvalset.parseJsonl('''
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"x","language":"ko","query_type":"positive","expected_source_key":"src_a","hard_negative_source_keys":[]}
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"y","language":"en","query_type":"positive","expected_source_key":"src_b","hard_negative_source_keys":[]}
''');

      expect(
        () => evalset.validateAgainst(manifest),
        throwsA(predicate((e) => e.toString().contains('Duplicate item_id'))),
      );
    });

    // The tracked evaluation bundles (docs/milestones.md F1) must stay
    // parseable and consistent with their manifests.
    test('80-query regression bundle validates', () {
      final manifest = RelevanceSourceManifest.parse(
        File(
          'assets/evalsets/wiki_article_sources_manifest_80_balanced_v1.json',
        ).readAsStringSync(),
      );
      final evalset = RelevanceEvalset.parseJsonl(
        File(
          'assets/evalsets/hybrid_relevance_seed_80_balanced_v1.jsonl',
        ).readAsStringSync(),
      );
      final gold = ChunkGoldEvalset.parseJsonl(
        File(
          'assets/evalsets/hybrid_passage_gold_80_balanced_v1.jsonl',
        ).readAsStringSync(),
      );

      evalset.validateAgainst(manifest);
      gold.validateAgainst(
        manifest: manifest,
        sourceEvalset: evalset,
        requireExactItemIds: true,
      );

      final classCounts = <String, int>{};
      for (final item in evalset.items) {
        classCounts[item.queryClass] = (classCounts[item.queryClass] ?? 0) + 1;
      }
      expect(manifest.sources, hasLength(80));
      expect(classCounts, {
        'lexical': 16,
        'semantic': 16,
        'mixed': 16,
        'hard_negative': 16,
        'multilingual': 16,
      });
      for (final source in manifest.sources) {
        expect(
          File(source.filePath).existsSync(),
          isTrue,
          reason: source.filePath,
        );
      }
    });

    test('F1 query bundle validates', () {
      final manifest = RelevanceSourceManifest.parse(
        File(
          'assets/evalsets/f1/f1_sources_manifest_v1.json',
        ).readAsStringSync(),
      );
      final evalset = RelevanceEvalset.parseJsonl(
        File('assets/evalsets/f1/f1_evalset_v1.jsonl').readAsStringSync(),
      );
      final gold = ChunkGoldEvalset.parseJsonl(
        File('assets/evalsets/f1/f1_passage_gold_v1.jsonl').readAsStringSync(),
      );

      evalset.validateAgainst(manifest);
      gold.validateAgainst(
        manifest: manifest,
        sourceEvalset: evalset,
        requireExactItemIds: true,
      );
      for (final item in gold.items) {
        final text = File(
          manifest.sourceByKey[item.goldSourceKey]!.filePath,
        ).readAsStringSync();
        expect(
          normalizePassageText(
            text,
          ).contains(normalizePassageText(item.goldPassage)),
          isTrue,
          reason: '${item.itemId} gold passage is not in its source',
        );
      }
    });
  });

  group('ChunkGoldEvalset', () {
    test('parses JSONL and validates against manifest and source evalset', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);
      final sourceEvalset = RelevanceEvalset.parseJsonl(_evalsetJsonl);
      final chunkGold = ChunkGoldEvalset.parseJsonl(_chunkGoldJsonl);

      sourceEvalset.validateAgainst(manifest);
      chunkGold.validateAgainst(
        manifest: manifest,
        sourceEvalset: sourceEvalset,
        requireExactItemIds: true,
      );

      expect(chunkGold.items, hasLength(2));
      expect(chunkGold.items.first.goldSourceKey, 'src_a');
      expect(chunkGold.items.first.goldPassage, contains('시장 추세'));
      expect(
        chunkGold.items.first.hardNegativePassages.first.sourceKey,
        'src_b',
      );
    });

    test('gold source must match source-level expected source', () {
      final manifest = RelevanceSourceManifest.parse(_manifestJson);
      final sourceEvalset = RelevanceEvalset.parseJsonl(_evalsetJsonl);
      final chunkGold = ChunkGoldEvalset.parseJsonl('''
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q1","query":"시장 추세","language":"ko","query_type":"positive","gold_source_key":"src_b","gold_passage":"wrong source passage","hard_negative_passages":[]}
{"dataset_id":"unit_dataset","schema_version":1,"item_id":"q2","query":"customer perception","language":"en","query_type":"paraphrase","gold_source_key":"src_b","gold_passage":"Customer experience includes perceptions.","hard_negative_passages":[]}
''');

      expect(
        () => chunkGold.validateAgainst(
          manifest: manifest,
          sourceEvalset: sourceEvalset,
          requireExactItemIds: true,
        ),
        throwsA(predicate((e) => e.toString().contains('gold_source_key'))),
      );
    });
  });
}
