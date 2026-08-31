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
`1110a243fdf4706b3f48f1d95db1a4f5529b4d41`. Vector storage is fixed to Q8_0;
it never enables a VABQ profile. Use `--repair` only to replace a file that
fails its SHA-256/length check. VABQ remains an experimental advanced opt-in on
the custom two-asset initialization path.

The first success is adding documents, rebuilding the index, then searching for
non-empty chunks/context. LLM generation is outside this package step.

---

## Advanced / legacy custom ONNX assets

## Model Comparison

| Model | Dimensions | Size (ONNX) | Max Tokens | Languages | Best For |
|:------|:----------:|:-----------:|:----------:|:----------|:---------|
| [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (INT8) | **384** | ~23 MB | 256 | English | English-only apps, lightweight & fast |
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
- Android release builds should keep ONNX Runtime classes in ProGuard/R8 rules.

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
