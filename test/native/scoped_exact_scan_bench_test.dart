import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/benchmark_service.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';

Future<void> _ensureRustLoaded() async {
  if (!RustLib.instance.initialized) {
    await RustLib.init();
  }
}

void main() {
  setUpAll(() async {
    await _ensureRustLoaded();
  });

  test('scoped exact-scan elides content when bm25_weight is 0', () async {
    final dir = await Directory.systemTemp.createTemp(
      'mobile_rag_scoped_exact_scan_',
    );
    try {
      const chunkBytes = 256;

      final small = await BenchmarkService.benchmarkScopedExactScan(
        scopedChunkCount: 50,
        distractorChunkCount: 10,
        chunkContentChars: chunkBytes,
        topK: 4,
        bm25Weights: const [0.0, 0.5],
        dbPathOverride: '${dir.path}/scoped_50.sqlite',
      );

      expect(small.variants, hasLength(2));

      // bm25_weight=0 → SELECT elides c.content, counter stays at 0.
      final smallZero = small.variants[0];
      expect(smallZero.nativeScopedExactScanRows, 0);
      expect(smallZero.nativeScopedExactScanContentBytes, 0);

      // bm25_weight>0 → every scoped chunk body is read.
      final smallBm25 = small.variants[1];
      expect(smallBm25.nativeScopedExactScanRows, small.scopedChunkCount);
      expect(
        smallBm25.nativeScopedExactScanContentBytes,
        greaterThanOrEqualTo(small.scopedChunkCount * chunkBytes),
      );

      final large = await BenchmarkService.benchmarkScopedExactScan(
        scopedChunkCount: 500,
        distractorChunkCount: 10,
        chunkContentChars: chunkBytes,
        topK: 4,
        bm25Weights: const [0.0, 0.5],
        dbPathOverride: '${dir.path}/scoped_500.sqlite',
      );

      expect(large.variants, hasLength(2));
      final largeZero = large.variants[0];
      expect(largeZero.nativeScopedExactScanRows, 0);
      expect(largeZero.nativeScopedExactScanContentBytes, 0);

      final largeBm25 = large.variants[1];
      expect(largeBm25.nativeScopedExactScanRows, large.scopedChunkCount);
      expect(
        largeBm25.nativeScopedExactScanContentBytes,
        greaterThanOrEqualTo(large.scopedChunkCount * chunkBytes),
      );

      // 10× scope → ≥ 10× scoped-scan bytes for the bm25-on path.
      expect(
        largeBm25.nativeScopedExactScanContentBytes,
        greaterThanOrEqualTo(smallBm25.nativeScopedExactScanContentBytes * 10),
      );

      // searchMetaHybrid is meta-only: no result body is materialized.
      for (final v in [...small.variants, ...large.variants]) {
        expect(v.nativeHybridResultContentBytes, 0);
        expect(v.nativeFullHydrateContentBytes, 0);
      }

      // ignore: avoid_print
      print(small.renderSummary());
      // ignore: avoid_print
      print(large.renderSummary());
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
