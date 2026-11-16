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
  // Optional: hybrid search weights, default 0.2 / 0.8. See below.
  // defaultVectorWeight: ...,
  // defaultBm25Weight: ...,
);
```

**Hybrid search weights are your choice.** This section reports what each
weight found and does not pick one for you. Which weight found the most
answers differed between models, languages and document sets, so measure on
your own documents and questions where you can.

The default weights (vector 0.2, BM25 0.8) were set for the English-only
default model. With them, hybrid search (`ask`, `prepareAsk`, `searchHybrid*`,
`RagSearchTool.fromMobileRag`) keeps almost only keyword results whenever the
20 keyword candidates that `ask` looks at are full: a passage found only by
vector search cannot outrank them. Korean keywords are matched as two-syllable
pieces, so on Korean text that list is nearly always full; English lists were
also nearly always full in these tests. With a vector weight above about 0.43 a
vector-only passage can outrank the last keyword candidate, and from about
0.485 its top passage can outrank the fifth. `defaultVectorWeight` / `defaultBm25Weight`
apply to every hybrid search that does not pass its own `vectorWeight` /
`bm25Weight`.

Measured in the `ask` condition (5 passages, 20 candidates per list) with
KoEn-E5-Tiny, profile build on an Apple M3 Pro Mac, 2026-11-14 (questions with
an answer in the top 5):

| Questions | Vector only | 0.2 / 0.8 (default) | 0.5 / 0.5 | 0.6 / 0.4 |
|---|---|---|---|---|
| MIRACL Korean dev, 213 questions, 5,000 passages | 196 | 167 | 182 | 187 |
| Same, 15,000 passages | 176 | 165 | 178 | 181 |
| 32 hand-written questions (13 share no word with the answer) | 28 | 20 | 26 | 27 |
| 80 Wikipedia questions that share words with the answer | – | 72 | 73 | 73 |
| KorQuAD 1.0 dev, 500 questions, 5,000 passages | 454 | 483 | 484 | 477 |
| AutoRAG Korean, 114 questions, 720 documents | 111 | 112 | 112 | 112 |

MIRACL's training split was used to train KoEn-E5-Tiny's base model, so
vector search may look better there than on your documents. On KorQuAD and
AutoRAG, which these models were not trained on, 0.6 / 0.4 lost answers that
keyword search had found (KorQuAD: 12 lost, 6 gained), mostly to other
paragraphs of the same article; 0.5 / 0.5 lost 3 and gained 4. The method and
all numbers, including BGE-m3, are in
[the F2-0 report](../perf/f2-fusion/f2_0_report.md) and
[the Korean validation](../perf/f2-fusion/validation_ko.md). With the
English-only MiniLM, raising the vector weight lost Korean answers in every
test.

English documents, two sets the models were not trained on (biomedical paper
abstracts), same condition and setup:

| Questions | Vector only | 0.2 / 0.8 (default) | 0.5 / 0.5 | 0.6 / 0.4 |
|---|---|---|---|---|
| NFCorpus test, 323 questions, 3,633 documents | 191 | 207 | 214 | 202 |
| SciFact test, 300 claims, 5,183 abstracts | 221 | 219 | 224 | 225 |

Against the default, 0.5 / 0.5 gained 16 and lost 4; 0.6 / 0.4 gained 25 and
lost 24. Details, including MiniLM and BGE-m3, are in
[the English validation](../perf/f2-fusion/validation_en.md).

App-style documents: 56 documents (GNOME Help pages, short app FAQs, release
notes and office policies, two large PDFs) in English and Korean, 90 questions
with an answer, same condition and setup. The questions were drafted in-session
for this test; review verdicts were drafted in-session and confirmed by the
maintainer. Answers in the top 5 at each vector weight
(BM25 weight = 1 − vector weight; 0.0 is BM25 only, 1.0 is vector only):

| KoEn-E5-Tiny | 0.0 | 0.2 (default) | 0.4 | 0.5 | 0.6 | 0.8 | 1.0 |
|---|---|---|---|---|---|---|---|
| English, 45 | 34 | 34 | 35 | 38 | 38 | 38 | 38 |
| Korean, 45 | 30 | 37 | 38 | 42 | 42 | 42 | 41 |

These are measurements, not a choice. Here 0.5 through 0.8 score the same and
vector only is within one; nothing in this test picks 0.5 over the others.
Answers rise between 0.485 and 0.5, where a passage found only by vector search
starts to outrank the fifth keyword-only result. With 45 questions per
language, a difference of one or two is noise. Pick the weights for your own
model, languages and documents, ideally by measuring on your own questions.
The full grid for MiniLM, KoEn-E5-Tiny and BGE-m3 (MiniLM's English stays at
34–38 at every weight; BGE-m3's English keeps rising up to vector only) is in
[the E1 report](../perf/e1-app-docs/README.md). The example app's "App docs"
screen lets you try the weights on the same questions.

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

KoEn-E5-Tiny has 12 layers to MiniLM's 6. Measured on one iPhone 17
(iOS 27.0.1, profile build, 2026-11-16) with the example app, 56 app
documents (about 2,300 chunks) and 120 questions:

| | MiniLM | KoEn-E5-Tiny |
|---|---|---|
| Query embedding, English (median / p95) | 1.5 / 2.0 ms | 2.5 / 3.7 ms |
| Query embedding, Korean (median / p95) | 2.6 / 4.2 ms | 2.5 / 3.6 ms |
| Whole query, embedding + search, top 5 (p95) | 3.5–4.7 ms | 4.7–4.8 ms |
| Ingestion per chunk (`addDocumentFromFile`) | 4.7 ms | 6.4 ms |
| `initialize`, first launch / later launches | 425 / 111 ms | 859 / 160 ms |
| Memory added by `initialize` / peak RSS | 134 / 242 MB | 197 / 314 MB |

Korean queries take the same time with both models: MiniLM splits Korean into
about 2.5 times as many tokens, which cancels out its smaller size. English
queries are about 1.7 times slower with KoEn-E5-Tiny, and ingestion about
1.3 times slower. The first launch includes installing the Model Pack. These
are one device's numbers; conditions and the full results are in
[the M5 report](../perf/multilingual-embedding/README.md#6-iphone-실기기-측정-m5-2026-11-16).
On a desktop CPU (one thread), embedding a chunk took about twice as long
with KoEn-E5-Tiny (55 ms vs 28 ms).

### Keeping the model files out of git

The model and tokenizer are binary files of tens of megabytes. To keep them
out of your repository, commit only `model-pack.json`, which already records
the revision and the SHA-256 of both files, and ignore the two files:

```gitignore
# .gitignore
assets/mobile_rag/model.onnx
assets/mobile_rag/tokenizer.json
```

Then fetch them after cloning and before every build on a clean machine (CI),
with a script that downloads the revision named in the manifest and refuses a
file whose hash differs:

```bash
#!/usr/bin/env bash
# scripts/fetch_rag_model.sh — download the model files at the revision pinned
# in model-pack.json and check them against the manifest's sha256 values.
set -euo pipefail

