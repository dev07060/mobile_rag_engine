import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OfflineEvalApp());
}

class _OfflineEvalApp extends StatefulWidget {
  const _OfflineEvalApp();

  @override
  State<_OfflineEvalApp> createState() => _OfflineEvalAppState();
}

class _OfflineEvalAppState extends State<_OfflineEvalApp> {
  static const _manifestAsset = String.fromEnvironment(
    'EVALSET_MANIFEST_ASSET',
    defaultValue: 'assets/evalsets/week1_sources_manifest.json',
  );
  static const _evalsetAsset = String.fromEnvironment(
    'EVALSET_JSONL_ASSET',
    defaultValue: 'assets/evalsets/week1_evalset_v1.jsonl',
  );
  static const _databaseName = String.fromEnvironment(
    'EVAL_DB_NAME',
    defaultValue: 'offline_eval_runner.sqlite',
  );
  static const _recallK = int.fromEnvironment('EVAL_RECALL_K', defaultValue: 5);
  static const _rankK = int.fromEnvironment('EVAL_RANK_K', defaultValue: 10);
  static const _emitQueryLogs =
      String.fromEnvironment('EVAL_EMIT_QUERY_LOGS', defaultValue: '1') == '1';
  static const _outputJsonPath = String.fromEnvironment(
    'EVAL_OUTPUT_JSON_PATH',
    defaultValue: '',
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final manifest = await _loadManifest(_manifestAsset);
      final evalItems = await _loadEvalItems(_evalsetAsset);
      if (manifest.sources.isEmpty) {
        throw StateError('No sources found in manifest: $_manifestAsset');
      }
      if (evalItems.isEmpty) {
        throw StateError('No eval items found in jsonl: $_evalsetAsset');
      }

      _validateEvalset(manifest, evalItems);

      await MobileRag.initialize(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
        databaseName: _databaseName,
        threadLevel: ThreadUseLevel.low,
      );
      await MobileRag.instance.clearAllData();

      final sourceIdByKey = <String, int>{};
      for (final source in manifest.sources) {
        final bytes = await _loadBytes(source.filePath);
        final text = await _extractDocumentText(source.filePath, bytes);
        final addResult = await MobileRag.instance.addDocument(
          text,
          name: source.sourceKey,
          filePath: source.filePath,
          metadata:
              '{"source_key":"${source.sourceKey}","language":"${source.language}"}',
        );
        sourceIdByKey[source.sourceKey] = addResult.sourceId;
        stdout.writeln(
          'OFFLINE_EVAL_SOURCE '
          'source_key=${source.sourceKey} '
          'source_id=${addResult.sourceId} '
          'is_duplicate=${addResult.isDuplicate ? 1 : 0} '
          'chunk_count=${addResult.chunkCount}',
        );
      }

      await MobileRag.instance.rebuildIndex();

      final topK = math.max(_recallK, _rankK).clamp(1, 100);
      final overall = _MetricAccumulator(recallK: _recallK, rankK: _rankK);
      final positives = _MetricAccumulator(recallK: _recallK, rankK: _rankK);
      final hardNegatives = _MetricAccumulator(
        recallK: _recallK,
        rankK: _rankK,
      );
      final korean = _MetricAccumulator(recallK: _recallK, rankK: _rankK);
      final english = _MetricAccumulator(recallK: _recallK, rankK: _rankK);
      final queryOutcomes = <_QueryOutcome>[];

      stdout.writeln(
        'OFFLINE_EVALSET_INFO '
        'dataset_id=${manifest.datasetId} '
        'schema_version=${manifest.schemaVersion} '
        'sources=${manifest.sources.length} '
        'items=${evalItems.length} '
        'recall_k=$_recallK '
        'rank_k=$_rankK '
        'search_top_k=$topK',
      );

      for (final item in evalItems) {
        final expectedSourceId = sourceIdByKey[item.expectedSourceKey];
        if (expectedSourceId == null) {
          throw StateError(
            'Expected source key not indexed: ${item.expectedSourceKey}',
          );
        }

        final results = await MobileRag.instance.searchHybrid(
          item.query,
          topK: topK,
        );
        final sourceIds = results.map((r) => r.sourceId.toInt()).toList();
        final rank = sourceIds.indexOf(expectedSourceId);

        overall.record(rank);
        if (item.queryType == 'hard_negative') {
          hardNegatives.record(rank);
        } else {
          positives.record(rank);
        }
        if (item.language == 'ko') {
          korean.record(rank);
        } else if (item.language == 'en') {
          english.record(rank);
        }

        final top1SourceId = sourceIds.isEmpty ? -1 : sourceIds.first;
        String? top1SourceKey;
        for (final entry in sourceIdByKey.entries) {
          if (entry.value == top1SourceId) {
            top1SourceKey = entry.key;
            break;
          }
        }
        queryOutcomes.add(
          _QueryOutcome(
            itemId: item.itemId,
            query: item.query,
            queryType: item.queryType,
            language: item.language,
            expectedSourceKey: item.expectedSourceKey,
            expectedSourceId: expectedSourceId,
            rank: rank < 0 ? -1 : rank + 1,
            top1SourceId: top1SourceId,
            top1SourceKey: top1SourceKey ?? 'unknown',
          ),
        );

        if (_emitQueryLogs) {
          stdout.writeln(
            'OFFLINE_EVAL_QUERY '
            'item_id=${item.itemId} '
            'type=${item.queryType} '
            'lang=${item.language} '
            'expected_source_key=${item.expectedSourceKey} '
            'rank=${rank < 0 ? -1 : rank + 1} '
            'top1_source_key=${top1SourceKey ?? 'unknown'} '
            'top1_source_id=$top1SourceId '
            'query="${_clip(item.query, 100)}"',
          );
        }
      }

      _printMetricLine(scope: 'overall', metric: overall);
      _printMetricLine(scope: 'positive', metric: positives);
      _printMetricLine(scope: 'hard_negative', metric: hardNegatives);
      _printMetricLine(scope: 'ko', metric: korean);
      _printMetricLine(scope: 'en', metric: english);

      if (_outputJsonPath.isNotEmpty) {
        await _writeSnapshot(
          outputPath: _outputJsonPath,
          manifest: manifest,
          evalItemCount: evalItems.length,
          sourceIdByKey: sourceIdByKey,
          searchTopK: topK,
          overall: overall,
          positives: positives,
          hardNegatives: hardNegatives,
          korean: korean,
          english: english,
          queryOutcomes: queryOutcomes,
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(0);
    } catch (e, st) {
      stderr.writeln('OFFLINE_EVAL_ERROR $e');
      stderr.writeln(st);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(1);
    }
  }

  Future<_EvalManifest> _loadManifest(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manifest must be a JSON object');
    }
    return _EvalManifest.fromJson(decoded);
  }

