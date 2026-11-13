import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/bm25_search.dart' as rust_bm25;
import 'package:mobile_rag_engine/src/rust/api/hnsw_index.dart' as rust_hnsw;
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;
import 'package:mobile_rag_engine_example/profiling/query_profiler.dart';
import 'package:mobile_rag_engine_example/profiling/relevance_evalset.dart';
import 'package:mobile_rag_engine_example/profiling/relevance_metrics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _manifestAsset = String.fromEnvironment(
  'HYBRID_PASSAGE_MANIFEST_ASSET',
  defaultValue:
      'assets/evalsets/wiki_article_sources_manifest_20_small_v1.json',
);
const _sourceEvalsetAsset = String.fromEnvironment(
  'HYBRID_PASSAGE_SOURCE_EVALSET_ASSET',
  defaultValue: 'assets/evalsets/hybrid_relevance_seed_20_v1.jsonl',
);
const _chunkGoldAsset = String.fromEnvironment(
  'HYBRID_PASSAGE_CHUNK_GOLD_ASSET',
  defaultValue: 'assets/evalsets/hybrid_passage_gold_20_v1.jsonl',
);
const _outputDir = String.fromEnvironment(
  'HYBRID_PASSAGE_OUTPUT_DIR',
  defaultValue: '',
);
const _dbName = String.fromEnvironment(
  'HYBRID_PASSAGE_DB_NAME',
  defaultValue: 'hybrid_passage_relevance_measure.sqlite',
);
const _collectionId = String.fromEnvironment(
  'HYBRID_PASSAGE_COLLECTION_ID',
  defaultValue: 'hybrid_passage_relevance_seed_v1',
);
const _reuseExistingIndex = bool.fromEnvironment(
  'HYBRID_PASSAGE_REUSE_EXISTING_INDEX',
);

const _modelAsset = String.fromEnvironment(
  'EVAL_MODEL_ASSET',
  defaultValue: 'assets/model.onnx',
);
const _tokenizerAsset = String.fromEnvironment(
  'EVAL_TOKENIZER_ASSET',
  defaultValue: 'assets/tokenizer.json',
);
final _searchMicros = <String, List<int>>{};

const _searchTopK = 100;
const _hydratedTopK = 10;

