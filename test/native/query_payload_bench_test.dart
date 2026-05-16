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

  test('query payload baseline: full > preview > contextOnly', () async {
    final dir = await Directory.systemTemp.createTemp(
      'mobile_rag_query_payload_',
    );
    try {
      final result = await BenchmarkService.benchmarkQueryPayload(
        topK: 4,
        adjacentChunks: 1,
        previewMaxBytes: 24,
        dbPathOverride: '${dir.path}/query_payload_bench.sqlite',
      );

      expect(result.legacySearchHybrid.hitCount, greaterThan(0));
      expect(result.legacySearchHybrid.fullChunkBytes, greaterThan(0));
      expect(result.legacySearchHybrid.nativeHybridResultRows, greaterThan(0));
      expect(result.legacySearchHybrid.nativeFullHydrateRows, 0);
      expect(result.legacySearchHybrid.nativePreviewRows, 0);
      expect(result.legacySearchHybrid.nativeAssemblyRows, 0);
      expect(result.legacySearchHybrid.nativeUnclassifiedRows, 0);

      expect(result.handleFull.hitCount, greaterThanOrEqualTo(4));
      expect(result.handleFull.contextBytes, greaterThan(0));
      expect(result.handleFull.fullChunkBytes, greaterThan(0));
      // search_meta_hybrid no longer materializes HybridSearchResult.content.
      expect(result.handleFull.nativeHybridResultRows, 0);
      expect(result.handleFull.nativeHybridResultContentBytes, 0);
      expect(result.handleFull.nativeAssemblyRows, greaterThan(0));
      expect(result.handleFull.nativeFullHydrateRows, greaterThan(0));
      expect(result.handleFull.nativePreviewRows, 0);
      expect(result.handleFull.nativeUnclassifiedRows, 0);

      expect(result.handlePreview.contextBytes, result.handleFull.contextBytes);
      expect(result.handlePreview.previewBytes, greaterThan(0));
      expect(
        result.handlePreview.previewBytes,
        lessThan(result.handleFull.fullChunkBytes),
      );
      expect(result.handlePreview.nativeHybridResultRows, 0);
      expect(result.handlePreview.nativeHybridResultContentBytes, 0);
      expect(result.handlePreview.nativeAssemblyRows, greaterThan(0));
      expect(result.handlePreview.nativeFullHydrateRows, 0);
      expect(result.handlePreview.nativePreviewRows, greaterThan(0));
      expect(result.handlePreview.nativeUnclassifiedRows, 0);

      expect(
        result.handleContextOnly.contextBytes,
        result.handleFull.contextBytes,
      );
      expect(result.handleContextOnly.fullChunkBytes, 0);
      expect(result.handleContextOnly.previewBytes, 0);
      expect(result.handleContextOnly.nativeHybridResultRows, 0);
      expect(result.handleContextOnly.nativeHybridResultContentBytes, 0);
      expect(result.handleContextOnly.nativeAssemblyRows, greaterThan(0));
      expect(result.handleContextOnly.nativeFullHydrateRows, 0);
      expect(result.handleContextOnly.nativePreviewRows, 0);
      expect(result.handleContextOnly.nativeUnclassifiedRows, 0);
      expect(
        result.handleContextOnly.totalStringBytes,
        lessThan(result.handlePreview.totalStringBytes),
      );
      expect(
        result.handlePreview.totalStringBytes,
        lessThan(result.handleFull.totalStringBytes),
      );

      // ignore: avoid_print
      print(result.renderSummary());
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
