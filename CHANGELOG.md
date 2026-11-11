# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased
* **Shipping without the bundled model works again**:
  - Apps that leave the model out of their release bundle and download it themselves failed in `MobileRag.initialize` with `Unable to load asset` in 0.23.0, because the engine read the bundled asset on every launch before looking at the copied file. When an asset is not in the bundle and a non-empty file exists where it would be copied, that file is used as it is, as up to 0.22.3, and a message is logged. If the model file is a different model, the embedding fingerprint still locks search until `reembedAll()` or `clearAndRestart()`. The tokenizer file is not checked this way, so keep it in step with the model.
  - `MobileRag.initialize(tokenizerPath:, modelPath:)` loads files your app placed on disk, without copying from assets. Use it instead of `tokenizerAsset`/`modelAsset` or `modelPack`, not together with them. See the [Release Build guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/release_build.md).
* **Short documents next to a large one are found by vector search again** (Rust core, needs the next `rag_engine_flutter` release):
  - A short document stored together with a large one, such as one sentence next to a 1820-chunk PDF, was missing from `search` and `searchHybrid` even with `topK: 50`, although a search limited to its source found it. The vector index kept, for every node, only the closest links, so a node far from the dense group of the large document's chunks lost every link that led to it and the search could not reach it. The index now picks links with the neighbour selection heuristic of the HNSW paper and, after the build, links any node that a search from the entry point cannot reach.
  - The same change raises vector recall on collections made of several documents: on a synthetic corpus of 20 dense groups, recall@10 against exact search went from 0.72–0.86 to 1.0, and building that index got faster. On uniformly random vectors, the worst case for the heuristic, building an index of more than 1,000 vectors takes about 3.6 times as long (5,000 vectors: 1.5 s to 5.5 s on an M-series Mac).
  - `.hnsw` files are now written as format version 2. A file written by 0.23.0 or earlier (version 1) is not loaded, and the first search after the upgrade rebuilds the index from the database once. The file layout is unchanged; downgrading to 0.23.0 likewise rebuilds the index once.
* **Documents can be added again after `clearAndRestart()`** (Rust core, needs the next `rag_engine_flutter` release): `clearAndRestart()` deletes every chunk and keeps the source rows. Adding a document whose content matches a kept source returned `isDuplicate: true` with no chunks ("Source ingestion already in progress"), so the documents could not be indexed again without removing the sources first. Such a source is now embedded again: `addDocument` returns its new `chunkCount` and the message "Source resumed and completed", like a resumed failed ingestion (`isDuplicate` stays `true` because the source row is reused). This applies to any completed source that has no chunks.
* **Dependencies**: requires `flutter_onnxruntime` 1.8.3 or later, up from 1.8.0. 1.8.0 can crash with out-of-memory on iPhone A18 and Mac M4 devices (fixed in 1.8.1), and apps built through Swift Package Manager with 1.8.0 to 1.8.2 are rejected by App Store Connect (ITMS-90208, fixed in 1.8.3). Apps whose lockfile still had one of these versions now move to a fixed version when they upgrade. On iOS and macOS, a `Podfile.lock` written with an earlier `flutter_onnxruntime` pins an older `onnxruntime-objc` (1.24.2 with 1.8.0, 1.23.0 with 1.8.1 to 1.8.4), so `pod install` can fail with "CocoaPods's specs repository is too out-of-date to satisfy dependencies". Run `pod update onnxruntime-objc onnxruntime-c` in `ios/` and `macos/` once.

## Known problems in earlier 0.22.x releases
Versions 0.22.0 to 0.22.2 shipped within two days and each had problems that a fresh app would hit. They were found after publishing and fixed in the next release. Use 0.22.3 or later.

| Version | Problem | Fixed in |
|---|---|---|
| 0.22.0 | A new iOS or macOS app that follows the README Installation steps fails in `pod install` (deployment target and static linkage were not set up). | 0.22.1 |
| 0.22.0, 0.22.1 | Release builds and store submission: Android release APKs abort on the first embedding (R8), iOS and macOS release or archive builds fail with `Failed to lookup symbol 'frb_get_rust_content_hash'`, the Android library is not 16 KB aligned, and iOS apps have no privacy manifest. Debug builds were unaffected. | 0.22.2 |
| 0.22.0 to 0.22.2 | Search results could be wrong without any error: after deleting a document and adding another, deleted text could match and new text could be missed. Also DOCX text extraction, hard-wrapped text chunking, and `database is locked` after `closeDbPool()`. | 0.22.3 |

If you are on one of these versions, upgrade to 0.22.3 or later. The first launch after upgrading to 0.22.3 rebuilds the vector index once.

## 0.23.0
* Requires `rag_engine_flutter: 0.22.0`.
* **Breaking**:
  - `currentEmbeddingFingerprint` has a fourth component, the model-content hash. A 0.22.3 database is updated in place on its first launch (see "Model swaps" below).
  - `flutter_rust_bridge` is pinned to 2.13.0. Apps that depend on it directly must allow 2.13.0.
  - `MobileRag` and `CollectionRag` have new methods (`ask`, `prepareAsk`), so classes that `implements` them must add these. `mocktail` mocks are unaffected.
* **Search quality for dense scripts** (with `rag_engine_flutter` 0.22.0):
  - Chunks are embedded up to 512 tokens instead of a limit chosen by character count, which cut most Korean, Japanese and Chinese chunks under 1,200 characters at 256 tokens. In a desktop measurement on a Korean retrieval benchmark, nDCG@10 rose from 0.907 to 0.942 (`TextChunker.recursive`) and from 0.805 to 0.895 (`TextChunker.markdown`).
  - Dense text is split into fewer, fuller chunks. English text at the default chunk size is chunked as before.
  - Markdown chunks, including code blocks and tables, now fit the token limit, so no text is dropped at embedding time.
  - Existing databases keep working. Re-ingesting Korean, Japanese or Chinese documents is optional and recovers the truncated text.
* **Search** (with `rag_engine_flutter` 0.22.0):
  - Korean keyword search matches words with attached particles: a query for "검색엔진" finds "검색엔진은".
  - Building the vector index after adding or removing documents is about 3.8× faster, and vector search is about 2× faster.
