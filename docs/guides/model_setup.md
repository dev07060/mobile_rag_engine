# Model Setup Guide

This guide covers the recommended fixed Model Pack plus advanced custom ONNX
assets for `mobile_rag_engine`. The Model Pack is installed during development,
bundled with the app, and never downloaded at runtime.

## Recommended: stable MiniLM Model Pack

From your Flutter project, run:

```bash
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
```

It verifies the immutable revision and creates exactly:

```text
assets/mobile_rag/model.onnx
assets/mobile_rag/tokenizer.json
assets/mobile_rag/model-pack.json
```

Verify the installed files before initializing the engine:

```bash
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --check
```

The command does not edit `pubspec.yaml`. Declare the directory yourself:

```yaml
flutter:
  assets:
    - assets/mobile_rag/
```

Initialize from the manifest:

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset(
    'assets/mobile_rag/model-pack.json',
  ),
);
```

The sole v1 preset is `stable-minilm-l6-v2-arm64-en`: English, arm64,
384-dimensional, Apache-2.0 MiniLM at revision
`1110a243fdf4706b3f48f1d95db1a4f5529b4d41`. Vector storage is Q8_0. Use
`--repair` only to replace a file that fails its SHA-256/length check.

The first success is adding documents, rebuilding the index, then searching for
non-empty chunks/context. LLM generation is outside this package step.

---

<a id="korean-koen-e5-tiny"></a>

## Korean documents: KoEn-E5-Tiny

MiniLM is English-only. On Korean retrieval benchmarks it scores close to
random, so Korean apps should swap in a Korean-English model.
[KoEn-E5-Tiny](https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX)
(Apache-2.0) is the one we measured and recommend: it is 384-dimensional like
MiniLM and adds about 17 MB to the app.

| Model | Ko-StrategyQA nDCG@10 | AutoRAG nDCG@10 | ONNX + tokenizer |
|:------|:---:|:---:|:---:|
| all-MiniLM-L6-v2 (default) | 0.014 | 0.059 | 22.4 MB |
| KoEn-E5-Tiny (int8, arm64) | 0.762 | 0.866 | 39.3 MB |

Desktop measurement, whole documents embedded up to 512 tokens (MiniLM with
the earlier character-based limit). Method and the chunked numbers are in
[the measurement notes](../perf/multilingual-embedding/README.md).

KoEn-E5-Tiny only covers Korean and English. Text in other scripts, such as
Japanese or Chinese, is likely to be retrieved poorly.

### 1. Download the files

Pin the revision so the files cannot change under you:

```bash
mkdir -p assets/mobile_rag && cd assets/mobile_rag

REV=5cf599a8cd6577f2f12a026130ad50132e472cfd
BASE=https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX/resolve/$REV

curl -L -o model.onnx "$BASE/onnx/model_qint8_arm64.onnx"
curl -L -o tokenizer.json "$BASE/tokenizer.json"
```

### 2. Write the Model Pack manifest

The `setup` command installs only the MiniLM pack, so write
`assets/mobile_rag/model-pack.json` yourself. The engine checks both files
against these hashes and lengths on first launch:

```json
{
  "schemaVersion": 1,
  "preset": "koen-e5-tiny-arm64-koen",
  "modelId": "exp-models/dragonkue-KoEn-E5-Tiny-ONNX",
  "revision": "5cf599a8cd6577f2f12a026130ad50132e472cfd",
  "modelAsset": "assets/mobile_rag/model.onnx",
  "tokenizerAsset": "assets/mobile_rag/tokenizer.json",
  "modelSha256": "d463c9b1c29f3202d510e2836265d60f9e6e6dd518c5930ba865700646489bd4",
  "tokenizerSha256": "a6dd38d692ac1caa6d5dbc195d92f1f978b5c74ec60e02ed15fdf04404742fe3",
  "modelBytes": 38275821,
  "tokenizerBytes": 2931715,
  "architecture": "arm64",
  "embeddingDimension": 384,
  "license": "apache-2.0",
  "language": "Korean, English"
}
```

Use a Model Pack rather than `modelAsset`/`tokenizerAsset`. In
`mobile_rag_engine` 0.22.3 and earlier, those parameters copy the tokenizer to a
fixed file name and skip the copy when that file already exists, so an app that
previously ran MiniLM would keep MiniLM's tokenizer. 0.23.0 and later refresh a
stale copy, but they load and hash the bundled files on every launch to check.
A Model Pack is stored under its hashes, is always the one you bundled, and
skips that check once installed.

### 3. Bundle and initialize

```yaml
flutter:
  assets:
    - assets/mobile_rag/
```

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
  defaultVectorWeight: 0.6,
  defaultBm25Weight: 0.4,
);
```

