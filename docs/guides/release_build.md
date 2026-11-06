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
**For production releases**, you can download the model at runtime to keep your bundle small. How depends on the version:

- **Releases after 0.23.0:** download the model and tokenizer to files of your choice, then pass their paths. Nothing is copied from assets, and the model does not need to be in `pubspec.yaml`.

  ```dart
  final support = await getApplicationSupportDirectory();
  final dir = await Directory('${support.path}/models').create(recursive: true);
  final tokenizerFile = File('${dir.path}/tokenizer.json');
  final modelFile = File('${dir.path}/model.onnx');

  for (final (file, url) in [(tokenizerFile, tokenizerUrl), (modelFile, modelUrl)]) {
    if (!await file.exists()) {
      // Download to a temporary file and rename it, so an interrupted
      // download never leaves a partial file at the path the engine loads.
      final partial = File('${file.path}.part');
      await download(url, partial); // your CDN / Hugging Face fetch
      await partial.rename(file.path);
    }
  }

  await MobileRag.initialize(
    tokenizerPath: tokenizerFile.path,
    modelPath: modelFile.path,
  );
  ```

  Check the downloaded files against a checksum you ship with the app before the rename; the engine loads whatever is at these paths.

  Any change to the model file's name or content locks search until `reembedAll()` or `clearAndRestart()`, because the embedding fingerprint includes the file name and a hash of the file. Re-embedding is needed even for an update of the same model, such as a re-quantized export.

- **0.23.0: shipping without the bundled model fails.** Bundle the model in every build, or stay on 0.22.3. Up to 0.22.3, you could leave `assets/model.onnx` out of `pubspec.yaml`, download the model to `<app storage directory>/model.onnx` yourself (the application documents directory, or the application support directory on Windows), and call `MobileRag.initialize(modelAsset: 'assets/model.onnx')`: the engine skipped the asset copy because the file already existed. 0.23.0 reads the bundled asset on every launch to check that the copy is current, so this setup fails in `MobileRag.initialize` with `Unable to load asset`. If you bundle the model in debug builds and remove it only for release, debug runs keep working and only the release build fails. Releases after 0.23.0 accept this setup again, but new code should pass `tokenizerPath`/`modelPath`. `RagModelPack.asset(...)` always needs the model bundled.

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