* **Ingestion** (with `rag_engine_flutter` 0.22.0): chunking long Korean and other token-dense text that has to be split is up to 3× faster.
* **Model swaps are detected by content** (with `rag_engine_flutter` 0.22.0): the embedding fingerprint includes a hash of the model file (its size and first and last MiB), not only its file name and dimension. Replacing a model with another of the same name and dimension, such as two 384-dimension `model_qint8_arm64.onnx` exports, now locks search and ingestion until `reembedAll()` or `clearAndRestart()`, instead of mixing vectors from both models. Existing databases are updated in place on the first launch when the model file name and dimension still match and the loaded model reproduces the stored vectors of three short chunks (cosine similarity of at least 0.95). Only those three chunks are embedded again. If one app update both upgrades and switches to another model under the same name, the database is locked instead of being updated. `currentEmbeddingFingerprint` gains a fourth component.
* **Search results for LLMs**: `RagSearchResult.toLlmJson()` returns the passages that fit the token budget as JSON (`{"results": [...]}`), with citation ids, source and chunk ids, source names, scores and text. Each passage text appears once. `score` is relative to the best passage in the result (1.0), because hybrid search scores are rank-based and too small to read on their own. Citation ids start at `firstId`; a `RagSearchTool` keeps counting across calls so ids never collide in one conversation. `RagSearchTool.fromCollection` takes a collection id and looks the collection up on every call, so it keeps working after re-initializing. `RagSearchTool` exposes hybrid search as an LLM tool: `definition` is a provider-neutral JSON Schema tool definition, and `call`/`callJson` run the model's tool call and return the JSON tool result. Invalid arguments come back as `{"error": ...}` so the model can retry. No LLM SDK is added; see the [LLM Tools guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/llm_tools.md) for OpenAI, Anthropic and Gemini formats.
* **Searching without documents** (with `rag_engine_flutter` 0.22.0): hybrid search (`searchHybridWithContext`, `RagSearchTool`, `ask`) on a database or collection with no documents returns no results instead of throwing `RagError.invalidInput("HNSW cache parity failed ...")`. This also happened in 0.22.3, for example in an app searching before its first document was added, or a collection whose documents were all removed.
* **Answers with citations**: `MobileRag.ask(question, generate: ...)` and `CollectionRag.ask` search with hybrid search (5 passages within 1500 tokens by default), build a prompt with numbered passages, call your generation function and return a `RagAnswer` with the answer text, the passages given to the model and the passages it cites (`[1]`, `[1, 2]` or `[1][2]`). Citation ids start at 1 for every question, and cited ids that were not in the prompt are left out. When no passage fits the budget, the generation function is not called and the answer is empty. To stream, `prepareAsk` returns the prompt and passages, and `RagAskPrompt.answer(text)` reads the citations from the complete answer. The prompt can be replaced with `buildPrompt`. No LLM SDK is added; see the [Ask guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/ask.md).
* **Stale model and tokenizer copies are replaced**: with `modelAsset`/`tokenizerAsset`, a copy left by an earlier run is rewritten when the bundled asset differs, instead of being kept because a file with that name exists. Switching tokenizers, or an app update that changes a model under the same file name, previously kept the old file, which could fail with an out-of-range `Gather` error or embed with the wrong model. Each copy now has an `.asset-stamp` file beside it, and every launch loads and hashes the bundled assets to compare. The first launch after upgrading copies both files once more. Model Packs are unchanged.
* **Dependencies**: `flutter_rust_bridge` is pinned to 2.13.0, up from 2.11.1, and needs `rag_engine_flutter` 0.22.0. The pin stays exact because the generated bindings must match the runtime version. Apps that also depend on `flutter_rust_bridge` directly must allow 2.13.0.

## 0.22.3
* Requires `rag_engine_flutter: 0.21.2`.
* **Search** (with `rag_engine_flutter` 0.21.2):
  - Deleted documents no longer appear in results after other documents are added, and newly added chunks are found by keyword search without a manual `rebuildIndex()`.
  - The first launch after upgrading rebuilds the vector index once.
* **Document extraction** (with `rag_engine_flutter` 0.21.2):
  - DOCX text keeps its spaces, tabs and line breaks, and tables, text boxes, headers, footers and footnotes are included in place. A DOCX ingested before this version extracts to different text, so adding it again creates a new source instead of being detected as a duplicate.
  - PDFs that only restrict copying or printing are now accepted.
* **Chunking** (with `rag_engine_flutter` 0.21.2):
  - Hard-wrapped text (for example from PDFs) is no longer split into one chunk per line, so these documents produce fewer, fuller chunks.
  - Chunks, including their overlap, now fit the embedding model's token limit, so no text is dropped at embedding time.
  - `overlapChars` is clamped below half of `maxChunkChars`, with a warning.
* **Database**: `closeDbPool()` returns only after every SQLite connection is closed, so writing to or deleting the database right after it no longer fails with `database is locked` or a file-in-use error, most often on Windows (with `rag_engine_flutter` 0.21.2).
* **Ingestion**: `chunkDelay` now defaults to no pause between embedding batches (previously 10 ms). Pass a duration to throttle long ingestions.

## 0.22.2
* Requires `rag_engine_flutter: 0.21.1`.
* **Release builds**:
  - Android release builds no longer abort on the first embedding. R8 removed ONNX Runtime classes; the native companion now ships the keep rule.
  - iOS release builds and iOS/macOS archives keep the Rust symbols Dart looks up at runtime, instead of failing with `Failed to lookup symbol 'frb_get_rust_content_hash'`.
  - Debug builds were unaffected. Apps on earlier versions can apply the same settings by hand (see Troubleshooting).
* **Store submission**:
  - The Android native library is 16 KB page aligned, as Google Play requires for apps targeting Android 15+.
  - iOS apps get a privacy manifest for the required-reason APIs the bundled SQLite uses, so App Store review accepts them.