**Set the hybrid search weights to 0.6 / 0.4.** The default weights (vector
0.2, BM25 0.8) suit the English-only default model. With them, hybrid search
(`ask`, `prepareAsk`, `searchHybrid*`, `RagSearchTool.fromMobileRag`) on Korean
text keeps almost only keyword results: Korean keywords are matched as
two-syllable pieces, so the 20 keyword candidates that `ask` looks at are nearly
always full, and a passage found only by KoEn-E5-Tiny's vector search cannot
outrank them. `defaultVectorWeight` / `defaultBm25Weight` apply to every
hybrid search that does not pass its own `vectorWeight` / `bm25Weight`.

Measured in the `ask` condition (5 passages, 20 candidates per list) with
KoEn-E5-Tiny, profile build on an Apple M3 Pro Mac, 2026-11-14:

| Questions | Vector only | 0.2 / 0.8 (default) | 0.6 / 0.4 |
|---|---|---|---|
| MIRACL Korean dev, 213 questions, 5,000 passages (answer in top 5) | 196 | 167 | 187 |
| Same, 15,000 passages | 176 | 165 | 181 |
| 32 hand-written questions (13 share no word with the answer) | 28 | 20 | 27 |
| 80 Wikipedia questions that share words with the answer | – | 72 | 73 |

MIRACL questions were written by native speakers; KoEn-E5-Tiny's base model was
trained on MIRACL's training split, so its vector numbers there may be
optimistic. The method and all numbers, including BGE-m3, are in
[the F2-0 report](../perf/f2-fusion/f2_0_report.md). Keep the defaults with the
English-only MiniLM: on its Korean questions, raising the vector weight loses
answers.

You do not need to add `query: ` or `passage: ` prefixes. With KoEn-E5-Tiny
they change scores by 0.002 or less.

### 4. Switching an existing database from MiniLM

Vectors from different models cannot be compared, so the stored chunks must be
embedded again.

**`mobile_rag_engine` 0.22.3 and earlier** identify the model by file name and
dimension only. Both packs install as `model.onnx` with 384 dimensions, so the
engine does not notice the switch and would mix vectors from both models. Open
a new database instead and add your documents again:

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
  databaseName: 'rag_koen.sqlite',
);
```

**0.23.0 and later** also hash the model file. After the switch they lock search
and ingestion until the stored chunks are embedded again. This also holds when
one app update both upgrades from 0.22.3 and switches the model. A 0.22.3
database records only the file name and dimension. So on its first launch the
engine re-embeds three short stored chunks and compares them with the stored
vectors before it records the model hash, and locks if they differ:

```dart
final rag = MobileRag.instance;
if (rag.embeddingFingerprintLock != null) {
  await rag.reembedAll(
    onProgress: (p) => debugPrint('re-embedding ${p.done}/${p.total}'),
  );
}
```

`reembedAll` keeps your documents and resumes after an app restart. If you
would rather re-ingest from your own sources, call `clearAllData()` and add
the documents again. `clearAndRestart(...)` also removes the lock, deletes the
stored chunks and keeps the rows that `listSources()` returns; add the
documents again afterwards (on 0.23.0 and earlier, remove the kept sources
first). See
[Data Migration & Re-embedding](../features/index_management.md#3-data-migration--re-embedding).

### Cost

KoEn-E5-Tiny has 12 layers to MiniLM's 6. On a desktop CPU, embedding a chunk
takes about twice as long (55 ms vs 28 ms, one thread), so ingestion is
slower. Queries are as fast or faster, because Korean text needs far fewer
tokens with this tokenizer. Loading the model and tokenizer takes about
110 MB of memory, against about 60 MB for MiniLM. These numbers have not been
measured on a phone yet.

---

## Advanced / legacy custom ONNX assets

## Model Comparison

| Model | Dimensions | Size (ONNX) | Max Tokens | Languages | Best For |
|:------|:----------:|:-----------:|:----------:|:----------|:---------|
| [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (INT8) | **384** | ~23 MB | 256 | English | English-only apps, lightweight & fast |
| [KoEn-E5-Tiny](https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX) (INT8) | **384** | ~37 MB | 512 | Korean, English | Korean apps ([recipe](#korean-documents-koen-e5-tiny)) |
| [Teradata/bge-m3](https://huggingface.co/Teradata/bge-m3) (INT8) | **1024** | ~542 MB | 8,194 | 100+ (multilingual) | Korean, CJK, mixed-language apps |

> **Dimension Matters**: The embedding dimension affects your vector index. Once you choose a model, all documents must use the same dimension. Switching models requires re-embedding all documents.

### Validated ONNX Artifacts

- MiniLM: `https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/onnx/model_qint8_arm64.onnx`
- BGE-m3: `https://huggingface.co/Teradata/bge-m3/resolve/main/onnx/model_int8.onnx`

These are the regression-tested artifacts for each patch release.

