# Changelog

## 0.20.0-dev.5
* **Bug Fix**: Fixed a `PanicException` during Phase 2 of HNSW search by adding a missing cursor offset skip for `blob_len` (vector data) before reading `node_max_layer`.

## 0.20.0-dev.4
* **Bug Fix**: Fixed a binary header parsing bug in `custom_hnsw.rs` where the cursor size was `14` instead of `18` bytes, causing `failed to fill whole buffer` errors when loading the HNSW index.

## 0.20.0-dev.3
* **Critical Bug Fix**: Fixed HNSW and Linear search to read quantized blobs from `MMAP_STORE` via `mmap_id` when SQLite `embedding_i8` is empty. Fixed a false-positive in linear search fallback where empty arrays caused fake 0.0 similarity results.

## 0.20.0-dev.2
* **Bug Fix**: Fixed a critical bug in HNSW index rebuilding where `f32` vectors were read as empty instead of being dequantized from `i8` compressed blobs, causing a fallback to linear scan.

## 0.20.0-dev.1
* **VABQ Quantization**:
  - Implemented core VABQ (Variance-aware Adaptive Block Quantization) kernel in Rust (`vector_quant.rs`).
  - Asymmetric precision (INT8 for high-variance blocks, INT4 for low-variance blocks) optimizing for memory while preserving Recall.

## 0.19.2
* **Block-wise Quantization**:
  - Implemented block-wise scalar quantization (Q8_0 style) with 32-dimension block sizes.
  - Implemented backwards-compatible exact-scan similarity kernel supporting dynamic fallback for legacy 768-byte uniform blobs and new 864-byte packed blobs.
* **HNSW Reconstruction**:
  - Re-routed HNSW rebuilding to load original high-precision f32 embeddings directly, resolving the compound distortion loop and restoring semantic recall.

## 0.18.4
* **PDF extraction UX**:
  - Preserves the `scanned/image-only` marker for mixed scanned PDFs that also contain page-level extraction failures so host apps can route them to OCR.
  - Omits the OCR marker when every page fails to extract, avoiding misleading OCR guidance for fully corrupt/unsupported PDFs.
* **Release-path validation**:
  - Added i8 cosine, recall@10 floor, and cosine-fidelity safety nets for the shipped `vector_quant_i8` hot path.
  - Added fail-closed CI guards for the shipped `vector_faer,vector_quant_i8` feature combo.
  - Added bench-only i8 wrappers and measured i8 scan/hot-kernel baselines without changing production kernels.
* **Diagnostics**:
  - Logs corrupt f32 embedding blobs with row ids during index rebuild instead of silently skipping them.

## 0.18.3
* **PDF extraction quality**:
  - Preserved paragraph boundaries while normalizing PDF text so downstream chunking can split on semantic breaks instead of one long flattened body.
  - Added per-page PDF extraction with per-page fallback so a single malformed page no longer aborts the whole document.
  - Deduplicated dense adjacent double-rendered text artifacts seen in Korean PDFs while guarding natural repetitions and English words from false-positive rewrites.
  - Surfaced scanned/image-only or effectively empty PDF extraction as an error instead of silently indexing an unsearchable 0-chunk source.

## 0.18.2
* **Scoped BM25 search**:
  - Added scoped BM25 ranking over the existing in-memory inverted index, restricted by the scoped chunk ids collected during exact vector scan.
  - Removed query-time chunk-body reads/tokenization from the source/metadata scoped exact-scan path when BM25 is enabled.

## 0.18.1
* **Ingest session**:
  - Added extracted body byte/character lengths to `PreparedIngestion` so Dart file-ingest callers can display body-size metadata without materializing the full body.
  - Kept `prepare_source_ingestion_from_file` on the path-only fast path: the extracted body is measured in Rust while document text still avoids Dart FFI body transfer.

## 0.18.0
* **Retrieval hot path (copy-minimized Rust core)**:
  - Added `search_hnsw_slice(&[f32], usize)` and `search_hybrid_inner(String, &[f32], ...)` as borrowed-slice variants of the existing FFI-public entrypoints. The owned-`Vec<f32>` signatures of `search_hnsw` and `search_hybrid` are preserved for `flutter_rust_bridge` compatibility and now delegate to the slice helpers.
  - Updated `search_meta_hybrid`'s retry loop to borrow the query text, embedding, and options across attempts. A transient `ConcurrentMutation` no longer forces per-attempt `Vec<f32>` / `String` / `SearchMetaHybridOptions` clones.
  - Refactored the parallel vector + BM25 fan-out inside `search_hybrid_inner` to capture the embedding by reference inside `std::thread::scope` rather than cloning per spawn.
  - Replaced the per-file `decode_f32_embedding` copies in `source_rag.rs`, `hybrid_search.rs`, and `simple_rag.rs` with a single shared `vector_math::decode_f32_embedding` so the SQLite-BLOB → `Vec<f32>` decode path is owned in one place.