const _profiles = <_HybridProfile>[
  _HybridProfile('vector_only', vectorWeight: 1.0, bm25Weight: 0.0),
  _HybridProfile('bm25_only', vectorWeight: 0.0, bm25Weight: 1.0),
  _HybridProfile('default_hybrid', vectorWeight: 0.2, bm25Weight: 0.8),
  _HybridProfile('sweep_0_4_0_6', vectorWeight: 0.4, bm25Weight: 0.6),
  _HybridProfile('sweep_0_6_0_4', vectorWeight: 0.6, bm25Weight: 0.4),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'passage-level hybrid relevance across five weight profiles',
    () async {
      _assertProfileMode();
      // ignore: avoid_print
      print('PASSAGE_EVAL model=$_modelAsset manifest=$_manifestAsset');

      final manifest = RelevanceSourceManifest.parse(
        await rootBundle.loadString(_manifestAsset),
      );
      final sourceEvalset = RelevanceEvalset.parseJsonl(
        await rootBundle.loadString(_sourceEvalsetAsset),
      );
      final chunkGold = ChunkGoldEvalset.parseJsonl(
        await rootBundle.loadString(_chunkGoldAsset),
      );
      sourceEvalset.validateAgainst(manifest);
      chunkGold.validateAgainst(
        manifest: manifest,
        sourceEvalset: sourceEvalset,
        requireExactItemIds: true,
      );

      if (!_reuseExistingIndex) {
        await _deleteDbFiles(_dbName);
      }
      await MobileRag.initialize(
        tokenizerAsset: _tokenizerAsset,
        modelAsset: _modelAsset,
        databaseName: _dbName,
        deferIndexWarmup: true,
      );

      final profiler = QueryProfiler(dbPath: MobileRag.instance.dbPath);
      if (!_reuseExistingIndex) {
        await profiler.deleteOnDiskIndex(_collectionId);
      }

      final tempFiles = <String>[];
      try {
        final sourceIdByKey = <String, int>{};
        final sourceKeyById = <int, String>{};
        final tempDir = await getTemporaryDirectory();

        if (_reuseExistingIndex) {
          sourceIdByKey.addAll(
            _loadSourceIdsFromDb(MobileRag.instance.dbPath, _collectionId),
          );
          sourceKeyById.addEntries(
            sourceIdByKey.entries.map(
              (entry) => MapEntry(entry.value, entry.key),
            ),
          );
          final missingSources = [
            for (final source in manifest.sources)
              if (!sourceIdByKey.containsKey(source.sourceKey))
                source.sourceKey,
          ];
          expect(
            missingSources,
            isEmpty,
            reason: 'reused DB is missing manifest sources',
          );
          // ignore: avoid_print
          print(
            'HYBRID_PASSAGE_RELEVANCE_REUSE_INDEX '
            'db=${MobileRag.instance.dbPath} '
            'sources=${sourceIdByKey.length}',
          );
        } else {
          final collection = MobileRag.instance.inCollection(_collectionId);
          for (final source in manifest.sources) {
            final ingestPath = await _materializeSourceFile(
              source.filePath,
              tempDir: tempDir,
              tempFiles: tempFiles,
            );
            final result = await collection.addDocumentFromFile(
              ingestPath,
              name: source.sourceKey,
              metadata: jsonEncode({
                'source_key': source.sourceKey,
                'language': source.language,
              }),
            );
            sourceIdByKey[source.sourceKey] = result.sourceId;
            sourceKeyById[result.sourceId] = source.sourceKey;
            // ignore: avoid_print
            print(
              'HYBRID_PASSAGE_RELEVANCE_SOURCE '
              'source_key=${source.sourceKey} '
              'source_id=${result.sourceId} '
              'chunks=${result.chunkCount}',
            );
          }

          expect(sourceIdByKey, hasLength(manifest.sources.length));
          await collection.rebuildIndex(force: true);
        }

        final outcomes = <_PassageQueryOutcome>[];
        for (final item in sourceEvalset.items) {
          final goldItem = chunkGold.itemById[item.itemId];
          expect(
            goldItem,
            isNotNull,
            reason: 'missing gold for ${item.itemId}',
          );
          final queryEmbedding = await EmbeddingService.embed(item.query);
          if (_dumpCandidates) {
            await _dumpCandidateLists(
              profiler: profiler,
              itemId: item.itemId,
              query: item.query,
              queryEmbedding: queryEmbedding,
            );
          }
          for (final profile in _profiles) {
            final chunks = await _searchPassageChunks(
              profiler: profiler,
              profile: profile,
              query: item.query,
              queryEmbedding: queryEmbedding,
              sourceKeyById: sourceKeyById,
            );
            expect(
              chunks.every((chunk) => !chunk.sourceKey.startsWith('unknown:')),
              isTrue,
              reason: '${item.itemId}/${profile.name} returned unknown source',
            );

            final score = scorePassageRanking(
              goldSourceKey: goldItem!.goldSourceKey,
              goldPassage: goldItem.goldPassage,
              rankedChunks: [
                for (final chunk in chunks)
                  PassageCandidate(
                    chunkId: chunk.chunkId,
                    sourceKey: chunk.sourceKey,
                    chunkIndex: chunk.chunkIndex,
                    content: chunk.content,
                  ),
              ],
              hardNegativeSourceKeys: [
                for (final passage in goldItem.hardNegativePassages)
                  passage.sourceKey,
              ],
              answerableContextByK: await _answerableContextByK(
                profiler: profiler,
                profile: profile,
                query: item.query,
                queryEmbedding: queryEmbedding,
                goldPassage: goldItem.goldPassage,
              ),
            );
            final outcome = _PassageQueryOutcome(
              item: item,
              goldItem: goldItem,
              profile: profile,
              score: score,
              chunks: chunks,
            );
            outcomes.add(outcome);
            // F-3: the `ask` condition (topK 5, facade context assembly).
            final ask = await _askCondition(
              profiler: profiler,
              profile: profile,
              query: item.query,
              queryEmbedding: queryEmbedding,
              goldPassage: goldItem.goldPassage,
            );
            _askRows.add({
              'item_id': item.itemId,
              'profile': profile.name,
              'query_class': item.queryClass,
              'language': item.language,
              'ask_gold_rank': ask.goldRank,
              'ask_recall@5': ask.goldRank > 0 ? 1 : 0,
              'ask_in_context': ask.inContext ? 1 : 0,
              'ask_context_chunks': ask.contextChunks,
              'ask_context_tokens': ask.contextTokens,
              'top100_gold_rank': score.goldPassageRank ?? -1,
              'ask_top1_similarity': ask.top1Similarity,
              'tags': item.tags,
            });
            // ignore: avoid_print
            print(
              'HYBRID_PASSAGE_RELEVANCE_QUERY '
              'profile=${profile.name} '
              'item_id=${item.itemId} '
              'class=${item.queryClass} '
              'lang=${item.language} '
              'gold_source=${goldItem.goldSourceKey} '
              'source_rank=${score.goldSourceRank ?? -1} '
              'passage_rank=${score.goldPassageRank ?? -1} '
              'top1=${outcome.top1SourceKey}',
            );
          }
        }

        expect(
          outcomes,
          hasLength(sourceEvalset.items.length * _profiles.length),
        );
        final aggregate = _aggregateOutcomes(outcomes);
        final export = await _writeArtifacts(
          manifest: manifest,
          sourceEvalset: sourceEvalset,
          chunkGold: chunkGold,
          sourceIdByKey: sourceIdByKey,
          aggregate: aggregate,
          outcomes: outcomes,
        );

        // ignore: avoid_print
        print('HYBRID_PASSAGE_RELEVANCE_EXPORT_DIR ${export.dirPath}');
        final stats = await MobileRag.instance.inCollection(_collectionId).getStats();
        if (_noAnswerAsset.isNotEmpty) {
          for (final raw in (await rootBundle.loadString(_noAnswerAsset))
              .split('\n')
              .where((l) => l.trim().isNotEmpty)) {
            final item = jsonDecode(raw) as Map<String, dynamic>;
            final query = item['query'] as String;
            final embedding = await EmbeddingService.embed(query);
            if (_dumpCandidates) {
              await _dumpCandidateLists(
                profiler: profiler,
                itemId: item['item_id'] as String,
                query: query,
                queryEmbedding: embedding,
              );
            }
            for (final profile in _profiles) {
              final ask = await _askCondition(
                profiler: profiler,
                profile: profile,
                query: query,
                queryEmbedding: embedding,
                goldPassage: '',
              );
              _noAnswerRows.add({
                'item_id': item['item_id'],
                'profile': profile.name,
                'language': item['language'],
                'ask_top1_similarity': ask.top1Similarity,
                'ask_top_source_keys': [
                  for (final id in ask.topSourceIds)
                    sourceKeyById[id] ?? 'unknown:$id',
                ],
                'ask_context_chunks': ask.contextChunks,
                'ask_context_tokens': ask.contextTokens,
              });
            }
          }
        }
        if (_dumpCandidates) {
          await _writeCandidateDump(
            chunks: stats.chunkCount,
            fingerprint: MobileRag.instance.currentEmbeddingFingerprint,
            dbPath: MobileRag.instance.dbPath,
          );
        }
        await _writeAskRows(
          chunks: stats.chunkCount,
          fingerprint: MobileRag.instance.currentEmbeddingFingerprint,
        );
        // ignore: avoid_print
        print(
          'PASSAGE_SUMMARY chunks=${stats.chunkCount} '
          'fp=${MobileRag.instance.currentEmbeddingFingerprint}',
        );
        for (final profile in _profiles) {
          final agg = aggregate[profile.name]!;
          final o = agg['overall']!;
          final langs = (agg['by_language'] as Map).map(
            (k, v) => MapEntry(
              k,
              '${((v as Map)['passage_recall@10'] as num) * (v['total'] as num)}/${v['total']}',
            ),
          );
          final micros = _searchMicros[profile.name]!..sort();
          // ignore: avoid_print
          print(
            'PASSAGE_SUMMARY profile=${profile.name} '
            'recall10=${o['passage_recall@10']} '
            'answerable10=${o['answerable_context@10']} '
            'mrr10=${(o['passage_mrr@10'] as num).toStringAsFixed(4)} '
            'langs=$langs '
            'search_us_median=${micros[micros.length ~/ 2]} '
            'search_us_mean=${micros.reduce((a, b) => a + b) ~/ micros.length}',
          );
        }
        // ignore: avoid_print
        print(
          'HYBRID_PASSAGE_RELEVANCE_EXPORT_FILE '
          '${export.jsonPath} ${export.csvPath}',
        );

        for (final profile in _profiles) {
          final total = aggregate[profile.name]?['overall']?['total'];
          expect(total, sourceEvalset.items.length);
        }
      } finally {
        for (final path in tempFiles) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
    },
    timeout: const Timeout(Duration(minutes: _timeoutMinutes)),
    skip: kDebugMode
        ? 'Measurement requires flutter drive --profile; debug uses fallback '
              'native backend and would not represent shipped retrieval.'
        : false,
  );
}

