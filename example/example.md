# Mobile RAG Engine - Example

A complete on-device RAG (Retrieval-Augmented Generation) implementation.

## Quick Start

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize MobileRag (Singleton)
  await MobileRag.initialize(
    tokenizerAsset: 'assets/tokenizer.json',
    modelAsset: 'assets/model.onnx',
  );
  
  runApp(const MyApp());
}
```

## Adding Documents

```dart
// Add a document with automatic chunking and embedding
final result = await MobileRag.instance.addDocument(
  'Flutter is Google\'s UI toolkit for building beautiful apps...',
  onProgress: (done, total) => print('Embedding: $done/$total'),
);

print('Created ${result.chunkCount} chunks');

// Rebuild HNSW index after adding documents
await MobileRag.instance.rebuildIndex();
```

## PDF & DOCX Support

Can automatically extract text from PDF and DOCX files. When you have a stable local path, prefer `addDocumentFromFile` so the native side can read and chunk the file directly.

```dart
import 'dart:io';

final file = File('path/to/document.pdf');

await MobileRag.instance.addDocumentFromFile(
  file.path,
  metadata: '{"source": "document.pdf"}',
  name: 'document.pdf',
);
```

## Managing Documents

```dart
// Remove a source by ID
await MobileRag.instance.removeSource(sourceId);

// Check stats
final stats = await MobileRag.instance.getStats();
print('Total sources: ${stats.sourceCount}');
```

## Semantic Search

```dart
// Search for relevant chunks
final searchResult = await MobileRag.instance.search(
  'How to build mobile apps?',
  topK: 5,
  tokenBudget: 2000,
);

// Get assembled context for LLM
print('Found ${searchResult.chunks.length} chunks');
print('Context tokens: ${searchResult.context.estimatedTokens}');

// Format prompt for LLM
final prompt = MobileRag.instance.formatPrompt(
  'How to build mobile apps?',
  searchResult,
);
```

## Advanced Usage (Low-Level)

For advanced scenarios, you can still access the underlying services:

```dart
// Batch embedding directly
final embeddings = await EmbeddingService.embedBatch(
  ['Text 1', 'Text 2', 'Text 3'],
);

// Parse user intent (low-level)
final intent = IntentParser.classify('Summarize this document');
if (intent is UserIntent_Summary) {
  // Handle summary
}
```

## Performance

| Operation | Time | Engine |
|:----------|-----:|:-------|
| Tokenization | 0.04ms | Rust |
| HNSW Search | 0.3ms | Rust |
| Embedding | 25-100ms | ONNX |

See the full example app in the [GitHub repository](https://github.com/dev07060/mobile_rag_engine/tree/main/example).