DIR=assets/mobile_rag
MANIFEST="$DIR/model-pack.json"
REPO=exp-models/dragonkue-KoEn-E5-Tiny-ONNX
MODEL_FILE=onnx/model_qint8_arm64.onnx

field() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" "$MANIFEST"; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

REV=$(field revision)
BASE="https://huggingface.co/$REPO/resolve/$REV"

fetch() { # <remote path> <local file> <manifest sha256 key>
  local want got
  want=$(field "$3")
  if [ -f "$2" ] && [ "$(sha256 "$2")" = "$want" ]; then
    echo "ok (already there) $2"
    return
  fi
  curl -fL --retry 3 -o "$2.part" "$BASE/$1"
  got=$(sha256 "$2.part")
  if [ "$got" != "$want" ]; then
    rm -f "$2.part"
    echo "sha256 mismatch for $2: got $got, $MANIFEST has $want" >&2
    exit 1
  fi
  mv "$2.part" "$2"
  echo "ok $2"
}

fetch "$MODEL_FILE" "$DIR/model.onnx" modelSha256
fetch tokenizer.json "$DIR/tokenizer.json" tokenizerSha256
```

Run it from the project root. A second run downloads nothing while the files
match. On a mismatch it exits with an error and leaves the existing file
alone, so a changed upstream file cannot reach your build; the engine checks
the same hashes again on first launch. `shasum` ships with macOS and most
Linux images; use `sha256sum` where it does not. For another model, change
`REPO` and `MODEL_FILE` and write its manifest as in step 2.

For the MiniLM pack, ignore the same two files and run
`dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en`
instead: it downloads the pinned revision and checks the hashes itself, and
`--check` exits with an error while a file is missing.

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
