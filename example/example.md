# Mobile RAG Engine - Example

A complete on-device RAG (Retrieval-Augmented Generation) implementation.

## Initialization

Install the Model Pack with `dart run mobile_rag_engine:setup --preset
stable-minilm-l6-v2-arm64-en`, declare `assets/mobile_rag/` in `pubspec.yaml`,
and initialize from its manifest. See the
[Quick Start](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/guides/quick_start.md).

```dart
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize MobileRag (Singleton)
  await MobileRag.initialize(
    modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
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
// No rebuildIndex() needed: the next search waits for the index update.
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

## Search

```dart
// Hybrid (vector + keyword) search with LLM-ready context
final searchResult = await MobileRag.instance.searchHybridWithContext(
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


See the full example app in the [GitHub repository](https://github.com/dev07060/mobile_rag_engine/tree/main/example).
