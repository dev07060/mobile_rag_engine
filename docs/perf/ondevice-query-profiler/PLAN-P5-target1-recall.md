# P5 Target ① — e2e Hybrid Recall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a physical iPhone (profile build), measure `recall@10` of the shipped hybrid search (i8-HNSW + BM25 RRF) against a Dart-side original-f32 brute-force ground truth — the first *quality* number for the profiler, with **zero core-crate Rust change**.

**Architecture:** Freeze each query's embedding once via `EmbeddingService.embed` and feed the SAME vector to both (a) the shipped `searchMetaHybrid` (PROD top-10 chunkIds) and (b) a Dart brute-force f32 cosine over every chunk in the collection (GT top-10 chunkIds). Original f32 vectors are read straight from the engine's SQLite DB (`chunks.embedding` BLOB) via `package:sqlite3` opened read-only. Report two numbers per query: `recall_vectoronly@10` (bm25Weight=0 → isolates i8-HNSW graph+quant error vs f32 GT — this is the headline quality number that §3.1's 0.90 verdict targets) and `recall_hybrid@10` (shipped 0.2/0.8 weights → shows how BM25 RRF reorders vs pure-vector GT). Pure logic is host-TDD'd; the device run is a `flutter drive --profile` integration entrypoint mirroring P3/P4.

**Tech Stack:** Dart/Flutter (example app), `package:sqlite3` (+ `sqlite3_flutter_libs` for on-device), existing profiler harness (`example/lib/profiling/`), flutter_rust_bridge engine bindings (`searchMetaHybrid`, `EmbeddingService`).

**Anchors (verified live, do not re-derive):** Shipped HNSW is built on i8-dequant vectors — source_rag.rs:886-899; original f32 = `chunks.embedding` BLOB — source_rag.rs:291; `decode_f32_embedding` (native-endian, len%4 guard) — vector_math.rs:23-31; RRF k=60 — hybrid_search.rs:417-462; `ef_search=max(100,topK*5)`, M/ef_construction size-bucketed const, **no runtime tuning API** — hnsw_index.rs:69-75,259. `SearchHitMeta.chunkId` — lib/src/rust/api/source_rag.dart:562-599; `searchMetaHybrid(collectionId, queryText, queryEmbedding, options)` — :146-156; `SearchMetaHybridOptions(topK, vectorWeight, bm25Weight, sourceIds, adjacentChunks)` — :601-614; `EmbeddingService.embed` — embedding_service.dart:92-125; `SourceRagService.dbPath` — source_rag_service.dart:208.

**Dependency note:** ① has **no hard code-dependency on P4** (it ships its own recall model/export and only reuses P3's `QueryProfiler` + P2's `QueryFixture`, both already on `main`). Per DESIGN-P5 §5 and the user's chosen sequencing we still branch `feat/loc-70-recall` from `main` *after* the P4 rescue PR #75 merges, so the new files land on a P4-bearing main. There is no shared-file conflict with P4 (recall uses new files only; the timing model `query_profile_report.dart` is left untouched).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `example/pubspec.yaml` | Modify | Add `sqlite3` + `sqlite3_flutter_libs` deps (Dart-side DB read on device). |
| `example/lib/profiling/recall_math.dart` | Create | Pure functions: `decodeF32Blob`, `cosineSimilarity`, `groundTruthTopK`, `recallAtK`. Host-testable, no IO. |
| `example/lib/profiling/recall_db.dart` | Create | `fetchChunkEmbeddingsF32(dbPath, collectionId)` → `Map<int, Float32List>` via sqlite3 read-only. |
| `example/lib/profiling/recall_report.dart` | Create | `RecallQueryResult` + `RecallReport` models (toJson/toCsv/means) + `RecallExport.write` (JSON/CSV to app docs dir, mirrors P4 `ProfileExport`). |
| `example/integration_test/query_recall_measure_test.dart` | Create | Device measure entrypoint (`flutter drive --profile`): seed → activate A → per-query GT vs PROD(hybrid + vector-only) → recall → print/export. Includes an early DB-read smoke (risk-first). |
| `example/test_driver/integration_test.dart` | Reuse | Existing generic `integrationDriver()` entry — no change; new `--target` points at the recall test. |
| `example/test/profiling/recall_math_test.dart` | Create | Host unit tests for `recall_math.dart`. |
| `example/test/profiling/recall_db_test.dart` | Create | Host unit test for `recall_db.dart` against a temp sqlite DB. |
| `docs/perf/ondevice-query-profiler/PR-P5-1.md` | Create (Task 9) | Result journal: recall numbers + verdict. |

**Why separate files (not extending `query_profile_report.dart`):** recall data is per-query intersection, not a timing distribution. Keeping it in its own model leaves the P3/P4 timing structures untouched (lowest risk, zero P4 merge conflict).

---

## Task 0: Branch + example sqlite3 deps

**Files:**
- Modify: `example/pubspec.yaml`

**Precondition:** PR #75 (P4 rescue) is merged to `main`. Then branch from a freshly-pulled `main`.

- [ ] **Step 1: Cut the branch from main**

```bash
git fetch origin --quiet
git switch -c feat/loc-70-recall origin/main
# sanity: P4 export must be present on this base
test -f example/lib/profiling/profile_export.dart && echo "P4 present" || echo "MISSING P4 — do not proceed"
```
Expected: `P4 present`

- [ ] **Step 2: Add sqlite3 deps to the example**

In `example/pubspec.yaml`, under `dependencies:` add (match the main package's `sqlite3: ^2.4.0`):

```yaml
  sqlite3: ^2.4.0
  sqlite3_flutter_libs: ^0.5.0
```

`sqlite3_flutter_libs` bundles a sqlite3 build for iOS/Android so `sqlite3.open()` works on-device (the engine's own SQLite is statically linked in Rust and is NOT reachable from Dart).

- [ ] **Step 3: Resolve deps**

Run: `cd example && flutter pub get`
Expected: resolves with no version conflict; `sqlite3` + `sqlite3_flutter_libs` in `.dart_tool/package_config.json`.

- [ ] **Step 4: Commit**

```bash
git add example/pubspec.yaml example/pubspec.lock
git commit -m "build(example): add sqlite3 for Dart-side ground-truth DB reads (LOC-70)"
```

---

## Task 1: `decodeF32Blob` (host TDD)

**Files:**
- Create: `example/lib/profiling/recall_math.dart`
- Test: `example/test/profiling/recall_math_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// example/test/profiling/recall_math_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/recall_math.dart';

void main() {
  group('decodeF32Blob', () {
    test('round-trips a known Float32List (native endian)', () {
      final original = Float32List.fromList([1.0, -2.5, 3.25, 0.0]);
      final bytes = original.buffer.asUint8List();
      final decoded = decodeF32Blob(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.length, 4);
      expect(decoded[0], closeTo(1.0, 1e-7));
      expect(decoded[1], closeTo(-2.5, 1e-7));
      expect(decoded[2], closeTo(3.25, 1e-7));
      expect(decoded[3], closeTo(0.0, 1e-7));
    });

    test('returns null when length is not a multiple of 4', () {
      expect(decodeF32Blob(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: FAIL — `recall_math.dart` / `decodeF32Blob` not defined.

- [ ] **Step 3: Write minimal implementation**

```dart
// example/lib/profiling/recall_math.dart
import 'dart:typed_data';

/// Decode a raw little/native-endian f32 blob (the `chunks.embedding` column)
/// into a Float32List. Mirrors Rust `decode_f32_embedding` (vector_math.rs:23-31):
/// native-endian, returns null if the byte length is not a multiple of 4.
Float32List? decodeF32Blob(Uint8List bytes) {
  if (bytes.lengthInBytes % 4 != 0) return null;
  // Copy into an aligned buffer (the sqlite3 blob may be unaligned).
  final copy = Uint8List.fromList(bytes);
  return copy.buffer.asFloat32List(0, copy.lengthInBytes ~/ 4);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add example/lib/profiling/recall_math.dart example/test/profiling/recall_math_test.dart
git commit -m "feat(recall): f32 blob decode helper for ground truth (LOC-70)"
```

---

## Task 2: `cosineSimilarity` (host TDD)

**Files:**
- Modify: `example/lib/profiling/recall_math.dart`
- Modify: `example/test/profiling/recall_math_test.dart`

- [ ] **Step 1: Write the failing test** (append a group)

```dart
  group('cosineSimilarity', () {
    test('identical vectors → 1.0', () {
      final v = <double>[1, 2, 3];
      expect(cosineSimilarity(v, v), closeTo(1.0, 1e-9));
    });
    test('orthogonal vectors → 0.0', () {
      expect(cosineSimilarity(<double>[1, 0], <double>[0, 1]), closeTo(0.0, 1e-9));
    });
    test('opposite vectors → -1.0', () {
      expect(cosineSimilarity(<double>[1, 0], <double>[-1, 0]), closeTo(-1.0, 1e-9));
    });
    test('zero vector → 0.0 (no NaN)', () {
      expect(cosineSimilarity(<double>[0, 0], <double>[1, 1]), 0.0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: FAIL — `cosineSimilarity` not defined.

- [ ] **Step 3: Write minimal implementation** (append)

```dart
/// Cosine similarity of two equal-length vectors. Returns 0.0 if either
/// vector has zero magnitude (avoids NaN). Accepts Float32List (is-a List<double>).
double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length, 'vector length mismatch: ${a.length} vs ${b.length}');
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na == 0.0 || nb == 0.0) return 0.0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
```

Add at top of file: `import 'dart:math' as math;`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add example/lib/profiling/recall_math.dart example/test/profiling/recall_math_test.dart
git commit -m "feat(recall): cosine similarity for f32 ground truth (LOC-70)"
```

---

## Task 3: `groundTruthTopK` (host TDD)

**Files:**
- Modify: `example/lib/profiling/recall_math.dart`
- Modify: `example/test/profiling/recall_math_test.dart`

- [ ] **Step 1: Write the failing test** (append)

```dart
  group('groundTruthTopK', () {
    test('ranks corpus by cosine to query, returns top-k chunkIds in order', () {
      final query = <double>[1.0, 0.0];
      final corpus = <int, List<double>>{
        10: [1.0, 0.0],     // cos 1.0
        20: [0.9, 0.1],     // high
        30: [0.0, 1.0],     // cos 0.0
        40: [-1.0, 0.0],    // cos -1.0
      };
      expect(groundTruthTopK(query: query, corpus: corpus, k: 2), [10, 20]);
    });
    test('k larger than corpus returns all, ranked', () {
      final corpus = <int, List<double>>{1: [1, 0], 2: [0, 1]};
      expect(groundTruthTopK(query: [1, 0], corpus: corpus, k: 10), [1, 2]);
    });
    test('ties broken by ascending chunkId (deterministic)', () {
      final corpus = <int, List<double>>{7: [1, 0], 3: [1, 0]};
      expect(groundTruthTopK(query: [1, 0], corpus: corpus, k: 2), [3, 7]);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: FAIL — `groundTruthTopK` not defined.

- [ ] **Step 3: Write minimal implementation** (append)

```dart
/// Brute-force ground truth: rank every (chunkId → vector) entry by cosine to
/// `query` (descending), tie-break by ascending chunkId for determinism, and
/// return the top-`k` chunkIds in ranked order.
List<int> groundTruthTopK({
  required List<double> query,
  required Map<int, List<double>> corpus,
  required int k,
}) {
  final scored = corpus.entries
      .map((e) => (id: e.key, score: cosineSimilarity(query, e.value)))
      .toList()
    ..sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return [for (final s in scored.take(k)) s.id];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add example/lib/profiling/recall_math.dart example/test/profiling/recall_math_test.dart
git commit -m "feat(recall): brute-force ground-truth top-k ranking (LOC-70)"
```

---

## Task 4: `recallAtK` (host TDD)

**Files:**
- Modify: `example/lib/profiling/recall_math.dart`
- Modify: `example/test/profiling/recall_math_test.dart`

- [ ] **Step 1: Write the failing test** (append)

```dart
  group('recallAtK', () {
    test('full overlap → 1.0', () {
      expect(recallAtK(gt: [1, 2, 3], prod: [3, 2, 1], k: 3), 1.0);
    });
    test('half overlap → 0.5', () {
      expect(recallAtK(gt: [1, 2, 3, 4], prod: [1, 2, 9, 8], k: 4), 0.5);
    });
    test('denominator is min(k, gt.length) so short corpora are not penalised', () {
      // Only 2 ground-truth items exist; both retrieved → 1.0 even at k=10.
      expect(recallAtK(gt: [1, 2], prod: [2, 1], k: 10), 1.0);
    });
    test('prod truncated to k before intersect', () {
      expect(recallAtK(gt: [1, 2], prod: [9, 8, 1, 2], k: 2), 0.0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: FAIL — `recallAtK` not defined.

- [ ] **Step 3: Write minimal implementation** (append)

```dart
/// recall@k = |topK(gt) ∩ topK(prod)| / min(k, gt.length).
/// Both lists are truncated to k first; gt is the brute-force ranking, prod is
/// the engine's hybrid result. Denominator uses min(k, gt.length) so a corpus
/// smaller than k is not unfairly penalised.
double recallAtK({required List<int> gt, required List<int> prod, required int k}) {
  final gtTop = gt.take(k).toSet();
  if (gtTop.isEmpty) return 0.0;
  final prodTop = prod.take(k).toSet();
  final hit = gtTop.intersection(prodTop).length;
  return hit / gtTop.length;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd example && flutter test test/profiling/recall_math_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add example/lib/profiling/recall_math.dart example/test/profiling/recall_math_test.dart
git commit -m "feat(recall): recall@k metric (LOC-70)"
```

---

## Task 5: `fetchChunkEmbeddingsF32` via sqlite3 (host TDD with temp DB)

**Files:**
- Create: `example/lib/profiling/recall_db.dart`
- Test: `example/test/profiling/recall_db_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// example/test/profiling/recall_db_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:mobile_rag_engine_example/profiling/recall_db.dart';

void main() {
  test('fetchChunkEmbeddingsF32 reads only the target collection, decodes f32', () {
    final dir = Directory.systemTemp.createTempSync('recall_db_test');
    final path = '${dir.path}/t.sqlite';
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE chunks (
        id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL,
        collection_id TEXT NOT NULL, chunk_index INTEGER NOT NULL,
        content TEXT NOT NULL, start_pos INTEGER NOT NULL, end_pos INTEGER NOT NULL,
        chunk_type TEXT, embedding BLOB NOT NULL,
        embedding_i8 BLOB, embedding_scale REAL
      );''');
    Uint8List blob(List<double> v) => Float32List.fromList(v).buffer.asUint8List();
    final stmt = db.prepare(
        'INSERT INTO chunks(id,source_id,collection_id,chunk_index,content,start_pos,end_pos,embedding) '
        'VALUES(?,?,?,?,?,?,?,?)');
    stmt.execute([1, 1, 'A', 0, 'x', 0, 1, blob([1.0, 2.0])]);
    stmt.execute([2, 1, 'A', 1, 'y', 0, 1, blob([3.0, 4.0])]);
    stmt.execute([3, 9, 'B', 0, 'z', 0, 1, blob([9.0, 9.0])]); // other collection
    stmt.dispose();
    db.dispose();

    final got = fetchChunkEmbeddingsF32(dbPath: path, collectionId: 'A');
    expect(got.keys.toSet(), {1, 2});
    expect(got[1], [1.0, 2.0]);
    expect(got[2], [3.0, 4.0]);

    dir.deleteSync(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd example && flutter test test/profiling/recall_db_test.dart`
Expected: FAIL — `recall_db.dart` / `fetchChunkEmbeddingsF32` not defined.

- [ ] **Step 3: Write minimal implementation**

```dart
// example/lib/profiling/recall_db.dart
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'recall_math.dart';

/// Read every chunk's ORIGINAL f32 embedding for one collection straight from
/// the engine's SQLite file (`chunks.embedding` BLOB, source_rag.rs:291).
/// Opens READ-ONLY so it never contends with the engine's writer (WAL allows
/// concurrent readers). Skips rows whose blob length is not a multiple of 4.
Map<int, Float32List> fetchChunkEmbeddingsF32({
  required String dbPath,
  required String collectionId,
}) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final rs = db.select(
      'SELECT id, embedding FROM chunks WHERE collection_id = ? ORDER BY id',
      [collectionId],
    );
    final out = <int, Float32List>{};
    for (final row in rs) {
      final id = row['id'] as int;
      final blob = row['embedding'] as Uint8List;
      final decoded = decodeF32Blob(blob);
      if (decoded != null) out[id] = decoded;
    }
    return out;
  } finally {
    db.dispose();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd example && flutter test test/profiling/recall_db_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add example/lib/profiling/recall_db.dart example/test/profiling/recall_db_test.dart
git commit -m "feat(recall): read original f32 embeddings from engine DB (LOC-70)"
```

---

## Task 6: `RecallReport` model + export (host TDD)

**Files:**
- Create: `example/lib/profiling/recall_report.dart`
- Test: `example/test/profiling/recall_report_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// example/test/profiling/recall_report_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/recall_report.dart';

void main() {
  final report = RecallReport(
    meta: {'k': 10, 'collection': 'profile_a'},
    results: [
      RecallQueryResult(
        queryIndex: 0, query: 'a', recallVectorOnly: 1.0, recallHybrid: 0.8),
      RecallQueryResult(
        queryIndex: 1, query: 'b', recallVectorOnly: 0.9, recallHybrid: 0.7),
    ],
  );

  test('means average each metric across queries', () {
    expect(report.meanVectorOnly, closeTo(0.95, 1e-9));
    expect(report.meanHybrid, closeTo(0.75, 1e-9));
  });

  test('toJson includes per-query results, means, and meta', () {
    final j = report.toJson();
    expect((j['results'] as List).length, 2);
    expect(j['mean_recall_vectoronly@10'], closeTo(0.95, 1e-9));
    expect(j['mean_recall_hybrid@10'], closeTo(0.75, 1e-9));
    expect((j['meta'] as Map)['collection'], 'profile_a');
  });

  test('toCsv has header + one row per query', () {
    final lines = report.toCsv().trim().split('\n');
    expect(lines.first,
        'query_index,query,recall_vectoronly@10,recall_hybrid@10');
    expect(lines.length, 3); // header + 2 rows
    expect(lines[1], '0,a,1.0,0.8');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd example && flutter test test/profiling/recall_report_test.dart`
Expected: FAIL — `recall_report.dart` not defined.

- [ ] **Step 3: Write minimal implementation**

```dart
// example/lib/profiling/recall_report.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// One query's recall outcome. `recallVectorOnly` = GT(f32) vs PROD(bm25Weight=0)
/// isolates the i8-HNSW graph/quant error (the §3.1 0.90-verdict number).
/// `recallHybrid` = GT(f32) vs PROD(shipped 0.2/0.8) shows BM25 RRF reorder.
class RecallQueryResult {
  final int queryIndex;
  final String query;
  final double recallVectorOnly;
  final double recallHybrid;
  const RecallQueryResult({
    required this.queryIndex,
    required this.query,
    required this.recallVectorOnly,
    required this.recallHybrid,
  });

  Map<String, Object?> toJson() => {
        'query_index': queryIndex,
        'query': query,
        'recall_vectoronly@10': recallVectorOnly,
        'recall_hybrid@10': recallHybrid,
      };
}

class RecallReport {
  final List<RecallQueryResult> results;
  final Map<String, Object?> meta;
  const RecallReport({required this.results, required this.meta});

  double get meanVectorOnly => _mean((r) => r.recallVectorOnly);
  double get meanHybrid => _mean((r) => r.recallHybrid);
  double _mean(double Function(RecallQueryResult) f) => results.isEmpty
      ? 0.0
      : results.map(f).reduce((a, b) => a + b) / results.length;

  Map<String, Object?> toJson() => {
        'mean_recall_vectoronly@10': meanVectorOnly,
        'mean_recall_hybrid@10': meanHybrid,
        'results': [for (final r in results) r.toJson()],
        'meta': meta,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toCsv() {
    final b = StringBuffer()
      ..writeln('query_index,query,recall_vectoronly@10,recall_hybrid@10');
    for (final r in results) {
      b.writeln('${r.queryIndex},${r.query},${r.recallVectorOnly},${r.recallHybrid}');
    }
    return b.toString();
  }
}

/// Writes recall JSON/CSV to the app documents dir and prints greppable lines.
/// Mirrors P4 `ProfileExport.write`; kept separate to leave the timing export
/// untouched. Returns the docs dir path (logged for operator pull).
class RecallExport {
  static Future<String> write(RecallReport report, {required String tsTag}) async {
    final dir = await getApplicationDocumentsDirectory();
    final json = File('${dir.path}/query_recall_$tsTag.json');
    final csv = File('${dir.path}/query_recall_$tsTag.csv');
    await json.writeAsString(report.toJsonString());
    await csv.writeAsString(report.toCsv());
    // Per-line print (device console truncates large single prints — PR-P3 lesson).
    for (final line in report.toCsv().trimRight().split('\n')) {
      // ignore: avoid_print
      print('RECALL_CSV $line');
    }
    // ignore: avoid_print
    print('RECALL_EXPORT_DIR ${dir.path}');
    return dir.path;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd example && flutter test test/profiling/recall_report_test.dart`
Expected: PASS (the model/CSV tests; `RecallExport.write` is exercised on device, not host).

- [ ] **Step 5: Commit**

```bash
git add example/lib/profiling/recall_report.dart example/test/profiling/recall_report_test.dart
git commit -m "feat(recall): recall report model + JSON/CSV export (LOC-70)"
```

---

## Task 7: Device measure entrypoint — risk-first DB smoke

**Files:**
- Create: `example/integration_test/query_recall_measure_test.dart`

**Why a smoke first:** the single make-or-break on-device assumption is "Dart `sqlite3.open()` can read the engine's DB file on a physical iPhone." Prove that in isolation before wiring full recall, so a failure is unambiguous.

- [ ] **Step 1: Write the smoke entrypoint** (mirrors `query_profile_measure_test.dart` init: assert profile mode, delete DB files before init, real-ONNX init, seed)

```dart
// example/integration_test/query_recall_measure_test.dart
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/profiling/recall_db.dart';

const _docs = 500;
const _dbName = 'recall_smoke.sqlite';

void _assertProfileMode() {
  if (kDebugMode) {
    fail(
      'Query recall profiler must run in PROFILE/RELEASE via flutter drive.\n'
      'Debug builds use the cargokit debug profile = fallback Rust backend '
      '(no vector_faer / vector_quant_i8), so the recall number would be invalid. '
      'Aborting to avoid a fake-green quality baseline. '
      '(detected: kDebugMode=$kDebugMode, kProfileMode=$kProfileMode, '
      'kReleaseMode=$kReleaseMode)',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recall DB smoke — Dart reads engine f32 embeddings on device',
    () async {
      _assertProfileMode();

      // Fresh DB without clearAllData: delete SQLite files BEFORE initialize
      // so the engine starts clean and nothing races the seed (PR-P3 lesson).
      final docsDir = await getApplicationDocumentsDirectory();
      await _deleteDbFiles('${docsDir.path}/$_dbName');

      await MobileRag.initialize(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
        databaseName: _dbName,
        deferIndexWarmup: true,
      );
      await QueryFixture.seed(docsPerCollection: _docs);

      final corpus = fetchChunkEmbeddingsF32(
        dbPath: MobileRag.instance.dbPath,
        collectionId: QueryFixture.collectionA,
      );
      expect(corpus, isNotEmpty,
          reason: 'Dart must read at least one chunk embedding from engine DB');
      expect(corpus.length, _docs);
      expect(corpus.values.first.length, greaterThan(0));

      // ignore: avoid_print
      print('RECALL_SMOKE chunks=${corpus.length} '
          'dim=${corpus.values.first.length}');
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: kDebugMode
        ? 'Measurement requires flutter drive --profile; flutter test is debug.'
        : false,
  );
}

Future<void> _deleteDbFiles(String dbStem) async {
  for (final path in [dbStem, '$dbStem-wal', '$dbStem-shm', '$dbStem-journal']) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
```

- [ ] **Step 2: Run the smoke on a physical iPhone**

Run:
```bash
DEVICE_ID="$(flutter devices | awk -F' • ' '/iPhone/ {print $2; exit}')"
test -n "$DEVICE_ID"
cd example && flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/query_recall_measure_test.dart \
  --profile -d "$DEVICE_ID"
```
Expected device log: `RECALL_SMOKE chunks=500 dim=768` for the current bundled example model, and the test passes. If the model asset is swapped, the dimension may differ; the invariant is `chunks=500` and `dim>0`.
If it fails on `sqlite3.open` (missing lib) → confirm `sqlite3_flutter_libs` is in `example/pubspec.yaml` and rebuilt; if "database is locked" → ensure WAL + `OpenMode.readOnly` and the delete-before-init ran. (DDS flaky: kill stale processes + retry, per PR-P3.)

- [ ] **Step 3: Commit the smoke**

```bash
git add example/integration_test/query_recall_measure_test.dart
git commit -m "test(recall): on-device DB-read smoke before full recall (LOC-70)"
```

---

## Task 8: Full recall measurement (device)

**Files:**
- Modify: `example/integration_test/query_recall_measure_test.dart`

- [ ] **Step 1: Replace the smoke body with the full recall loop**

```dart
// example/integration_test/query_recall_measure_test.dart
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine/src/rust/api/source_rag.dart' as rust_rag;
import 'package:mobile_rag_engine_example/profiling/query_fixture.dart';
import 'package:mobile_rag_engine_example/profiling/query_profiler.dart';
import 'package:mobile_rag_engine_example/profiling/recall_db.dart';
import 'package:mobile_rag_engine_example/profiling/recall_math.dart';
import 'package:mobile_rag_engine_example/profiling/recall_report.dart';

const _docs = 500;
const _dbName = 'recall_measure.sqlite';

void _assertProfileMode() {
  if (kDebugMode) {
    fail(
      'Query recall profiler must run in PROFILE/RELEASE via flutter drive.\n'
      'Debug builds use the cargokit debug profile = fallback Rust backend '
      '(no vector_faer / vector_quant_i8), so the recall number would be invalid. '
      'Aborting to avoid a fake-green quality baseline. '
      '(detected: kDebugMode=$kDebugMode, kProfileMode=$kProfileMode, '
      'kReleaseMode=$kReleaseMode)',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'e2e hybrid recall@10 — GT(f32) vs shipped i8-HNSW+BM25 RRF',
    () async {
      _assertProfileMode();

      final docsDir = await getApplicationDocumentsDirectory();
      await _deleteDbFiles('${docsDir.path}/$_dbName');

      await MobileRag.initialize(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
        databaseName: _dbName,
        deferIndexWarmup: true,
      );

      final seeded = await QueryFixture.seed(docsPerCollection: _docs);
      expect(seeded[QueryFixture.collectionA]!.length, _docs);
      expect(seeded[QueryFixture.collectionB]!.length, _docs);

      final collection = QueryFixture.collectionA;
      final profiler = QueryProfiler(dbPath: MobileRag.instance.dbPath);

      // Warm the single global HNSW slot onto collection A and force a rebuild
      // from the just-seeded DB instead of reusing stale on-disk artifacts.
      await profiler.deleteOnDiskIndex(collection);
      await profiler.activateOnly(collection);

      // Ground-truth corpus (original f32) read once.
      final corpus = fetchChunkEmbeddingsF32(
        dbPath: MobileRag.instance.dbPath,
        collectionId: collection,
      );
      expect(corpus.length, _docs);

      const k = 10;
      final queries = QueryFixture.unfilteredQueries; // deterministic Q
      final results = <RecallQueryResult>[];

      for (var qi = 0; qi < queries.length; qi++) {
        final q = queries[qi];
        // FREEZE the query embedding: one vector for GT and both PROD calls.
        final qvec = await EmbeddingService.embed(q);

        // Ground truth: brute-force f32 cosine over the whole collection.
        final gt = groundTruthTopK(query: qvec, corpus: corpus, k: k);

        // PROD vector-only (bm25Weight=0): isolates i8-HNSW graph/quant error.
        final vecOnly = await _prodTopK(collection, q, qvec,
            topK: k, vectorWeight: 1.0, bm25Weight: 0.0);
        // PROD shipped hybrid (default 0.2/0.8 weights).
        final hybrid = await _prodTopK(collection, q, qvec,
            topK: k, vectorWeight: 0.2, bm25Weight: 0.8);

        // Fail-closed: PROD must return hits in the same chunk-id space as GT.
        expect(gt, hasLength(k));
        expect(vecOnly, isNotEmpty);
        expect(hybrid, isNotEmpty);

        results.add(RecallQueryResult(
          queryIndex: qi,
          query: q,
          recallVectorOnly: recallAtK(gt: gt, prod: vecOnly, k: k),
          recallHybrid: recallAtK(gt: gt, prod: hybrid, k: k),
        ));
      }

      final report = RecallReport(results: results, meta: {
        'k': k,
        'collection': collection,
        'docs_per_collection': _docs,
        'query_count': queries.length,
        'build_mode':
            kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
        'features': 'vector_faer,vector_quant_i8',
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'gt': 'dart_f32_brute_force_cosine',
        'note':
            'recall_vectoronly isolates i8-HNSW graph+quant error vs f32 GT; '
            'recall_hybrid reflects BM25 RRF reorder vs pure-vector GT.',
      });

      final tsTag = DateTime.now().millisecondsSinceEpoch.toString();
      await RecallExport.write(report, tsTag: tsTag);
      // ignore: avoid_print
      print('RECALL_MEAN vectoronly=${report.meanVectorOnly} '
          'hybrid=${report.meanHybrid}');
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: kDebugMode
        ? 'Measurement requires flutter drive --profile; flutter test is debug.'
        : false,
  );
}

Future<void> _deleteDbFiles(String dbStem) async {
  for (final path in [dbStem, '$dbStem-wal', '$dbStem-shm', '$dbStem-journal']) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Run the shipped search with a FROZEN embedding and return top-k chunkIds.
Future<List<int>> _prodTopK(
  String collection,
  String query,
  List<double> qvec, {
  required int topK,
  required double vectorWeight,
  required double bm25Weight,
}) async {
  final handle = await rust_rag.searchMetaHybrid(
    collectionId: collection,
    queryText: query,
    queryEmbedding: qvec,
    options: rust_rag.SearchMetaHybridOptions(
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
      sourceIds: null,
      adjacentChunks: 0,
    ),
  );
  try {
    final hits = await handle.hitMeta();
    return <int>[for (final h in hits) h.chunkId];
  } finally {
    await handle.dispose();
  }
}
```

- [ ] **Step 2: Run on a physical iPhone**

Run:
```bash
DEVICE_ID="$(flutter devices | awk -F' • ' '/iPhone/ {print $2; exit}')"
test -n "$DEVICE_ID"
cd example && flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/query_recall_measure_test.dart \
  --profile -d "$DEVICE_ID"
```
Expected device log:
```
RECALL_CSV query_index,query,recall_vectoronly@10,recall_hybrid@10
RECALL_CSV 0,vector search ranking,1.0,0.8
RECALL_CSV 1,embedding topic3 retrieval,0.9,0.7
RECALL_MEAN vectoronly=0.94 hybrid=0.76
RECALL_EXPORT_DIR /var/mobile/Containers/Data/Application/UUID/Documents
```
The numeric lines above are an example shape; the actual values are the P5-① result. All `expect` checks must pass.

- [ ] **Step 3: Pull the exported JSON/CSV** (iOS container: Xcode Devices & Simulators → Download Container, or `xcrun devicectl`), per P4's pull instructions.

- [ ] **Step 4: Commit**

```bash
git add example/integration_test/query_recall_measure_test.dart
git commit -m "test(recall): on-device e2e recall@10 (vector-only + hybrid) (LOC-70)"
```

---

## Task 9: Journal + Linear + PR

**Files:**
- Create: `docs/perf/ondevice-query-profiler/PR-P5-1.md`
- Modify: `docs/perf/ondevice-query-profiler/README.md` (status row: P5-① done)

- [ ] **Step 1: Write PR-P5-1.md** — the recall table (per-query + mean for vector-only and hybrid), device/config, and the **verdict against §3.1**: if `recall_vectoronly@10 < 0.90`, the follow-up is a Rust change to make `ef_search`/`M` configurable (currently compile-time const, hnsw_index.rs:69-75,259) — that becomes the cost basis for a per-collection quality-SLA feature. Note the joint-error caveat (vector-only recall folds graph-approximation + i8 distortion together, per §2.1) and that it is NOT comparable to PR6's pure-kernel 0.997.

- [ ] **Step 2: Update README status row** for P5-① (done + link PR-P5-1.md).

- [ ] **Step 3: Commit + push + open PR (base main)**

```bash
git add docs/perf/ondevice-query-profiler/PR-P5-1.md docs/perf/ondevice-query-profiler/README.md
git commit -m "docs(perf): P5-① e2e recall results + verdict (LOC-70)"
git push -u origin feat/loc-70-recall
gh pr create --base main --head feat/loc-70-recall \
  --title "feat(profiling): P5-① e2e hybrid recall@10 (LOC-70)" \
  --body-file docs/perf/ondevice-query-profiler/PR-P5-1.md
```
Stop at **PR opened + CI green** (user owns the merge). Mirror the recall numbers + verdict into Linear LOC-70 (KR).

---

## Self-Review

**Spec coverage (DESIGN-P5 §3.1):**
- recall@10 GT(f32 brute force) vs PROD(searchMetaHybrid) — Tasks 3,4,8 ✓
- vector-only (bm25_weight=0) variant to isolate BM25 — Task 8 `_prodTopK(vectorWeight: 1.0, bm25Weight: 0.0)` ✓
- query embedding freeze (compute once, reuse for GT + PROD) — Task 8 `qvec` ✓
- ground truth = `SELECT id, embedding FROM chunks WHERE collection_id = ? → Float32List → cosine → top-10` — Tasks 1,5,3 ✓
- per-query breakdown + mean — Task 6 model, Task 8 loop ✓
- verdict `recall<0.90 → raise M/ef_search` (Rust follow-up, out of ① scope) — Task 9 ✓
- "no Rust change" feasibility — confirmed (example-only sqlite3 dep) ✓

**Deliberately deferred (flagged, not gated into ①):**
- **i8 on/off isolation** (§3.1 risk): separating i8 distortion from graph-approximation error needs a *second build* with `vector_quant_i8` off (f32-HNSW) — a build-config run, not a Dart change. Recommend as a follow-up comparison run reusing this same harness; note it in PR-P5-1.md.
- **within/cross-cluster decomposition** (§3.1 risk): the current `QueryFixture` corpus is deterministic but not explicitly clustered, so a within/cross-cluster recall split isn't meaningful yet. Optional follow-up = a clustered fixture; out of ① core scope.
- **Query-set size:** defaults to the 5 deterministic `QueryFixture.unfilteredQueries`. 5×10 = 50 GT slots gives a coarse first mean; if a tighter mean is wanted, parameterise `queries` to a larger deterministic set (no code-shape change). Flagged for the user.

**Placeholder scan:** no unresolved code placeholders remain. Device selection is handled by the concrete `DEVICE_ID="$(flutter devices | awk -F' • ' '/iPhone/ {print $2; exit}')"` command; unknown recall values are represented only in the expected-output example and must be replaced by the actual device output in `PR-P5-1.md` after Task 8.

**Type consistency:** `recallAtK({gt, prod, k})`, `groundTruthTopK({query, corpus, k})`, `cosineSimilarity(a, b)`, `decodeF32Blob(bytes)→Float32List?`, `fetchChunkEmbeddingsF32({dbPath, collectionId})→Map<int,Float32List>`, `RecallQueryResult{queryIndex, query, recallVectorOnly, recallHybrid}`, `RecallReport{results, meta}` — names consistent across tasks 1-9. `_prodTopK` returns `List<int>` chunkIds; GT returns `List<int>` chunkIds — same id space (chunk ids), the §-corrected pitfall (NOT sourceIds).

---

## Open Decisions (defaults chosen — override if needed)

1. **Query set:** default = existing 5 fixture queries. Larger set = tighter mean. *(Default proceeds.)*
2. **i8 on/off second build:** deferred to a follow-up run. *(Default proceeds without it.)*
3. **Report co-location:** recall ships its own `recall_report.dart` + `RecallExport` (timing model untouched, zero P4 conflict). *(Default proceeds.)*

## Execution Handoff

Plan saved to `docs/perf/ondevice-query-profiler/PLAN-P5-target1-recall.md`. Two execution options once PR #75 is merged and `feat/loc-70-recall` is cut from main:

1. **Subagent-Driven (recommended)** — fresh subagent per task (Tasks 1-6 are host-TDD and fully automatable; Tasks 7-9 need the physical iPhone, so those are operator-in-the-loop), review between tasks.
2. **Inline Execution** — execute tasks in this session with checkpoints.

Which approach?
