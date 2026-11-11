# Mobile RAG Engine

**Build local, on-device RAG in Flutter with a Dart package.**

Add your app's documents, search them with hybrid semantic + keyword retrieval,
and hand the result to any LLM. Chunking, embedding, storage and search all run
on the device: no server, no API cost, no network round-trip for retrieval.

![pub package](https://img.shields.io/pub/v/mobile_rag_engine)
![flutter](https://img.shields.io/badge/Flutter-3.35.3%2B-blue)
![platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Windows-lightgrey)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

```dart
final rag = MobileRag.instance; // after MobileRag.initialize, see Installation

// 1. Add documents. They are chunked and embedded on the device.
await rag.addDocument('Refunds are accepted within 14 days of purchase.');
await rag.addDocumentFromFile('/path/to/manual.pdf');

// 2. Search. The result is context that is ready to send to an LLM.
final result = await rag.search(
  'How long is the refund period?',
  tokenBudget: 2000,
);
print(result.context.text);

// 3. Or get an answer with citations from the LLM you choose.
final answer = await rag.ask(
  'How long is the refund period?',
  generate: (prompt) => myLlm.complete(prompt), // any Future<String>
);
print(answer.text); // "Within 14 days of purchase [1]."
```

Use it for private notes, document Q&A, chat with PDF, offline assistants, or
enterprise apps where user data must stay on the device.

## Why this package?

- **Offline and private.** Documents, embeddings and the search index stay on
  the user's device. Retrieval needs no server and costs nothing per query.
- **Hybrid search with measured quality.** HNSW vector search and BM25 keyword
  search are fused into one ranking. On an 80-query benchmark fixture,
  the right passage is in the top 10 for 92.5% of queries (see
  [Supported and verified scope](#supported-and-verified-scope)).
- **Works with any LLM.** There is no LLM inside. `search` returns context
  within a token budget, and `ask` takes your own generation function, so a
  cloud SDK, an on-device model or a local server all fit. See the
  [Ask guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/ask.md).

<p align="center">
  <img src="https://raw.githubusercontent.com/dev07060/mobile_rag_engine/main/assets/readme-sources/package_introduction.png" width="860" alt="End-to-End RAG Pipeline">
</p>

> **One package, complete pipeline.** From PDF, DOCX, Markdown and plain text to LLM-ready context.

---

## Installation

### 1. Add the dependency

```yaml
dependencies:
  mobile_rag_engine: ^0.23.0
```

### 2. Install the verified Model Pack

> **This preset is English-only.** For Korean documents, follow the
> [KoEn-E5-Tiny recipe](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md#korean-documents-koen-e5-tiny)
> instead of the command below; English MiniLM scores close to random on
> Korean text.

```bash
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --check
```

It writes `assets/mobile_rag/model.onnx`, `tokenizer.json`, and
`model-pack.json`. It also raises the iOS and macOS host settings the native
dependencies need (Podfile platform, static framework linkage and the Runner
deployment target) and prints each change; existing higher targets are kept,
and `--skip-host-config` turns this off. Add the directory to your app assets:

```yaml
flutter:
  assets:
    - assets/mobile_rag/
```

### 3. Initialize once

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset(
    'assets/mobile_rag/model-pack.json',
  ),
);
```

The first success is to add a document and get non-empty context back from
`search`, as in the example at the top. `search` waits for a pending index
update, so you do not need to call `rebuildIndex()` first.

For other languages and model choices, see the
[Model Setup Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md).

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

### Adding Documents and Searching

```dart
import 'dart:io';

import 'package:mobile_rag_engine/mobile_rag_engine.dart';

Future<String> addAndSearch() async {
  // 1. Add documents (chunked and embedded automatically). The index is
  //    updated in the background, and a search waits for a pending update.
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
  return result.context.text; // Ready to send to an LLM
}
```

### Answering with Your LLM

`ask` searches, builds a prompt with numbered passages, calls the function you
pass, and returns the answer with the passages it cites.

```dart
final answer = await MobileRag.instance.ask(
  'What is Flutter?',
  generate: (prompt) => myLlm.complete(prompt), // Future<String>
);

print(answer.text);
for (final passage in answer.citations) {
  print('[${passage.id}] ${passage.sourceName}: ${passage.text}');
}
```

See the [Ask guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/ask.md)
for custom prompts and the no-result case, and
[LLM Tools](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/llm_tools.md)
to expose search as a tool instead.

### Handling File Picker Fallback

`addDocumentFromFile` is the fastest path because the native core reads and chunks the file directly. Some platform pickers (cloud-backed pickers, content URIs without a stable local path, etc.) return data that is not exposed as a real filesystem path. In those cases, fall back to UTF-8 or parsed-text ingestion:

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

### Multi-Collection

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
collection.

> **Advanced Usage:** For fine-grained control, use the high-level metadata lane (`searchMeta`, `assembleContext`, `hydrateChunks`, `getChunkExcerpts`) and the public API reference. Most apps should stay on the `MobileRag` facade.

---

## Features

| Category | Features |
|:---------|:---------|
| **Document Input** | Text-layer PDF, DOCX, Markdown and plain text (up to 50 MB per file); file-path and UTF-8 ingest fast paths |
| **Chunking** | Plain-text paragraph/line chunking with heading-aware split and tokenizer hard guard; Markdown structure-aware chunking with header-path metadata |
| **Search** | HNSW vector + BM25 keyword hybrid search with RRF fusion; metadata-first search with explicit context/chunk hydration |
| **Storage** | SQLite persistence, HNSW Index persistence (fast startup), connection pooling, resumable indexing |
| **Collections** | Collection-scoped ingest/search/rebuild via `inCollection('id')` |
| **Context** | Engine-tokenizer exact context budget, adjacent chunk expansion, single source mode |
| **LLM bridge** | `ask` with your own generation function and cited passages; search results as JSON and as a tool definition |
| **Native core** | Tokenization, chunking, storage and search run in a compiled native core with thread control; HuggingFace `tokenizers` |

**Support boundaries:**

- **PDF**: text-layer PDFs are verified on a small sample set (see the table below). Large or table-heavy PDFs are still being validated. Scanned or image-only PDFs need an OCR layer before indexing, and AES-encrypted PDFs are rejected.
- **DOCX**: body text, tables, text boxes, headers, footers and footnotes are extracted as plain text. Table cells are separated by ` | `; other layout such as columns and styling is not kept.
- **Other formats** (HTML, RTF, PPTX, XLSX, images): not supported. Extract the text in your app and pass it to `addDocument`.

### Supported and Verified Scope

| Area | Current status | Evidence / boundary |
|:-----|:---------------|:--------------------|
| **Local Flutter RAG retrieval** | Supported | Dart facade over a native core for ingest, chunking, embedding, SQLite storage, HNSW vector search, BM25 keyword search, RRF fusion, and context assembly |
| **Offline / on-device operation** | Supported | Models and user documents stay local after you bundle the ONNX model and tokenizer assets |
| **Hybrid source retrieval** | Verified on benchmark fixtures | 80-source balanced profile run: `source_recall@10 = 1.000` for shipped `default_hybrid` |
| **Passage/context retrieval** | Verified on benchmark fixtures | 80-query passage run: `passage_recall@10 = 0.925`, `answerable_context@10 = 0.938`; semantic passage misses remain the main improvement area |
| **Text-layer PDF-to-RAG** | Verified on sample scope | `sample_eng.pdf` and `sample_kor.pdf` profile run: 8/8 PDF-derived queries reached source, passage, and answerable context at top-10 |
| **Scanned/image-only PDFs** | Detected, not OCR-processed | OCR-required PDFs are surfaced as extraction errors so your app can route to an OCR layer; OCR is not bundled in this package |
| **Large, table-heavy, OCR-heavy PDFs** | Still being validated | Do not treat the PDF smoke result as broad PDF robustness or mobile latency/memory proof |

Numbers vary by device and corpus. To measure on your own hardware, see
[`benchmark_service`](https://github.com/dev07060/mobile_rag_engine/blob/main/lib/services/benchmark_service.dart).
For the implementation-oriented guide, see
[Flutter Local RAG Engine Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/local-rag-engine.md).

---

## Requirements

| Platform | Minimum Version |
|:---------|:----------------|
| **iOS** | 16.0+ |
| **Android** | API 24+ (Android 7.0), the minimum of the ONNX Runtime Android library |
| **macOS** | 14.0+ |
| **Windows** | Windows 10+ (x64) |
| **Flutter** | 3.35.3+ (Dart 3.9.2) |
| **Build host** | Network access to `github.com` on the first build of each platform |

Windows on ARM64 and Linux are not supported. Windows builds need Visual Studio
with the "Desktop development with C++" workload, as for any Flutter Windows
app. On Windows, the engine stores its database, index files, and copied model
assets in the app support directory (`%APPDATA%\<company>\<app>`) instead of the
user's (often OneDrive-synced) Documents folder.

**Build host.** The native core ships as signed, pre-compiled binaries for
Android (arm64-v8a, armeabi-v7a, x86_64, x86), iOS (device and simulator),
macOS (arm64, x86_64) and Windows (x64). `flutter build` downloads the binary
for your target from this repository's GitHub releases, verifies its signature,
and links it, so no extra toolchain is needed. If `rustup` is installed on the
build machine, the core is built from source instead; that path needs Rust
stable and its first build takes longer.

**ONNX Runtime** is provided through
[`flutter_onnxruntime`](https://pub.dev/packages/flutter_onnxruntime).
CocoaPods builds on iOS and macOS need static framework linkage
(`use_frameworks! :linkage => :static`) and deployment targets of iOS 16.0+ and
macOS 14.0+, while `flutter create` generates iOS 13.0 / macOS 10.15 with
dynamic frameworks. The `setup` command above applies these settings for you.
The package also ships the Android R8 keep rule for ONNX Runtime, the iOS/macOS
release linker settings, 16 KB Android page alignment and an iOS privacy
manifest. If a build fails, see
[Troubleshooting](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/troubleshooting.md).

Upgrading from 0.20.x or earlier? See
[CHANGELOG.md](https://github.com/dev07060/mobile_rag_engine/blob/main/CHANGELOG.md).

---

## Documentation

### Guides
*   [Quick Start](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/quick_start.md) - Setup in 5 minutes.
*   [Model Setup](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md) - Choosing and downloading models.
*   [Ask](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/ask.md) - Answer a question with your own LLM and get the cited passages.
*   [LLM Tools](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/llm_tools.md) - Search results as JSON and as a tool for any LLM.
*   [Flutter Local RAG Engine Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/local-rag-engine.md) - Build local/on-device RAG in Flutter with Dart APIs.
*   [Release Build](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/release_build.md) - Bundle size optimization for production.
*   [Troubleshooting](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/troubleshooting.md) - Common fixes.
*   [FAQ](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/faq.md) - Frequently asked questions.

### Features
*   [Adjacent Chunk Retrieval](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/adjacent_chunk_retrieval.md) - Fetch surrounding context.
*   [Index Management](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/index_management.md) - Stats, persistence, and recovery.
*   [Markdown Chunker](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/markdown_chunker.md) - Structure-aware text splitting.
*   [Multi-Collection](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/multi_collection.md) - Isolate ingest/search/rebuild by category.
*   [Prompt Compression](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/prompt_compression.md) - Reduce token usage.
*   [Search by Source](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/search_by_source.md) - Filter results by document.
*   [Search Strategies](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/features/search_strategies.md) - Tune ranking and retrieval.

### Testing
*   [Unit Testing](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/test/unit_testing.md) - Mocking for isolated tests.

---

## Sample App

The [`example/`](https://github.com/dev07060/mobile_rag_engine/tree/main/example)
app in this repository exercises ingest, chunking, and search against the
current source.

[mobile-ondevice-rag-desktop](https://github.com/dev07060/mobile-ondevice-rag-desktop)
is an older desktop demo that pairs retrieval with LLM generation (Gemma 2B
through a local [Ollama](https://ollama.com/) server). It is built against
`mobile_rag_engine` 0.14.x and predates the Model Pack setup, so treat it as a
reference for wiring retrieval into an LLM prompt, not as a copy-paste starting
point.

<p align="center">
  <img src="https://raw.githubusercontent.com/dev07060/mobile_rag_engine/main/assets/readme-sources/sample_app.png" width="860" alt="Sample App Screenshot">
</p>

---

## Contributing

Bug reports, feature requests, and PRs are all welcome!

## License

This project is licensed under the [MIT License](https://github.com/dev07060/mobile_rag_engine/blob/main/LICENSE).
