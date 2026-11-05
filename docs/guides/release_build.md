# Release Build Guide

This guide covers bundle size optimization for production releases.

---

## ONNX Model — Bundle Size Impact

The ONNX embedding model is the single largest contributor to your app's download size:

| Model | ONNX Size | Impact on AAB |
|:------|:---------:|:-------------:|
| all-MiniLM-L6-v2 (INT8) | ~23 MB | Moderate |
| BGE-m3 (INT8) | ~542 MB | **Exceeds Play Store 150 MB limit** |

**Bundle the model in `assets/` in every build, including release builds.** In 0.23.0 there is no supported way to ship without the model in your bundle and download it at runtime.

> **0.23.0: shipping without the bundled model fails.** Up to 0.22.3, you could leave `assets/model.onnx` out of `pubspec.yaml`, download the model to `<app storage directory>/model.onnx` yourself, and call `MobileRag.initialize(modelAsset: 'assets/model.onnx')`: the engine skipped the asset copy because the file already existed. Since 0.23.0, the engine reads the bundled asset on every launch to check that the copy is current, so this setup fails in `MobileRag.initialize` with `Unable to load asset`. If you bundle the model in debug builds and remove it only for release, debug runs keep working and only the release build fails. If your app uses this setup, keep the model in `assets/` when you upgrade to 0.23.0, or stay on 0.22.3. `RagModelPack.asset(...)` also needs the model bundled.

To keep the download size down today, choose a smaller model (see the table above and the [Model Setup Guide](model_setup.md)).

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