## 0.22.1
* **Setup applies the Apple host settings**:
  - Requires `rag_engine_flutter: 0.21.0` (unchanged from 0.22.0).
  - `dart run mobile_rag_engine:setup` now raises the iOS and macOS host settings the native dependencies need: the Podfile `platform` (iOS 16.0 / macOS 14.0), the Runner deployment target, and `use_frameworks! :linkage => :static`. Previously a fresh `flutter create` app that followed the README Installation steps failed in `pod install`. Higher targets are kept, each change is printed, `--check` fails while changes are pending, and `--skip-host-config` opts out.

## 0.22.0
* **Windows (x64)**:
  - Requires `rag_engine_flutter: 0.21.0`.
  - Supported on Windows 10+ x64 through the native companion's Windows plugin and signed pre-compiled binary. No Rust toolchain is required, as on the other platforms. Windows on ARM64 and Linux are not supported.
  - On Windows, the database, index files and copied model assets live in the app support directory (`%APPDATA%\<company>\<app>`) instead of the user's Documents folder. Other platforms keep their existing location.
* **Fixes**:
  - `clearAllData()` unmaps the loaded HNSW index before deleting it. Windows refuses to delete a memory-mapped file.

## 0.21.0
* **No Rust toolchain required**:
  - Requires `rag_engine_flutter: 0.20.0`, which ships signed pre-compiled binaries for Android, iOS and macOS. Builds without `rustup` download and verify them instead of compiling Rust. With `rustup` installed, the core is still built from source.
  - Windows and Linux are not supported.
* **Breaking**:
  - Removed `VabqProfile` from the public API: `MobileRag.initialize(vabqProfile:)`, `RagConfig.vabqProfile` and `RagConfig.fromAssets(vabqProfile:)`. Storage is always Q8_0. Only apps that opted into VABQ on a 0.21.0 dev release are affected. Their databases report an embedding-fingerprint mismatch; call `regenerateAllEmbeddings()` or `clearAllData()`.
* **Model Pack onboarding** (since 0.21.0-dev.11): `dart run mobile_rag_engine:setup` -> `--check` -> `RagModelPack.asset(...)` is the recommended install-to-first-search path.
  - Cold start no longer re-hashes the model on every launch. A `.verified` marker is written after the pack is verified once.
* **Fixes**:
  - `clearAllData()` now deletes the mmap vector store (`.vec`), every HNSW index (including non-default collections), `.dirty` markers and SQLite sidecars. Previously, quantized embeddings could be left on disk, and an old index could be reused against the new database.
  - Re-embedding, non-multiple-of-32 embedding dimensions, corrupt `.hnsw` and empty `.vec` files are fixed in the native companion (see `rag_engine_flutter` 0.20.0).
  - Includes the 0.20.1 fixes: `search()` no longer prints the query text and query-embedding values via `debugPrint`, and interrupted ingestions are recovered on startup.


## 0.21.0-dev.12
* **Initialization reliability**:
  - Serialized embedding fingerprint initialization ahead of deferred BM25/HNSW warmup, preventing fresh-database SQLite lock contention.
  - Made `clearAllData()` wait for active warmup and complete replacement index initialization before immediate re-ingest.

## 0.21.0-dev.11
* **Model Pack onboarding**:
  - Made the immutable MiniLM Model Pack `setup` -> `--check` -> manifest initialization flow the recommended install-to-first-search path.
* **Storage contract**:
  - Kept Q8_0 as the public default and VABQ as an explicit advanced research opt-in, without making speed, RSS, or retrieval-quality claims for VABQ.
* **Native compatibility**:
  - Aligned exactly with hosted `rag_engine_flutter 0.20.0-dev.11` and `flutter_rust_bridge 2.11.1`.
* **macOS qualification boundary**:
  - A fresh macOS consumer completed Model Pack initialization and first search in profile mode plus a separate universal release build with this root as a clean path package and the native companion hosted. This is not a fully hosted root-package proof until this version is published and retested from pub.dev.

## 0.21.0-dev.5
* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.5` fixing HNSW Phase 2 binary offset calculation, preventing search panics.

## 0.21.0-dev.4
* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.5` fixing HNSW index loading (buffer size 14 -> 18).

