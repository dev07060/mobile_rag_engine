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
