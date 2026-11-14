// The E1 app-document bundle (docs/milestones.md E1, docs/perf/e1-app-docs/):
// GNOME Help pages, short app/office documents and the two sample PDFs, with
// 120 questions (lexical, paraphrase, no answer) in English and Korean.
//
// Used by the "App docs" screen and by
// integration_test/e1_app_docs_parity_test.dart. Documents are ingested the
// way the evaluation harness does it (asset copied to a file, then
// addDocumentFromFile), and questions are searched in the `ask` condition
// (searchMeta, top 5, in a collection), so the app shows what the reports
// measured.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';

const e1CollectionId = 'e1_app_docs';
const e1ManifestAsset = 'assets/evalsets/e1/e1_sources_manifest_v1.json';
const e1EvalsetAsset = 'assets/evalsets/e1/e1_evalset_v1.jsonl';
const e1GoldAsset = 'assets/evalsets/e1/e1_passage_gold_v1.jsonl';
const e1NoAnswerAsset = 'assets/evalsets/e1/e1_no_answer_v1.jsonl';

class E1Source {
  const E1Source(this.key, this.filePath, this.language, this.title);
  final String key;
  final String filePath;
  final String language;
  final String title;
}

class E1Question {
  const E1Question({
    required this.id,
    required this.query,
    required this.language,
    required this.intent,
    required this.measuredClass,
    this.goldSourceKey,
    this.goldPassage,
  });

  final String id;
  final String query;
  final String language;

  /// lexical | paraphrase | no_answer
  final String intent;

  /// none | partial | high | no_answer (BM25-token overlap with the gold passage)
  final String measuredClass;
  final String? goldSourceKey;
  final String? goldPassage;

  bool get hasAnswer => goldPassage != null;
}

/// A weight setting to compare. [vectorWeight] 1 / [bm25Weight] 0 ranks by
/// the vector list only, and the reverse by BM25 only.
class E1Weights {
  const E1Weights(this.label, this.vectorWeight, this.bm25Weight);
  final String label;
  final double? vectorWeight;
  final double? bm25Weight;
}

const e1WeightPresets = <E1Weights>[
  E1Weights('App default', null, null),
  E1Weights('0.2 / 0.8', 0.2, 0.8),
  E1Weights('0.5 / 0.5', 0.5, 0.5),
  E1Weights('0.6 / 0.4', 0.6, 0.4),
  E1Weights('Vector only', 1.0, 0.0),
  E1Weights('BM25 only', 0.0, 1.0),
];

class E1Hit {
  const E1Hit({
    required this.rank,
    required this.sourceKey,
    required this.text,
    required this.isGold,
  });
  final int rank;
  final String sourceKey;
  final String text;
  final bool isGold;
}

class E1Bundle {
  E1Bundle._(this.sources, this.questions);

  final List<E1Source> sources;
  final List<E1Question> questions;

  static Future<E1Bundle> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final manifest =
        jsonDecode(await b.loadString(e1ManifestAsset)) as Map<String, dynamic>;
    final sources = [
      for (final s in manifest['sources'] as List)
        E1Source(
          s['source_key'] as String,
          s['file_path'] as String,
          s['language'] as String,
          s['description'] as String,
        ),
    ];
    final gold = {
      for (final row in _jsonl(await b.loadString(e1GoldAsset)))
        row['item_id'] as String: row,
    };
    final questions = <E1Question>[];
    for (final row in _jsonl(await b.loadString(e1EvalsetAsset))) {
      final id = row['item_id'] as String;
      questions.add(
        E1Question(
          id: id,
          query: row['query'] as String,
          language: row['language'] as String,
          intent: _tag(row, 'intent'),
          measuredClass: _tag(row, 'class'),
          goldSourceKey: gold[id]?['gold_source_key'] as String?,
          goldPassage: gold[id]?['gold_passage'] as String?,
        ),
      );
    }
    for (final row in _jsonl(await b.loadString(e1NoAnswerAsset))) {
      questions.add(
        E1Question(
          id: row['item_id'] as String,
          query: row['query'] as String,
          language: row['language'] as String,
          intent: 'no_answer',
          measuredClass: 'no_answer',
        ),
      );
    }
    questions.sort((a, b) => a.id.compareTo(b.id));
    return E1Bundle._(sources, questions);
  }

  CollectionRag get collection =>
      MobileRag.instance.inCollection(e1CollectionId);

  /// Adds every source that is not in the collection yet, then rebuilds the
  /// index. Returns the number of sources added.
  Future<int> ingest({
    AssetBundle? bundle,
    void Function(int done, int total, String key)? onProgress,
  }) async {
    final b = bundle ?? rootBundle;
    final existing = {for (final s in await collection.listSources()) s.name};
    final tempDir = await getTemporaryDirectory();
    var added = 0;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      onProgress?.call(i, sources.length, source.key);
      if (existing.contains(source.key)) continue;
      final data = await b.load(source.filePath);
      final safe = source.filePath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${tempDir.path}/e1_$safe');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      try {
        await collection.addDocumentFromFile(
          file.path,
          name: source.key,
          metadata: jsonEncode({
            'source_key': source.key,
            'language': source.language,
          }),
        );
      } finally {
        if (await file.exists()) await file.delete();
      }
      added++;
    }
    onProgress?.call(sources.length, sources.length, '');
    if (added > 0) {
      await collection.rebuildIndex(force: true);
    }
    return added;
  }

  /// Searches like `ask` does (top 5 in the collection) and marks the hit that
  /// contains the question's gold passage.
  Future<List<E1Hit>> search(
    String query, {
    E1Weights weights = const E1Weights('App default', null, null),
    String? goldPassage,
  }) async {
    final meta = await collection.searchMeta(
      query,
      topK: 5,
      vectorWeight: weights.vectorWeight,
      bm25Weight: weights.bm25Weight,
    );
    if (meta.hits.isEmpty) return const [];
    final chunks = await collection.hydrateChunks(
      searchHandle: meta.handle,
      chunkIds: [for (final h in meta.hits) h.chunkId.toInt()],
    );
    final byId = {for (final c in chunks) c.chunkId.toInt(): c};
    final names = {
      for (final s in await collection.listSources()) s.id.toInt(): s.name,
    };
    final gold = goldPassage == null ? null : normalize(goldPassage);
    return [
      for (var i = 0; i < meta.hits.length; i++)
        if (byId[meta.hits[i].chunkId.toInt()] case final c?)
          E1Hit(
            rank: i + 1,
            sourceKey: names[c.sourceId.toInt()] ?? '#${c.sourceId}',
            text: c.content,
            isGold: gold != null && normalize(c.content).contains(gold),
          ),
    ];
  }
}

/// Same as normalizePassageText in lib/profiling/relevance_metrics.dart.
String normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _tag(Map<String, dynamic> row, String name) {
  for (final t in row['tags'] as List) {
    final s = t as String;
    if (s.startsWith('$name:')) return s.substring(name.length + 1);
  }
  return '';
}

Iterable<Map<String, dynamic>> _jsonl(String raw) sync* {
  for (final line in const LineSplitter().convert(raw)) {
    if (line.trim().isEmpty) continue;
    yield jsonDecode(line) as Map<String, dynamic>;
  }
}