Future<List<_RetrievedPassageChunk>> _searchPassageChunks({
  required QueryProfiler profiler,
  required _HybridProfile profile,
  required String query,
  required List<double> queryEmbedding,
  required Map<int, String> sourceKeyById,
}) async {
  await rust_rag.activateCollectionForHybridSearch(
    collectionId: _collectionId,
    basePath: profiler.indexBasePath(_collectionId),
  );
  final watch = Stopwatch()..start();
  final handle = await rust_rag.searchMetaHybrid(
    collectionId: _collectionId,
    queryText: query,
    queryEmbedding: queryEmbedding,
    options: rust_rag.SearchMetaHybridOptions(
      topK: _searchTopK,
      vectorWeight: profile.vectorWeight,
      bm25Weight: profile.bm25Weight,
      sourceIds: null,
      adjacentChunks: 0,
    ),
  );
  _searchMicros
      .putIfAbsent(profile.name, () => <int>[])
      .add(watch.elapsedMicroseconds);
  try {
    final hits = await handle.hitMeta();
    final topHits = hits.take(_hydratedTopK).toList(growable: false);
    if (topHits.isEmpty) {
      return const [];
    }
    final hydrated = await handle.hydrateChunks(
      chunkIds: _toInt64List([for (final hit in topHits) hit.chunkId.toInt()]),
    );
    return _toRetrievedPassageChunks(
      hits: topHits,
      hydrated: hydrated,
      sourceKeyById: sourceKeyById,
    );
  } finally {
    await handle.dispose();
  }
}

