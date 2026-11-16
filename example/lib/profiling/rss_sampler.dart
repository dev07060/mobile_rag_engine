import 'dart:async';
import 'dart:io';

typedef RssReader = int Function();

class RssSampler {
  final RssReader _readRssBytes;

  RssSampler({RssReader? readRssBytes})
      : _readRssBytes = readRssBytes ?? (() => ProcessInfo.currentRss);

  RssTracker start() {
    final tracker = RssTracker._(_readRssBytes);
    tracker.sample();
    return tracker;
  }
}

class RssTracker {
  final RssReader _readRssBytes;
  final List<int> _samplesBytes = [];

  RssTracker._(this._readRssBytes);

  int sample() {
    final value = _readRssBytes();
    _samplesBytes.add(value);
    return value;
  }

  RssSummary finish() {
    if (_samplesBytes.isEmpty) {
      sample();
    }
    return RssSummary(samplesBytes: List.unmodifiable(_samplesBytes));
  }
}

class RssSummary {
  final List<int> samplesBytes;

  const RssSummary({required this.samplesBytes});

  int get startBytes => samplesBytes.first;
  int get endBytes => samplesBytes.last;
  int get peakBytes => samplesBytes.reduce((a, b) => a > b ? a : b);
  int get deltaBytes => endBytes - startBytes;

  Map<String, Object?> toJson({String prefix = 'rss'}) => {
        '${prefix}_start_bytes': startBytes,
        '${prefix}_end_bytes': endBytes,
        '${prefix}_peak_bytes': peakBytes,
        '${prefix}_delta_bytes': deltaBytes,
        '${prefix}_samples_bytes': samplesBytes,
      };
}

/// Samples RSS on a timer while async work runs (FFI calls run off the main
/// isolate's event loop, so the timer keeps firing), plus the process
/// high-water mark ([ProcessInfo.maxRss]) at the end.
class PeriodicRss {
  PeriodicRss._(this._tracker, this._timer);

  final RssTracker _tracker;
  final Timer _timer;

  static PeriodicRss start({
    Duration every = const Duration(milliseconds: 50),
    RssSampler? sampler,
  }) {
    final tracker = (sampler ?? RssSampler()).start();
    final timer = Timer.periodic(every, (_) => tracker.sample());
    return PeriodicRss._(tracker, timer);
  }

  /// Stops the timer. Peak covers the timer samples, not every allocation.
  Map<String, Object?> finish({required String prefix}) {
    _timer.cancel();
    _tracker.sample();
    final s = _tracker.finish();
    return {
      '${prefix}_start_bytes': s.startBytes,
      '${prefix}_end_bytes': s.endBytes,
      '${prefix}_peak_bytes': s.peakBytes,
      '${prefix}_sample_count': s.samplesBytes.length,
      '${prefix}_process_max_rss_bytes': ProcessInfo.maxRss,
    };
  }
 }
