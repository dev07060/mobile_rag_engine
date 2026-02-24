# Frequently Asked Questions

Common questions about `mobile_rag_engine`.

---

## General

### Q: Does it support Korean?

**Yes!** Switch to the BGE-m3 model, which supports 100+ languages with excellent Korean performance.

```bash
# Download multilingual model (INT8 quantized, ~542MB)
curl -L -o model.onnx "https://huggingface.co/Teradata/bge-m3/resolve/main/onnx/model_int8.onnx"
curl -L -o tokenizer.json "https://huggingface.co/BAAI/bge-m3/resolve/main/tokenizer.json"
```

See [Model Setup Guide](model_setup.md) for details.

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
| Korean / Multilingual apps | **BGE-m3** (1024 dim, ~542MB) |
| Quick prototyping | **MiniLM** |

### Q: BGE-m3 is too large (542MB) for my app

Several options available:

1. **Use MiniLM instead** (~23MB, English only) — this is the default
2. **Download at runtime** - Download BGE-m3 on first app launch
3. **Accept the size** - iOS allows 4GB, Android Play allows 150MB AAB

See [Model Setup Guide](model_setup.md#production-deployment-strategies) for details.

### Q: Can I use custom models?

**Yes!** Any Sentence Transformer model can be converted to ONNX:

```bash
pip install optimum[exporters]
optimum-cli export onnx --model sentence-transformers/YOUR_MODEL ./output
```

### Q: What happens if I switch models?

**All documents must be re-embedded.** Each model produces different vector dimensions:
- BGE-m3: 1024 dimensions
- MiniLM: 384 dimensions

---

## Performance

### Q: Embedding is slow

1. **Use batch processing**:
   ```dart
   await EmbeddingService.embedBatch(texts, onProgress: ...);
   ```

2. **Run in isolate** (prevents UI freezing):
   ```dart
   await compute(embedInBackground, texts);
   ```

3. **Use INT8 quantized models** - 2-4x faster

### Q: Search is slow

Rebuild the HNSW index:
```dart
await MobileRag.instance.rebuildIndex();
```

### Q: Memory usage is high

- **Limit document count**: 10K+ may cause degradation
- **Use INT8 models**: 50% memory savings
- **Rebuild index periodically**: Call `MobileRag.instance.rebuildIndex()`

---

## Integration

### Q: How do I integrate with an LLM?

`mobile_rag_engine` handles the **Retrieval** part of RAG. LLM integration example:

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

Currently supports **iOS, Android, and macOS** only. Web support is planned for future releases.

---

## Data

### Q: Where is data stored?

In the Documents directory as a SQLite database (via `path_provider`):
- iOS: `~/Documents/rag.db`
- Android: `/data/data/<package>/files/rag.db`

### Q: Can I backup/restore data?

Copy the database file (`rag.db`):

```dart
final dbFile = File('${dir.path}/rag.db');
await dbFile.copy(backupPath);
```

### Q: What's the maximum document count?

Tested with **10,000+ documents**. Actual limits depend on device memory.
