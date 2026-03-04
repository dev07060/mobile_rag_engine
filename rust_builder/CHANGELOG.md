# Changelog

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