Future<Map<int, bool>> _answerableContextByK({
  required QueryProfiler profiler,
  required _HybridProfile profile,
  required String query,
  required List<double> queryEmbedding,
  required String goldPassage,
}) async {
  final result = <int, bool>{};
  for (final k in const [5, 10]) {
    await rust_rag.activateCollectionForHybridSearch(
      collectionId: _collectionId,
      basePath: profiler.indexBasePath(_collectionId),
    );
    final contextHandle = await rust_rag.searchMetaHybrid(
      collectionId: _collectionId,
      queryText: query,
      queryEmbedding: queryEmbedding,
      options: rust_rag.SearchMetaHybridOptions(
        topK: k,
        vectorWeight: profile.vectorWeight,
        bm25Weight: profile.bm25Weight,
        sourceIds: null,
        adjacentChunks: 0,
      ),
    );
    try {
      final assembled = await contextHandle.assembleContext(
        options: const rust_rag.AssembleContextOptions(
          tokenBudget: 1200,
          strategy: rust_rag.ContextAssemblyStrategy.relevanceFirst,
          separator: '\n\n',
          singleSourceMode: false,
        ),
      );
      result[k] = normalizePassageText(
        assembled.text,
      ).contains(normalizePassageText(goldPassage));
    } finally {
      await contextHandle.dispose();
    }
  }
  return result;
}

List<_RetrievedPassageChunk> _toRetrievedPassageChunks({
  required List<rust_rag.SearchHitMeta> hits,
  required List<rust_rag.ChunkSearchResult> hydrated,
  required Map<int, String> sourceKeyById,
}) {
  final hydratedById = {
    for (final chunk in hydrated) chunk.chunkId.toInt(): chunk,
  };
  return [
    for (var i = 0; i < hits.length; i++)
      _RetrievedPassageChunk.fromHit(
        rank: i + 1,
        hit: hits[i],
        hydrated: hydratedById[hits[i].chunkId.toInt()],
        sourceKeyById: sourceKeyById,
      ),
  ];
}

frb.Int64List _toInt64List(List<int> values) {
  final result = frb.Int64List(values.length);
  for (var i = 0; i < values.length; i++) {
    result[i] = values[i];
  }
  return result;
}

Map<String, Map<String, Map<String, Object?>>> _aggregateOutcomes(
  List<_PassageQueryOutcome> outcomes,
) {
  final result = <String, Map<String, Map<String, Object?>>>{};
  for (final profile in _profiles) {
    final profileOutcomes = outcomes
        .where((outcome) => outcome.profile.name == profile.name)
        .toList();
    result[profile.name] = {
      'overall': _aggregateScores(profileOutcomes).toJson(),
      'by_query_class': _aggregateBy(
        profileOutcomes,
        (outcome) => outcome.item.queryClass,
      ),
      'by_language': _aggregateBy(
        profileOutcomes,
        (outcome) => outcome.item.language,
      ),
    };
  }
  return result;
}

PassageRelevanceAggregate _aggregateScores(
  List<_PassageQueryOutcome> outcomes,
) {
  final accumulator = PassageRelevanceAccumulator();
  for (final outcome in outcomes) {
    accumulator.add(outcome.score);
  }
  return accumulator.toAggregate();
}

Map<String, Object?> _aggregateBy(
  List<_PassageQueryOutcome> outcomes,
  String Function(_PassageQueryOutcome outcome) keyOf,
) {
  final grouped = <String, PassageRelevanceAccumulator>{};
  for (final outcome in outcomes) {
    grouped
        .putIfAbsent(keyOf(outcome), PassageRelevanceAccumulator.new)
        .add(outcome.score);
  }
  return {
    for (final entry in grouped.entries)
      entry.key: entry.value.toAggregate().toJson(),
  };
}

