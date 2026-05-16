# Index Management & Maintenance

Mobile RAG Engine provides a suite of tools for managing your vector index, monitoring statistics, and handling model updates.

## 1. Monitoring Statistics (`SourceStats`)

You can check the current state of your index at any time. This is useful for displaying usage info to users (e.g., "Indexed 5 documents (120 chunks)").

```dart
final stats = await MobileRag.instance.getStats();

print('Documents: ${stats.sourceCount}');
print('Chunks: ${stats.chunkCount}');
```

## 2. Listing & Deleting Sources

You can manage the documents in your index individually.

### List all sources
```dart
final sources = await MobileRag.instance.listSources();

for (final source in sources) {
  print('ID: ${source.id}, Name: ${source.name}');
  print('Indexed At: ${DateTime.fromMillisecondsSinceEpoch(source.createdAt * 1000)}');
}
```

### Delete a source
Deleting a source removes it from the database immediately. The search index (HNSW) will lazily filter it out until the next rebuild.

```dart
await MobileRag.instance.removeSource(sourceId);
```

**Note:** If you delete a significant portion of your data (e.g., >50%), it's recommended to call `MobileRag.instance.rebuildIndex()` to reclaim memory and optimize search performance.

## 3. Data Migration & Re-embedding

If you update your embedding model (e.g., switch from a 384-dim model to a 512-dim model), existing vectors become invalid. The advanced `RagEngine` API provides a utility to **re-calculate embeddings** for all existing chunks without re-parsing original files.

```dart
// Run this after initializing the engine with a NEW model
await MobileRag.instance.engine.regenerateAllEmbeddings(
  onProgress: (done, total) {
    print('Re-embedding: $done / $total');
  },
);
```



## 4. Resetting the Engine

If you need to wipe everything and start fresh (e.g., "Delete All Data" button in settings):

```dart
// WARNING: Irreversible!
await MobileRag.instance.clearAllData();
```
This deletes the SQLite database, HNSW index files, and resets the internal state.

## 5. Persistence & Recovery

Mobile RAG Engine uses a robust persistence system to ensure fast startups and data integrity.

### HNSW Index Persistence
Instead of rebuilding the vector index from SQLite on every app launch (which can be slow for large datasets), the engine **saves the HNSW graph to disk** (`.hnsw.data`, `.hnsw.graph`).

- **On Startup:** The engine checks for these files. If found, it loads them into memory instantly (O(1) vs O(N)).
- **On Change:** When you add/remove documents, the index is marked as "dirty".
- **Auto-Save:** The index is automatically rebuilt and saved to disk after a short debounce period.

### Crash Recovery
If the app crashes during an indexing operation, the engine leaves a `.dirty` marker file. On the next launch, it detects this marker and automatically triggers a full index rebuild from the SQLite source of truth, ensuring your search index never gets corrupted.
