import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/query_profile_report.dart';

void main() {
  test('SegmentSamples aggregates and serializes', () {
    final seg = SegmentSamples('embed')..addAll([10, 12, 11, 13, 9]);
    final j = seg.toJson();
    expect(j['segment'], 'embed');
    expect(j['p50_ms'], isNotNull);
    expect((j['samples_ms'] as List).length, 5);
  });

  test('ffiOverheadMs = dart segment minus rust internal', () {
    expect(QueryProfileRun.ffiOverheadMs(dartMs: 5.0, rustInternalMs: 3.2), closeTo(1.8, 1e-6));
    expect(QueryProfileRun.ffiOverheadMs(dartMs: 3.0, rustInternalMs: 3.4), 0.0);
  });

  test('empty SegmentSamples serializes to zero stats', () {
    final seg = SegmentSamples('embed');
    final j = seg.toJson();
    expect(j['segment'], 'embed');
    expect(j['p50_ms'], 0.0);
    expect((j['samples_ms'] as List).isEmpty, true);
  });

  test('report toCsv has one row per (lane,category,segment) + toJson', () {
    final run = QueryProfileRun(
      lane: 'unfiltered', category: 'pure_warm',
      segments: {
        'embed': SegmentSamples('embed')..addAll([10, 11]),
        'search': SegmentSamples('search')..addAll([2, 3]),
      },
      io: const {'scoped_exact_scan_rows': 0},
      meta: const {'device': 'test'},
    );
    final report = QueryProfileReport(runs: [run]);
    final csv = report.toCsv();
    expect(csv, contains('lane,category,segment,p50_ms,p95_ms,avg_ms,min_ms,max_ms,stddev_ms,n'));
    expect(csv, contains('unfiltered,pure_warm,embed,'));
    expect(csv, contains('unfiltered,pure_warm,search,'));
    expect((report.toJson()['runs'] as List).length, 1);
  });
}
