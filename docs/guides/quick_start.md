# Quick Start Guide

Get started with `mobile_rag_engine` in 5 minutes.

---

## Prerequisites

- Flutter 3.9+
- iOS 13.0+ / Android API 21+ / macOS 10.15+

---

## Step 1: Add Dependency

```yaml
# pubspec.yaml
dependencies:
  mobile_rag_engine:
```

```bash
flutter pub get
```

---

## Step 2: Download Model

Run from your project root:

```bash
mkdir -p assets && cd assets

# all-MiniLM-L6-v2 (INT8 quantized for ARM64, ~23MB)
curl -L -o model.onnx "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_qint8_arm64.onnx"
curl -L -o tokenizer.json "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"
```

> Need multilingual support (Korean, CJK)? See [Model Setup Guide](model_setup.md) for BGE-m3.

Register assets in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/model.onnx
    - assets/tokenizer.json
```

---

## Step 3: Initialize

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

Future<void> initializeRAG() async {
  await MobileRag.initialize(
    tokenizerAsset: 'assets/tokenizer.json',
    modelAsset: 'assets/model.onnx',
    threadLevel: ThreadUseLevel.medium, // Recommended for most apps
    // Optional: return before BM25/HNSW warmup finishes
    deferIndexWarmup: true,
  );
}
```

### All Parameters

| Parameter | Default | Description |
|:----------|:--------|:------------|
| `tokenizerAsset` | (required) | Path to tokenizer.json in assets |
| `modelAsset` | (required) | Path to ONNX model in assets |
| `databaseName` | `'rag.sqlite'` | SQLite database file name |
| `maxChunkChars` | `500` | Maximum characters per chunk |
| `overlapChars` | `50` | Overlap between chunks for context |
| `threadLevel` | `null` | CPU usage level: `low` (~20%), `medium` (~40%), `high` (~80%) |
| `embeddingIntraOpNumThreads` | `null` | Precise thread count (⚠️ mutually exclusive with `threadLevel`) |
| `deferIndexWarmup` | `false` | If `true`, initialization returns before BM25/HNSW warmup completes |
| `onProgress` | `null` | Callback for initialization status |

> **Note:** Choose either `threadLevel` OR `embeddingIntraOpNumThreads`, not both. Setting both will throw an error.

### When to use `deferIndexWarmup`

- Use `false` (default) when your app must allow full-quality search immediately after startup.
- Use `true` when faster first UI render is more important (low-end device, debug/hot-restart loops, large local corpus).
- With `true`, block search until warmup completes:

```dart
if (!MobileRag.instance.isIndexReady) {
  await MobileRag.instance.warmupFuture;
}
```

## Step 4: Add Documents

```dart
import 'dart:io';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

// Add text
await MobileRag.instance.addDocument(
  'Flutter is Google\'s UI toolkit for building beautiful apps.',
);

// Add PDF/DOCX
// See [Markdown Chunker](../features/markdown_chunker.md) for structural handling
final bytes = await File('document.pdf').readAsBytes();
final text = await DocumentParser.parse(bytes.toList());
await MobileRag.instance.addDocument(text, filePath: 'document.pdf');

// Optional: force immediate rebuild if you need deterministic timing.
// In most apps this is not required because indexing is auto-managed.
await MobileRag.instance.rebuildIndex();
```

---

## Step 5: Search

See [Search Strategies](../features/search_strategies.md) and [Adjacent Chunk Retrieval](../features/adjacent_chunk_retrieval.md) for more details.

```dart
final result = await MobileRag.instance.search(
  'What is Flutter?',
  topK: 5,
  tokenBudget: 2000,
);

// LLM-ready context
print(result.context.text);

// Or iterate chunks
for (final chunk in result.chunks) {
  print('Score: ${chunk.similarity}');
  print('Content: ${chunk.content}');
}
```

---

## Step 6: Source-Filtered Search (New!)

You can search within specific documents using `searchHybrid` with `sourceIds`. See [Search by Source](../features/search_by_source.md) for full guide.

**Key Feature - Independent Source Search (Exact Scan):**
When you specify a source, the engine switches to a "Brute Force" mode, scanning *every* chunk in that source. This guarantees perfect recall within that document, even if the content isn't "globally" top-ranked.

