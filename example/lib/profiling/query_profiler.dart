// On-device RAG query profiler — P3 (LOC-68) per-segment timing driver.
//
// Mirrors the canonical metadata-first search path in
// SourceRagService.searchMeta (lib/services/source_rag_service.dart:933-995),
// but times each FFI step in ISOLATION so the dominant bucket is found from
// data: embed / activate (collection switch) / search / hydrate.
//
// This is profiling-only code (example app, NOT shipped). To measure each
// segment independently it calls the engine's low-level rust API directly and
// replicates two private helpers from SourceRagService:
//   * _indexPath           (source_rag_service.dart:283-309) — HNSW base path
//   * _toInt64List          (source_rag_service.dart:261-268) — FRB i64 list
// Both are mirrored verbatim (with citations); the scenario runner adds a
// fail-closed hit-count + filter-correctness check so a drifted index path or
// an unapplied filter can never pass silently.
import 'dart:io';

import 'package:mobile_rag_engine/services/embedding_service.dart';
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/activation_metrics.dart' as am;
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;
// ignore: implementation_imports
import 'package:mobile_rag_engine/src/rust/api/query_metrics.dart' as qm;
// frb.Int64List is flutter_rust_bridge's generalized (BigInt-backed) Int64List
// re-exported by flutter_rust_bridge_for_generated.dart — NOT dart:typed_data's.
// The generated API (SearchMetaHybridOptions.sourceIds / hydrateChunks chunkIds)
// expects exactly this generalized type; the generated bindings import the same
// library unaliased, so building it element-by-element matches the engine.
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

/// Result of a single measured query: per-segment milliseconds + the sourceIds
/// of the returned hits (used for fail-closed hit-count + filter checks).
typedef MeasuredQuery = ({
  Map<String, double> ms,
  List<int> hitSourceIds,
  Map<String, Object?> activation,
});

/// Per-segment timing driver. One instance per profiling run.
class QueryProfiler {
  /// Resolved SQLite db path — pass `MobileRag.instance.dbPath`.
  /// Used to reconstruct the engine's private HNSW index base path.
  final String dbPath;

  /// Hybrid weights mirrored from kDefaultVectorWeight / kDefaultBm25Weight
  /// (lib/src/internal/defaults.dart). They are finite and in-range, so the
  /// engine's normalizeHybridWeights is identity — no need to replicate it.
  final double vectorWeight;
  final double bm25Weight;

  QueryProfiler({
    required this.dbPath,
    this.vectorWeight = 0.2,
    this.bm25Weight = 0.8,
  });

  static Future<double> _timeMs(Future<void> Function() fn) async {
    final sw = Stopwatch()..start();
    await fn();
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  }

  // --- index base path reconstruction (mirrors SourceRagService:283-309) ---

  String get _dbPathWithoutExtension {
    const knownDbExtensions = ['.sqlite3', '.sqlite', '.db'];
    final lower = dbPath.toLowerCase();
    for (final ext in knownDbExtensions) {
      if (lower.endsWith(ext)) {
        return dbPath.substring(0, dbPath.length - ext.length);
      }
    }
    return dbPath;
  }

