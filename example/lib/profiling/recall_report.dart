import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One query's recall outcome. `recallVectorOnly` compares f32 GT against the
/// shipped vector-only search path; `recallHybrid` compares f32 GT against the
/// default hybrid BM25/RRF search path.
class RecallQueryResult {
  final int queryIndex;
  final String query;
  final double recallVectorOnly;
  final double recallHybrid;

  const RecallQueryResult({
    required this.queryIndex,
    required this.query,
    required this.recallVectorOnly,
    required this.recallHybrid,
  });

  Map<String, Object?> toJson() => {
        'query_index': queryIndex,
        'query': query,
        'recall_vectoronly@10': recallVectorOnly,
        'recall_hybrid@10': recallHybrid,
      };
}

class RecallReport {
  final List<RecallQueryResult> results;
  final Map<String, Object?> meta;

  const RecallReport({required this.results, required this.meta});

  double get meanVectorOnly => _mean((result) => result.recallVectorOnly);
  double get meanHybrid => _mean((result) => result.recallHybrid);

  double _mean(double Function(RecallQueryResult result) select) {
    if (results.isEmpty) return 0.0;
    return results.map(select).reduce((a, b) => a + b) / results.length;
  }

  Map<String, Object?> toJson() => {
        'mean_recall_vectoronly@10': meanVectorOnly,
        'mean_recall_hybrid@10': meanHybrid,
        'results': [for (final result in results) result.toJson()],
        'meta': meta,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toCsv() {
    final buffer = StringBuffer()
      ..writeln('query_index,query,recall_vectoronly@10,recall_hybrid@10');
    for (final result in results) {
      buffer.writeln(
        '${result.queryIndex},${result.query},'
        '${result.recallVectorOnly},${result.recallHybrid}',
      );
    }
    return buffer.toString();
  }
}

/// Writes recall JSON/CSV to the app documents dir and prints greppable lines.
class RecallExport {
  static Future<String> write(
    RecallReport report, {
    required String tsTag,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final base = '${dir.path}/query_recall_$tsTag';

    await File('$base.json').writeAsString(report.toJsonString(), flush: true);
    await File('$base.csv').writeAsString(report.toCsv(), flush: true);

    for (final line in report.toCsv().trimRight().split('\n')) {
      // ignore: avoid_print
      print('RECALL_CSV $line');
    }
    // ignore: avoid_print
    print('RECALL_EXPORT_DIR ${dir.path}');
    return dir.path;
  }
}