## 0.21.0-dev.3
* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.5` fixing MMAP data reading and false 0.0 similarities in linear search fallback.

## 0.21.0-dev.2
* **Bug Fix**: Required `rag_engine_flutter: ^0.20.0-dev.5` which fixes a critical HNSW index rebuilding bug where quantized embeddings were not unpacked, causing a fallback to linear scanning.

## 0.21.0-dev.1
* **VABQ Research Engine**:
  - Added experimental Variance-aware Adaptive Block Quantization (VABQ) research support.
  - VABQ is an explicit advanced opt-in; normal initialization continues to use Q8_0 storage by default. This research entry does not make general speed, memory, or retrieval-quality claims relative to Q8_0.

## 0.20.1
* **Privacy**:
  - `search()` no longer prints the query text and query-embedding values through `debugPrint`, which also emitted them in release builds.
* **Ingestion recovery**:
  - Requires `rag_engine_flutter: ^0.19.3`: sources interrupted mid-ingest by a crash or kill are marked `failed` on next startup instead of staying `processing` forever, so re-adding them resumes ingestion.
* **Documentation**:
  - Corrected the install requirements: published packages do not include pre-compiled binaries, so a Rust toolchain (rustup) is required. Windows and Linux are removed from the supported platforms. Model download URLs are pinned to a fixed revision.

## 0.20.0
* **Block-wise Quantization**:
  - Integrated block-wise scalar quantization (Q8_0 style, 32-dim blocks) for on-device exact-scans.
  - Implemented backward-compatible dynamic fallback in distance similarity logic to search both legacy 768-byte uniform blobs and new 864-byte packed block-wise blobs.
* **Retrieval Quality**:
  - Optimized HNSW index rebuild loops to load original high-precision f32 database embeddings directly, resolving the compound distortion loop and restoring semantic query recall to baseline parity.
* **Compatibility**:
  - Bumped native dependency constraint to `rag_engine_flutter: ^0.19.2`.

## 0.19.1
* **Packaging**:
  - Fixed the publish archive so `lib/models/*.dart` is included again.

## 0.19.0
* **Compatibility**:
  - Replaced the unmaintained `onnxruntime` package dependency with `flutter_onnxruntime: ^1.8.0`.
  - Updated ONNX session, tensor, output, and cleanup handling to the `flutter_onnxruntime` API while keeping the existing `EmbeddingService` public API.
  - Raised the documented iOS/macOS runtime requirements to match `flutter_onnxruntime`: iOS 16.0+ and macOS 14.0+.
* **Validation**:
  - Validated the runtime swap with local init/embed/repeat/dispose/reinit smoke coverage.

## 0.18.6
* **PDF extraction UX**:
  - Added OCR-needed classification helpers for scanned/image-only PDF extraction errors.
  - Keeps mixed scanned + partially failed PDFs on the OCR-recoverable path while leaving fully failed/corrupt PDFs as raw extraction errors.
  - Clarified production support boundaries: text-layer PDFs are production-ready, scanned PDFs require app-provided OCR, and DOCX remains beta.
* **Release-path validation**:
  - Added i8 hot-path recall/fidelity safety nets for the shipped `vector_quant_i8` path.
  - Runs the shipped `vector_faer,vector_quant_i8` native feature combo in CI with fail-closed checks for renamed or skipped safety nets.
  - Logs corrupt f32 embedding blobs with row ids during HNSW rebuild instead of silently dropping them.
* **Packaging**:
  - Excludes profiler-only example harnesses and tests from the published archive.
* **Compatibility**:
  - Bumped dependency constraint to `rag_engine_flutter: ^0.18.4` so consumers receive the matching native hardening patch.

## 0.18.5
* **PDF extraction quality**:
  - Bumped dependency constraint to `rag_engine_flutter: ^0.18.3` so consumers receive the native PDF extraction improvements.
  - Preserves paragraph boundaries during PDF extraction, improving downstream semantic chunking for long documents.
  - Recovers around per-page PDF extraction failures instead of failing the entire document when one page is malformed.
  - Cleans dense adjacent double-rendered text artifacts while keeping conservative false-positive guards for natural repetitions and English words.
  - Surfaces scanned/image-only or effectively empty PDFs as extraction errors instead of silently indexing unsearchable 0-chunk sources.

## 0.18.4
* **Retrieval hot path**:
  - Scoped source/metadata hybrid searches now preserve BM25 ranks through the active collection BM25 term index instead of reading and tokenizing every scoped chunk body at query time.
  - Updated scoped exact-scan benchmarks to assert zero query-time body reads and zero body tokenization for both vector-only and BM25-on scoped paths.
* **Compatibility**:
  - Bumped dependency constraint to `rag_engine_flutter: ^0.18.2` so consumers receive the matching native scoped BM25 search implementation.

## 0.18.3
* **Documentation**:
  - Removed the oversized README memory benchmark note from the top of the pub.dev page.
  - Aligned guide and example snippets with the current `MobileRag` facade and file-path ingest APIs.
  - Fixed stale example model download URLs and clarified the supported platform/documentation release guidance.

## 0.18.2
* **Ingest fast path**:
  - Updated example/evaluation runners to use `addDocumentFromFile(...)` so PDF and asset-backed ingestion exercise the Rust-side file fast path instead of the removed byte-ingest compatibility call.
  - Exposed extracted body byte/character lengths through `SourceAddResult` for file-path ingest UIs without materializing the full body in Dart.
* **Compatibility**:
  - Bumped dependency constraint to `rag_engine_flutter: ^0.18.1` because the body-length fields are part of the generated Rust FFI surface.
* **Packaging**:
  - Excluded generated docs and local scratch output directories from the published archive.

## 0.18.1
* **Compatibility**:
  - Bumped dependency constraint to `rag_engine_flutter: ^0.18.0` so consumers actually receive the matching native release with the 0.18.0 retrieval hot-path optimizations. The 0.18.0 publish shipped with the prior `^0.17.0` constraint by mistake and resolved to `rag_engine_flutter 0.17.0` for new installs.

## 0.18.0
* **Embedding path (zero-copy transport)**:
  - `EmbeddingService.embed()` now returns `Future<Float32List>` (previously `Future<List<double>>`). The worker isolate narrows the mean-pooled vector to `Float32List` before transfer and delivers it via `TransferableTypedData`, eliminating the isolate-boundary deep copy and the downstream `Float32List.fromList(...)` re-allocation at every ingest callsite.
  - `EmbeddingService.embedBatch()` returns `Future<List<Float32List>>` by the same narrowing. Mean-pooling accumulation still happens in `Float64List` so numerical output is bit-identical to the prior f64 → f32 narrowing performed at the receiver.
  - Removed redundant `Float32List.fromList(embedding)` wrappers in `SourceRagService.addSource()` and `SourceRagService.regenerateAllEmbeddings()`.
* **Retrieval hot path (Rust core)**:
  - Hybrid and metadata-first search no longer clone the query embedding on every attempt. The `search_meta_hybrid` retry loop, `search_hybrid`'s parallel `std::thread::scope` fan-out, and the incremental-index lookup all borrow the embedding by reference via the new `search_hnsw_slice` / `search_hybrid_inner` slice helpers. Public FRB signatures of `search_hnsw` and `search_hybrid` are unchanged.
  - Consolidated the SQLite-BLOB `decode_f32_embedding` helper into `vector_math` (previously duplicated in `source_rag.rs`, `hybrid_search.rs`, and `simple_rag.rs`).
  - Added `quantize_f32_to_u8_blob` for the `vector_quant_i8` feature so chunk-ingest and re-embedding write the quantized SQLite BLOB without first materializing a `Vec<i8>`.
* **Migration note**:
  - `Float32List` implements `List<double>`, so `final List<double> e = await embed(x);` and all read-only usages (`e[i]`, `e.length`, iteration, `.fold(...)`) continue to compile and run. Growable-list mutations such as `.add(...)` or `.removeAt(...)` on the returned vector will throw at runtime; embedding vectors were never intended to be appended to in practice.
* **Docs**:
  - Updated README coverage for the file/UTF-8 ingest fast paths (`addDocumentFromFile`, `addDocumentUtf8`).
  - Added README guidance for the metadata-first search lane (`searchMeta`, `assembleContext`, `hydrateChunks`, `getChunkExcerpts`).
  - Clarified memory and advanced-usage wording for the 0.18.0 embedding transport changes.

## 0.17.0
* **Low-level APIs**:
  - Added an additive metadata-first search lane with `searchMeta`, `assembleContext`, `hydrateChunks`, and `getChunkExcerpts`.
  - Added `addDocumentUtf8` and `addDocumentFromFile` as ingest fast paths that reduce input-side string materialization.
* **Search / Compatibility**:
  - Preserved existing `search()` and `searchHybridWithContext()` semantics while introducing generation-pinned low-level handles underneath.
  - Added deterministic stale-handle and concurrent-mutation error coverage for low-level search-handle operations.
* **Compatibility**:
  - Updated dependency constraint to `rag_engine_flutter: ^0.17.0`.

## 0.16.0
* **Context**:
  - Improved `ContextBuilder` packing to skip oversized chunks instead of stopping at the first overflow.
  - Added `ContextBuilder.deriveContextBudgetForPrompt(...)` and `PromptBudgetOptions` for full-prompt budgeting on top of exact `context.text` counting.
* **Chunking**:
  - Hardened plain-text heading detection against short imperative, UI-label, and command-style false positives.
  - Clarified markdown table splitting to preserve raw source-backed slices without synthetic repeated header rows in later chunks.
* **Parser / Quality**:
  - Added parser regression coverage for mixed Unicode/PDF-like artifacts and an ignored `join_pages()` stress benchmark.
* **Docs**:
  - Clarified README memory wording to describe a copy-minimized Rust core rather than end-to-end zero-copy FFI transport.
* **Compatibility**:
  - Updated dependency constraint to `rag_engine_flutter: ^0.16.0`.

## 0.15.0
* **Feat**:
  - Switched context budgeting to exact engine-tokenizer counting through a shared rendered-context path.
* **Chunking**:
  - Improved plain-text chunking with heading-aware boundaries and boundary-snapped overlap semantics.
  - Preserved markdown contextual path information consistently through embed, re-embed, and retrieval flows.
* **Docs**:
  - Aligned chunking, `tokenBudget`, `overlapChars`, and markdown header-path contracts with runtime behavior.
* **Compatibility**:
  - Updated dependency constraint to `rag_engine_flutter: ^0.15.0`.

## 0.14.4
* **Fix**:
  - Improved PDF text quality by consuming `rag_engine_flutter 0.14.2`, which normalizes private-use/noncharacter extraction artifacts into safe separators.
* **Docs**:
  - Added a new release optimization guide: `docs/guides/release_build.md`.
  - Linked the new guide in README under `Guides`.
* **Compatibility**:
  - Updated dependency constraint to `rag_engine_flutter: ^0.14.2`.

## 0.14.3
* **Feat**:
  - Added ingestion safety with claim/status/clear APIs and status-aware indexing.
* **Refactor**:
  - Moved ONNX inference to a dedicated background isolate for better UI performance without dropping frames.
  - Extracted data classes into `lib/models/` directory for better structural organization.
  - Extracted `RagController` from the example app to simplify `main.dart` into pure UI code.
* **Fix**:
  - Restored global DB pool after quality test cleanup.
  - Changed internal error messages to English for better international developer experience.

## 0.14.2
* **Fix**:
  - Added dynamic ONNX input handling for `token_type_ids` based on model `inputNames`.
  - Improved inference error messaging for input-signature mismatches (includes model input names).
  - Centralized config/search defaults into shared internal constants.
  - Added runtime soft validation for chunking config, thread conflict handling, and hybrid search weights.
  - Aligned low-level `SourceRagService.searchHybrid` defaults to `vector=0.2`, `bm25=0.8`.
  - Hardened embedding runtime with single FIFO serialization across `init/embed/embedBatch`.
  - Added embedding dimension baseline guard (fail-fast on mismatch with recovery guidance).
  - Switched re-initialization to safe session swap (keep old session until new session is ready).
  - Added deterministic `EmbeddingService.disposeAsync()` and updated engine/isolate cleanup paths.
* **Docs**:
  - Clarified model compatibility constraints (`input_ids`, `attention_mask`, optional `token_type_ids`).
  - Added validated ONNX artifact references and troubleshooting guidance for `Missing Input: token_type_ids`.
  - Synchronized docs with effective defaults and runtime validation behavior.

## 0.14.1
* **Docs**: 
  - Update feature documents
* **Refactor**: 
  - Refactoring example app `main.dart`

## 0.14.0
* **Vector Math Refactor**:
  - Replaced `ndarray` dependency with a zero-allocation `vector_math` module for mobile-optimized cosine similarity, dot product, and L2 norm.
  - Added optional `faer` backend (`vector_faer` feature) for SIMD-accelerated vector math.
* **i8 Scalar Quantization (Feature-Gated)**:
  - Added `vector_quant_i8` feature flag for i8 scalar quantization support in search paths.
  - Schema migration adds `embedding_i8` and `embedding_scale` columns to `docs` and `chunks` tables.
  - Linear scan search paths support quantized cosine similarity with f32 fallback.
* **Benchmark Service**:
  - Added `DetailedBenchmarkStats` with warmup, p50/p95 percentiles, stddev, and raw sample collection.
  - Added `benchmarkDetailed()`, `collectSamples()`, `summarizeSamples()`, and `aggregateRoundStats()` APIs.
* **Benchmark FFI**:
  - Added `benchmarkSearchLinearScan()` for deterministic linear scan measurement (bypasses HNSW).
  - Added `benchmarkSearchChunksLinearInCollection()` for collection-scoped linear scan benchmarks.
* **Code Quality**:
  - Applied `rustfmt` formatting across all Rust source files.
  - Sorted module declarations alphabetically in `mod.rs`.

## 0.13.0
* **Multi-Collection v1**:
  - Added collection-scoped workflows via `MobileRag.inCollection(...)` / `CollectionRag`.
  - Added optional `collectionId` support across core operations (ingest/search/rebuild/stats/list/remove).
  - Kept backward compatibility with default `__default__` collection behavior.
* **Search & Index Isolation**:
  - Scoped hybrid search filters by collection and aligned collection-specific index activation before query.
  - Updated delete/rebuild flows to operate on the active collection context.
* **Initialization Stability**:
  - Added per-collection init in-flight guard to prevent duplicate concurrent initialization.
  - Shared logger stream ownership across collection-scoped services to avoid duplicate logger bootstrap/freeze scenarios.
* **Crash Recovery Visibility**:
  - Restored ingest status visibility by creating source rows before long embedding work.
  - Improved failure handling to persist `failed` state for interrupted/failed ingests.
* **Example App DX**:
  - Moved collection testing into the main example screen (collection switch/apply/chips).
  - Updated sample load and delete-all behavior to be collection-aware for non-default collections.
* **Docs**:
  - Updated README.md for added features

## 0.12.0+1
* **Fix engine version**:
  - fix rag engine version

## 0.12.0
* **Initialization & DX**:
  - Added `deferIndexWarmup` to `MobileRag.initialize(...)` and `RagConfig`.
  - Added `isIndexReady` and `warmupFuture` to `MobileRag`/`RagEngine` for explicit warmup gating.
  - Enabled non-blocking startup path so UI can render before BM25/HNSW warmup completes.
* **Index Lifecycle Reliability**:
  - Serialized index warmup/rebuild tasks to prevent overlapping rebuild operations.
  - Added dirty-version tracking to avoid stale clean-state during concurrent mutations.
  - Normalized index/dirty marker paths for `.sqlite3`, `.sqlite`, and `.db` database names.
  - Expanded `clearAllData()` cleanup to remove legacy/new HNSW artifact naming patterns.
  - Preserved defer policy when reinitializing service after `clearAllData()`.

## 0.11.0+1
* **Fix Pub readme**:
  - Fix Broken Readme on Pub.dev

## 0.11.0
* **Retrieval Quality**:
  - Applied `overlapChars` in semantic chunk overlap path.
  - Preserved `chunkIndex` in source-filtered hybrid search path.
  - Improved source selection heuristic for short/CJK query terms.
  - Updated hybrid default weights to `vector=0.2`, `bm25=0.8`.
* **Search/Core**:
  - Added dynamic tokenizer truncation policy (256/384/512 by input length).
  - Improved BM25 tokenization for single-char CJK/code-like tokens.
  - Kept scoped BM25 contribution in source-filter exact-scan hybrid path.
* **Context Assembly**:
  - Refined context token budget estimation using rendered output size.
  - Reduced single-source output overhead by skipping header wrappers.
* **Quality & CI**:
  - Added offline evaluation runners and evalset fixtures in `example/`.
  - Split test tiers (`unit` / `native`) and added dedicated CI gates.

## 0.10.4
* **New API**: Added data retrieval methods to `MobileRag` facade:
  - `getSourceChunks()` — retrieve all chunk texts for a specific source document.
  - `getSourceChunkCount()` — get the number of chunks for a source (useful for pagination and batch processing).
  - `getSourceDocument()` — get original source document content by source ID.
  - `getAdjacentChunks()` — context expansion without going through the service layer directly.
* **Export**: Added `ChunkForReembedding` type to public exports for custom re-embedding scenarios.

## 0.10.3+1
* **Code Quality**: Removed unnecessary imports to improve pub score.

## 0.10.3
* **Stability**: Fixed HNSW index persistence issue where index was not saved to disk on creation.
* **Performance**: Offloaded PDF chunking and embedding to a background isolate to prevent UI freezes.
* **UX**: Restored progress reporting for document addition using `Isolate` communication.
* **Internal**: Optimized initialization flow to ensure index is persisted immediately after rebuild.


## 0.10.2
* Maintenance release:
  * Fix hnsw uninitialized error.(caused by updating hnsw cargo version)


## 0.10.1
* **Documentation**: Updated README and Quick Start guide.

## 0.10.0
* **Testing Support**: Added `mocktail` dev dependency and fixed mock testing utilities.
* **Internal Refactoring**: Improved `SourceRagService` and internal APIs.
* **Documentation**: Updated guides and examples.

## 0.9.3
* **Core Engine Update**: Incorporates `rag_engine_flutter` v0.9.2 improvements.
  * Enhanced markdown chunking with structure preservation for code blocks and tables.
  * Added linking metadata for split code blocks to support context reconstruction.
  * Improved handling of large tables with automatic header repetition.

## 0.9.2

### Changed
- **README Overhaul**: Redesigned Features section with End-to-End RAG Pipeline diagram and Key Features table.
- **Documentation**: Streamlined structure by consolidating Architecture and Benchmarks into Features section.
- **Visual Improvements**: Updated all images to consistent width (860px) for better presentation.

## 0.9.1

### Added
- **Contextual Chunk Retrieval for Hybrid Search**: `searchHybridWithContext()` now supports `adjacentChunks` and `singleSourceMode` parameters for feature parity with `search()`.

### Fixed
- **Code Quality**: Removed unnecessary `dart:typed_data` imports (already provided by `flutter/foundation.dart`).

## 0.9.0

### Added
- **ThreadUseLevel API**: New high-level thread configuration with `ThreadUseLevel.low` (~20%), `medium` (~40%), and `high` (~80%) options for easier CPU usage control.
- **Memory Optimization**: ONNX model is now loaded from file instead of memory buffer, reducing Dart heap usage by ~20-50MB (model size).

### Changed
- **Documentation**: Updated README and Quick Start guide with `threadLevel` parameter and full parameter table.
- **Architecture Section**: Updated to reflect Hybrid Search (HNSW + BM25 with RRF fusion).

### Fixed
- **API Consistency**: `threadLevel` and `embeddingIntraOpNumThreads` are now mutually exclusive (throws `AssertionError` if both set).

## 0.8.0


### Added
- **Independent Source Search (Exact Scan)**: When filtering by `sourceIds`, the engine now switches to a brute-force scan of ALL chunks in that source. This guarantees perfect recall within a specific document, bypassing global index limitations.
- **Advanced Documentation**: Expanded "Quick Start" guide with "Advanced Features" (Cached Index, LLM Context, usage of `searchHybridWithContext`).
- **API Improvements**: Exported `SourceStats` type for easier usage of `getStats()`.

### Fixed
- **PDF Text Extraction**: Improved "Smart Dehyphenation" to correctly handle broken newlines in Korean text (joining words split by line breaks incorrectly).
- **Example App**: Fixed crash when deleting sources caused by incorrect `BuildContext`.

## 0.7.11

### Fixed
- **Reverted Model Integration**: Reverted changes related to `ko-sroberta` integration due to ONNX runtime compatibility issues (`Invalid Feed Input Name:token_type_ids`).
- **Stability**: Restored original embedding logic compatible with standard models (e.g., `bge-m3`, `all-MiniLM-L6-v2`).

## 0.7.10 (Withdrawn)
- Attempted `ko-sroberta` integration (caused runtime errors).

## 0.7.9

### Fixed
- **Library Exports**: Added missing exports for `BenchmarkService`, `QualityTestService`, `PromptCompressor`, and `SemanticChunk` types. Now all services are accessible via the main library import.
- **Example App**: Fixed internal import paths in example code to use the public API.
## 0.7.8

### Changed
- **API Clean-up**: Refactored global functions into namespaced classes for better DX.
  - `extractTextFrom*` → `DocumentParser.*`
  - `parseUserIntent` → `IntentParser.classify`
- **Error Handling**: Exported `RagError` class for proper error catching.
- **Documentation**: 
  - Updated `quick_start.md` and `example/example.md` to match the new API.
  - Updated `mobile_rag_engine.dart` API usage examples.

## 0.7.6

### Fixed
- **Duplicate Logs**: Fixed issue where Rust logs were printed twice (both to console and Dart stream).
- **Log Format**: Simplified log format from `[Rust] [INFO] message` to `[INFO] message`.

### Changed
- **Logger**: Rust logger now only uses `println!` when Dart stream is not connected, avoiding duplicate output.

---

## 0.7.5

### Fixed
- **BM25 Search**: Fixed critical bug where BM25 index was never built for Source RAG, causing Hybrid Search to only use Vector search.
- **Hybrid Search Accuracy**: BM25 keyword matching now works correctly alongside Vector similarity search.

### Changed
- **Initialization**: Both HNSW and BM25 indexes are now rebuilt on app startup to ensure Hybrid Search works immediately.
- **Index Rebuild**: `rebuildIndex()` now rebuilds both HNSW (vector) and BM25 (keyword) indexes.

### Added
- **`rebuildChunkBm25Index()`**: New low-level API for manually rebuilding BM25 index (internal use).

## 0.7.1

### Documentation
- **README**: Added "Sample App" section with screenshot and link to `mobile-ondevice-rag-desktop` example app.

## 0.7.0

### Added
- **Hybrid Search API**: New `searchHybrid()` combining Vector and BM25 search for better accuracy.
- **Context Assembly**: New `searchHybridWithContext()` generates optimized prompts for LLMs.
- **Metadata Support**: `addDocument()` now accepts `metadata` (e.g., filenames, page numbers), which is preserved in search results.

### Changed
- **Prompt Format**: Converted LLM context format to use **XML tags** (`<document>...`) instead of text headers for better parsing by modern LLMs.
- **Internal**: Updated to use `rag_engine_flutter` 0.7.0 with schema changes.

## 0.6.0

### Added
- **DB Connection Pool**: Implemented `r2d2` based connection pooling
- **Performance**: Search operations are now 50-90% faster (100ms -> 11ms)
- **Automatic Initialization**: `RagEngine` now automatically manages connection pool lifecycle

### Changed
- **Internal**: Refactored database operations to share connections efficiently
- **API**: Internal Rust API no longer requires `db_path` for every operation
- **README Quick Start**: Updated to showcase new simplified `RagEngine` API
- **Documentation**: Rewrote `docs/guides/quick_start.md` with `RagEngine` examples
- **Example app**: Refactored `main.dart` to use `RagEngine` instead of manual initialization
- **Library exports**: Updated `mobile_rag_engine.dart` with new Quick Start example in docstring

### Migration Guide
**Before (0.4.x):**
```dart
final dir = await getApplicationDocumentsDirectory();
await _copyAssetToFile('assets/tokenizer.json', tokenizerPath);
await initTokenizer(tokenizerPath: tokenizerPath);
final modelBytes = await rootBundle.load('assets/model.onnx');
await EmbeddingService.init(modelBytes.buffer.asUint8List());
_ragService = SourceRagService(dbPath: dbPath);
await _ragService!.init();
```

**After (0.5.0):**
```dart
final rag = await RagEngine.initialize(
  config: RagConfig.fromAssets(
    tokenizerAsset: 'assets/tokenizer.json',
    modelAsset: 'assets/model.onnx',
  ),
);
```

## 0.5.3

### Added
- **Singleton Pattern**: Introduced `MobileRag` class for simplified, global access to the engine
  - `MobileRag.initialize()`: Single-line initialization that handles Rust FFI, Config, and Database
  - `MobileRag.instance`: Static accessor for using the engine anywhere in the app
- **Auto-Initialization**: Eliminated the need to manually call `RustLib.init()`

### Changed
- **API Exports**: Hides low-level Rust API by default to improve IDE auto-completion relevance
- **Documentation**: Updated all guides and examples to use the new `MobileRag` singleton pattern

## 0.5.0

### Added
- **`RagEngine` class**: New unified API that simplifies initialization from ~40 lines to ~3 lines
  - `RagEngine.initialize()` handles tokenizer, ONNX model, and database setup automatically
  - `RagEngine.initialize()` handles tokenizer, ONNX model, and database setup automatically
  - `RagConfig.fromAssets()` for convenient asset-based configuration
  - Delegates to `SourceRagService` internally, maintaining full functionality
- **`RagConfig` class**: Configuration object for `RagEngine` with chunking and database options
- **Progress callback**: `onProgress` parameter in `RagEngine.initialize()` for status updates

## 0.4.4

### Added
- **Documentation**: Added comprehensive guides in `docs/guides/`:
  - `quick_start.md` - Get started in 5 minutes
  - `model_setup.md` - Model selection, download, deployment strategies
  - `faq.md` - Frequently asked questions
  - `troubleshooting.md` - Problem solving guide
- **README**: Added Requirements section with platform minimum versions (iOS 13.0+, Android API 21+, macOS 10.15+)
- **README**: Added Documentation section with links to all guides

### Changed
- **README**: Enhanced Model Options table with dimensions, max tokens, and language support info
- **README**: Updated all doc links to absolute GitHub URLs for pub.dev compatibility

## 0.4.3

### Added
- **PDF/DOCX Text Extraction**: New `extractTextFromPdf()`, `extractTextFromDocx()`, and `extractTextFromDocument()` functions
- **Markdown Structure-Aware Chunking**: New `markdownChunk()` function with header path inheritance, code block/table preservation
- **API**: Added `removeSource(id)` to `SourceRagService` for deleting documents
- **Smart Dehyphenation**: Automatically rejoins words split by line breaks and page boundaries
- **Page Number Removal**: Strips standalone page numbers from PDF text extraction
- **macOS Entitlements**: Added file read permissions for macOS file picker support
- **Documentation**: Enhanced `example/example.md` with PDF/DOCX handling and document management examples

### Changed
- **Project Structure Cleanup**: Removed duplicate `/rust/` directory; consolidated Rust source to `rust_builder/rust/` only
- **Flutter Rust Bridge Config**: Updated `rust_root` path in `flutter_rust_bridge.yaml`
- **Rust Core**: Added `pdf-extract`, `docx-lite`, and `regex` crates for document processing

### Fixed
- **PDF Text Extraction**: Fixed issue where paragraph breaks were removed during text normalization
- **Safety**: Added 50MB limit for document extraction to prevent OOM

## 0.4.0

### Changed
- **README Cleanup**: Removed all emojis and unnecessary sections for cleaner documentation

## 0.3.9

### Fixed
- **README Images**: Updated image paths to use GitHub raw URLs for pub.dev compatibility

## 0.3.8

### Changed
- **ONNX Runtime**: Reverted to `onnxruntime ^1.4.1` for CocoaPods compatibility (1.23.2 not yet available)
- **README**: Added benchmark result screenshots (iOS/Android) and architecture diagram
- **Platform Support**: Removed Linux/Windows from publish (no pre-compiled binaries available)

### Removed
- **ChunkingTestScreen**: Removed unnecessary test screen from example app

### Added
- **Android Platform**: Added Android support to example app

## 0.3.7

### Changed
- **ONNX Runtime Upgrade**: Migrated from `onnxruntime` to `onnxruntime_v2` (v1.23.2) with optional GPU acceleration support
- **README Remake**: Completely redesigned README with "No Rust Installation Required" emphasis, accurate benchmarks, and Mermaid architecture diagram
- **Benchmark UI Overhaul**: Visual separation of Rust-powered (fast) vs ONNX (standard) operations with category headers and icons

### Added
- **GPU Acceleration Option**: `EmbeddingService.init()` now accepts `useGpuAcceleration` parameter (CoreML/NNAPI support, disabled by default)
- **macOS Support for Example App**: Example app now supports macOS platform
- **Benchmark Categories**: Results now grouped by `BenchmarkCategory.rust` and `BenchmarkCategory.onnx`

### Fixed
- **Pub Point Warning**: Removed non-existent `assets/` directory reference from pubspec.yaml
- **Static Analysis**: Fixed all lint issues (unnecessary imports, avoid_print, curly braces)

## 0.3.5
- Globalization: Removed all Korean text and logic, replaced with English.
- Updated prompt builder and semantic chunker for better international support.
- Updated default language settings to English.

## 0.3.4

- Fix model download URLs in README (use correct Teradata/bge-m3 and BAAI/bge-m3 sources)
- Add production model deployment strategies guide

## 0.3.3

- Improve README with Quick Start guide and model download instructions
- Update to pub.dev dependency instead of git

## 0.3.2

- Update `rag_engine_flutter` dependency to `^0.3.0` (fixes platform directory issue)

## [0.3.1] - 2026-01-08

### Fixed
- **Package structure fix**: Update `rag_engine_flutter` dependency to v0.2.0 which includes rust/ source

## [0.3.0] - 2026-01-08

### Changed
- **Package Rename**: Rust crate renamed to `rag_engine_flutter` for pub.dev distribution.
- **iOS Podspec Fix**: Resolved linker path issues for iOS builds.
- **Asset Handling**: Force-overwrite asset files to prevent stale cache issues.

### Removed
- Deprecated `test_app` and `local-gemma-macos` directories.

## [0.2.0] - 2025-12-08


### Added
- **LLM-Optimized Chunking**: Introduced `ChunkingService` with Recursive Character Splitting and Overlap support.
- **Improved Data Model**: Separated storage into `Source` (original document) and `Chunk` (searchable parts).
- **Context Assembly**: Added `ContextBuilder` to intelligently assemble LLM context within a token budget.
- **High-Level API**: New `SourceRagService` for automated chunking, embedding, and indexing pipeline.
- **Context Strategies**: Support for `relevanceFirst`, `diverseSources`, and `chronological` context assembly strategies.

## [0.1.0] - 2025-12-08

### Added
- Initial release
- On-device semantic search with HNSW vector indexing
- Rust-powered tokenization via HuggingFace tokenizers
- ONNX Runtime integration for embedding generation
- SQLite-based vector storage with content deduplication
- Batch embedding support with progress callback
- Cross-platform support (iOS and Android)

### Features
- `initDb()` - Initialize SQLite database
- `addDocument()` - Add documents with SHA256 deduplication
- `searchSimilar()` - HNSW-based semantic search
- `rebuildHnswIndex()` - Manual index rebuild
- `EmbeddingService.embed()` - Generate embeddings
- `EmbeddingService.embedBatch()` - Batch embedding

### Performance
- HNSW search: O(log n) complexity
- Tokenization: ~0.8ms for short text
- Embedding: ~4ms for short text, ~36ms for long text
- Search (100 docs): ~1ms
