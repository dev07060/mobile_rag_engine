# Frequently Asked Questions

Common questions about `mobile_rag_engine`.

---

## General

### Q: Does it support Korean?

**Yes, with a Korean model.** The default Model Pack (`all-MiniLM-L6-v2`) is
English-only and scores close to random on Korean text. For Korean documents
use **KoEn-E5-Tiny**: it covers Korean and English, has 384 dimensions like
MiniLM, and its model and tokenizer take about 39 MB.

The `setup` command installs only the MiniLM pack, so follow
[Korean documents: KoEn-E5-Tiny](model_setup.md#korean-documents-koen-e5-tiny):
download the two files, write the Model Pack manifest, and initialize with it.

KoEn-E5-Tiny covers only Korean and English. For other languages, see the
[model comparison](model_setup.md#model-comparison).

### Q: Does it work offline?

**Yes, 100% offline.** All models and data are stored locally on the device. No network connection required.

### Q: Can I test on iOS Simulator?

Yes, but it's **3-5x slower than real devices**. Always run performance tests on physical hardware.

---

## Models

### Q: Which model should I choose?

| Use Case | Recommended Model |
|:---------|:------------------|
| English-only apps (default) | **MiniLM** (384 dim, ~23MB) |
| Korean, or Korean and English | **KoEn-E5-Tiny** (384 dim, ~37MB); see the [recipe](model_setup.md#korean-documents-koen-e5-tiny) |
| Other languages, or many languages mixed | **BGE-m3** (1024 dim, ~542MB) |
| Quick prototyping | **MiniLM** |

### Q: BGE-m3 is too large (542MB) for my app

Several options available:

1. **Use a smaller model** - MiniLM (~23MB, English only, the default) or KoEn-E5-Tiny (~37MB, Korean and English)
2. **Download at runtime** - Download BGE-m3 on first app launch and pass it with `tokenizerPath`/`modelPath` (releases after 0.23.0; 0.23.0 needs the model bundled). See [Release Build Guide](release_build.md).
3. **Accept the size** - iOS allows 4GB, Android Play allows 150MB AAB

See [Model Setup Guide](model_setup.md#production-deployment-strategies) for details.

### Q: Can I use custom models?

**Yes, with compatibility constraints.**

Supported ONNX required inputs:
- `input_ids`
- `attention_mask`
- optional `token_type_ids` (auto-filled with zeros when required)

Not supported yet:
- Models requiring extra mandatory inputs such as `position_ids`

Validated ONNX artifacts:
- `https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_qint8_arm64.onnx`
- `https://huggingface.co/Teradata/bge-m3/resolve/main/onnx/model_int8.onnx`

Models outside the validated list are best-effort.

```bash
pip install optimum[exporters]
optimum-cli export onnx --model sentence-transformers/YOUR_MODEL --task feature-extraction ./output
```

### Q: What happens if I switch models?

**Search and ingestion are locked until the stored chunks are embedded again.**
Vectors from different models cannot be compared. 0.23.0 and later record the
model file's name, dimension and content hash, and compare them on every
`MobileRag.initialize`. After a model change, `search`, `addDocument` and the
other search and ingest calls throw:

```
RagError.embeddingFingerprintMismatch(field0: <stored model>, field1: <loaded model>, field2: <chunks to re-embed>)
```

Check for the lock after `initialize` and pick one of the two ways out:

```dart
final rag = MobileRag.instance;
if (rag.isEmbeddingFingerprintLocked) {
  // Keep the documents: embed every stored chunk again with the new model.
  await rag.reembedAll(
    onProgress: (p) => debugPrint('re-embedding ${p.done}/${p.total}'),
  );
}
```

`reembedAll()` resumes after an app restart. To start over instead, call
`clearAllData()` and add your documents again:

```dart
if (rag.isEmbeddingFingerprintLocked) {
  await rag.clearAllData(); // deletes every document, chunk and index
}
```

`regenerateAllEmbeddings()` and `rebuildIndex()` do not remove the lock. See
[Data Migration & Re-embedding](../features/index_management.md#3-data-migration--re-embedding)
for `clearAndRestart()` and the details.

---

## Performance

### Q: Embedding is slow

1. **Use batch processing**:
   ```dart
   await EmbeddingService.embedBatch(
     texts,
     onProgress: (done, total) => print('$done / $total'),
   );
   ```

2. **Keep embedding off the UI thread**: `MobileRag.initialize(...)` configures the embedding worker isolate for normal app flows.

3. **Use INT8 quantized models** - 2-4x faster

### Q: Search is slow

Rebuild the HNSW index:
```dart
await MobileRag.instance.rebuildIndex();
```

### Q: A short document is not in the answer, although `search` finds it

`ask` and `prepareAsk` put only the top 5 passages in the prompt. A
one-sentence document stored next to a large one can rank below chunks of the
large document that match common words of the question. See
[Short documents next to a large one](ask.md#short-documents-next-to-a-large-one)
in the Ask guide for the three things that help.

### Q: Memory usage is high

- **Prefer file-path ingest for large local files**: Use `addDocumentFromFile(path)` for text-layer PDFs, DOCX, Markdown, and text files when you have a stable path. Scanned/image-only PDFs need OCR before indexing.
- **Use UTF-8 ingest when bytes are already loaded**: Use `addDocumentUtf8(bytes)` for text/Markdown bytes instead of converting them to a Dart `String` first.
- **Limit document count**: 10K+ may cause degradation.
- **Use INT8 models**: Smaller models reduce memory pressure.
- **Rebuild index periodically**: Call `MobileRag.instance.rebuildIndex()` when you need deterministic index freshness.

### Q: Which dispose API should I use?

For deterministic cleanup in advanced flows, prefer:

```dart
await EmbeddingService.disposeAsync();
```

`EmbeddingService.dispose()` remains for backward compatibility, but it is fire-and-forget.

### Q: What happens if I pass invalid config/search values?

The engine applies **soft runtime validation** for stability:

- `maxChunkChars < 100` → normalized to `100`
- `overlapChars < 0` → normalized to `0`
- `vectorWeight` / `bm25Weight` outside `0.0 ~ 1.0` → clamped
- if both weights become `0` → restored to defaults `0.2 / 0.8`

If both `threadLevel` and `embeddingIntraOpNumThreads` are set, debug builds assert; release builds keep running with `threadLevel` precedence and warning logs.

---

## Integration

### Q: How do I integrate with an LLM?

`mobile_rag_engine` has no LLM inside. Pass your own generation function to
`ask`: it searches, builds a prompt with numbered passages, calls your
function, and returns the answer with the passages it cites.

```dart
final answer = await MobileRag.instance.ask(
  query,
  generate: (prompt) => yourLlmService.generate(prompt), // Future<String>
);

print(answer.text);
for (final passage in answer.citations) {
  print('[${passage.id}] ${passage.text}');
}
```

See the [Ask guide](ask.md) for streaming, custom prompts and the no-result
case, and [LLM Tools](llm_tools.md) to give search to the model as a tool.

To build the prompt yourself, search and format it:

```dart
// 1. RAG search
final searchResult = await MobileRag.instance.search(query, topK: 5);

// 2. Format prompt
final prompt = MobileRag.instance.formatPrompt(query, searchResult);

// 3. Send to LLM (e.g., Gemini, OpenAI, etc.)
final response = await yourLlmService.generate(prompt);
```

### Q: Can I use it with Firebase?

**Yes!** It's completely independent. Use it in any Firebase app.

### Q: Does it support Web?

No. Supported platforms are **iOS, Android, macOS and Windows (x64)**. Web,
Linux and Windows on ARM64 are not supported.

---

## Data

### Q: Where is data stored?

In one directory, chosen through `path_provider`: the application documents
directory, or the application support directory on Windows.

| Platform | Directory |
|:---------|:----------|
| iOS | `<app container>/Documents/` |
| Android | `/data/user/0/<package>/app_flutter/` |
| macOS | `~/Library/Containers/<bundle id>/Data/Documents/` for a sandboxed app (the `flutter create` default), `~/Documents/` without the sandbox |
| Windows | `%APPDATA%\<company>\<app>\` |

`MobileRag.instance.dbPath` returns the full path of the database file on the
running device.

With the default `databaseName: 'rag.sqlite'` the engine keeps these files
there. Another database name changes the `rag` prefix.

| File | Contents |
|:-----|:---------|
| `rag.sqlite` | Sources, chunk text and metadata (SQLite) |
| `rag.sqlite-wal`, `rag.sqlite-shm` | SQLite write-ahead log. Present while the engine is open; recent writes are here and not yet in `rag.sqlite` |
| `rag.vec` | The stored embedding vectors. This is their only copy |
| `rag_hnsw.hnsw`, `rag_hnsw_<8 hex>.hnsw` | Vector index of the default collection and of each other collection. Rebuilt from the two files above when missing |
| `rag.dirty`, `rag.<8 hex>.dirty` | Empty markers that exist while an index update is pending |

The copied model and tokenizer are in the same directory (`model.onnx`,
`tokenizer.json`, or `mobile_rag_model_packs/` for a Model Pack).

### Q: Can I backup/restore data?

Yes. Close the engine first, then copy the database and the vector store
together. `rag.sqlite` alone is not a backup: while the engine is open most
recent writes are still in the `-wal` file, and the embeddings are in
`rag.vec`.

```dart
final dbPath = MobileRag.instance.dbPath; // .../rag.sqlite
await MobileRag.dispose(); // closes the database and merges the write-ahead log

final vecPath = '${dbPath.substring(0, dbPath.lastIndexOf('.'))}.vec';
for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm', vecPath]) {
  final file = File(path);
  if (await file.exists()) {
    await file.copy('${backupDir.path}/${file.uri.pathSegments.last}');
  }
}
```

To restore, put the files back in the storage directory under the same names
before `MobileRag.initialize`, and initialize with the same model. The index
files (`*.hnsw`) do not need to be backed up; the engine rebuilds them on the
next start. If the directory still has files of an older database with that
name, delete its `.hnsw` and `.dirty` files so that an old index is not
matched with the restored data.

Restoring `rag.sqlite` without `rag.vec` fails in `MobileRag.initialize` with
`RagError.invalidInput(... missing or invalid persisted embedding)`.

### Q: What's the maximum document count?

Tested with **10,000+ documents**. Actual limits depend on device memory.
