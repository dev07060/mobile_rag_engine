import 'dart:convert';
import 'dart:typed_data';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

/// Deterministic fixture: two collections (A/B) with reproducible short docs,
/// plus a fixed query set. Used by the on-device query profiler integration test.
class QueryFixture {
  static const collectionA = 'profile_a';
  static const collectionB = 'profile_b';

  /// Deterministic short docs for a collection. `count` controls corpus size.
  static List<String> docs(String seedTag, int count) => List.generate(
        count,
        (i) => 'doc $seedTag $i: mobile retrieval augmented generation '
            'embedding vector search bm25 ranking topic${i % 17} '
            'token${(i * 7) % 53} alpha beta gamma delta epsilon',
      );

  /// Lane-1 (unfiltered) query set. Lane-2 (filtered) injects sourceIds at call time.
  static const unfilteredQueries = <String>[
    'vector search ranking',
    'embedding topic3 retrieval',
    'bm25 token alpha',
    'mobile generation gamma',
    'topic9 delta epsilon',
  ];

  /// Seed both collections via the real ingest path (chunks + embeddings + indexes).
  /// Returns source ids per collection (used to drive the filtered lane).
  static Future<Map<String, List<int>>> seed({required int docsPerCollection}) async {
    final ids = <String, List<int>>{};
    for (final c in [collectionA, collectionB]) {
      final col = MobileRag.instance.inCollection(c);
      final ds = docs(c, docsPerCollection);
      final srcIds = <int>[];
      for (var i = 0; i < ds.length; i++) {
        final r = await col.addDocumentUtf8(
          Uint8List.fromList(utf8.encode(ds[i])),
          name: 'doc_${c}_$i',
        );
        srcIds.add(r.sourceId);
      }
      ids[c] = srcIds;
    }
    return ids;
  }
}
