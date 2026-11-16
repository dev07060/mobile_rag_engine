# Prompt Compression

> **Not an officially supported feature.** `PromptCompressor` and `ContextBuilder.buildWithCompression` may change or be removed in a later release.

`ContextBuilder.buildWithCompression` removes exact duplicate sentences from the assembled context and cuts it to the token budget.

## Quick Start

The easiest way to use compression is via `ContextBuilder.buildWithCompression`.

```dart
final result = await MobileRag.instance.search('query');
final originalContext = result.context;

// Build context with compression
final context = await ContextBuilder.buildWithCompression(
  searchResults: result.chunks,
  tokenBudget: 1000, // Stricter budget
  compressionLevel: 1, // Balanced
);

print('Original: ${originalContext.text.length} chars');
print('Compressed: ${context.text.length} chars');
```

## Compression Levels

`compressionLevel` currently has no effect: every level removes exact duplicate sentences and cuts the text to the budget.

## Semantic Sentence Selection

`compressWithSimilarity` splits chunks into sentences, embeds each sentence (one embedding per sentence) and keeps up to `maxSentences` sentences above `minSimilarity`.

```dart
// 1. Get query embedding
final queryEmb = await EmbeddingService.embed('What is the battery life?');
final result = await MobileRag.instance.search('battery life');

// 2. Compress by selecting top 15 relevant sentences
final compressed = await PromptCompressor.compressWithSimilarity(
  chunks: result.chunks,
  queryEmbedding: queryEmb,
  maxSentences: 15,
  minSimilarity: 0.3,
);
```

## How it Works

1.  **Deduplication**: Removes repeated sentences across documents.
2.  **Relevance Filtering** (`compressWithSimilarity`): Uses embedding similarity to score individual sentences within a chunk, keeping only the most salient points.