Future<_ExportedPassageArtifacts> _writeArtifacts({
  required RelevanceSourceManifest manifest,
  required RelevanceEvalset sourceEvalset,
  required ChunkGoldEvalset chunkGold,
  required Map<String, int> sourceIdByKey,
  required Map<String, Map<String, Map<String, Object?>>> aggregate,
  required List<_PassageQueryOutcome> outcomes,
}) async {
  final dir = _outputDir.isEmpty
      ? await getApplicationDocumentsDirectory()
      : Directory(_outputDir);
  await dir.create(recursive: true);
  final tsTag = DateTime.now().millisecondsSinceEpoch.toString();
  final base = '${dir.path}/hybrid_passage_relevance_$tsTag';
  final jsonPath = '$base.json';
  final csvPath = '$base.csv';

  final snapshot = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'build_mode': kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug'),
    'manifest_asset': _manifestAsset,
    'source_evalset_asset': _sourceEvalsetAsset,
    'chunk_gold_asset': _chunkGoldAsset,
    'dataset_id': manifest.datasetId,
    'schema_version': manifest.schemaVersion,
    'collection_id': _collectionId,
    'database_name': _dbName,
    'search_top_k': _searchTopK,
    'hydrated_top_k': _hydratedTopK,
    'phase': 'passage_level_only',
    'profiles': [for (final profile in _profiles) profile.toJson()],
    'source_id_by_key': sourceIdByKey,
    'items': sourceEvalset.items.length,
    'chunk_gold_items': chunkGold.items.length,
    'aggregates': aggregate,
    'query_outcomes': [for (final outcome in outcomes) outcome.toJson()],
  };

  await File(jsonPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(snapshot),
    flush: true,
  );
  await File(csvPath).writeAsString(_toCsv(outcomes), flush: true);

  return _ExportedPassageArtifacts(
    dirPath: dir.path,
    jsonPath: jsonPath,
    csvPath: csvPath,
  );
}

String _toCsv(List<_PassageQueryOutcome> outcomes) {
  final buffer = StringBuffer()
    ..writeln(
      [
        'item_id',
        'profile',
        'language',
        'query_type',
        'query_class',
        'gold_source_key',
        'gold_source_rank',
        'gold_passage_rank',
        'top1_source_key',
        'top1_chunk_id',
        'passage_recall@5',
        'passage_recall@10',
        'passage_mrr@10',
        'passage_ndcg@10',
        'answerable_context@5',
        'answerable_context@10',
        'source_recall@10',
        'source_but_passage_miss@10',
        'hard_negative_passage_intrusion@10',
        'hard_negative_passage_above_gold_count',
        'best_ngram_jaccard@10',
        'query',
        'gold_passage',
        'top10_chunk_ids',
        'top10_source_keys',
      ].join(','),
    );

  for (final outcome in outcomes) {
    final score = outcome.score;
    buffer.writeln(
      [
        outcome.item.itemId,
        outcome.profile.name,
        outcome.item.language,
        outcome.item.queryType,
        outcome.item.queryClass,
        outcome.goldItem.goldSourceKey,
        score.goldSourceRank ?? -1,
        score.goldPassageRank ?? -1,
        outcome.top1SourceKey,
        outcome.top1ChunkId,
        score.passageRecallAt(5),
        score.passageRecallAt(10),
        score.passageMrrAt(10),
        score.passageNdcgAt(10),
        score.answerableContextAt(5),
        score.answerableContextAt(10),
        score.sourceRecallAt(10),
        score.sourceButPassageMissAt(10),
        score.hardNegativePassageIntrusionAt(10),
        score.hardNegativePassageAboveGoldCount,
        score.bestNgramJaccardAt(10),
        outcome.item.query,
        outcome.goldItem.goldPassage,
        outcome.chunks.map((chunk) => chunk.chunkId).join('|'),
        outcome.chunks.map((chunk) => chunk.sourceKey).join('|'),
      ].map(_csvCell).join(','),
    );
  }
  return buffer.toString();
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

Future<String> _materializeSourceFile(
  String assetPath, {
  required Directory tempDir,
  required List<String> tempFiles,
}) async {
  final localFile = File(assetPath);
  if (await localFile.exists()) {
    return localFile.path;
  }

  final data = await rootBundle.load(assetPath);
  final safeName = assetPath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final tempFile = File('${tempDir.path}/hybrid_passage_$safeName');
  await tempFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
  tempFiles.add(tempFile.path);
  return tempFile.path;
}

Map<String, int> _loadSourceIdsFromDb(String dbPath, String collectionId) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      'SELECT id, name FROM sources '
      'WHERE collection_id = ? AND name IS NOT NULL '
      'ORDER BY id',
      [collectionId],
    );
    return {for (final row in rows) row['name'] as String: (row['id'] as int)};
  } finally {
    db.dispose();
  }
}

