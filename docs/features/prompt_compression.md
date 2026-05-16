# Prompt Compression (REFRAG)

Mobile RAG Engine includes a built-in **Prompt Compressor** inspired by REFRAG principles. This feature reduces the token count of your retrieved context, allowing you to fit more information into the LLM's context window or save on API costs.

## Why use Prompt Compression?

1.  **Cost Savings**: Reduces input tokens sent to paid APIs (OpenAI, Gemini).
2.  **Larger Context**: Fits more search results into the same context window.
3.  **Noise Reduction**: Removes redundant information that might confuse the model.

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

You can adjust the aggressiveness of the compression:

| Level | Value | Description | Use Case |
|-------|-------|-------------|----------|
| **Minimal** | `0` | Removes exact duplicate sentences. | Safe for all use cases. |
| **Balanced** | `1` | Removes duplicates and near-duplicates. | **Recommended default.** Good balance of size vs coherence. |
| **Aggressive** | `2` | Aggressive deduplication and pruning. | When you strictly need to minimize tokens at all costs. |

## Advanced: Semantic Sentence Selection (Phase 2)

For advanced use cases, you can use the **Semantic Sentence Selector**. This breaks chunks down into sentences and keeps only the ones most relevant to the query, discarding irrelevant fluff surrounding the key information.

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

The compressor runs locally on-device using Rust for high performance.

1.  **Deduplication**: Identifies and removes repeated sentences/phrases across different documents.
2.  **Stopword Filtering** (Optional): Can remove excessive "filler" words (e.g., "the", "a", "is") if configured, though disabled by default to preserve natural language flow for modern LLMs.
3.  **Relevance Filtering** (Phase 2): Uses embedding similarity to score individual sentences within a chunk, keeping only the most salient points.
