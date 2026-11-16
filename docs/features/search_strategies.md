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
**Behavior**: takes the highest-ranked chunk whose source differs from the previous chunk's, so two chunks of one source are not placed next to each other while another source is left.
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
- **Scope note**: This budget applies to `context.text` only. It does **not** automatically include the extra system instruction, question, or answer wrapper added later by `formatPrompt()`.
- **Tip**: `tokenBudget` counts engine tokens, which can differ several times from your LLM's; see [Token budget](../guides/ask.md#token-budget).

### `adjacentChunks`
- **Default**: `0`
- **Description**: For every matching chunk, also fetch `n` chunks before and `n` chunks after it.
- **Use Case**: recovering lost context.
- **Example**: If a chunk says "It returns true.", fetching adjacent chunks reveals *what* function returns true.
```dart
// Hits first in rank order, then their neighbors (ContextStrategy.chronological for document order)
await MobileRag.instance.search(query, adjacentChunks: 1);
```

### `vectorWeight` vs `bm25Weight`
- **Default**: `0.2`, `0.8`, or the `defaultVectorWeight` / `defaultBm25Weight` passed to `MobileRag.initialize`
- **Description**: Controls the balance between Semantic Search (Vector) and Keyword Search (BM25).
- **Formula**: `score = vectorWeight / (60 + vectorRank) + bm25Weight / (60 + bm25Rank)` (reciprocal rank fusion)
- **Validation**:
    - Values outside `0.0 ~ 1.0` are clamped at runtime.
    - If both become `0`, defaults (`0.2`, `0.8`) are restored.
- **Scenarios**:
    - **Concept Search**: `vectorWeight: 0.8`, `bm25Weight: 0.2` (e.g., "How does this feel?")
    - **Exact Term Search**: `vectorWeight: 0.2`, `bm25Weight: 0.8` (e.g., "Error code 0x1234")

## Example Scenarios

### Scenario A: Precise QA on Technical Manuals
Technical terms matter, so keep the keyword weight high (the default 0.8). Need exact context.
```dart
await MobileRag.instance.searchHybridWithContext(
  'How to fix Error 505?',
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
