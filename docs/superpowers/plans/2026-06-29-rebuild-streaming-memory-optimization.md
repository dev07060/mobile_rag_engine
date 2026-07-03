# Rebuild Streaming Memory Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce rebuild peak RSS under the system allocator by removing avoidable full-corpus collections where the target platform proves a win, before doing any further mimalloc default-enable evaluation.

**Architecture:** Keep `allocator_mimalloc` feature-gated and treat allocator selection as an experiment. HNSW row streaming is platform-gated because realistic system-allocator A/B showed a macOS peak-RSS win but an iPad 10 peak-RSS and runtime regression. BM25 can still proceed as an allocator-independent structural optimization, but each streaming change must be measured against a realistic system-allocator baseline before any mimalloc A/B. Measurement gates compare `system baseline` to the platform-appropriate `system + structural change` first, then optionally compare that result to mimalloc.

**Tech Stack:** Rust 2021, rusqlite, hnsw_rs 0.3, flutter_rust_bridge 2.11.1, Dart/Flutter integration tests, existing allocator indexing macro.

---

## Scope And File Map

### Detailed in this plan

- Modify: `rust_builder/rust/src/api/hnsw_index.rs`
  - Add an internal streaming builder that accepts a point-count hint and an iterator of `(i64, Vec<f32>)`.
  - Keep the existing FRB-compatible `build_hnsw_index(Vec<(i64, Vec<f32>)>)` public API by delegating to the streaming builder.
  - Add unit tests for empty streaming input and successful streaming build/search.

- Modify: `rust_builder/rust/src/api/source_rag.rs`
  - Keep the source RAG HNSW rebuild collect path as the non-macOS default.
  - Use count-then-stream insertion only on macOS by default, or when the `hnsw_streaming_rebuild` Rust feature is explicitly enabled for an experiment.
  - Preserve completed-source filtering, i8 dequant fallback behavior, activation metrics, and active collection marking.

### Kept as connected follow-up work in the same document

- Modify later: `rust_builder/rust/src/api/bm25_search.rs`
  - Add an iterator-based batch helper that holds the write lock once.
  - Later reduce tokenizer allocations by building term frequencies directly.

- Modify later: `rust_builder/rust/src/api/source_rag.rs`
  - Replace BM25 rebuild `Vec<(i64, String)>` collection with a row-streaming iterator.

- Measure later: `example/integration_test/allocator_indexing_measure_test.dart`
  - Use the existing realistic macro after the HNSW platform policy lands.

## Current Baseline Anchors

- HNSW source rebuild currently materializes all rows at `rust_builder/rust/src/api/source_rag.rs:890`.
- HNSW builder currently requires `Vec<(i64, Vec<f32>)>` at `rust_builder/rust/src/api/hnsw_index.rs:56`.
- BM25 source rebuild currently materializes all rows at `rust_builder/rust/src/api/source_rag.rs:970`.
- BM25 tokenization currently allocates `Vec<String>` at `rust_builder/rust/src/api/bm25_search.rs:60` and then clones tokens into a second `HashMap<String, u32>` at `rust_builder/rust/src/api/bm25_search.rs:66`.
- The realistic allocator macro uses 500-char chunks, 30-char overlap metadata, and 384-dim stub embeddings in `example/integration_test/allocator_indexing_measure_test.dart:185`.
- Existing result JSONL files are legacy synthetic allocator-pressure evidence when they report `embedding_dim:32`; they are not enough for a mimalloc default-enable decision.

## Non-Goals

- Do not default-enable `allocator_mimalloc`.
- Do not market this as a mimalloc stabilization phase.
- Do not wire SQLite custom allocation to mimalloc.
- Do not tune SQLite `mmap_size`, `cache_size`, `temp_store`, WAL, or checkpoint behavior in this branch.
- Do not change public Dart/FRB API shape for HNSW rebuild.
- Do not remove the legacy `build_hnsw_index(Vec<...>)` entrypoint; tests and simple RAG paths still use it.
- Do not default HNSW streaming on iOS, Android, or unvalidated targets.

---

## Task 1: HNSW Streaming Builder In `hnsw_index.rs`

**Files:**
- Modify: `rust_builder/rust/src/api/hnsw_index.rs:50-119`
- Test: `rust_builder/rust/src/api/hnsw_index.rs:299-360`

- [ ] **Step 1: Add failing unit tests for the streaming builder**