  Future<List<_EvalItem>> _loadEvalItems(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final items = <_EvalItem>[];
    for (final line in lines) {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Each JSONL line must be a JSON object');
      }
      items.add(_EvalItem.fromJson(decoded));
    }
    return items;
  }

  void _validateEvalset(_EvalManifest manifest, List<_EvalItem> items) {
    final sourceKeys = manifest.sources.map((s) => s.sourceKey).toSet();
    final itemIds = <String>{};

    for (final item in items) {
      if (!itemIds.add(item.itemId)) {
        throw StateError('Duplicate item_id found: ${item.itemId}');
      }
      if (!sourceKeys.contains(item.expectedSourceKey)) {
        throw StateError(
          'Unknown expected_source_key in eval item ${item.itemId}: '
          '${item.expectedSourceKey}',
        );
      }
      for (final key in item.hardNegativeSourceKeys) {
        if (!sourceKeys.contains(key)) {
          throw StateError(
            'Unknown hard_negative_source_key in eval item ${item.itemId}: $key',
          );
        }
      }
    }
  }

  Future<Uint8List> _loadBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return File(path).readAsBytes();
    }
  }

  Future<String> _extractDocumentText(String path, Uint8List bytes) async {
    final lower = path.toLowerCase();
    final isTextLike =
        lower.endsWith('.md') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');

    if (isTextLike) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    try {
      return await DocumentParser.parse(bytes.toList());
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  Future<void> _writeSnapshot({
    required String outputPath,
    required _EvalManifest manifest,
    required int evalItemCount,
    required Map<String, int> sourceIdByKey,
    required int searchTopK,
    required _MetricAccumulator overall,
    required _MetricAccumulator positives,
    required _MetricAccumulator hardNegatives,
    required _MetricAccumulator korean,
    required _MetricAccumulator english,
    required List<_QueryOutcome> queryOutcomes,
  }) async {
    final file = File(outputPath);
    await file.parent.create(recursive: true);

    final snapshot = <String, dynamic>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'dataset_id': manifest.datasetId,
      'schema_version': manifest.schemaVersion,
      'manifest_asset': _manifestAsset,
      'evalset_asset': _evalsetAsset,
      'database_name': _databaseName,
      'items': evalItemCount,
      'sources': manifest.sources
          .map(
            (s) => {
              'source_key': s.sourceKey,
              'file_path': s.filePath,
              'language': s.language,
              'source_id': sourceIdByKey[s.sourceKey],
            },
          )
          .toList(),
      'recall_k': _recallK,
      'rank_k': _rankK,
      'search_top_k': searchTopK,
      'metrics': {
        'overall': overall.toJson(),
        'positive': positives.toJson(),
        'hard_negative': hardNegatives.toJson(),
        'ko': korean.toJson(),
        'en': english.toJson(),
      },
      'query_outcomes': queryOutcomes.map((q) => q.toJson()).toList(),
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot),
      flush: true,
    );

    stdout.writeln(
      'OFFLINE_EVAL_SNAPSHOT path=$outputPath items=${queryOutcomes.length}',
    );
  }

  void _printMetricLine({
    required String scope,
    required _MetricAccumulator metric,
  }) {
    stdout.writeln(
      'OFFLINE_EVAL_RESULT '
      'scope=$scope '
      'total=${metric.total} '
      'recall_at_${metric.recallK}=${metric.recallAtK.toStringAsFixed(6)} '
      'mrr_at_${metric.rankK}=${metric.mrrAtK.toStringAsFixed(6)} '
      'ndcg_at_${metric.rankK}=${metric.ndcgAtK.toStringAsFixed(6)}',
    );
  }

  String _clip(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Running offline evaluation...')),
      ),
    );
  }
}

