# Adjacent Chunk Retrieval

Adjacent chunk retrieval is a powerful feature in `mobile_rag_engine` that allows you to fetch the "surrounding context" of a specific chunk. This is essential for features like **"Read Previous/Next"** in a UI or expanding the context window for LLMs when a single chunk is too short.

## Why is this needed?

Search results (chunks) are often small fragments of a document (e.g., 500 characters). Sometimes, a match is correct, but the *answer* lies in the sentence immediately following the chunk. Retrieving adjacent chunks bridges this gap.

## Method 1: Automatic Expansion (Search API)

The easiest way to get adjacent chunks is to ask for them directly during the search.

### Usage

Use the `adjacentChunks` parameter in the `search` method.

```dart
final result = await MobileRag.instance.search(
  'What is the refund policy?',
  topK: 5,
  adjacentChunks: 1, // Fetch 1 chunk before and 1 chunk after each match
);
```

### Behavior
- If `adjacentChunks: 1` is set, the engine will fetch:
    - `[Match Index - 1]` (Previous chunk)
    - `[Match Index]` (The search result itself)
    - `[Match Index + 1]` (Next chunk)
- These chunks are automatically combined or returned in the `chunks` list depending on implementation (in `mobile_rag_engine`, they are usually flattened into the results list).

**Note:** This increases the number of chunks returned and consumes more tokens if you are building an LLM context.

## Method 2: Manual Retrieval (Low-Level API)

For specific UI interactions (e.g., a "Show More" button), you can manually fetch adjacent chunks using the chunk ID or index.

### Prerequisites
You need the `sourceId` and `chunkIndex` from an existing `ChunkSearchResult`.

```dart
// Assume you have a search result
final chunk = searchResults.first;
final currentSourceId = chunk.sourceId;
final currentIndex = chunk.chunkIndex; // The sequential index of this chunk in the doc
```

### Fetching Neighbors

Use `getAdjacentChunks` when you already have a source ID and chunk index.

```dart
// 1. Calculate the range you want
// e.g., Get 2 chunks before and 2 chunks after
final minIndex = (currentIndex - 2).clamp(0, 999999);
final maxIndex = currentIndex + 2;

// 2. Fetch adjacent chunks
final neighbors = await MobileRag.instance.getAdjacentChunks(
  sourceId: currentSourceId,
  minIndex: minIndex,
  maxIndex: maxIndex,
);

// 3. Use the results
for (final neighbor in neighbors) {
  print('[${neighbor.chunkIndex}] ${neighbor.content}');
}
```

## Use Cases

1.  **"Expand Context" Button**: Display a search result card with a button to load the surrounding paragraph.
2.  **Continuous Reading**: Allow users to click a search result and then scroll up/down to read the rest of the document naturally.
3.  **LLM Context Windowing**: If a user asks a follow-up question that implies "what happened next?", you can fetch `[Match + 1, Match + 2]` to provide that context to the AI.