Insert these tests inside `#[cfg(test)] mod tests` in `rust_builder/rust/src/api/hnsw_index.rs`, after `test_build_empty_index`:

```rust
    #[test]
    fn test_streaming_build_empty_index() {
        clear_hnsw_index();

        let inserted = build_hnsw_index_streaming(0, std::iter::empty()).unwrap();

        assert_eq!(inserted, 0);
        assert!(!is_hnsw_index_loaded());
    }

    #[test]
    fn test_streaming_build_and_search() {
        clear_hnsw_index();
        let points: Vec<(i64, Vec<f32>)> = (0..100)
            .map(|i| (i, make_random_embedding(i as u64, 384)))
            .collect();

        let inserted = build_hnsw_index_streaming(points.len(), points.into_iter()).unwrap();

        assert_eq!(inserted, 100);
        assert!(is_hnsw_index_loaded());

        let query = make_random_embedding(42, 384);
        let results = search_hnsw(query, 5).unwrap();
        assert!(!results.is_empty());
    }
```

- [ ] **Step 2: Run the targeted HNSW tests and verify the expected failure**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib hnsw_index::tests::test_streaming_build -- --test-threads=1
```

Expected before implementation:

```text
error[E0425]: cannot find function `build_hnsw_index_streaming` in this scope
```

- [ ] **Step 3: Replace the HNSW build body with a streaming-compatible implementation**

In `rust_builder/rust/src/api/hnsw_index.rs`, replace the current `pub fn build_hnsw_index(...)` implementation at lines 56-119 with this block:

```rust
fn hnsw_build_params(count: usize) -> (usize, usize, usize, &'static str) {
    if count > 10_000 {
        (24, 48, 200, "large (>10K)")
    } else if count > 1_000 {
        (20, 40, 150, "medium (1K-10K)")
    } else {
        (16, 32, 100, "small (<1K)")
    }
}

pub(crate) fn build_hnsw_index_streaming<I>(
    point_count_hint: usize,
    points: I,
) -> anyhow::Result<usize>
where
    I: IntoIterator<Item = (i64, Vec<f32>)>,
{
    info!(
        "[hnsw] Building index with {} point capacity hint",
        point_count_hint
    );

    let capacity = point_count_hint.max(1);
    let (m, m0, ef_construction, size_category) = hnsw_build_params(capacity);

    #[cfg(debug_assertions)]
    {
        println!(
            "[HNSW] Dataset size hint: {} points ({})",
            point_count_hint, size_category
        );
        println!(
            "[HNSW] Parameters: M={}, M0={}, efConstruction={}",
            m, m0, ef_construction
        );
        println!(
            "[HNSW] Expected recall: ~{}%",
            if capacity > 10_000 {
                "97"
            } else if capacity > 1_000 {
                "95"
            } else {
                "92"
            }
        );
    }

    debug!(
        "[hnsw] Using M={}, M0={}, efConstruction={}",
        m, m0, ef_construction
    );

    let hnsw = Hnsw::new(m, capacity, m0, ef_construction, DistCosine);
    let mut inserted = 0usize;

    for (id, embedding) in points {
        if embedding.is_empty() {
            continue;
        }
        hnsw.insert((&embedding, id as usize));
        inserted += 1;
    }

    if inserted == 0 {
        warn!("[hnsw] No points provided");
        return Ok(0);
    }

    let mut index_guard = HNSW_INDEX.write().unwrap();
    *index_guard = Some(hnsw);

    #[cfg(debug_assertions)]
    println!("[HNSW] Index build complete");

    info!(
        "[hnsw] Index build complete (inserted={}, M={}, M0={}, efC={})",
        inserted, m, m0, ef_construction
    );
    Ok(inserted)
}

pub fn build_hnsw_index(points: Vec<(i64, Vec<f32>)>) -> anyhow::Result<()> {
    let point_count = points.len();
    let _ = build_hnsw_index_streaming(point_count, points)?;
    Ok(())
}
```

- [ ] **Step 4: Run the targeted HNSW tests and verify they pass**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib hnsw_index::tests::test_streaming_build -- --test-threads=1
```

Expected:

```text
test api::hnsw_index::tests::test_streaming_build_empty_index ... ok
test api::hnsw_index::tests::test_streaming_build_and_search ... ok
```

