# Model Setup Guide

This guide covers the recommended fixed Model Pack plus advanced custom ONNX
assets for `mobile_rag_engine`. The Model Pack is installed during development,
bundled with the app, and never downloaded at runtime.

## Which model

These three models were measured with this package. Each one installs as a
Model Pack in `assets/mobile_rag/`; pick one per app.

| Model | Dimensions | Files to bundle | How to install |
|:------|:----------:|:---------------:|:---------------|
| all-MiniLM-L6-v2 (default) | 384 | about 23 MB | [`setup` command](#recommended-stable-minilm-model-pack), one line |
| KoEn-E5-Tiny, for Korean documents | 384 | about 41 MB | [`setup` command](#korean-documents-koen-e5-tiny), one line |
| BGE-m3 | 1024 | about 586 MB | [download two files and write the manifest](#bge-m3-model-pack) |

On an 80-question English/Korean benchmark, the right passage is in the top 10
for 92.5% of questions with MiniLM, 95% with KoEn-E5-Tiny and 96.25% with
BGE-m3. Results on NFCorpus, SciFact, MIRACL, KorQuAD and AutoRAG, with the
measurement conditions, are in
[Benchmarks](https://github.com/dev07060/mobile_rag_engine/blob/main/docs/benchmarks.md).

All three use the same steps after installing: declare `assets/mobile_rag/` in
`pubspec.yaml` and initialize with
`modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json')`.
Switching an app from one model to another needs the stored chunks to be
embedded again; see
[Switching an existing database](#4-switching-an-existing-database-from-minilm).

## Recommended: stable MiniLM Model Pack

From your Flutter project, run:

```bash
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
```

It verifies the immutable revision and creates these files (it also adjusts
the iOS and macOS host projects; see [ONNX Runtime Notes](#onnx-runtime-notes)):

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

The `stable-minilm-l6-v2-arm64-en` preset is English, arm64,
384-dimensional, Apache-2.0 MiniLM at revision
`1110a243fdf4706b3f48f1d95db1a4f5529b4d41`. For Korean documents, use the
[`koen-e5-tiny-arm64-koen`](#korean-documents-koen-e5-tiny) preset. Vector storage is Q8_0. Use
`--repair` only to replace a file that fails its SHA-256/length check.

The first success is adding documents, then searching for non-empty
chunks/context (searches wait for the pending index update). LLM generation is outside this package step.

---

<a id="korean-koen-e5-tiny"></a>

## Korean documents: KoEn-E5-Tiny

MiniLM is English-only. On Korean retrieval benchmarks it scores close to
random, so Korean apps should swap in a Korean-English model.
[KoEn-E5-Tiny](https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX)
(Apache-2.0) is the one we measured and recommend: it is 384-dimensional like
MiniLM and adds about 18 MB to the app.

| Model | Ko-StrategyQA nDCG@10 | AutoRAG nDCG@10 | ONNX + tokenizer |
|:------|:---:|:---:|:---:|
| all-MiniLM-L6-v2 (default) | 0.014 | 0.059 | 23.5 MB |
| KoEn-E5-Tiny (int8, arm64) | 0.762 | 0.866 | 41.2 MB |

Desktop measurement on 2026-11-02 (Apple M3 Pro, ONNX Runtime CPU), with a
standalone script that follows the engine's tokenizer and mean pooling (no
vector index); whole documents embedded up to 512 tokens (MiniLM with the
earlier character-based limit).

KoEn-E5-Tiny only covers Korean and English. Text in other languages is likely
to be retrieved poorly.

### 1. Install the files

From your Flutter project, run:

```bash
dart run mobile_rag_engine:setup --preset koen-e5-tiny-arm64-koen
```

It downloads the model and tokenizer at the pinned revision
`5cf599a8cd6577f2f12a026130ad50132e472cfd`, checks their SHA-256 and length,
and writes `model.onnx`, `tokenizer.json` and `model-pack.json` to
`assets/mobile_rag/`. Like the MiniLM preset, it also applies the iOS and macOS
host settings. Use `--output` to install somewhere else inside the project.

### 2. Check the files

```bash
dart run mobile_rag_engine:setup --preset koen-e5-tiny-arm64-koen --check
```

The preset writes the same `model-pack.json` that earlier versions of this
guide had you write by hand, so an app set up that way passes `--check` and
needs no change. The engine also checks both files against the manifest on
first launch and fails with a `RagModelPackException` if one differs.

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
KoEn-E5-Tiny, profile build on an Apple M3 Pro Mac, 2026-11-14, before the
Korean keyword changes of 0.24.0 (questions with an answer in the top 5):

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
paragraphs of the same article; 0.5 / 0.5 lost 3 and gained 4. With the
English-only MiniLM, raising the vector weight lost Korean answers in every
test.

English documents, two sets the models were not trained on (biomedical paper
abstracts), same condition and setup:

| Questions | Vector only | 0.2 / 0.8 (default) | 0.5 / 0.5 | 0.6 / 0.4 |
|---|---|---|---|---|
| NFCorpus test, 323 questions, 3,633 documents | 191 | 207 | 214 | 202 |
| SciFact test, 300 claims, 5,183 abstracts | 221 | 219 | 224 | 225 |

Against the default, 0.5 / 0.5 gained 16 and lost 4; 0.6 / 0.4 gained 25 and
lost 24.

App-style documents: 56 documents (GNOME Help pages, short app FAQs, release
notes and office policies, two large PDFs) in English and Korean, 90 questions
with an answer, same condition, `mobile_rag_engine` 0.24.0 code, 2026-11-16.
Answers in the top 5 at each vector weight (BM25 weight = 1 − vector weight;
0.0 is BM25 only, 1.0 is vector only):

| KoEn-E5-Tiny | 0.0 | 0.2 (default) | 0.5 | 0.6 | 1.0 |
|---|---|---|---|---|---|
| English, 45 | 34 | 34 | 38 | 38 | 38 |
| Korean, 45 | 31 | 37 | 43 | 42 | 41 |

These are measurements, not a choice. Here 0.5, 0.6 and vector only are
within two; nothing in this test picks 0.5 over the others.
Answers rise between 0.485 and 0.5, where a passage found only by vector search
starts to outrank the fifth keyword-only result. With 45 questions per
language, a difference of one or two is noise. Pick the weights for your own
model, languages and documents, ideally by measuring on your own questions.
The example app's "App docs"
screen lets you try the weights on the same questions.

You do not need to add `query: ` or `passage: ` prefixes.

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
(iOS 27.0.1, profile build, engine commit `ffb0ab8`, 2026-11-16) with the
example app (hybrid weights 0.2 / 0.8 for MiniLM, 0.5 / 0.5 for KoEn-E5-Tiny), 56 app
documents (about 2,300 chunks) and 120 questions:

| | MiniLM | KoEn-E5-Tiny |
|---|---|---|
| Query embedding, English (median / p95) | 1.5 / 2.0 ms | 2.5 / 3.7 ms |
| Query embedding, Korean (median / p95) | 2.6 / 4.2 ms | 2.5 / 3.6 ms |
| Whole query, embedding + search + reading the chunks, top 5 (p95) | 3.5–4.7 ms | 4.7–4.8 ms |
| Ingestion per chunk (`addDocumentFromFile`) | 4.7 ms | 6.4 ms |
| `initialize`, first launch / later launches | 425 / 111 ms | 859 / 160 ms |
| Memory added by `initialize` / peak RSS | 134 / 242 MB | 197 / 314 MB |

Korean queries take the same time with both models: MiniLM splits Korean into
about 2.5 times as many tokens, which cancels out its smaller size. English
queries are about 1.7 times slower with KoEn-E5-Tiny, and ingestion about
1.3 times slower. The first launch includes installing the Model Pack. These
are one device's numbers.

### Keeping the model files out of git

The model and tokenizer are binary files of tens of megabytes. To keep them
out of your repository, commit only `model-pack.json`, which already records
the revision and the SHA-256 of both files, and ignore the two files:

```gitignore
# .gitignore
assets/mobile_rag/model.onnx
assets/mobile_rag/tokenizer.json
```

Then run the `setup` command after cloning and before every build on a clean
machine (CI):

```bash
dart run mobile_rag_engine:setup --preset koen-e5-tiny-arm64-koen
```

It downloads nothing while the files match the pinned hashes, and fails
without touching an existing file that differs (add `--repair` to replace it),
so a changed upstream file cannot reach your build. `--check` exits with an
error while a file is missing. The same works for the MiniLM preset.

---

<a id="bge-m3-model-pack"></a>

## BGE-m3

[Teradata/bge-m3](https://huggingface.co/Teradata/bge-m3) is the INT8 ONNX
export of BAAI's BGE-m3 (MIT license). It is the largest model measured here:
1024 dimensions, a 569 MB model file and a 17 MB tokenizer. Its vectors take
about 2.7 times the space of the 384-dimensional models, and the app must ship
or download about 586 MB. Use the files below: the tokenizer must come from
the same Teradata revision. The `tokenizer.json` in the `BAAI/bge-m3`
repository is a different file and was not tested.

### 1. Download the files

```bash
mkdir -p assets/mobile_rag && cd assets/mobile_rag

REV=53f8835700d8ff5988f30d529894940d0338ea62
BASE=https://huggingface.co/Teradata/bge-m3/resolve/$REV

curl -L -o model.onnx "$BASE/onnx/model_int8.onnx"
curl -L -o tokenizer.json "$BASE/tokenizer.json"

shasum -a 256 model.onnx tokenizer.json
cd -
# fc4692db47a783252a0dba2d5601a3b9ab0c5058186eced9b963bb0e112f011a  model.onnx
# 249df0778f236f6ece390de0de746838ef25b9d6954b68c2ee71249e0a9d8fd4  tokenizer.json
```

### 2. Write the Model Pack manifest

Save as `assets/mobile_rag/model-pack.json`:

```json
{
  "schemaVersion": 1,
  "preset": "bge-m3-int8",
  "modelId": "Teradata/bge-m3",
  "revision": "53f8835700d8ff5988f30d529894940d0338ea62",
  "modelAsset": "assets/mobile_rag/model.onnx",
  "tokenizerAsset": "assets/mobile_rag/tokenizer.json",
  "modelSha256": "fc4692db47a783252a0dba2d5601a3b9ab0c5058186eced9b963bb0e112f011a",
  "tokenizerSha256": "249df0778f236f6ece390de0de746838ef25b9d6954b68c2ee71249e0a9d8fd4",
  "modelBytes": 568921578,
  "tokenizerBytes": 17082799,
  "architecture": "arm64",
  "embeddingDimension": 1024,
  "license": "mit",
  "language": "see the model card"
}
```

`architecture` must be `"arm64"`, the only value Model Pack v1 accepts. The
same files are used on every supported platform.

### 3. Bundle and initialize

Declare `assets/mobile_rag/` in `pubspec.yaml` and initialize as for
KoEn-E5-Tiny:

```dart
await MobileRag.initialize(
  modelPack: const RagModelPack.asset('assets/mobile_rag/model-pack.json'),
);
```

On first launch the engine loads both files (about 586 MB) into memory to hash
and copy them, so the first `initialize` takes noticeably longer than with the
smaller models. This was checked only on a Mac, not on a phone.

This manifest and these files were run through `MobileRag.initialize` on
2026-11-16 (`mobile_rag_engine` 0.24.0 code, profile build, Apple M3 Pro Mac,
macOS 27.2.1): the pack was checked and copied, 4492 chunks were indexed, and
the 80 Wikipedia questions gave `passage_recall@10` 0.9625 with default hybrid
search.

### Shipping it without bundling

To keep 586 MB out of the app download, download the same two files at
runtime, check their SHA-256 values as above, and pass the paths instead of a
Model Pack:

```dart
await MobileRag.initialize(
  tokenizerPath: '${support.path}/bge-m3/tokenizer.json',
  modelPath: '${support.path}/bge-m3/model.onnx',
);
```

The [Release Build guide](release_build.md) shows the download flow (use the
BGE-m3 URLs and hashes above). To keep
the files out of git, use the fetch script in
[Keeping the model files out of git](#keeping-the-model-files-out-of-git) with
`REPO=Teradata/bge-m3` and `MODEL_FILE=onnx/model_int8.onnx`.

---

## Advanced / legacy custom ONNX assets

The sections below pass the files directly with `tokenizerAsset` / `modelAsset`
or `tokenizerPath` / `modelPath` instead of a Model Pack.

### Model Comparison

| Model | Dimensions | Size (ONNX) | Model max tokens | Best For |
|:------|:----------:|:-----------:|:----------:|:---------|
| [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (INT8) | **384** | ~23 MB | 256 | English documents, smallest |
| [KoEn-E5-Tiny](https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX) (INT8) | **384** | ~38 MB | 512 | Korean documents ([recipe](#korean-documents-koen-e5-tiny)) |
| [Teradata/bge-m3](https://huggingface.co/Teradata/bge-m3) (INT8) | **1024** | ~569 MB | 8,192 | Apps that can ship a 569 MB model ([recipe](#bge-m3-model-pack)) |

> **Dimension Matters**: The embedding dimension affects your vector index. Once you choose a model, all documents must use the same dimension. Switching models requires re-embedding all documents.

### Validated ONNX Artifacts

- MiniLM: `https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/onnx/model_qint8_arm64.onnx`
- KoEn-E5-Tiny: `https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX/resolve/5cf599a8cd6577f2f12a026130ad50132e472cfd/onnx/model_qint8_arm64.onnx`
- BGE-m3: `https://huggingface.co/Teradata/bge-m3/resolve/53f8835700d8ff5988f30d529894940d0338ea62/onnx/model_int8.onnx` (tokenizer from the same revision)

The engine cuts every input at 512 tokens, whatever the model's own limit.

Models that need `token_type_ids` work without re-export: the engine reads the
ONNX input names and passes zero `token_type_ids` only when the model requires
them. Models outside this list are best-effort.

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

### BGE-m3

```bash
mkdir -p assets && cd assets

# Download INT8 quantized model (~569MB) and its tokenizer (~17MB), same revision
curl -L -o model.onnx "https://huggingface.co/Teradata/bge-m3/resolve/53f8835700d8ff5988f30d529894940d0338ea62/onnx/model_int8.onnx"
curl -L -o tokenizer.json "https://huggingface.co/Teradata/bge-m3/resolve/53f8835700d8ff5988f30d529894940d0338ea62/tokenizer.json"
```

---

## Production Deployment Strategies

### Strategy 1: Bundle with App (Recommended for <100MB)

Include model files in your app bundle. Simple and works offline immediately.

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/mobile_rag/   # Model Pack
    # - assets/            # files from "Download Instructions" above
```

**Pros:**
- Works immediately after install
- No network dependency
- Consistent performance

**Cons:**
- Increases app download size
- App store size limits (see [Google Play app size limits](https://support.google.com/googleplay/android-developer/answer/9859372))

### Strategy 2: Download at runtime

Download the model and tokenizer on first launch, check their SHA-256 values,
and pass `tokenizerPath` / `modelPath` to `MobileRag.initialize`. See the
[Release Build guide](release_build.md).

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
2. `addDocument*` already embeds in a worker isolate, so ingestion does not block the UI.

---

## Troubleshooting

Model loading and tokenizer errors are covered in [Troubleshooting](troubleshooting.md#initialization-errors).

### iOS Simulator Limitations

Performance in the simulator differs from a device; measure on a physical device.

### Android Emulator

ARM-based emulators (M1/M2 Mac) work well. x86 emulators may have compatibility issues with some ONNX operations.
