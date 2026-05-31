import 'dart:convert';
import 'package:mobile_rag_engine/services/benchmark_service.dart';
import 'package:mobile_rag_engine/models/benchmark_models.dart';

/// Per-segment sample collector; defers stats to BenchmarkService.summarizeSamples.
class SegmentSamples {
  final String segment;
  final List<double> samplesMs = [];
  SegmentSamples(this.segment);
  void add(double ms) => samplesMs.add(ms);
  void addAll(Iterable<double> ms) => samplesMs.addAll(ms);

  DetailedBenchmarkStats stats() =>
      BenchmarkService.summarizeSamples(samplesMs, warmupIterations: 0);

  Map<String, dynamic> toJson() {
    final s = stats();
    return {'segment': segment, ...s.toJson()};
  }
}

/// One scenario run: a (lane, category) cell with its measured segments.
class QueryProfileRun {
  final String lane;       // 'unfiltered' | 'filtered'
  final String category;   // 'pure_cold' | 'switching_cold' | 'pure_warm'
  final Map<String, SegmentSamples> segments;
  final Map<String, Object?> io;   // query_metrics snapshot
  final Map<String, Object?> meta; // device/config

  QueryProfileRun({
    required this.lane, required this.category,
    required this.segments, required this.io, required this.meta,
  });

  /// FFI marshalling + isolate context-switch cost = Dart-measured - Rust-internal.
  /// Clamped to 0 (clock noise can make it slightly negative).
  static double ffiOverheadMs({required double dartMs, required double rustInternalMs}) {
    final d = dartMs - rustInternalMs;
    return d > 0 ? d : 0.0;
  }

  Map<String, dynamic> toJson() => {
    'lane': lane,
    'category': category,
    'segments': segments.map((k, v) => MapEntry(k, v.toJson())),
    'io': io,
    'meta': meta,
  };
}

class QueryProfileReport {
  final List<QueryProfileRun> runs;
  QueryProfileReport({required this.runs});

  Map<String, dynamic> toJson() => {'runs': runs.map((r) => r.toJson()).toList()};
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toCsv() {
    final b = StringBuffer()
      ..writeln('lane,category,segment,p50_ms,p95_ms,avg_ms,min_ms,max_ms,stddev_ms,n');
    for (final r in runs) {
      for (final seg in r.segments.values) {
        final s = seg.stats();
        b.writeln('${r.lane},${r.category},${seg.segment},'
            '${s.p50Ms},${s.p95Ms},${s.avgMs},${s.minMs},${s.maxMs},${s.stdDevMs},'
            '${s.measuredIterations}');
      }
    }
    return b.toString();
  }
}