- [ ] **Step 5: Run existing HNSW regression tests**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib hnsw_index::tests -- --test-threads=1
```

Expected:

```text
test result: ok.
```

---

## Task 2: HNSW Source Rebuild Platform Gate In `source_rag.rs`

**Files:**
- Modify: `rust_builder/rust/Cargo.toml`
- Modify: `rust_builder/rust/src/api/runtime_info.rs`
- Modify: `rust_builder/rust/src/api/source_rag.rs:23-26`
- Modify: `rust_builder/rust/src/api/source_rag.rs:856-950`
- Test: `rust_builder/rust/src/api/source_rag.rs:2774-2850`
- Test: `rust_builder/rust/src/api/source_rag.rs:3112-3196`

- [ ] **Step 1: Add a non-default experiment feature**

Add a Rust feature named `hnsw_streaming_rebuild`. Do not include it in default
features. Add it to native runtime feature reporting so benchmark rows can
distinguish default builds from explicit HNSW streaming experiments.

- [ ] **Step 2: Add a platform policy helper**

Default policy:

```text
macOS: stream HNSW rebuild rows by default.
iOS / Android / other unvalidated targets: keep collect-based rebuild by default.
Explicit experiment: enable Rust feature `hnsw_streaming_rebuild`.
```

Add a pure testable helper:

```rust
fn hnsw_streaming_rebuild_enabled_for_target_os(target_os: &str, force_enabled: bool) -> bool {
    force_enabled || target_os == "macos"
}
```

- [ ] **Step 3: Route the source rebuild through the platform policy**

Keep one SQL row iterator and shared embedding decode logic. Route the decoded
rows into `build_hnsw_index_streaming(point_count_hint, points)` only when
`hnsw_streaming_rebuild_enabled()` is true. Otherwise collect filtered points
into `Vec<(i64, Vec<f32>)>` and call the legacy `build_hnsw_index(points)` path.

- [ ] **Step 4: Verify the platform policy test**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib source_rag::tests::test_hnsw_streaming_rebuild_policy -- --test-threads=1
```

Expected:

```text
test api::source_rag::tests::test_hnsw_streaming_rebuild_policy_is_macos_only_by_default ... ok
```

- [ ] **Step 5: Verify source rebuild behavior still filters non-completed sources**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib source_rag::tests::test_completed_filter_excludes_pending_and_failed_sources -- --test-threads=1
```

Expected:

```text
test api::source_rag::tests::test_completed_filter_excludes_pending_and_failed_sources ... ok
```

- [ ] **Step 6: Verify activation metrics still observe one HNSW rebuild**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib activation_metrics -- --test-threads=1
```

Expected:

```text
test result: ok.
```

- [ ] **Step 7: Run the Rust library test suite under the system allocator**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib -- --test-threads=1
```

Expected:

```text
test result: ok.
```

- [ ] **Step 8: Run the Rust library test suite with mimalloc still gated**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features allocator_mimalloc -- --test-threads=1
```

Expected:

```text
test result: ok.
```

- [ ] **Step 9: Run the Rust library test suite with the HNSW streaming experiment feature**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features hnsw_streaming_rebuild -- --test-threads=1
```

Expected:

```text
test result: ok.
```

- [ ] **Step 10: Commit the HNSW platform gate change**

Run:

```bash
git add rust_builder/rust/Cargo.toml rust_builder/rust/src/api/runtime_info.rs rust_builder/rust/src/api/hnsw_index.rs rust_builder/rust/src/api/source_rag.rs
git commit -m "perf(native): gate hnsw streaming rebuild"
```

---

## Task 3: HNSW System Allocator Measurement Gate

**Files:**
- Read: `docs/perf/mimalloc-allocator-ab/README.md`
- Read: `docs/perf/mimalloc-allocator-ab/RESULTS.md`
- Use: `example/integration_test/allocator_indexing_measure_test.dart`
- Update after runs: `docs/perf/mimalloc-allocator-ab/RESULTS.md`

- [ ] **Step 1: Establish the post-HNSW system allocator run label**

Use this folder naming convention for system-only validation after a
platform-specific HNSW streaming experiment:

```text
docs/perf/mimalloc-allocator-ab/runs/<platform>-hnsw-<streaming|nonstreaming>-system-YYYYMMDD-HHMMSS/
```

Example:

```text
docs/perf/mimalloc-allocator-ab/runs/macos-hnsw-streaming-system-20260629-140000/
docs/perf/mimalloc-allocator-ab/runs/ios-ipad10-hnsw-nonstreaming-system-20260629-140000/
```

- [ ] **Step 2: Run the realistic allocator indexing macro under the system allocator**

Run on a physical device when available. Use macOS as macOS evidence only; do
not generalize it to iOS or Android:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/allocator_indexing_measure_test.dart \
  --profile -d <device-id> \
  --dart-define=EXPECTED_NATIVE_ALLOCATOR=system \
  --dart-define=EXPECTED_RUST_FEATURES=vector_faer,vector_quant_i8 \
  --dart-define=ALLOCATOR_INDEXING_TEXT_MB=5,10,25
```

