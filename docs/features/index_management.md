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

Vectors from different embedding models cannot be compared. The engine stores
a fingerprint of the model that produced the vectors (file name, dimension and
a hash of the model file, from 0.23.0) and compares it with the loaded model
on every `MobileRag.initialize`. If they differ, `initialize` still succeeds,
but search and ingestion are locked: `search`, `addDocument` and the other
search and ingest calls throw
`RagError.embeddingFingerprintMismatch(<stored>, <loaded>, <chunks to re-embed>)`.

```dart
final rag = MobileRag.instance;
final lock = rag.embeddingFingerprintLock; // null when not locked
if (lock != null) {
  print('stored: ${lock.stored}, loaded: ${lock.current}, '
      'chunks: ${lock.remainingChunks}');
}
```

There are three ways out of the lock.

**Keep the documents: `reembedAll()`.** It embeds every stored chunk again
with the loaded model, without re-parsing the original files, then rebuilds
the index and removes the lock. Progress is saved per chunk, so after an app
restart the next call continues where the last one stopped.

```dart
if (rag.isEmbeddingFingerprintLocked) {
  await rag.reembedAll(
    onProgress: (p) => print('Re-embedding: ${p.done} / ${p.total}'),
  );
}
```

**Start over: `clearAllData()`.** It deletes every document, chunk and index
(see [Resetting the Engine](#4-resetting-the-engine)) and removes the lock.
Add your documents again afterwards.

**Drop only the embeddings: `clearAndRestart()`.** It deletes the chunks and
their vectors and removes the lock, but keeps the rows that `listSources()`
returns. Adding a document whose content matches a kept source returns
`isDuplicate: true` with no chunks, so remove the kept sources before you add
the documents again:

```dart
if (rag.isEmbeddingFingerprintLocked) {
  await rag.clearAndRestart(
    confirm:
        ClearAndRestartConfirmation.iUnderstandThisDeletesAllOnDeviceEmbeddings,
  );
  for (final source in await rag.listSources()) {
    await rag.removeSource(source.id.toInt());
  }
  // Now add the documents again.
}
```

`reembedAll()` and `clearAndRestart()` throw `StateError` when there is no
lock. `engine.regenerateAllEmbeddings()` and `rebuildIndex()` do not remove
the lock, so they are not a way to switch models.

## 4. Resetting the Engine

If you need to wipe everything and start fresh (e.g., "Delete All Data" button in settings):

```dart
// WARNING: Irreversible!
await MobileRag.instance.clearAllData();
```
This deletes the SQLite database, the vector store, the HNSW index files of
every collection, and resets the internal state. The model files stay.

## 5. Persistence & Recovery

### Files on disk

With the default `databaseName: 'rag.sqlite'`, the engine keeps these files in
its storage directory. Another database name changes the `rag` prefix.

| File | Contents | Back up? |
|:-----|:---------|:---------|
| `rag.sqlite` | Sources, chunk text and metadata (SQLite) | Yes |
| `rag.sqlite-wal`, `rag.sqlite-shm` | SQLite write-ahead log. Present while the engine is open; recent writes are here and not yet in `rag.sqlite` | Yes, if present |
| `rag.vec` | The stored embedding vectors. This is their only copy | Yes |
| `rag_hnsw.hnsw`, `rag_hnsw_<8 hex>.hnsw` | Vector index of the default collection and of each other collection | No, rebuilt when missing |
| `rag.dirty`, `rag.<8 hex>.dirty` | Empty markers that exist while an index update is pending | No |

The storage directory is the application documents directory, or the
application support directory on Windows. `MobileRag.instance.dbPath` returns
the database path on the running device. The
[FAQ](../guides/faq.md#q-where-is-data-stored) lists the directory per
platform.

### Backup and restore

Call `MobileRag.dispose()` first: it closes the database and merges the
write-ahead log into `rag.sqlite`. Then copy `rag.sqlite` and `rag.vec`
together (and the `-wal`/`-shm` files if they still exist). To restore, put
them back under the same names before `MobileRag.initialize` and use the same
model. The engine rebuilds the `.hnsw` files on the next start. The
[FAQ](../guides/faq.md#q-can-i-backuprestore-data) has the code.

`rag.sqlite` without `rag.vec` is not a backup: `MobileRag.initialize` fails
with `RagError.invalidInput(... missing or invalid persisted embedding)`.

### HNSW Index Persistence
Instead of rebuilding the vector index on every app launch (which can be slow
for large datasets), the engine **saves the HNSW graph to disk**
(`rag_hnsw.hnsw`, and `rag_hnsw_<8 hex>.hnsw` for each other collection).

- **On Startup:** The engine loads the saved index. If there is none, or an index update was still pending when the app last stopped, it rebuilds the index.
- **On Change:** When you add or remove documents, the index is marked as "dirty".
- **Auto-Save:** The index is rebuilt and saved to disk after a short debounce period, or before the next search, whichever comes first.

### Crash Recovery
While an index update is pending, the engine keeps an empty marker file
(`rag.dirty`, or `rag.<8 hex>.dirty` for another collection). It is created
when documents are added or removed and deleted once the rebuilt index is
saved. If the app is killed in between, the next launch finds the marker and
rebuilds the index from the database and the vector store.