Future<void> _deleteDbFiles(String dbName) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dbStem = '${docsDir.path}/$dbName';
  for (final path in [
    dbStem,
    '$dbStem-wal',
    '$dbStem-shm',
    '$dbStem-journal',
  ]) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

void _assertProfileMode() {
  if (kDebugMode) {
    fail(
      'Hybrid passage relevance measurement must run in PROFILE/RELEASE via '
      'flutter drive. Debug builds use the fallback native backend and would '
      'not represent shipped retrieval. '
      '(detected: kDebugMode=$kDebugMode, kProfileMode=$kProfileMode, '
      'kReleaseMode=$kReleaseMode)',
    );
  }
}

String _preview(String value, {int maxChars = 240}) {
  final normalized = normalizePassageText(value);
  if (normalized.length <= maxChars) {
    return normalized;
  }
  return normalized.substring(0, maxChars);
}

class _HybridProfile {
  final String name;
  final double vectorWeight;
  final double bm25Weight;

  const _HybridProfile(
    this.name, {
    required this.vectorWeight,
    required this.bm25Weight,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'vector_weight': vectorWeight,
    'bm25_weight': bm25Weight,
  };
}

class _RetrievedPassageChunk {
  final int rank;
  final int chunkId;
  final int sourceId;
  final String sourceKey;
  final int chunkIndex;
  final String rawType;
  final String? headerPathPreview;
  final double similarity;
  final String content;

  const _RetrievedPassageChunk({
    required this.rank,
    required this.chunkId,
    required this.sourceId,
    required this.sourceKey,
    required this.chunkIndex,
    required this.rawType,
    required this.headerPathPreview,
    required this.similarity,
    required this.content,
  });

  factory _RetrievedPassageChunk.fromHit({
    required int rank,
    required rust_rag.SearchHitMeta hit,
    required rust_rag.ChunkSearchResult? hydrated,
    required Map<int, String> sourceKeyById,
  }) {
    final sourceId = hit.sourceId.toInt();
    return _RetrievedPassageChunk(
      rank: rank,
      chunkId: hit.chunkId.toInt(),
      sourceId: sourceId,
      sourceKey: sourceKeyById[sourceId] ?? 'unknown:$sourceId',
      chunkIndex: hit.chunkIndex,
      rawType: hit.rawType,
      headerPathPreview: hit.headerPathPreview,
      similarity: hit.similarity,
      content: hydrated?.content ?? '',
    );
  }

  Map<String, Object?> toJson(String goldPassage) {
    final normalizedContent = normalizePassageText(content);
    final normalizedGold = normalizePassageText(goldPassage);
    return {
      'rank': rank,
      'chunk_id': chunkId,
      'source_id': sourceId,
      'source_key': sourceKey,
      'chunk_index': chunkIndex,
      'raw_type': rawType,
      'header_path_preview': headerPathPreview,
      'similarity': similarity,
      'passage_match':
          normalizedGold.isNotEmpty &&
          normalizedContent.contains(normalizedGold),
      'ngram_jaccard': ngramJaccard(content, goldPassage),
      'content_preview': _preview(content),
    };
  }
}

class _PassageQueryOutcome {
  final RelevanceEvalItem item;
  final ChunkGoldItem goldItem;
  final _HybridProfile profile;
  final PassageRankingScore score;
  final List<_RetrievedPassageChunk> chunks;

  const _PassageQueryOutcome({
    required this.item,
    required this.goldItem,
    required this.profile,
    required this.score,
    required this.chunks,
  });

  String get top1SourceKey => chunks.isEmpty ? 'none' : chunks.first.sourceKey;

  int get top1ChunkId => chunks.isEmpty ? -1 : chunks.first.chunkId;

  Map<String, int> get hardNegativePositions {
    final hardNegativeSourceKeys = {
      for (final passage in goldItem.hardNegativePassages) passage.sourceKey,
    };
    final positions = <String, int>{};
    for (final chunk in chunks) {
      if (!positions.containsKey(chunk.sourceKey) &&
          hardNegativeSourceKeys.contains(chunk.sourceKey)) {
        positions[chunk.sourceKey] = chunk.rank;
      }
    }
    return positions;
  }

  Map<String, Object?> toJson() => {
    ...item.toJson(),
    'profile': profile.name,
    'vector_weight': profile.vectorWeight,
    'bm25_weight': profile.bm25Weight,
    'gold_source_key': goldItem.goldSourceKey,
    'gold_passage': goldItem.goldPassage,
    'gold_source_rank': score.goldSourceRank ?? -1,
    'gold_passage_rank': score.goldPassageRank ?? -1,
    'top1_source_key': top1SourceKey,
    'top1_chunk_id': top1ChunkId,
    'top1_chunk_preview': chunks.isEmpty ? '' : _preview(chunks.first.content),
    'retrieved_chunks': [
      for (final chunk in chunks) chunk.toJson(goldItem.goldPassage),
    ],
    'hard_negative_positions': hardNegativePositions,
    'best_ngram_jaccard': score.bestNgramJaccardAt(10),
    'metrics': score.toJson(),
  };
}

class _ExportedPassageArtifacts {
  final String dirPath;
  final String jsonPath;
  final String csvPath;

