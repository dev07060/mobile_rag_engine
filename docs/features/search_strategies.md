# Search Strategies & Parameters

Mobile RAG Engine provides powerful control over how search results are retrieved, ranked, and assembled into context for LLMs. This guide explains the key parameters and strategies available.

## Search Methods

| Method | Description | Use Case |
|--------|-------------|----------|
| `search()` | Vector-only semantic search. | Fastest, good for general meaning matching. |
| `searchHybrid()` | Combined Vector + BM25 (Keyword) search. | Best accuracy, balances meaning and exact keywords. |
| `searchHybridWithContext()` | Hybrid search + Context Assembly. | **Recommended for LLM Applications.** Automatically fits results into a token budget. |

## Context Strategy (`ContextStrategy`)

The `strategy` parameter controls how the engine selects and orders chunks when building the final context string.

### 1. `relevanceFirst` (Default)
**Behavior**: fills the token budget with the highest-scoring chunks first.
**Use Case**: General Q&A where accuracy is paramount.
```dart
final result = await MobileRag.instance.searchHybridWithContext(
  query,
  strategy: ContextStrategy.relevanceFirst,
);
```

### 2. `diverseSources`
**Behavior**: penalizes consecutive chunks from the same source to ensure variety. It tries to pick the best chunk from Source A, then Source B, then Source C, before going back to A.
**Use Case**: Summarization across multiple documents, "What do different reports say about X?".
```dart
final result = await MobileRag.instance.searchHybridWithContext(
  query,
  strategy: ContextStrategy.diverseSources,
);
```

### 3. `chronological`
**Behavior**: searches for relevant chunks, but re-orders them based on their document order (Chunk Index).
**Use Case**: Narratives, long manuals, or code where the sequence of information is critical for understanding.
```dart
final result = await MobileRag.instance.searchHybridWithContext(
  query,
  strategy: ContextStrategy.chronological,
);
```

## Key Parameters

### `topK`
- **Default**: `10`
- **Description**: The number of candidate chunks to retrieve initially.
- **Tip**: Set this higher (e.g., 20) if you use `tokenBudget` to filter them later, or if you expect relevant information to be scattered.

### `tokenBudget`
- **Default**: `2000`
- **Description**: The maximum number of **engine tokenizer** tokens the final `context.text` string can contain.
- **Counting basis**: document wrappers, metadata, and markdown header-path contextual text are included in this count because the engine measures the fully rendered context string.
- **Scope note**: This budget applies to `context.text` only. It does **not** automatically include the extra system instruction, question, or answer wrapper added later by `formatForPrompt()`.
- **Tip**: Set this based on your LLM's context window minus your prompt size. (e.g., for 4k model, use ~3000).

### `adjacentChunks`
- **Default**: `0`
- **Description**: For every matching chunk, also fetch `n` chunks before and `n` chunks after it.
- **Use Case**: recovering lost context.
- **Example**: If a chunk says "It returns true.", fetching adjacent chunks reveals *what* function returns true.
```dart
// Fetch context: [Prev Chunk] + [Match] + [Next Chunk]
await MobileRag.instance.search(query, adjacentChunks: 1);
```

### `vectorWeight` vs `bm25Weight`
- **Default**: `0.2`, `0.8`
- **Description**: Controls the balance between Semantic Search (Vector) and Keyword Search (BM25).
- **Formula**: `Final Score = (VectorRank * vectorWeight) + (BM25Rank * bm25Weight)` (Rank fusion)
- **Validation**:
    - Values outside `0.0 ~ 1.0` are clamped at runtime.
    - If both become `0`, defaults (`0.2`, `0.8`) are restored.
- **Scenarios**:
    - **Concept Search**: `vectorWeight: 0.8`, `bm25Weight: 0.2` (e.g., "How does this feel?")
    - **Exact Term Search**: `vectorWeight: 0.2`, `bm25Weight: 0.8` (e.g., "Error code 0x1234")

## Example Scenarios

### Scenario A: Precise QA on Technical Manuals
Technical terms matter, so boost BM25. Need exact context.
```dart
await MobileRag.instance.searchHybridWithContext(
  'How to fix Error 505?',
  bm25Weight: 0.7, // Boost keyword search
  vectorWeight: 0.3,
  adjacentChunks: 1, // Get surrounding steps
  strategy: ContextStrategy.chronological, // Maintain step order
);
```

### Scenario B: Broad Theme Summarization
"What are the main themes in these meeting notes?"
```dart
await MobileRag.instance.searchHybridWithContext(
  'Project themes and updates',
  topK: 20, // Look broadly
  strategy: ContextStrategy.diverseSources, // Get updates from everyone
  tokenBudget: 3000, // Allow detailed summary
);
```

## Testing Strategies

Because search behaviors can be complex, it's important to verify them. You can unit test your strategy configurations without the native engine using mocks.

See the [Unit Testing Guide](../test/unit_testing.md) for details on how to inject mock results to verify that your `tokenBudget` and `strategy` logic is handling the returned chunks correctly.
