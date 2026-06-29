import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/activation_metrics.dart' as am;
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/runtime_info.dart'
    as runtime_info;
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/rust_library_loader.dart';
import 'package:mobile_rag_engine_example/profiling/native_runtime_expectations.dart';
import 'package:mobile_rag_engine_example/profiling/rss_sampler.dart';

// Allocator-sensitive indexing/reindexing macro for mimalloc A/B validation.
//
// This intentionally bypasses ONNX embedding and seeds deterministic stub
// embeddings through the low-level Rust API. Seed time is logged but excluded
// from the allocator decision; the measured cell is BM25/HNSW rebuild + save.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const expectedNativeAllocator = String.fromEnvironment(
    'EXPECTED_NATIVE_ALLOCATOR',
  );
  const expectedRustFeatures = String.fromEnvironment('EXPECTED_RUST_FEATURES');
  const textMbCsv = String.fromEnvironment(
    'ALLOCATOR_INDEXING_TEXT_MB',
    defaultValue: '5,10,25',
  );
  final textCases = _parseTextMbCases(textMbCsv);

  tearDown(() async {
    try {
      await closeDbPool();
    } catch (_) {}
  });

  test(
    'allocator indexing macro: deterministic BM25/HNSW rebuild cells',
    () async {
      _assertProfileMode();

      await initRustLibForPlatform();

      final nativeInfo = runtime_info.nativeRuntimeInfo();
      verifyNativeRuntimeExpectations(
        actualAllocator: nativeInfo.nativeAllocator,
        actualRustFeatures: nativeInfo.rustFeatures,
        expectedAllocator: expectedNativeAllocator,
        expectedRustFeatures: expectedRustFeatures,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final dbStem = '${docsDir.path}/allocator_indexing.sqlite';
      final exportFile = File(
        '${docsDir.path}/allocator_indexing_profile_latest.jsonl',
      );
      if (await exportFile.exists()) await exportFile.delete();
      for (final p in [
        dbStem,
        '$dbStem-wal',
        '$dbStem-shm',
        '$dbStem-journal',
      ]) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }

      await initDbPool(dbPath: dbStem, maxSize: 4);
      await rust_rag.initSourceDb();

      for (final textCase in textCases) {
        final collectionId = 'allocator_indexing_${textCase.id}';
        final basePath = '${dbStem}_hnsw_$collectionId';

        final seedSw = Stopwatch()..start();
        final source = await rust_rag.addSourceInCollection(
          collectionId: collectionId,
          content: 'allocator indexing macro ${textCase.label}',
          metadata: jsonEncode({
            'kind': 'allocator_indexing_macro',
            'target_text_mb': textCase.targetTextMb,
            'target_text_bytes': textCase.targetTextBytes,
            'actual_text_bytes': textCase.actualTextBytes,
            'chunk_count': textCase.chunkCount,
            'chunk_text_chars': _chunkTextChars,
            'chunk_overlap_chars': _chunkOverlapChars,
            'embedding_dim': _embeddingDim,
          }),
          name: 'allocator_indexing_${textCase.id}',
        );
        await rust_rag.updateSourceStatus(
          sourceId: source.sourceId,
          status: 'completed',
        );
        await rust_rag.addChunks(
          sourceId: source.sourceId,
          chunks: _chunks(textCase.chunkCount),
        );
        seedSw.stop();

        am.resetActivationTimingStats();
        final rss = RssSampler().start();
        final rebuildSw = Stopwatch()..start();
        await rust_rag.rebuildChunkHnswIndexForCollection(
          collectionId: collectionId,
        );
        rss.sample();
        await rust_rag.saveCollectionHnswIndex(
          collectionId: collectionId,
          basePath: basePath,
        );
        rss.sample();
        await rust_rag.rebuildChunkBm25IndexForCollection(
          collectionId: collectionId,
        );
        rebuildSw.stop();
        final stats = am.takeActivationTimingStats();
        final rssSummary = rss.finish();

        final row = {
          'cell': 'indexing_rebuild',
          'profile_label': textCase.label,
          'text_unit': 'MB_decimal',
          'target_text_mb': textCase.targetTextMb,
          'target_text_bytes': textCase.targetTextBytes,
          'actual_text_mb': textCase.actualTextMb,
          'actual_text_bytes': textCase.actualTextBytes,
          'chunk_count': textCase.chunkCount,
          'chunk_text_chars': _chunkTextChars,
          'chunk_overlap_chars': _chunkOverlapChars,
          'embedding_dim': _embeddingDim,
          'embedding_bytes': textCase.embeddingBytes,
          'embedding_mib': textCase.embeddingMiB,
          'seed_ms': seedSw.elapsedMicroseconds / 1000.0,
          'rebuild_total_ms': rebuildSw.elapsedMicroseconds / 1000.0,
          'native_allocator': nativeInfo.nativeAllocator,
          'rust_features': nativeInfo.rustFeatures,
          'build_mode': kReleaseMode
              ? 'release'
              : (kProfileMode ? 'profile' : 'debug'),
          'hnsw_rebuild_nanos': stats.hnswRebuildNanos.toInt(),
          'hnsw_rebuild_count': stats.hnswRebuildCount.toInt(),
          'hnsw_save_nanos': stats.hnswSaveNanos.toInt(),
          'hnsw_save_count': stats.hnswSaveCount.toInt(),
          'bm25_rebuild_nanos': stats.bm25RebuildNanos.toInt(),
          'bm25_rebuild_count': stats.bm25RebuildCount.toInt(),
          ...rssSummary.toJson(prefix: 'rss'),
        };
        await exportFile.writeAsString(
          '${jsonEncode(row)}\n',
          mode: FileMode.append,
          flush: true,
        );
        // ignore: avoid_print
        print('INDEXING_PROFILE ${jsonEncode(row)}');

        expect(stats.hnswRebuildCount.toInt(), 1);
        expect(stats.hnswSaveCount.toInt(), 1);
        expect(stats.bm25RebuildCount.toInt(), 1);
      }
      // ignore: avoid_print
      print('INDEXING_PROFILE_EXPORT ${exportFile.path}');
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: kDebugMode
        ? 'Allocator indexing macro requires `flutter drive --profile`; '
              'debug builds are not valid A/B evidence.'
        : false,
  );
}

