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

  test('FFI text traffic: IngestSession is roughly 50% of legacy', () async {
    final dir = await Directory.systemTemp.createTemp('mobile_rag_ffi_bench_');
    try {
      // Use overlap=0 to isolate the "chunk-body round-trip" cost from the
      // overlap-induced inflation (chunks with overlap repeat ~overlap_chars
      // of content per boundary, inflating both chunker-out and add_chunks-in
      // proportionally; the *ratio* is preserved but the absolute multiples
      // drift above the clean analytical numbers).
      final result = await BenchmarkService.benchmarkIngestFfiTraffic(
        targetBytes: 256 * 1024, // 256 KB — large enough for many chunks, fast enough for CI
        maxChunkChars: 1500,
        overlapChars: 0,
        batchSize: 16,
        dbPathOverride: '${dir.path}/ffi_bench.sqlite',
      );

      // Document sanity: should produce multiple chunks at 1500 char max.
      expect(
        result.chunkCount,
        greaterThan(50),
        reason: 'A 256 KB doc should split into many chunks',
      );

      // Legacy chain — analytical claim is ~4× document body across FFI:
      //   add_source_in (1×) + chunker text in (1×)
      //   + chunker chunks out (~1×) + add_chunks in (~1×).
      // Tolerance: chunker output rounds chunk boundaries on whitespace so
      // the chunks-out / add-chunks-in totals are a few % above 1× each.
      expect(
        result.legacyMultiple,
        greaterThan(3.9),
        reason: 'Legacy chain should be ~4× document size; '
            'got ${result.legacyMultiple.toStringAsFixed(2)}×',
      );
      expect(
        result.legacyMultiple,
        lessThan(4.2),
        reason: 'Legacy chain should be ~4× document size; '
            'got ${result.legacyMultiple.toStringAsFixed(2)}×',
      );

      // IngestSession chain — analytical claim is ~2× document body:
      //   prepare content in (1×) + embedding_text out (~1×).
      expect(
        result.sessionMultiple,
        greaterThan(1.9),
        reason: 'IngestSession should be ~2× document size; '
            'got ${result.sessionMultiple.toStringAsFixed(2)}×',
      );
      expect(
        result.sessionMultiple,
        lessThan(2.2),
        reason: 'IngestSession should be ~2× document size; '
            'got ${result.sessionMultiple.toStringAsFixed(2)}×',
      );

      // Combined: session must shave at least 45% off legacy traffic.
      expect(
        result.reductionRatio,
        lessThan(0.55),
        reason: 'Session should cut legacy FFI text traffic by ≥45%; '
            'session/legacy = ${result.reductionRatio.toStringAsFixed(2)}',
      );

      // Also assert per-counter sanity so a regression localizes the cause.
      // Each side records exactly one prepare/add_source call for the doc.
      expect(result.legacy.legacyAddSourceInCalls.toInt(), 1);
      expect(result.legacy.legacyChunkerTextInCalls.toInt(), 1);
      expect(result.session.sessionPrepareContentInCalls.toInt(), 1);
      // IngestSession path should not have triggered any legacy counters.
      expect(result.session.legacyAddSourceInBytes.toInt(), 0);
      expect(result.session.legacyChunkerTextInBytes.toInt(), 0);
      expect(result.session.legacyChunkerChunksOutBytes.toInt(), 0);
      expect(result.session.legacyAddChunksInBytes.toInt(), 0);

      // Print the human-readable summary so it shows up in the test log.
      // ignore: avoid_print
      print(result.renderSummary());
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'FFI text traffic: from_utf8 / from_file deliver promised pass-through',
    () async {
      // Locks in the claim that:
      //   - prepareSourceIngestion(String):   prepare_in == doc body bytes
      //   - prepareSourceIngestionFromUtf8:   prepare_in == doc body bytes
      //     (same FFI traffic, but Dart heap allocation is avoided —
      //     measurable only at runtime, not in counters)
      //   - prepareSourceIngestionFromFile:   prepare_in == 0
      //     (body never crosses FFI; only the path string does)
      final dir = await Directory.systemTemp.createTemp(
        'mobile_rag_ffi_entrypoints_',
      );
      try {
        final result = await BenchmarkService.benchmarkIngestFfiEntrypoints(
          targetBytes: 256 * 1024,
          maxChunkChars: 1500,
          overlapChars: 0,
          batchSize: 16,
          dbPathOverride: '${dir.path}/ffi_entrypoints_bench.sqlite',
        );

        // String entrypoint records full body once.
        expect(
          result.stringPrepareInBytes,
          result.docBytes,
          reason: 'String path should record exactly docBytes into '
              'session_prepare_content_in_bytes; got '
              '${result.stringPrepareInBytes} vs docBytes=${result.docBytes}',
        );

        // UTF-8 entrypoint records the same byte count: bytes flow straight
        // into Rust without a Dart String round-trip.
        expect(
          result.utf8PrepareInBytes,
          result.docBytes,
          reason: 'UTF-8 path should record exactly docBytes into '
              'session_prepare_content_in_bytes; got '
              '${result.utf8PrepareInBytes} vs docBytes=${result.docBytes}',
        );

        // File entrypoint records ZERO: the body never crosses FFI.
        expect(
          result.filePrepareInBytes,
          0,
          reason: 'File path must not credit body bytes to '
              'session_prepare_content_in_bytes; the body never crosses FFI. '
              'Got ${result.filePrepareInBytes}',
        );

        // ignore: avoid_print
        print(result.renderSummary());
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