* **Quantization storage path (`vector_quant_i8` feature)**:
  - Added `quantize_f32_to_u8_blob(&[f32]) -> (Vec<u8>, f32)` which produces the SQLite BLOB representation directly without the intermediate `Vec<i8>` that `quantize_f32_to_i8` + `i8_blob_from_slice` previously required. The two paths are byte-for-byte identical and covered by a parity regression test.
  - Switched the four ingest/migration callsites (`source_rag.rs`, `simple_rag.rs`) that store quantized embeddings to the direct blob path.

## 0.17.0
* **Low-level lane**:
  - Added a generation-pinned `SearchHandle` with metadata-first hybrid search, batch hydration, excerpt fetch, and Rust-side context assembly.
  - Added bounded `SearchHitMeta` plus `StaleSearchHandle` / `ConcurrentMutation` error paths for low-level handle operations.
* **Search / Context**:
  - Added Rust-side context assembly primitives that preserve the current header-path contextual injection and exact engine-tokenizer budgeting contract.
  - Tightened `SearchHandle` hydration/excerpt/assembly generation checks to reject stale handles and mid-operation mutations deterministically.
* **Ingest**:
  - Added UTF-8 bytes and file-based extraction fast paths for additive low-level ingest APIs.
* **Test**:
  - Added regression coverage for generation bumps, stale-handle rejection, concurrent mutations during hydration/assembly, duplicate hydration requests, and low-level lane parity.

## 0.16.0
* **Chunking**:
  - Hardened plain-text heading detection against short imperative, UI-label, and command-style false positives.
  - Clarified the markdown table split contract around raw source-backed slices and non-repeated later headers.
* **Parser / Quality**:
  - Added parser regression coverage for mixed Unicode/PDF-like artifacts.
  - Added an ignored `join_pages()` stress benchmark for release-time performance checks.

## 0.15.0
* **Feat**:
  - Added non-truncating `count_tokens` support for exact engine-tokenizer budgeting paths.
* **Chunking**:
  - Tightened plain-text chunk planning with heading-aware boundaries and boundary-snapped overlap.
  - Standardized chunk offsets around raw source byte ranges for both plain-text and markdown paths.
* **Parser / Runtime**:
  - Promoted CJK newline restoration into the production page-join path.
  - Removed experimental CJK helper leftovers and reduced avoidable clone-heavy paths.

## 0.14.2
* **Fix**:
  - Normalized PDF extraction artifacts (private-use, noncharacter, and control code points) into safe separators to prevent broken box characters in extracted text.
  - Applied normalization before page-number trimming and dehyphenation to improve downstream chunking and embedding stability.
* **Test**:
  - Added regression coverage for malformed PDF spacing artifacts.

## 0.14.1
* **Feat**:
  - Added ingestion safety with claim/status/clear APIs and status-aware indexing in vectors.
* **Refactor**:
  - Refactored `vector_math` module to tighten internal function visibility.

## 0.14.0
* **Vector Math Refactor**:
  - Removed `ndarray` dependency; introduced `vector_math` module with allocation-free dot product, L2 norm, and cosine kernels.
  - Added optional `vector_faer` feature using `faer` crate for SIMD-accelerated vector operations.
* **i8 Scalar Quantization (`vector_quant_i8` feature)**:
  - Added `vector_quant` module with `quantize_f32_to_i8`, `dequantize_i8_to_f32`, and i8 cosine similarity kernels.
  - Updated `init_db` / `init_source_db` schema migration to add `embedding_i8` and `embedding_scale` columns.
  - Linear scan search paths (`search_similar`, `search_chunks_linear_in_collection`) use quantized cosine when available, with f32 fallback.
* **Benchmark API**:
  - Added `benchmark_search_linear_scan()` and `benchmark_search_chunks_linear_in_collection()` FFI entrypoints for deterministic linear scan measurement.
* **Code Quality**:
  - Applied `rustfmt` formatting across all source files.
  - Sorted module declarations alphabetically in `mod.rs`.
  - Removed unused `ndarray` crate dependency from `Cargo.toml`.

## 0.13.0
* **Multi-Collection Core**:
  - Added collection-scoped schema and lifecycle support (`collection_id` on sources/chunks, collection index state).
  - Added collection-aware source/chunk APIs for list/add/delete/stats/rebuild/search paths.
  - Preserved legacy compatibility through default collection mapping.
* **Hybrid Search Isolation**:
  - Extended `SearchFilter` with `collection_id`.
  - Updated exact-scan switching rules to trigger on source/metadata filters while preserving collection post-filter behavior.
  - Added collection-scoped activation hook to align BM25/HNSW in-memory indexes before hybrid search.
* **Reliability & Recovery**:
  - Improved collection activation and index-state transitions for load/rebuild flows.
  - Added/expanded tests for collection isolation, scoped dedupe, and filter semantics.