For an explicit non-macOS HNSW streaming experiment, enable the Rust feature and
include it in `EXPECTED_RUST_FEATURES`:

```text
vector_faer,vector_quant_i8,hnsw_streaming_rebuild
```

Expected row shape:

```json
{"cell":"indexing_rebuild","profile_label":"5MB_text_500char_384d","embedding_dim":384,"native_allocator":"system"}
```

- [ ] **Step 3: Compare against the pre-streaming realistic baseline only if it exists**

Search for realistic baseline rows:

```bash
rg -n '"embedding_dim":384|"target_text_mb"|"profile_label"' docs/perf/mimalloc-allocator-ab/runs
```

Expected interpretation:

```text
If no rows are found, record the HNSW streaming run as the first realistic baseline and do not compare it against legacy 32-dim JSONL.
```

- [ ] **Step 4: Update RESULTS.md with a system-only structural optimization note**

Add a section under `## Interpretation`:

```markdown
### HNSW Streaming Rebuild Platform Gate

The HNSW rebuild path streams SQLite rows into the native HNSW builder only
where the platform gate allows it. Treat macOS streaming as a platform-specific
structural memory optimization, not allocator adoption evidence and not
mobile-wide evidence. Keep iOS, Android, and unvalidated targets on the
collect-based path unless a dedicated experiment enables
`hnsw_streaming_rebuild`. Compare every claim against a realistic
system-allocator baseline only when both sides use 500-char chunks and 384-dim
embeddings.
```

---

## Task 4: BM25 Streaming Rebuild Follow-Up

**Files:**
- Modify later: `rust_builder/rust/src/api/bm25_search.rs:272-287`
- Modify later: `rust_builder/rust/src/api/source_rag.rs:948-987`
- Test later: `rust_builder/rust/src/api/bm25_search.rs:354-443`
- Test later: `rust_builder/rust/src/api/source_rag.rs:3112-3196`

Implement this only after Task 3 records the system-allocator HNSW streaming gate.

- [ ] **Step 1: Add an iterator-based BM25 batch helper**

Target helper shape in `bm25_search.rs`:

```rust
pub(crate) fn bm25_add_documents_iter<I>(docs: I) -> usize
where
    I: IntoIterator<Item = (i64, String)>,
{
    let mut index = INVERTED_INDEX.write().unwrap();
    let mut added = 0usize;
    for (doc_id, content) in docs {
        let before = index.len();
        index.add_document(doc_id, &content);
        if index.len() != before {
            added += 1;
        }
    }
    info!("[bm25] Added {} documents to index", added);
    added
}
```

Then make the existing FRB-compatible helper delegate to it:

```rust
pub fn bm25_add_documents(docs: Vec<(i64, String)>) {
    let _ = bm25_add_documents_iter(docs);
}
```

- [ ] **Step 2: Stream rows in `rebuild_chunk_bm25_index_for_collection_inner`**

Replace the `docs: Vec<(i64, String)>` collection in `source_rag.rs` with a `query_map` iterator passed to `bm25_add_documents_iter`.