Compatibility improvements introduced in the `0.14.x` hardening patches remain available in current releases:
- models requiring `token_type_ids` are now supported without re-export
- the engine reads ONNX `inputNames` and injects zero `token_type_ids` only when required

Additional models outside this list are supported on a best-effort basis.
Validated examples during this compatibility patch: `all-MiniLM-L6-v2/onnx`, `intfloat/e5-small-v2`.

---

## Download Instructions

### all-MiniLM-L6-v2

```bash
mkdir -p assets && cd assets

# Download INT8 quantized model for ARM64 (~23MB)
curl -L -o model.onnx "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/onnx/model_qint8_arm64.onnx"

# Download tokenizer
curl -L -o tokenizer.json "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/tokenizer.json"
```

### BGE-m3 (Multilingual — Korean, CJK, etc.)

```bash
mkdir -p assets && cd assets

# Download INT8 quantized model (~542MB)
curl -L -o model.onnx "https://huggingface.co/Teradata/bge-m3/resolve/main/onnx/model_int8.onnx"

# Download tokenizer (~17MB)
curl -L -o tokenizer.json "https://huggingface.co/BAAI/bge-m3/resolve/main/tokenizer.json"
```

---

## Production Deployment Strategies

### Strategy 1: Bundle with App (Recommended for <100MB)

Include model files in your app bundle. Simple and works offline immediately.

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/model.onnx
    - assets/tokenizer.json
```

**Pros:**
- Works immediately after install
- No network dependency
- Consistent performance

**Cons:**
- Increases app download size
- App store limits (iOS: 4GB, Android Play: 150MB AAB)

## Custom Model Export

Custom ONNX models are supported when required inputs are:

- `input_ids`
- `attention_mask`
- optional `token_type_ids` (auto-filled with zeros when required)

Models with additional mandatory inputs (for example `position_ids`) are not supported yet.
Reason: architecture-specific mandatory inputs cannot be inferred safely by this package without model-specific preprocessing logic.

Export compatible Sentence Transformer models to ONNX format:

```bash
# Install optimum
pip install optimum[exporters]

# Export to ONNX
optimum-cli export onnx \
  --model sentence-transformers/YOUR_MODEL \
  --task feature-extraction \
  ./output

# (Optional) Quantize to INT8 for mobile
python -m onnxruntime.quantization.preprocess \
  --input model.onnx \
  --output model_prep.onnx

python -m onnxruntime.quantization.quantize \
  --input model_prep.onnx \
  --output model_int8.onnx \
  --per_channel
```

---

## ONNX Runtime Notes

This package uses the [`flutter_onnxruntime`](https://pub.dev/packages/flutter_onnxruntime) Flutter plugin for ONNX Runtime.

Runtime setup notes:
- iOS apps need minimum deployment target 16.0.
- macOS apps need minimum deployment target 14.0.
- CocoaPods builds on both iOS and macOS require static framework linkage:
  `use_frameworks! :linkage => :static` in the Runner target.
- Set the macOS Runner project's deployment target to 14.0 as well as
  `platform :osx, '14.0'` in its Podfile.
- From 0.22.1, `dart run mobile_rag_engine:setup` applies the settings above
  to the generated iOS and macOS hosts (`--skip-host-config` turns this off).
- Android release builds must keep the ONNX Runtime classes from R8. From
  0.22.2 (`rag_engine_flutter` 0.21.1) the plugin ships this rule; on earlier versions
  add `-keep class ai.onnxruntime.** { *; }` to the app's ProGuard rules (see
  [Troubleshooting](troubleshooting.md#android-release-build-crashes-on-the-first-search)).

`mobile_rag_engine` uses the default ONNX Runtime execution path for embedding inference. Do not assume CoreML, NNAPI, or another hardware execution provider is active unless you configure and validate that path in your host app.

### Performance Tips

1. **Use INT8 quantized models** - 2-4x smaller, similar accuracy
2. **Batch embeddings** when processing many documents:
   ```dart
   await EmbeddingService.embedBatch(
     texts,
     onProgress: (done, total) => print('$done / $total'),
   );
   ```
3. **Run in isolate** for heavy processing to avoid UI jank

---

## Troubleshooting

### "Failed to load ONNX model"

- Ensure model file exists at the specified path
- Check file is not corrupted (re-download if needed)
- Verify model is ONNX format (not PyTorch .bin or .safetensors)

### "Tokenizer initialization failed"

- Ensure `tokenizer.json` file exists
- File must be HuggingFace tokenizers format (not SentencePiece)

### iOS Simulator Limitations

ONNX Runtime works on iOS Simulator but without hardware acceleration. Expect ~3-5x slower inference compared to physical devices.

### Android Emulator

ARM-based emulators (M1/M2 Mac) work well. x86 emulators may have compatibility issues with some ONNX operations.
