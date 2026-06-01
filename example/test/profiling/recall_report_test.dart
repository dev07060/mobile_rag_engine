import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/recall_report.dart';

void main() {
  final report = RecallReport(
    meta: {'k': 10, 'collection': 'profile_a'},
    results: const [
      RecallQueryResult(
        queryIndex: 0,
        query: 'a',
        recallVectorOnly: 1.0,
        recallHybrid: 0.8,
      ),
      RecallQueryResult(
        queryIndex: 1,
        query: 'b',
        recallVectorOnly: 0.9,
        recallHybrid: 0.7,
      ),
    ],
  );

  test('means average each metric across queries', () {
    expect(report.meanVectorOnly, closeTo(0.95, 1e-9));
    expect(report.meanHybrid, closeTo(0.75, 1e-9));
  });

  test('toJson includes per-query results, means, and meta', () {
    final json = report.toJson();

    expect((json['results'] as List).length, 2);
    expect(json['mean_recall_vectoronly@10'], closeTo(0.95, 1e-9));
    expect(json['mean_recall_hybrid@10'], closeTo(0.75, 1e-9));
    expect((json['meta'] as Map)['collection'], 'profile_a');
  });

  test('toCsv has header and one row per query', () {
    final lines = report.toCsv().trim().split('\n');

    expect(
      lines.first,
      'query_index,query,recall_vectoronly@10,recall_hybrid@10',
    );
    expect(lines.length, 3);
    expect(lines[1], '0,a,1.0,0.8');
  });
}