- [ ] **Step 3: Verify BM25 behavior**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib bm25_search::tests -- --test-threads=1
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib source_rag::tests::test_completed_filter_excludes_pending_and_failed_sources -- --test-threads=1
```

Expected:

```text
test result: ok.
```

---

## Task 5: BM25 Tokenizer Allocation Follow-Up

**Files:**
- Modify later: `rust_builder/rust/src/api/bm25_search.rs:55-69`
- Preserve: `rust_builder/rust/src/api/bm25_search.rs:261-270`
- Test later: `rust_builder/rust/src/api/bm25_search.rs:370-443`

Implement this only after BM25 streaming rebuild is measured under the system allocator.

- [ ] **Step 1: Add a direct term-frequency helper**

Target helper shape:

```rust
fn bm25_term_freqs(text: &str) -> (HashMap<String, u32>, usize) {
    use unicode_segmentation::UnicodeSegmentation;

    let mut term_freqs: HashMap<String, u32> = HashMap::new();
    let mut doc_length = 0usize;
    for token in text.unicode_words().filter(|s| keep_bm25_token(s)) {
        doc_length += 1;
        *term_freqs.entry(token.to_lowercase()).or_insert(0) += 1;
    }
    (term_freqs, doc_length)
}
```

- [ ] **Step 2: Use the helper inside `InvertedIndex::add_document`**

Replace:

```rust
let tokens = tokenize_for_bm25(content);
let doc_length = tokens.len();
if doc_length == 0 {
    return;
}

let mut term_freqs: HashMap<String, u32> = HashMap::new();
for token in &tokens {
    *term_freqs.entry(token.clone()).or_insert(0) += 1;
}
```

with:

```rust
let (term_freqs, doc_length) = bm25_term_freqs(content);
if doc_length == 0 {
    return;
}
```

- [ ] **Step 3: Keep query tokenization stable**

Do not change `tokenize_for_bm25`; query paths and tests rely on the returned `Vec<String>`.

- [ ] **Step 4: Verify tokenization and ranking behavior**

Run:

```bash
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib bm25_search::tests -- --test-threads=1
```

Expected:

```text
test result: ok.
```

---

## Task 6: Final Structural Measurement And Mimalloc A/B

**Files:**
- Update: `docs/perf/mimalloc-allocator-ab/RESULTS.md`
- Read: `docs/perf/mimalloc-allocator-ab/README.md`
- Use: `example/integration_test/allocator_indexing_measure_test.dart`

- [ ] **Step 1: Measure `system + HNSW streaming + BM25 streaming + tokenizer reduction`**

Run:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/allocator_indexing_measure_test.dart \
  --profile -d <device-id> \
  --dart-define=EXPECTED_NATIVE_ALLOCATOR=system \
  --dart-define=EXPECTED_RUST_FEATURES=vector_faer,vector_quant_i8 \
  --dart-define=ALLOCATOR_INDEXING_TEXT_MB=5,10,25
```

- [ ] **Step 2: Measure `mimalloc + streaming` only after system improvement is recorded**

Run the same macro with the mimalloc native build and expected feature labels:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/allocator_indexing_measure_test.dart \
  --profile -d <device-id> \
  --dart-define=EXPECTED_NATIVE_ALLOCATOR=mimalloc \
  --dart-define=EXPECTED_RUST_FEATURES=vector_faer,vector_quant_i8,allocator_mimalloc \
  --dart-define=ALLOCATOR_INDEXING_TEXT_MB=5,10,25
```

- [ ] **Step 3: Apply the decision rule**

Record this exact interpretation in `RESULTS.md`:

```markdown
If the platform-appropriate structural path lowers peak RSS versus the realistic
system baseline, count that as structural rebuild memory improvement. If
mimalloc on top of that path still raises peak RSS materially, keep mimalloc
opt-in and do not default-enable it.
```

---

## Linear Tracking Recommendation

Use the existing Linear project:

```text
mobile_rag_engine mimalloc allocator validation
```

Use the existing Linear document for this plan and track four issues:

1. `HNSW platform-gated streaming rebuild`
2. `BM25 streaming rebuild without document Vec collect`
3. `Reduce BM25 tokenizer allocation`
4. `Measure platform-gated rebuild changes before mimalloc A/B`

The first issue should be the only implementation-ready issue immediately. The other three remain sequenced follow-ups so allocator, structure, and SQLite effects do not get mixed.

## Self-Review

- Spec coverage: The document keeps all connected memory optimization work in one plan and details only the HNSW implementation path as requested.
- Placeholder scan: No implementation step uses banned placeholder markers or unspecified error handling.
- Platform consistency: HNSW streaming is macOS-default only; non-macOS default rebuilds keep the collect-based path unless the explicit `hnsw_streaming_rebuild` feature is enabled.
- Type consistency: `build_hnsw_index_streaming` returns `anyhow::Result<usize>` in streaming tests and source rebuild call sites; the existing `build_hnsw_index(Vec<...>) -> anyhow::Result<()>` API remains intact.
