# Mobile RAG Engine

![pub package](https://img.shields.io/pub/v/mobile_rag_engine)
![flutter](https://img.shields.io/badge/Flutter-3.9%2B-blue)
![rust](https://img.shields.io/badge/Core-Rust-orange)
![platform](https://img.shields.io/badge/Platform-iOS%20|%20Android%20|%20macOS-lightgrey)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Production-ready, fully local RAG (Retrieval-Augmented Generation) engine for Flutter.**

Powered by a **Rust core**, it delivers lightning-fast vector search and embedding generation directly on the device. No servers, no API costs, no latency.

---

## Why this package?

### No Rust Installation Required

**You do NOT need to install Rust, Cargo, or Android NDK.**

This package includes **pre-compiled binaries** for iOS, Android, and macOS. Just `pub add` and run.

### Performance

| Feature | Pure Dart | **Mobile RAG Engine (Rust)** |
|:---|:---:|:---:|
| **Tokenization** | Slow | **10x Faster** (HuggingFace tokenizers) |
| **Vector Search** | O(n) | **O(log n)** (HNSW Index) |
| **Memory Usage** | High | **Optimized** (Zero-copy FFI) |

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
| **Document Input** | PDF, DOCX, Markdown, Plain Text with smart dehyphenation |
| **Chunking** | Semantic chunking, Markdown structure-aware, header path inheritance |
| **Search** | HNSW vector + BM25 keyword hybrid search with RRF fusion |
| **Storage** | SQLite persistence, HNSW Index persistence (fast startup), connection pooling, resumable indexing |
| **Collections** | Collection-scoped ingest/search/rebuild via `inCollection('id')` |
| **Performance** | Rust core, 10x faster tokenization, thread control, memory optimized |
| **Context** | Token budget, adjacent chunk expansion, single source mode |

---

## Requirements

| Platform | Minimum Version |
|:---------|:----------------|
| **iOS** | 13.0+ |
| **Android** | API 21+ (Android 5.0 Lollipop) |
| **macOS** | 10.15+ (Catalina) |

> **ONNX Runtime** is bundled automatically via the [`onnxruntime`](https://pub.dev/packages/onnxruntime) plugin. No additional native setup required.

---

## Installation

### 1. Add the dependency

```yaml
dependencies:
  mobile_rag_engine:
```

### 2. Download Model Files

```bash
# Create assets folder
mkdir -p assets && cd assets

# Download all-MiniLM-L6-v2 model (INT8 quantized for ARM64, ~23MB)
curl -L -o model.onnx "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_qint8_arm64.onnx"
curl -L -o tokenizer.json "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"
```

> Need multilingual (Korean, CJK, etc.)? See [Model Setup Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md) for BGE-m3 and other model options.

---

## Quick Index

### Features
*   [Adjacent Chunk Retrieval](docs/features/adjacent_chunk_retrieval.md) - Fetch surrounding context.
*   [Index Management](docs/features/index_management.md) - Stats, persistence, and recovery.
*   [Markdown Chunker](docs/features/markdown_chunker.md) - Structure-aware text splitting.
*   [Multi-Collection](docs/features/multi_collection.md) - Isolate ingest/search/rebuild by category.
*   [Prompt Compression](docs/features/prompt_compression.md) - Reduce token usage.
*   [Search by Source](docs/features/search_by_source.md) - Filter results by document.
*   [Search Strategies](docs/features/search_strategies.md) - Tune ranking and retrieval.

### Guides
*   [Quick Start](docs/guides/quick_start.md) - Setup in 5 minutes.
*   [Model Setup](docs/guides/model_setup.md) - Choosing and downloading models.
*   [Troubleshooting](docs/guides/troubleshooting.md) - Common fixes.
*   [FAQ](docs/guides/faq.md) - Frequently asked questions.

### Testing
*   [Unit Testing](docs/test/unit_testing.md) - Mocking for isolated tests.

---

Initialize the engine once in your `main()` function:



### Initialization Parameters 

```dart
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
  deferIndexWarmup: true,
);

// Before first search:
if (!MobileRag.instance.isIndexReady) {
  await MobileRag.instance.warmupFuture;
}
```


Then use it anywhere in your app:

```dart
class MySearchScreen extends StatelessWidget {
  Future<void> _search() async {
    // 2. Add Documents (auto-chunked & embedded)
    await MobileRag.instance.addDocument(
      'Flutter is a UI toolkit for building apps.',
    );
    await MobileRag.instance.addDocument(
      'Dart is the language used to build Flutter apps.',
    );
    // Indexing is automatic! (Debounced 500ms)
    // Optional: await MobileRag.instance.rebuildIndex(); // Call if you want it done NOW
  
    // 3. Search with LLM-ready context
    final result = await MobileRag.instance.search(
      'What is Flutter?', 
      tokenBudget: 2000,
    );
    
    print(result.context.text); // Ready to send to LLM
  }
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

> **Advanced Usage:** For fine-grained control, you can still use the low-level APIs (`initTokenizer`, `EmbeddingService`, `SourceRagService`) directly. See the [API Reference](https://pub.dev/documentation/mobile_rag_engine/latest/).

---

## Model Options

| Model | Dimensions | Size (ONNX) | Max Tokens | Languages |
|:------|:----------:|:-----------:|:----------:|:----------|
| [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (INT8) | **384** | ~23 MB | 256 | English |
| [Teradata/bge-m3](https://huggingface.co/Teradata/bge-m3) (INT8) | **1024** | ~542 MB | 8,194 | 100+ (multilingual) |

> **Important:** The embedding dimension must be consistent across all documents. Switching models requires re-embedding your entire corpus.

**Custom Models:** Export any Sentence Transformer to ONNX:
```bash
pip install optimum[exporters]
optimum-cli export onnx --model sentence-transformers/YOUR_MODEL ./output
```

See [Model Setup Guide](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md) for deployment strategies and troubleshooting.

---

## Documentation

| Guide | Description |
|:------|:------------|
| [Quick Start](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/quick_start.md) | Get started in 5 minutes |
| [Model Setup](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/model_setup.md) | Model selection, download, deployment strategies |
| [FAQ](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/faq.md) | Frequently asked questions |
| [Troubleshooting](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/troubleshooting.md) | Problem solving guide |

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

This project is licensed under the [MIT License](LICENSE).