const _bytesPerMb = 1000 * 1000;
const _bytesPerMiB = 1024 * 1024;
const _chunkTextChars = 500;
const _chunkOverlapChars = 30;
const _embeddingDim = 384;

List<_IndexingTextCase> _parseTextMbCases(String csv) {
  final sizes = csv
      .split(',')
      .map((part) => double.tryParse(part.trim()))
      .whereType<double>()
      .where((value) => value > 0)
      .toList(growable: false);
  if (sizes.isEmpty) {
    throw ArgumentError.value(
      csv,
      'ALLOCATOR_INDEXING_TEXT_MB',
      'no positive text sizes',
    );
  }
  return sizes.map(_IndexingTextCase.fromTextMb).toList(growable: false);
}

List<rust_rag.ChunkData> _chunks(int count) => List.generate(count, (i) {
  final startPos = i * (_chunkTextChars - _chunkOverlapChars);
  return rust_rag.ChunkData(
    content: _chunkText(i),
    chunkIndex: i,
    startPos: startPos,
    endPos: startPos + _chunkTextChars,
    chunkType: 'allocator-macro',
    embedding: _embedding(i),
  );
});

String _chunkText(int seed) {
  final prefix =
      'doc $seed allocator pressure bm25 hnsw rebuild token${seed % 997} ';
  final buffer = StringBuffer(prefix);
  while (buffer.length < _chunkTextChars) {
    buffer
      ..write('mobile rag indexing realistic chunk allocator memory ')
      ..write('section${seed % 31} ');
  }
  return buffer.toString().substring(0, _chunkTextChars);
}

Float32List _embedding(int seed) {
  final values = Float32List(_embeddingDim);
  for (var i = 0; i < values.length; i++) {
    values[i] = (((seed + 1) * (i + 3)) % 23) / 23.0;
  }
  return values;
}

void _assertProfileMode() {
  if (kDebugMode) {
    fail(
      'Allocator indexing macro must run in PROFILE/RELEASE via flutter drive.\n'
      'Run: cd example && flutter drive '
      '--driver=test_driver/integration_test.dart '
      '--target=integration_test/allocator_indexing_measure_test.dart '
      '--dart-define=ALLOCATOR_INDEXING_TEXT_MB=5,10,25 '
      '--profile -d <device-id>\n'
      'Detected: kDebugMode=$kDebugMode, kProfileMode=$kProfileMode, '
      'kReleaseMode=$kReleaseMode',
    );
  }
}

class _IndexingTextCase {
  _IndexingTextCase.fromTextMb(this.targetTextMb)
    : targetTextBytes = (targetTextMb * _bytesPerMb).round(),
      chunkCount = ((targetTextMb * _bytesPerMb) / _chunkTextChars).ceil();

  final double targetTextMb;
  final int targetTextBytes;
  final int chunkCount;

  int get actualTextBytes => chunkCount * _chunkTextChars;
  double get actualTextMb => actualTextBytes / _bytesPerMb;
  int get embeddingBytes => chunkCount * _embeddingDim * 4;
  double get embeddingMiB => embeddingBytes / _bytesPerMiB;

  String get id {
    final rounded = targetTextMb.roundToDouble();
    final value = targetTextMb == rounded
        ? rounded.toInt().toString()
        : targetTextMb.toString().replaceAll('.', 'p');
    return 'text_${value}mb';
  }

  String get label {
    final rounded = targetTextMb.roundToDouble();
    final value = targetTextMb == rounded
        ? rounded.toInt().toString()
        : targetTextMb.toString();
    return '${value}MB_text_500char_384d';
  }
}