  const _ExportedPassageArtifacts({
    required this.dirPath,
    required this.jsonPath,
    required this.csvPath,
  });
}


// ---- F-3: `ask` condition -------------------------------------------------
// `MobileRag.ask` -> RagSearchTool -> searchHybridWithContext(topK: 5,
// tokenBudget: 1500) -> searchMetaHybrid(topK 5, collection filter, so 20
// candidates per list) + assembleContext(relevanceFirst, '\n\n---\n\n',
// singleSourceMode false). Checked against lib/mobile_rag.dart and
// lib/services/source_rag_service.dart on 2026-11-13.
const _askTopK = 5;
const _askTokenBudget = 1500;
const _askSeparator = '\n\n---\n\n';
final _askRows = <Map<String, Object?>>[];
final _noAnswerRows = <Map<String, Object?>>[];
const _noAnswerAsset = String.fromEnvironment('F1_NO_ANSWER_ASSET');
// Large bundles with a large model (BGE-m3, 15,000 MIRACL passages) index for
// well over the default 90 minutes.
const _timeoutMinutes = int.fromEnvironment('EVAL_TIMEOUT_MINUTES', defaultValue: 90);

class _AskOutcome {
  const _AskOutcome(
    this.goldRank,
    this.inContext,
    this.contextChunks,
    this.contextTokens,
    this.top1Similarity,
    this.topSourceIds,
  );
  final int goldRank;
  final bool inContext;
  final int contextChunks;
  final int contextTokens;
  final double top1Similarity;
  final List<int> topSourceIds;
}

Future<_AskOutcome> _askCondition({
  required QueryProfiler profiler,
  required _HybridProfile profile,
  required String query,
  required List<double> queryEmbedding,
  required String goldPassage,
}) async {
  await rust_rag.activateCollectionForHybridSearch(
    collectionId: _collectionId,
    basePath: profiler.indexBasePath(_collectionId),
  );
  final handle = await rust_rag.searchMetaHybrid(
    collectionId: _collectionId,
    queryText: query,
    queryEmbedding: queryEmbedding,
    options: rust_rag.SearchMetaHybridOptions(
      topK: _askTopK,
      vectorWeight: profile.vectorWeight,
      bm25Weight: profile.bm25Weight,
      sourceIds: null,
      adjacentChunks: 0,
    ),
  );
  try {
    final gold = normalizePassageText(goldPassage);
    final hits = await handle.hitMeta();
    var goldRank = -1;
    if (hits.isNotEmpty) {
      final hydrated = await handle.hydrateChunks(
        chunkIds: _toInt64List([for (final h in hits) h.chunkId.toInt()]),
      );
      final byId = {for (final c in hydrated) c.chunkId.toInt(): c.content};
      for (var i = 0; i < hits.length; i++) {
        final content = byId[hits[i].chunkId.toInt()] ?? '';
        if (gold.isNotEmpty && normalizePassageText(content).contains(gold)) {
          goldRank = i + 1;
          break;
        }
      }
    }
    final assembled = await handle.assembleContext(
      options: const rust_rag.AssembleContextOptions(
        tokenBudget: _askTokenBudget,
        strategy: rust_rag.ContextAssemblyStrategy.relevanceFirst,
        separator: _askSeparator,
        singleSourceMode: false,
      ),
    );
    return _AskOutcome(
      goldRank,
      gold.isNotEmpty && normalizePassageText(assembled.text).contains(gold),
      assembled.includedChunkIds.length,
      assembled.exactTokens,
      hits.isEmpty ? 0 : hits.first.similarity,
      [for (final h in hits) h.sourceId.toInt()],
    );
  } finally {
    await handle.dispose();
  }
}

Future<void> _writeAskRows({
  required int chunks,
  required String? fingerprint,
}) async {
  final byProfile = <String, List<Map<String, Object?>>>{};
  for (final row in _askRows) {
    byProfile.putIfAbsent(row['profile']! as String, () => []).add(row);
  }
  double mean(List<Map<String, Object?>> rows, String key) =>
      rows.isEmpty
          ? 0
          : rows.map((r) => (r[key]! as num).toDouble()).reduce((a, b) => a + b) /
              rows.length;
  double top100At(List<Map<String, Object?>> rows, int k) => rows.isEmpty
      ? 0
      : rows.where((r) {
            final rank = r['top100_gold_rank']! as int;
            return rank > 0 && rank <= k;
          }).length /
          rows.length;
  final summary = <String, Object?>{};
  for (final entry in byProfile.entries) {
    final rows = entry.value;
    final s = {
      'total': rows.length,
      'ask_recall@5': mean(rows, 'ask_recall@5'),
      'ask_in_context': mean(rows, 'ask_in_context'),
      'top100_recall@5': top100At(rows, 5),
      'top100_recall@10': top100At(rows, 10),
      'ask_context_chunks_mean': mean(rows, 'ask_context_chunks'),
      'ask_context_tokens_mean': mean(rows, 'ask_context_tokens'),
    };
    summary[entry.key] = s;
    // ignore: avoid_print
    print(
      'F3_ASK profile=${entry.key} ask_recall5=${s['ask_recall@5']} '
      'ask_in_context=${s['ask_in_context']} '
      'top100_recall5=${s['top100_recall@5']} '
      'top100_recall10=${s['top100_recall@10']} '
      'ctx_chunks=${(s['ask_context_chunks_mean']! as double).toStringAsFixed(2)} '
      'ctx_tokens=${(s['ask_context_tokens_mean']! as double).toStringAsFixed(1)}',
    );
  }
  final dir = await getApplicationDocumentsDirectory();
  final path =
      '${dir.path}/f3_ask_${DateTime.now().millisecondsSinceEpoch}.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'build_mode': kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      'model_asset': _modelAsset,
      'embedding_fingerprint': fingerprint,
      'chunk_count': chunks,
      'manifest_asset': _manifestAsset,
      'source_evalset_asset': _sourceEvalsetAsset,
      'chunk_gold_asset': _chunkGoldAsset,
      'ask_top_k': _askTopK,
      'ask_token_budget': _askTokenBudget,
      'harness_search_top_k': _searchTopK,
      'summary': summary,
      'rows': _askRows,
      'no_answer_asset': _noAnswerAsset,
      'no_answer_rows': _noAnswerRows,
    }),
    flush: true,
  );
  // ignore: avoid_print
  print('F3_ASK_FILE $path');
}


