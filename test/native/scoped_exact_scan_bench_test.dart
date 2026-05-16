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

  test('scoped exact-scan uses indexed BM25 without content reads', () async {
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

      // bm25_weight=0 → BM25 contributes nothing, so no content is read.
      final smallZero = small.variants[0];
      expect(smallZero.nativeScopedExactScanRows, 0);
      expect(smallZero.nativeScopedExactScanContentBytes, 0);
      expect(smallZero.nativeScopedExactScanTokenizedRows, 0);
      expect(smallZero.nativeScopedExactScanTokenizedContentBytes, 0);
      expect(smallZero.nativeScopedExactScanTokens, 0);
      expect(smallZero.nativeScopedExactScanTokenizationNanos, 0);

      // bm25_weight>0 → BM25 ranks come from the active in-memory term index,
      // so query-time scoped scan still avoids body reads and tokenization.
      final smallBm25 = small.variants[1];
      expect(smallBm25.nativeScopedExactScanRows, 0);
      expect(smallBm25.nativeScopedExactScanContentBytes, 0);
      expect(smallBm25.nativeScopedExactScanTokenizedRows, 0);
      expect(smallBm25.nativeScopedExactScanTokenizedContentBytes, 0);
      expect(smallBm25.nativeScopedExactScanTokens, 0);
      expect(smallBm25.nativeScopedExactScanTokenizationNanos, 0);

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
      expect(largeZero.nativeScopedExactScanTokenizedRows, 0);
      expect(largeZero.nativeScopedExactScanTokenizedContentBytes, 0);
      expect(largeZero.nativeScopedExactScanTokens, 0);
      expect(largeZero.nativeScopedExactScanTokenizationNanos, 0);

      final largeBm25 = large.variants[1];
      expect(largeBm25.nativeScopedExactScanRows, 0);
      expect(largeBm25.nativeScopedExactScanContentBytes, 0);
      expect(largeBm25.nativeScopedExactScanTokenizedRows, 0);
      expect(largeBm25.nativeScopedExactScanTokenizedContentBytes, 0);
      expect(largeBm25.nativeScopedExactScanTokens, 0);
      expect(largeBm25.nativeScopedExactScanTokenizationNanos, 0);

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