```dart
// 1. Get list of sources
final sources = await MobileRag.instance.listSources();
final thesisId = sources.first.id;

// 2. Search ONLY within that source
final results = await MobileRag.instance.searchHybrid(
  'attention mechanism',
  topK: 5,
  sourceIds: [thesisId], // Filter active -> Exact Scan mode
);

print('Found ${results.length} results in thesis source');
```

---

## Step 7: Manage Data

See [Index Management](../features/index_management.md) for advanced operations.

```dart
// List all sources
final sources = await MobileRag.instance.listSources();
for (var s in sources) {
  print('#${s.id}: ${s.name}');
}

// Delete a specific source
await MobileRag.instance.removeSource(sourceId);

// Delete EVERYTHING (Factory Reset)
await MobileRag.instance.clearAllData();
```

---

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize
  await MobileRag.initialize(
    tokenizerAsset: 'assets/tokenizer.json',
    modelAsset: 'assets/model.onnx',
    threadLevel: ThreadUseLevel.medium, // CPU usage control
  );
  
  // Add a document
  await MobileRag.instance.addDocument(
    'Flutter is an open-source UI framework by Google.',
  );
  
  // Search
  final result = await MobileRag.instance.search('What is Flutter?', topK: 3);
  print('Found ${result.chunks.length} results');
  print('Context: ${result.context.text}');
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Mobile RAG Engine ready')),
      ),
    );
  }
}
```

---

## Advanced Usage

For fine-grained control, you can still use the low-level APIs:

```dart
// Use services directly for custom flows
final text = await DocumentParser.parsePdf(pdfBytes);
final intent = IntentParser.classify('Summarize this');
```

---

## Step 8: Adding Metadata

You can attach arbitrary string data (typically JSON) to any document. This is useful for storing URLs, authors, or timestamps.

```dart
import 'dart:convert';

await MobileRag.instance.addDocument(
  'Flutter 3.19 was released in Feb 2024.',
  metadata: jsonEncode({
    'url': 'https://flutter.dev',
    'author': 'Google',
    'year': 2024
  }),
);

// Retrieval
final results = await MobileRag.instance.search('frontend framework');
for (var r in results.chunks) {
  if (r.metadata != null) {
      final meta = jsonDecode(r.metadata!);
      print('Source URL: ${meta['url']}');
  }
}
```

---

---

## Step 9: Advanced Features

### 1. Optimize Startup (Cached Index)
HNSW cache load/rebuild is handled automatically during initialization.  
In most apps, you only need to gate first search when using `deferIndexWarmup: true`.  
See [Index Management](../features/index_management.md) for persistence details.

```dart
await MobileRag.initialize(...);

// If initialized with deferIndexWarmup: true, wait before first search
if (!MobileRag.instance.isIndexReady) {
  await MobileRag.instance.warmupFuture;
}
```

### 2. Search for LLM Context
If you are building a chat app, use `searchHybridWithContext` to get a formatted prompt context directly.

```dart
final result = await MobileRag.instance.searchHybridWithContext(
  'Explain quantum physics',
  tokenBudget: 1000, // Limit context size for LLM
);

// Ready-to-use prompt context
print(result.context.text); 
```

### 3. Database Stats
Check how much data you have stored.

```dart
final stats = await MobileRag.instance.getStats();
print('Sources: ${stats.sourceCount}, Chunks: ${stats.chunkCount}');
```

---

## Step 10: Multi-Collection (v1)

Use collection scopes when you want independent indexing/rebuild units by category
(for example `business` vs `travel`) without rebuilding the entire corpus.
For a focused guide, see [Multi-Collection Feature](../features/multi_collection.md).

```dart
final business = MobileRag.instance.inCollection('business');
final travel = MobileRag.instance.inCollection('travel');

await business.addDocument('Large business corpus text...');
await travel.addDocument('Small travel corpus text...');

// Rebuild/warmup only the target collection if needed
await travel.rebuildIndex();

if (!travel.isIndexReady) {
  await travel.warmupFuture;
}

final hits = await travel.searchHybrid('hotel near station', topK: 5);
print('travel hits: ${hits.length}');
```

Notes:
- Existing code without collection parameters still uses the default `__default__` collection.
- `searchHybrid` remains collection-scoped by default when called through a `CollectionRag`.

---

## Next Steps

- [Model Setup Guide](model_setup.md) - Model selection and deployment strategies
- [FAQ](faq.md) - Frequently asked questions
- [Troubleshooting](troubleshooting.md) - Problem solving guide