// ---- F-7: candidate lists for offline fusion comparison -------------------
// The engine's hybrid search (`compute_hybrid_rrf_scores` in
// rust_builder/rust/src/api/hybrid_search.rs) fuses `search_hnsw_slice(k)` and
// `bm25_search(k)` with k = topK x 4. This dumps the same two engine calls for
// the two candidate counts the evaluation uses: 20 (`ask`, topK 5) and 400
// (harness, topK 100). HNSW results depend on k (ef_search = max(100, 5k)),
// so both are kept. Offline fusion is scripts/eval/f7_fusion_compare.py.
const _dumpCandidates = bool.fromEnvironment('F7_DUMP_CANDIDATES');
const _dumpCandidateCounts = [20, 400];
final _candidateRows = <Map<String, Object?>>[];

Future<void> _dumpCandidateLists({
  required QueryProfiler profiler,
  required String itemId,
  required String query,
  required List<double> queryEmbedding,
}) async {
  await rust_rag.activateCollectionForHybridSearch(
    collectionId: _collectionId,
    basePath: profiler.indexBasePath(_collectionId),
  );
  final row = <String, Object?>{
    'item_id': itemId,
    'query': query,
    'query_embedding': queryEmbedding,
  };
  for (final k in _dumpCandidateCounts) {
    final vec = await rust_hnsw.searchHnswSlice(
      queryEmbedding: queryEmbedding,
      topK: BigInt.from(k),
    );
    final bm25 = await rust_bm25.bm25Search(query: query, topK: k);
    row['vector_$k'] = [
      for (final r in vec) [r.id.toInt(), r.distance],
    ];
    row['bm25_$k'] = [
      for (final r in bm25) [r.docId.toInt(), r.score],
    ];
  }
  _candidateRows.add(row);
}

Future<void> _writeCandidateDump({
  required int chunks,
  required String? fingerprint,
  required String dbPath,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final path =
      '${dir.path}/f7_candidates_${DateTime.now().millisecondsSinceEpoch}.json';
  await File(path).writeAsString(
    jsonEncode({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'model_asset': _modelAsset,
      'embedding_fingerprint': fingerprint,
      'chunk_count': chunks,
      'db_path': dbPath,
      'collection_id': _collectionId,
      'candidate_counts': _dumpCandidateCounts,
      'rrf_k': 60,
      'rows': _candidateRows,
    }),
    flush: true,
  );
  // ignore: avoid_print
  print('F7_CANDIDATES_FILE $path');
}