## 0.12.0
* **Logger Stability (Hot Restart)**:
  - Reworked Dart log sink ownership to `Arc<StreamSink<_>>` for safer cross-thread access.
  - Avoided holding logger locks while sending logs to Dart stream.
  - Switched log stream teardown to non-blocking cleanup to prevent restart deadlocks.
  - Added stale sink recovery on stream send failures.

## 0.11.0
* **Hybrid Search**:
  - Improved source-filter exact-scan path to keep scoped BM25 ranking.
  - Added regression test for source-filter + exact-keyword behavior.
* **Tokenizer**:
  - Added dynamic truncation policy by input length (256/384/512).
* **Chunking**:
  - Applied overlap prefix logic in `semantic_chunk_with_overlap`.
* **BM25**:
  - Improved tokenization to retain meaningful single-char CJK/code tokens.

## 0.10.2
* **Fix**: Corrected HNSW index loading path resolution in `load_hnsw_index`.
* **Fix**: Filtered out verbose debug logs from `hnsw_rs` crate.
* **Stabiity**: Handled uninitialized/empty index cases in `save_hnsw_index` to prevent crashes.

## 0.10.1
* Maintenance release:
  * Fix hnsw uninitialized error.(caused by updating hnsw cargo version)

## 0.10.0
* Maintenance release:
  * Updated dependencies.
  * Internal improvements for `mobile_rag_engine` compatibility.

## 0.9.1
* Improved markdown chunking logic:
  * **Structure Preservation**: Code blocks and tables are now split intelligently, preserving their type (`code`, `table`) instead of reverting to plain text.
  * **Code Block Linking**: Large code blocks split into multiple chunks now carry metadata (`batch_id`, `batch_index`, `batch_total`) to allow reconstructing the original block.
  * **Table Header Repetition**: Large tables split across chunks now automatically repeat the header row in every chunk to maintain column context.

## 0.9.0

- **Thread Configuration**: Added support for explicit thread count configuration in ONNX Runtime.
- **Memory Optimization**: Model loading now supports direct file path usage to reduce memory overhead.
- **Dependencies**: Bumps `mobile_rag_engine` compatibility.

## 0.8.0

- **Exact Scan Optimization**: Implemented brute-force vector scan for source-filtered searches, guaranteeing perfect recall within the selected source.
- **Smart Dehyphenation**: Fixed Korean text extraction to correctly handle words split by line breaks.
- **Dependencies**: Bumps `mobile_rag_engine` compatibility.

## 0.7.6

- **Duplicate Logs Fix**: Logger now only uses `println!` when Dart stream is not connected, preventing duplicate output.
- **Log Format**: Simplified log format to `[LEVEL] message` (removed redundant tags).

## 0.7.5

- **BM25 Index Fix**: Added `rebuild_chunk_bm25_index()` function to properly build BM25 index for Source RAG chunks.
- **Hybrid Search Fix**: BM25 keyword search now correctly works alongside Vector similarity search.
- **Initialization**: Both HNSW and BM25 indexes are now built during app initialization for existing chunks.

## 0.7.0

- **Metadata Support**: Added `metadata` column to `sources` table and support in `HybridSearchResult`.
- **Hybrid Search**: Enhanced `search_hybrid` with weighted scoring (Vector + BM25) and metadata retrieval.
- **Prompt Optimization**: Search results now include metadata for better LLM context construction.

## 0.6.1

- Updated README to remove specific version constraints in examples.
- Updated Supported Platforms documentation.

## 0.6.0
- **DB Connection Pool**: Implemented connection pooling with `r2d2` for 50-90% search performance improvement
- **Resource Optimization**: Eliminated redundant SQLite connections to reduce file descriptor usage
- **Refactoring**: Updated API to use pooled connections instead of direct file opens

## 0.5.1
- **Unit Tests**: Added tests for `hnsw_index` and `document_parser` modules
- **BM25 Korean Support**: Improved Korean tokenization using `unicode-segmentation` crate for better word boundary detection
- **Code Quality**: Enhanced test coverage for core Rust modules

## 0.5.0
- **PDF/DOCX Text Extraction**: New text extraction with smart dehyphenation
- **Markdown Chunking**: Structure-aware chunking with header path inheritance
- **PDF Fix**: Enhanced text normalization to preserve paragraph structure
- **Safety**: Added 50MB file size processing limit

## 0.4.0
- **Fix binary mismatch**: Rebuilt native binaries to resolve hash mismatch with Dart bindings.
## 0.3.0

- **Fix platform directories missing**: Include ios/, android/, macos/, linux/, windows/ in package
- Add .pubignore to prevent parent ignore rules from excluding platform configs

## 0.2.0

- **Fix package structure**: Include rust/ directory in package for correct pub.dev distribution
- Update platform build configs (iOS, macOS, Android, Linux, Windows) to reference internal rust/ path

## 0.1.0

- Initial release
- High-performance tokenization with HuggingFace tokenizers
- HNSW vector indexing for O(log n) similarity search  
- SQLite integration for persistent vector storage
- Semantic text chunking with Unicode boundary detection
- Prebuilt binaries for iOS, macOS, and Android
