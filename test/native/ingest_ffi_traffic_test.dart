import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/benchmark_service.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:mobile_rag_engine/src/rust/api/ingest_session.dart'
    as ingest_session;
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as source_rag;
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

  test('PreparedIngestion reports body byte and text lengths', () async {
    final dir = await Directory.systemTemp.createTemp(
      'mobile_rag_body_length_',
    );
    var poolOpen = false;
    try {
      final dbPath = '${dir.path}/body_length.sqlite';
      await initDbPool(dbPath: dbPath, maxSize: 4);
      poolOpen = true;
      await initDb();
      await source_rag.initSourceDb();

      const text = '보험 약관 test 😀';
      final file = File('${dir.path}/body.txt');
      await file.writeAsString(text, flush: true);

      final prepared = await ingest_session.prepareSourceIngestionFromFile(
        collectionId: 'body-length',
        filePath: file.path,
        metadata: null,
        name: 'body.txt',
        strategyHint: ingest_session.IngestStrategy.recursive,
        maxChars: 1500,
        overlapChars: 0,
      );

      expect(prepared.bodyByteLength, utf8.encode(text).length);
      expect(prepared.bodyCharLength, text.length);

      final session = prepared.session;
      if (session != null) {
        await session.abort();
        await session.dispose();
      }
    } finally {
      if (poolOpen) {
        try {
          await closeDbPool();
        } catch (_) {}
      }
      await dir.delete(recursive: true);
    }
  });

  test(
    'Peak-RSS delta: from_file < from_utf8 / string (heap pass-through)',
    () async {
      // Empirically check that the file-path variant avoids holding the
      // document body on the Dart side. The String/UTF-8 variants both
      // carry the body in Dart memory before passing it to Rust, so their
      // peak RSS delta should be markedly higher than the file variant.
      //
      // RSS is noisy at full-process granularity, so this test asserts an
      // ORDERING + magnitude floor rather than exact byte counts. A 4 MB
      // doc gives enough signal to clear the noise floor on a hot run.
      if (ProcessInfo.currentRss < 0) {
        // ignore: avoid_print
        print('Skipping: ProcessInfo.currentRss unsupported on this platform');
        return;
      }
      final dir = await Directory.systemTemp.createTemp(
        'mobile_rag_heap_bench_',
      );
      try {
        final result = await BenchmarkService.benchmarkIngestHeap(
          targetBytes: 4 * 1024 * 1024,
          maxChunkChars: 1500,
          overlapChars: 0,
          batchSize: 16,
          dbPathOverride: '${dir.path}/heap_bench.sqlite',
        );

        // The file path holds at most a few KB on the Dart side (path
        // string + chunk dispatch buffers). The String / UTF-8 paths must
        // hold the full body (~4 MB) before handing it to Rust. So the
        // string/utf8 deltas should exceed the file delta by at least
        // half the doc size to clear noise.
        final docHalf = result.docBytes ~/ 2;
        expect(
          result.stringPathPeakDeltaBytes - result.filePathPeakDeltaBytes,
          greaterThan(docHalf),
          reason:
              'String path should hold the doc body in Dart, raising peak RSS '
              'by at least half of docBytes vs file path. '
              'string=${result.stringPathPeakDeltaBytes}B, '
              'file=${result.filePathPeakDeltaBytes}B, '
              'docBytes=${result.docBytes}',
        );
        expect(
          result.utf8PathPeakDeltaBytes - result.filePathPeakDeltaBytes,
          greaterThan(docHalf),
          reason:
              'UTF-8 path should hold the doc bytes in Dart, raising peak RSS '
              'by at least half of docBytes vs file path. '
              'utf8=${result.utf8PathPeakDeltaBytes}B, '
              'file=${result.filePathPeakDeltaBytes}B, '
              'docBytes=${result.docBytes}',
        );

        // ignore: avoid_print
        print(result.renderSummary());
      } finally {
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Wall-clock latency: from_file is fastest, from_utf8 ≤ string',
    () async {
      // Stub-embedding latency measurement: with ONNX cost removed, the
      // residual is FFI + Rust-side staging. from_file does the file I/O
      // in Rust (skipping one boundary crossing); from_utf8 skips the Dart
      // String materialization; the canonical String path bears both.
      //
      // Loose assertion: file p50 should not be slower than string p50 by
      // more than 25%, and ideally is faster. We assert "file ≤ string ×
      // 1.25" rather than strict inequality to absorb scheduler jitter on
      // CI hosts where the absolute numbers are tiny (single-digit ms).
      final dir = await Directory.systemTemp.createTemp(
        'mobile_rag_latency_bench_',
      );
      try {
        final result = await BenchmarkService.benchmarkIngestLatency(
          targetBytes: 1 * 1024 * 1024,
          maxChunkChars: 1500,
          overlapChars: 0,
          batchSize: 16,
          warmupRuns: 2,
          measuredRuns: 5,
          dbPathOverride: '${dir.path}/latency_bench.sqlite',
        );

        // ignore: avoid_print
        print(result.renderSummary());

        // Loose ordering check: file path must not be materially slower
        // than the string path. The expected gain is small (single-digit
        // ms or sub-ms on hot caches with stub embeddings) so we tolerate
        // 25% noise.
        expect(
          result.fileP50Ms,
          lessThanOrEqualTo(result.stringP50Ms * 1.25),
          reason: 'file p50 should not be >25% slower than string p50. '
              'file=${result.fileP50Ms.toStringAsFixed(2)}ms, '
              'string=${result.stringP50Ms.toStringAsFixed(2)}ms',
        );
        expect(
          result.utf8P50Ms,
          lessThanOrEqualTo(result.stringP50Ms * 1.25),
          reason: 'utf8 p50 should not be >25% slower than string p50. '
              'utf8=${result.utf8P50Ms.toStringAsFixed(2)}ms, '
              'string=${result.stringP50Ms.toStringAsFixed(2)}ms',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