class _EvalManifest {
  final String datasetId;
  final int schemaVersion;
  final List<_EvalSource> sources;

  const _EvalManifest({
    required this.datasetId,
    required this.schemaVersion,
    required this.sources,
  });

  factory _EvalManifest.fromJson(Map<String, dynamic> json) {
    final sourceRaw = json['sources'];
    if (sourceRaw is! List) {
      throw const FormatException('"sources" must be a list');
    }
    return _EvalManifest(
      datasetId: json['dataset_id'] as String? ?? 'unknown',
      schemaVersion: json['schema_version'] as int? ?? 0,
      sources: sourceRaw
          .map((e) => _EvalSource.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _EvalSource {
  final String sourceKey;
  final String filePath;
  final String language;

  const _EvalSource({
    required this.sourceKey,
    required this.filePath,
    required this.language,
  });

  factory _EvalSource.fromJson(Map<String, dynamic> json) => _EvalSource(
    sourceKey: json['source_key'] as String,
    filePath: json['file_path'] as String,
    language: json['language'] as String? ?? 'unknown',
  );
}

class _EvalItem {
  final String itemId;
  final String query;
  final String language;
  final String queryType;
  final String expectedSourceKey;
  final List<String> hardNegativeSourceKeys;

  const _EvalItem({
    required this.itemId,
    required this.query,
    required this.language,
    required this.queryType,
    required this.expectedSourceKey,
    required this.hardNegativeSourceKeys,
  });

  factory _EvalItem.fromJson(Map<String, dynamic> json) {
    final hardNegRaw = json['hard_negative_source_keys'];
    final hardNegKeys = hardNegRaw is List
        ? hardNegRaw.map((e) => e.toString()).toList()
        : <String>[];

    return _EvalItem(
      itemId: json['item_id'] as String,
      query: json['query'] as String,
      language: json['language'] as String? ?? 'unknown',
      queryType: json['query_type'] as String? ?? 'positive',
      expectedSourceKey: json['expected_source_key'] as String,
      hardNegativeSourceKeys: hardNegKeys,
    );
  }
}

class _MetricAccumulator {
  final int recallK;
  final int rankK;

  int total = 0;
  double _recallHits = 0;
  double _mrrSum = 0;
  double _ndcgSum = 0;

  _MetricAccumulator({required this.recallK, required this.rankK});

  void record(int zeroBasedRank) {
    total++;

    if (zeroBasedRank < 0) {
      return;
    }

    final rank = zeroBasedRank + 1;
    if (rank <= recallK) {
      _recallHits += 1;
    }
    if (rank <= rankK) {
      _mrrSum += 1 / rank;
      _ndcgSum += 1 / (math.log(rank + 1) / math.log(2));
    }
  }

  double get recallAtK => total == 0 ? 0 : _recallHits / total;

  double get mrrAtK => total == 0 ? 0 : _mrrSum / total;

  double get ndcgAtK => total == 0 ? 0 : _ndcgSum / total;

  Map<String, dynamic> toJson() => {
    'total': total,
    'recall_at_$recallK': recallAtK,
    'mrr_at_$rankK': mrrAtK,
    'ndcg_at_$rankK': ndcgAtK,
  };
}

class _QueryOutcome {
  final String itemId;
  final String query;
  final String queryType;
  final String language;
  final String expectedSourceKey;
  final int expectedSourceId;
  final int rank;
  final int top1SourceId;
  final String top1SourceKey;

  const _QueryOutcome({
    required this.itemId,
    required this.query,
    required this.queryType,
    required this.language,
    required this.expectedSourceKey,
    required this.expectedSourceId,
    required this.rank,
    required this.top1SourceId,
    required this.top1SourceKey,
  });

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'query': query,
    'query_type': queryType,
    'language': language,
    'expected_source_key': expectedSourceKey,
    'expected_source_id': expectedSourceId,
    'rank': rank,
    'top1_source_id': top1SourceId,
    'top1_source_key': top1SourceKey,
  };
}