  /// Deterministic FNV-1a 32-bit hash for stable file names
  /// (mirrors SourceRagService._collectionFileSuffix, :296-304).
  static String _collectionFileSuffix(String collectionId) {
    var hash = 0x811C9DC5;
    for (final codeUnit in collectionId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// HNSW index base path for a NON-default collection (the profiler only uses
  /// profile_a / profile_b). Mirrors SourceRagService._indexPath (:307-309).
  String indexBasePath(String collectionId) =>
      '${_dbPathWithoutExtension}_hnsw_${_collectionFileSuffix(collectionId)}';

  /// On-disk index artifacts + dirty marker for a non-default collection,
  /// matching RagEngine.clearAllData's candidate set (rag_engine.dart:1061-1066)
  /// plus the dirty marker (source_rag_service.dart:313-315). clearAllData only
  /// cleans the DEFAULT collection's files, so the profiler must delete these
  /// itself to guarantee a stale-free, deterministic corpus on every run.
  List<String> indexArtifactPaths(String collectionId) {
    final base = indexBasePath(collectionId);
    final dirty =
        '$_dbPathWithoutExtension.${_collectionFileSuffix(collectionId)}.dirty';
    return [base, '$base.pbin', '$base.hnsw.data', '$base.hnsw.graph', dirty];
  }

  /// Delete a collection's on-disk index so the next activate rebuilds the
  /// current corpus from the DB (kills stale-index / cross-run accumulation).
  Future<void> deleteOnDiskIndex(String collectionId) async {
    for (final path in indexArtifactPaths(collectionId)) {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// Activate a collection WITHOUT running a query (no embed/search/hydrate).
  /// Used to evict the single global HNSW slot between collections so the next
  /// measured activate truly pays the switch/load cost, and to seed warm cells.
  Future<void> activateOnly(String collectionId) =>
      rust_rag.activateCollectionForHybridSearch(
        collectionId: collectionId,
        basePath: indexBasePath(collectionId),
      );

  /// Mirror of SourceRagService._toInt64List (:261-268). Builds the FRB
  /// generalized Int64List element-by-element (NOT .fromList) to match the
  /// generated API's expected type exactly.
  static frb.Int64List _toInt64List(List<int> list) {
    final result = frb.Int64List(list.length);
    for (var i = 0; i < list.length; i++) {
      result[i] = list[i];
    }
    return result;
  }

  /// One measured query, mirroring [SourceRagService.searchMeta].
  ///
  /// Segments returned (ms): `embed`, `search`, `hydrate`, and `activate` when
  /// [activate] is true (the cold/switch path). [sourceIds] non-null selects
  /// the filtered lane. Also returns the hits' sourceIds so the caller can
  /// fail-closed on an empty result or an unapplied filter.
  Future<MeasuredQuery> measureOnce({
    required String collectionId,
    required String query,
    List<int>? sourceIds,
    bool activate = false,
    int topK = 10,
  }) async {
    final ms = <String, double>{};
    var activation = <String, Object?>{};

    if (activate) {
      QueryProfiler.resetActivation();
      ms['activate'] = await _timeMs(
        () => rust_rag.activateCollectionForHybridSearch(
          collectionId: collectionId,
          basePath: indexBasePath(collectionId),
        ),
      );
      activation = QueryProfiler.takeActivation();
    }

    late final List<double> embedding; // Float32List is-a List<double>
    ms['embed'] = await _timeMs(() async {
      embedding = await EmbeddingService.embed(query);
    });

    late final rust_rag.SearchHandle handle;
    ms['search'] = await _timeMs(() async {
      handle = await rust_rag.searchMetaHybrid(
        collectionId: collectionId,
        queryText: query,
        queryEmbedding: embedding,
        options: rust_rag.SearchMetaHybridOptions(
          topK: topK,
          vectorWeight: vectorWeight,
          bm25Weight: bm25Weight,
          sourceIds: sourceIds == null ? null : _toInt64List(sourceIds),
          adjacentChunks: 0,
        ),
      );
    });

    final hits = await handle.hitMeta();
    final chunkIds = <int>[
      for (final h in hits) h.chunkId
    ]; // PlatformInt64==int (native)
    ms['hydrate'] = await _timeMs(() async {
      await handle.hydrateChunks(chunkIds: _toInt64List(chunkIds));
    });

    await handle.dispose();
    return (
      ms: ms,
      hitSourceIds: <int>[for (final h in hits) h.sourceId],
      activation: activation,
    );
  }

  /// Snapshot (and reset) the rust-side query_metrics I/O counters into a
  /// JSON-ready map. Call [resetIo] before the measured loop, this after.
  Map<String, Object?> snapshotIo() {
    final s = qm.takeQueryContentReadStats();
    return {
      'full_hydrate_rows': s.fullHydrateRows.toInt(),
      'full_hydrate_content_bytes': s.fullHydrateContentBytes.toInt(),
      'scoped_exact_scan_rows': s.scopedExactScanRows.toInt(),
      'scoped_exact_scan_content_bytes': s.scopedExactScanContentBytes.toInt(),
      'scoped_exact_scan_tokens': s.scopedExactScanTokens.toInt(),
      'scoped_exact_scan_tokenization_nanos':
          s.scopedExactScanTokenizationNanos.toInt(),
    };
  }

  /// Reset the rust-side query_metrics counters (call after warmup, before the
  /// measured loop, so the I/O snapshot reflects measured iterations only).
  static void resetIo() => qm.resetQueryContentReadStats();

  static void resetActivation() => am.resetActivationTimingStats();

  static Map<String, Object?> takeActivation() {
    final s = am.takeActivationTimingStats();
    return {
      'activate_total_nanos': s.activateTotalNanos.toInt(),
      'activate_count': s.activateCount.toInt(),
      'bm25_rebuild_nanos': s.bm25RebuildNanos.toInt(),
      'bm25_rebuild_count': s.bm25RebuildCount.toInt(),
      'hnsw_load_nanos': s.hnswLoadNanos.toInt(),
      'hnsw_load_count': s.hnswLoadCount.toInt(),
      'hnsw_load_success_count': s.hnswLoadSuccessCount.toInt(),
      'hnsw_load_miss_count': s.hnswLoadMissCount.toInt(),
      'hnsw_rebuild_nanos': s.hnswRebuildNanos.toInt(),
      'hnsw_rebuild_count': s.hnswRebuildCount.toInt(),
      'hnsw_save_nanos': s.hnswSaveNanos.toInt(),
      'hnsw_save_count': s.hnswSaveCount.toInt(),
    };
  }
}
