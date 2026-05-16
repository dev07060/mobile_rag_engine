# Release Build Guide

This guide covers bundle size optimization for production releases.

---

## ONNX Model — Bundle Size Impact

The ONNX embedding model is the single largest contributor to your app's download size:

| Model | ONNX Size | Impact on AAB |
|:------|:---------:|:-------------:|
| all-MiniLM-L6-v2 (INT8) | ~23 MB | Moderate |
| BGE-m3 (INT8) | ~542 MB | **Exceeds Play Store 150 MB limit** |

**For development**, bundle the model in `assets/` for quick iteration.
**For production releases**, download the model at runtime to keep your bundle small.

`MobileRag.initialize` only accepts asset paths today (`tokenizerAsset`, `modelAsset`), but the engine resolves `modelAsset` to `<appDocumentsDirectory>/<basename>` and skips the asset copy if that file already exists. You can use this to ship without the model in your bundle:

```dart
// 1. Before initialize, write the downloaded model to the destination filename
//    used by MobileRag (matches the basename of modelAsset).
final dir = await getApplicationDocumentsDirectory();
final modelFile = File('${dir.path}/model.onnx');
if (!await modelFile.exists()) {
  await downloadModel(modelFile); // your CDN / Hugging Face fetch
}

// 2. Initialize as usual. The asset copy is skipped because the file exists.
//    Do NOT list assets/model.onnx in pubspec.yaml when shipping this flow.
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json', // small (~750KB), safe to bundle
  modelAsset: 'assets/model.onnx',         // basename only is significant here
);
```

> See [Model Setup Guide — Production Deployment Strategies](model_setup.md#production-deployment-strategies) for complete examples including download-on-first-launch and hybrid approaches.

---

## Native Library Sizes

The following are bundled automatically and cannot be removed:

| Library | Per-arch Size (compressed) | Source |
|:--------|:--------------------------:|:-------|
| `librag_engine_flutter.so` | ~6 MiB | Rust core (this package) |
| `libflutter.so` | ~5 MiB | Flutter engine |
| `libonnxruntime.so` | ~3 MiB | ONNX Runtime |
| `libpdfium.so` | ~2 MiB | pdfrx (if used) |

---

## pdfrx Users

This package does not require `pdfrx`. If your app also uses [`pdfrx`](https://pub.dev/packages/pdfrx) for PDF rendering, it bundles a `pdfium.wasm` file (~2 MB) intended for web builds. This is unnecessary in native release builds.

Remove it before building:

```bash
dart run pdfrx:remove_wasm_modules
flutter build appbundle --release
```

> See [pdfrx release build docs](https://github.com/espresso3389/pdfrx/tree/master/packages/pdfrx#note-for-building-release-builds) for details.

---

## Bundle Verification

After building, inspect your AAB to confirm prohibited files are absent:

```bash
# List contents and check for large unexpected files
unzip -l build/app/outputs/bundle/release/app-release.aab | grep -E "model\.onnx|pdfium\.wasm|\.DS_Store"
```

If nothing is printed, your bundle is clean.

---

## Summary Checklist

- [ ] ONNX model is **not** listed in `pubspec.yaml` assets (use runtime download)
- [ ] `tokenizer.json` is listed in `pubspec.yaml` assets (small, safe to bundle)
- [ ] `dart run pdfrx:remove_wasm_modules` run before release build (if using pdfrx)
- [ ] AAB does not contain `model.onnx`, `pdfium.wasm`, or `.DS_Store`
