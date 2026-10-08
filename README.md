# Mobile RAG Engine

**Build local, on-device RAG in Flutter with a Dart package.**

Mobile RAG Engine is a Flutter package for local Retrieval-Augmented Generation
(RAG): ingest local documents, chunk and embed them on-device, then run hybrid
semantic + keyword search through a Dart API. No server, no API cost, no network
round-trip for retrieval.

![pub package](https://img.shields.io/pub/v/mobile_rag_engine)
![flutter](https://img.shields.io/badge/Flutter-3.9%2B-blue)
![rust](https://img.shields.io/badge/Core-Rust-orange)
![platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20macOS-lightgrey)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Use it when you need a **Flutter local RAG engine** for private notes, document
Q&A, chat with PDF, offline assistants, or enterprise apps where user data must
stay on the device.

---

## Why this package?

### Native Core Built by Cargokit

The Rust core (`rag_engine_flutter`) is compiled from source by
[Cargokit](https://github.com/irondash/cargokit) during your first
`flutter build`. Published packages do **not** include pre-compiled binaries
yet, so a Rust toolchain is required today:

- Install Rust with [rustup](https://rustup.rs/) (stable). Cargokit adds the
  Rust targets it needs through `rustup`.
- iOS/macOS builds need Xcode. Android builds need the Android SDK; if the
  NDK version your project requests is missing, Cargokit installs it with the
  SDK's `cmdline-tools` (`sdkmanager`).
- The first build of each platform compiles the Rust crate and takes longer;
  later builds reuse the cached artifacts.

Pre-compiled binaries are planned; this section will change when they ship.

### Performance

| Feature | Pure Dart | **Mobile RAG Engine (Rust)** |
|:---|:---:|:---:|
| **Tokenization** | Slow | HuggingFace `tokenizers` (Rust) |
| **Vector Search** | O(n) | HNSW Index — sub-linear retrieval |
| **Memory Usage** | High | Copy-minimized Rust core, `Float32List` zero-copy transport |

> Numbers vary by device and corpus. See [`benchmark_service`](https://github.com/dev07060/mobile_rag_engine/blob/main/lib/services/benchmark_service.dart) and the `0.18.0` retrieval-hot-path notes in [CHANGELOG.md](https://github.com/dev07060/mobile_rag_engine/blob/main/CHANGELOG.md) for measured deltas on your own hardware.

### Supported and Verified Scope

| Area | Current status | Evidence / boundary |
|:-----|:---------------|:--------------------|
| **Local Flutter RAG retrieval** | Supported | Dart facade over a Rust core for ingest, chunking, embedding, SQLite storage, HNSW vector search, BM25 keyword search, RRF fusion, and context assembly |
| **Offline / on-device operation** | Supported | Models and user documents stay local after you bundle the ONNX model and tokenizer assets |
| **Hybrid source retrieval** | Verified on benchmark fixtures | 80-source balanced profile run: `source_recall@10 = 1.000` for shipped `default_hybrid` |
| **Passage/context retrieval** | Verified on benchmark fixtures | 80-query passage run: `passage_recall@10 = 0.925`, `answerable_context@10 = 0.938`; semantic passage misses remain the main improvement area |
| **Text-layer PDF-to-RAG** | Verified on sample scope | `sample_eng.pdf` and `sample_kor.pdf` profile run: 8/8 PDF-derived queries reached source, passage, and answerable context at top-10 |
| **Scanned/image-only PDFs** | Detected, not OCR-processed | OCR-required PDFs are surfaced as extraction errors so your app can route to an OCR layer; OCR is not bundled in this package |
| **Large, table-heavy, OCR-heavy PDFs** | Still being validated | Do not treat the PDF smoke result as broad PDF robustness or mobile latency/memory proof |

For the implementation-oriented guide, see
[Flutter Local RAG Engine Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/local-rag-engine.md).

### 100% Offline & Private

Data never leaves the user's device. Perfect for privacy-focused apps (journals, secure chats, enterprise tools).

---

## Features

### End-to-End RAG Pipeline

<p align="center">
  <img src="https://raw.githubusercontent.com/dev07060/mobile_rag_engine/main/assets/readme-sources/package_introduction.png" width="860" alt="End-to-End RAG Pipeline">
</p>

> **One package, complete pipeline.** From any document format to LLM-ready context.

### Key Features

| Category | Features |
|:---------|:---------|
| **Document Input** | Text-layer PDF, Markdown, Plain Text, and beta DOCX support; file-path and UTF-8 ingest fast paths |
| **Chunking** | Plain-text paragraph/line chunking with heading-aware split and tokenizer hard guard; Markdown structure-aware chunking with header-path metadata |
| **Search** | HNSW vector + BM25 keyword hybrid search with RRF fusion; metadata-first search with explicit context/chunk hydration |
| **Storage** | SQLite persistence, HNSW Index persistence (fast startup), connection pooling, resumable indexing |
| **Collections** | Collection-scoped ingest/search/rebuild via `inCollection('id')` |
| **Performance** | Rust core, 10x faster tokenization, thread control, memory optimized |
| **Context** | Engine-tokenizer exact context budget, adjacent chunk expansion, single source mode |

**Support boundaries:** text-layer PDFs are production-ready. Scanned or image-only PDFs should be routed through an OCR layer before indexing. DOCX extraction is available for early adopters, but complex DOCX layouts such as tables, headers, and footnotes should be treated as beta.

---

## Requirements

| Platform | Minimum Version |
|:---------|:----------------|
| **iOS** | 16.0+ |
| **Android** | API 21+ (Android 5.0 Lollipop) |
| **macOS** | 14.0+ |
| **Build host** | Rust stable via rustup (see [Native Core Built by Cargokit](#native-core-built-by-cargokit)) |

Windows and Linux are not supported yet: the published native package does not
ship their build configuration.

> ONNX Runtime is provided through [`flutter_onnxruntime`](https://pub.dev/packages/flutter_onnxruntime). CocoaPods builds on both iOS and macOS require static framework linkage (`use_frameworks! :linkage => :static`); set the host deployment targets to iOS 16.0+ and macOS 14.0+. Android release builds should keep ONNX Runtime classes in ProGuard/R8 rules.

---

## Installation

There are two install paths. The `setup` command and Model Pack below ship only
in the `0.21.0` dev line (since `0.21.0-dev.11`); the latest stable, `0.20.0`,
uses manually downloaded model assets.

| Path | Version | Model setup |
|:-----|:--------|:------------|
| **Stable** | `^0.20.0` | Download `model.onnx` + `tokenizer.json` yourself ([Option A](#option-a-stable-020x-manual-model-assets)) |
| **Preview** | `0.21.0-dev.12` | `dart run mobile_rag_engine:setup` Model Pack ([Option B](#option-b-preview-0210-dev-model-pack)) |

### Option A: Stable (`0.20.x`) manual model assets

```yaml
dependencies:
  mobile_rag_engine: ^0.20.0
```

Download the MiniLM model (INT8, ARM64, ~23 MB) and tokenizer at a pinned
revision:

```bash
mkdir -p assets && cd assets
curl -L -o model.onnx "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/onnx/model_qint8_arm64.onnx"
curl -L -o tokenizer.json "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/tokenizer.json"
```

```yaml
flutter:
  assets:
    - assets/model.onnx
    - assets/tokenizer.json
```

```dart
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
);
```

### Option B: Preview (`0.21.0` dev) Model Pack

```yaml
dependencies:
  mobile_rag_engine: 0.21.0-dev.12
```

Install and verify the pinned Model Pack:

```bash
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --check
```

It writes `assets/mobile_rag/model.onnx`, `tokenizer.json`, and
`model-pack.json`. Add the directory to your app assets:

```yaml
flutter:
  assets:
    - assets/mobile_rag/
```

Then initialize with one manifest:

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset(
    'assets/mobile_rag/model-pack.json',
  ),
);
```

The first success is add documents, rebuild the index, and get non-empty
chunks/context from search. LLM generation remains your app's separate step.

Need a custom or multilingual ONNX model? The original two-asset initializer
remains available as an advanced/legacy path; see the
[Model Setup Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md).

---

## Quick Index

### Features
*   [Adjacent Chunk Retrieval](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/adjacent_chunk_retrieval.md) - Fetch surrounding context.
*   [Index Management](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/index_management.md) - Stats, persistence, and recovery.
*   [Markdown Chunker](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/markdown_chunker.md) - Structure-aware text splitting.
*   [Multi-Collection](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/multi_collection.md) - Isolate ingest/search/rebuild by category.
*   [Prompt Compression](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/prompt_compression.md) - Reduce token usage.
*   [Search by Source](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/search_by_source.md) - Filter results by document.
*   [Search Strategies](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/search_strategies.md) - Tune ranking and retrieval.

### Guides
*   [Flutter Local RAG Engine Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/local-rag-engine.md) - Build local/on-device RAG in Flutter with Dart APIs.
*   [Quick Start](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/quick_start.md) - Setup in 5 minutes.
*   [Model Setup](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md) - Choosing and downloading models.
*   [Release Build](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/release_build.md) - Bundle size optimization for production.
*   [Troubleshooting](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/troubleshooting.md) - Common fixes.
*   [FAQ](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/faq.md) - Frequently asked questions.

### Testing
*   [Unit Testing](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/test/unit_testing.md) - Mocking for isolated tests.

---

## Usage

### Minimal Setup

Initialize the engine once in your `main()` function. See the [Quick Start Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/quick_start.md#step-3-initialize) for the full parameter table.

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset(
    'assets/mobile_rag/model-pack.json',
  ),
  deferIndexWarmup: true,
);

// Before first search, wait for BM25/HNSW warmup if you deferred it:
if (!MobileRag.instance.isIndexReady) {
  await MobileRag.instance.warmupFuture;
}
```

On stable `0.20.x`, pass `tokenizerAsset:` and `modelAsset:` instead of
`modelPack:` ([Option A](#option-a-stable-020x-manual-model-assets)).

### Storage default and experimental VABQ

> `VabqProfile` exists only in the `0.21.0` dev line; `0.20.x` always uses Q8_0.

The normal public initialization paths use Q8_0 storage by default. VABQ is
an experimental, advanced opt-in: it is enabled only when you explicitly pass
a matching `VabqProfile` to `MobileRag.initialize` or `RagConfig`. Model asset
names and embedding dimensions never select VABQ automatically. Model Pack v1
is fixed to Q8_0 and rejects a VABQ profile; use the custom two-asset path for
VABQ research.

```dart
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
  vabqProfile: VabqProfile.allMiniLmL6V2, // explicit experimental opt-in
);
```

### Adding Documents and Searching

```dart
class MySearchScreen extends StatelessWidget {
  Future<void> _search() async {
    // 1. Add Documents (auto-chunked & embedded). Indexing is auto-managed
    //    (debounced ~500ms) — only call rebuildIndex() if you need it now.
    await MobileRag.instance.addDocument(
      'Flutter is a UI toolkit for building apps.',
    );

    // File / UTF-8 fast paths are useful for large local documents.
    await MobileRag.instance.addDocumentFromFile('/path/to/manual.pdf');
    final noteBytes = await File('/path/to/notes.md').readAsBytes();
    await MobileRag.instance.addDocumentUtf8(noteBytes, name: 'notes.md');

    // 2. Search with LLM-ready context
    final result = await MobileRag.instance.search(
      'What is Flutter?',
      tokenBudget: 2000,
    );
    print(result.context.text); // Ready to send to LLM
  }
}
```

### Handling File Picker Fallback

`addDocumentFromFile` is the fastest path because the Rust core reads and chunks the file directly. Some platform pickers (cloud-backed pickers, content URIs without a stable local path, etc.) return data that is not exposed as a real filesystem path. In those cases, fall back to UTF-8 or parsed-text ingestion:

```dart
try {
  await MobileRag.instance.addDocumentFromFile(path, name: fileName);
} on RagError {
  final bytes = await File(path).readAsBytes();
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.txt') ||
      lower.endsWith('.md') ||
      lower.endsWith('.markdown')) {
    await MobileRag.instance.addDocumentUtf8(bytes, name: fileName);
  } else {
    try {
      final text = await DocumentParser.parse(bytes);
      await MobileRag.instance.addDocument(text, name: fileName);
    } catch (error) {
      if (DocumentParser.isOcrRequiredPdfExtractionError(error)) {
        throw UnsupportedError(
          DocumentParser.userMessageForExtractionError(error),
        );
      }
      rethrow;
    }
  }
}
```

### Metadata-First Search

Use `searchMeta` when you want lightweight search metadata first, then explicitly assemble context or hydrate only the chunks you need.

```dart
final meta = await MobileRag.instance.searchMeta(
  'What is Flutter?',
  topK: 10,
);

try {
  final context = await MobileRag.instance.assembleContext(
    searchHandle: meta.handle,
    tokenBudget: 2000,
  );

  final chunkIds = meta.hits.map((hit) => hit.chunkId.toInt()).toList();
  final chunks = await MobileRag.instance.hydrateChunks(
    searchHandle: meta.handle,
    chunkIds: chunkIds,
  );
  final excerpts = await MobileRag.instance.getChunkExcerpts(
    searchHandle: meta.handle,
    chunkIds: chunkIds,
    maxBytes: 256,
  );

  print(context.text);
  print('hydrated=${chunks.length}, excerpts=${excerpts.length}');
} finally {
  await meta.handle.dispose();
}
```

### Multi-Collection (v1)

Use collection scopes when you want independent rebuild boundaries per category.

```dart
final business = MobileRag.instance.inCollection('business');
final travel = MobileRag.instance.inCollection('travel');

await business.addDocument('Quarterly planning memo...');
await travel.addDocument('Kyoto itinerary...');

if (!travel.isIndexReady) {
  await travel.warmupFuture;
}
final travelHits = await travel.searchHybrid('itinerary');
print(travelHits.length);
```

If you do not specify a collection, the engine uses the default `__default__`
collection for backward compatibility.

> **Advanced Usage:** For fine-grained control, use the high-level metadata lane (`searchMeta`, `assembleContext`, `hydrateChunks`, `getChunkExcerpts`) and the public API reference. Most apps should stay on the `MobileRag` facade.


---

## Sample App

Check out the example application using this package. This desktop app demonstrates **full RAG pipeline integration with an LLM (Gemma 2B)** running locally on-device.

[mobile-ondevice-rag-desktop](https://github.com/dev07060/mobile-ondevice-rag-desktop)

<p align="center">
  <img src="https://raw.githubusercontent.com/dev07060/mobile_rag_engine/main/assets/readme-sources/sample_app.png" width="860" alt="Sample App Screenshot">
</p>

---

## Contributing

Bug reports, feature requests, and PRs are all welcome!

## License

This project is licensed under the [MIT License](https://github.com/dev07060/mobile_rag_engine/blob/main/LICENSE).
