import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/rss_sampler.dart';

void main() {
  test('tracker records start, end, peak, delta, and samples', () {
    final values = [100, 130, 120];
    final sampler = RssSampler(readRssBytes: () => values.removeAt(0));

    final tracker = sampler.start();
    tracker.sample();
    tracker.sample();
    final summary = tracker.finish();

    expect(summary.startBytes, 100);
    expect(summary.endBytes, 120);
    expect(summary.peakBytes, 130);
    expect(summary.deltaBytes, 20);
    expect(summary.samplesBytes, [100, 130, 120]);
  });

  test('summary serializes with a stable prefix', () {
    final sampler = RssSampler(readRssBytes: () => 2048);

    final summary = sampler.start().finish();

    expect(summary.toJson(prefix: 'rss'), {
      'rss_start_bytes': 2048,
      'rss_end_bytes': 2048,
      'rss_peak_bytes': 2048,
      'rss_delta_bytes': 0,
      'rss_samples_bytes': [2048],
    });
  });
}
