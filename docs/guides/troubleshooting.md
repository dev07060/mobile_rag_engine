# Troubleshooting Guide

Solutions for common issues when using `mobile_rag_engine`.

---

## Install and First Build

### `setup` command or `RagModelPack` not found

**Cause:** Your app resolved 0.20.x. The Model Pack `setup` command and
`RagModelPack` exist only in 0.21.0 and later.

**Solution:** Use `mobile_rag_engine: ^0.22.2`, or stay on 0.20.x and follow
the
[`v0.20.1` README](https://github.com/dev07060/mobile_rag_engine/blob/v0.20.1/README.md#installation),
which downloads the model files manually and initializes with
`tokenizerAsset` + `modelAsset`.

---

### First build fails in Cargokit

0.21.0+ ships signed, pre-compiled native binaries for Android, iOS and macOS.
Cargokit uses them **only when `rustup` is not installed**; with `rustup` on
`PATH` it builds the Rust core from source.

**`Precompiled binaries not available` / download errors (no `rustup`):**
- The first build of each platform downloads the binary from
  `github.com/dev07060/mobile_rag_engine/releases`. Check that the build
  machine (including CI and corporate proxies) can reach `github.com`.
- `Signature verification failed! Ignoring binary.` means the downloaded file
  did not match the package's public key. Retry on a clean network; do not
  bypass the check.
- 0.20.x and earlier never shipped binaries, so they always need Rust. Upgrade
  to `^0.22.2`.

**Errors from `cargo` / `rustup` (Rust installed, source build):**
1. Make sure Rust stable is current: `rustup default stable`. Cargokit adds the
   Rust targets it needs through `rustup`.
2. iOS/macOS: make sure Xcode and its command line tools are installed.
3. Android: make sure the Android SDK `cmdline-tools` (`sdkmanager`) are
   installed so Cargokit can install a missing NDK.
4. Rebuild. The first source build of each platform is slow; later builds
   reuse the cached artifacts.

To skip the source build and use the pre-compiled binary instead, build on a
machine (or `PATH`) without `rustup`.

```bash
flutter clean
flutter pub get
flutter run
```

---

### Windows or Linux build fails

- **Windows x64** is supported from 0.22.0. Install Visual Studio with the
  "Desktop development with C++" workload. Windows on ARM64 is not supported.
- **Linux** is not supported.

---

## Initialization Errors

### "Failed to initialize Rust library"

**Symptom:**
```
RustLibraryException: Failed to initialize native library
```

**Solution:**
1. Run `flutter clean` and rebuild
2. iOS: `cd ios && pod install --repo-update`
3. Android: `./gradlew clean` and rebuild

```bash
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter run
```

---

### "Tokenizer initialization failed"

**Symptom:**
```
Exception: Failed to initialize tokenizer
```

**Causes and Solutions:**

| Cause | Solution |
|:------|:---------|
| Asset path not registered | Add the tokenizer to `pubspec.yaml` assets and pass the same asset path |
| Wrong file format | Must be HuggingFace `tokenizer.json` (not SentencePiece) |
| Corrupted file | Re-download |

```dart
// Correct: use the asset path registered in pubspec.yaml.
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
);

// Wrong: passing a filesystem path as tokenizerAsset.
await MobileRag.initialize(
  tokenizerAsset: '/tmp/tokenizer.json',
  modelAsset: 'assets/model.onnx',
);
```

---

### "Failed to load ONNX model"

**Symptom:**
```
OnnxRuntimeException: Failed to create session
```

**Checklist:**

- [ ] Verify file exists
- [ ] Verify file is ONNX format (not `.bin` or `.safetensors`)
- [ ] Verify file is not corrupted (re-download)
- [ ] Verify model is compatible with ONNX Runtime

```dart
// The engine copies modelAsset to <appDocumentsDirectory>/<basename>.
// Verify the resolved file the engine actually loads.
final dir = await getApplicationDocumentsDirectory();
final file = File('${dir.path}/model.onnx');
if (!await file.exists()) {
  throw Exception('Model file not found at expected path: ${file.path}');
}

// Verify file size (corruption check)
final size = await file.length();
print('Model size: ${size / 1024 / 1024} MB');
```

---

## Runtime Errors

### "Missing Input: token_type_ids"

**Symptom:**
```
Non-zero status code returned while running Gather node.
Missing Input: token_type_ids
```

**Cause:** The ONNX model requires `token_type_ids` as a mandatory input.

**Solution:**
1. Update to a current release. The engine auto-fills zero `token_type_ids` when the model requires them.
2. If the error persists, inspect model input names and confirm required inputs are limited to:
   - `input_ids`
   - `attention_mask`
   - optional `token_type_ids`
3. Models requiring extra mandatory inputs (for example `position_ids`) are not supported yet and should be re-exported to a compatible signature.

---

### "Embedding dimension mismatch"

**Symptom:**
```
StateError: Embedding dimension mismatch: expected 384, got 1024
```

**Cause:** Mixing embeddings from different models (for example after model swap)

**Solution:**
1. Re-embed all stored chunks after changing model
2. Use one of the recovery paths:
   - clear/rebuild flow (fresh vectors)
   - `regenerateAllEmbeddings()` (in-place regeneration)
3. Ensure old and new vectors are not mixed in the same index/database

```dart
// Clear existing data by removing DB file
final dbPath = MobileRag.instance.dbPath;
// ... delete file at dbPath ...
await MobileRag.initialize(...); // Re-initialize

// Advanced recovery: regenerate embeddings in-place.
await MobileRag.instance.engine.regenerateAllEmbeddings();
await MobileRag.instance.engine.rebuildIndex(force: true);
```

---

### "HNSW index corrupted"

**Symptom:**
```
Exception: Failed to search HNSW index
```

**Solution:**
```dart
// Rebuild the index
await MobileRag.instance.rebuildIndex();
```

---

### "PDF requires OCR"

**Symptom:** PDF ingestion fails with a message that the file may be scanned or image-based.

**Cause:** The PDF does not contain enough extractable text for semantic indexing. Mobile RAG Engine does not run OCR internally.

**Solution:** Route the file through your app's OCR flow, then index the recognized text:
```dart
try {
  await MobileRag.instance.addDocumentFromFile(file.path, name: fileName);
} catch (error) {
  if (DocumentParser.isOcrRequiredPdfExtractionError(error)) {
    // Replace this with your app-specific OCR implementation.
    final recognizedText = await runYourAppOcrPipeline(file);
    await MobileRag.instance.addDocument(recognizedText, name: fileName);
  } else {
    rethrow;
  }
}
```

---

### "Out of memory" on large documents

**Symptom:** App crashes when processing large PDFs

**Solutions:**

1. **Use file-path ingest for local files**:
   ```dart
   await MobileRag.instance.addDocumentFromFile(
     file.path,
     name: file.uri.pathSegments.last,
   );
   ```

2. **Limit file size** (50MB recommended):
   ```dart
   final bytes = await file.readAsBytes();
   if (bytes.length > 50 * 1024 * 1024) {
     throw Exception('File too large');
   }
   ```

3. **Use progress callbacks for long ingests**:
   ```dart
   await MobileRag.instance.addDocumentFromFile(
     file.path,
     onProgress: (done, total) => print('Progress: $done/$total'),
   );
   ```

---

## Platform-Specific Issues

### iOS Simulator: Slow Performance

**Cause:** Simulator cannot use Neural Engine

**Solution:** Run performance tests on **physical devices**

| Environment | Expected Performance |
|:------------|:--------------------|
| iPhone 14 (A15) | ~30ms/embedding |
| iOS Simulator | ~150ms/embedding |

---

### Android: NNAPI Errors

**Symptom:**
```
W/onnxruntime: NNAPI execution provider failed
```

**Solution:** This is just a warning. It automatically falls back to CPU. Safe to ignore.

For persistent issues on specific devices, reduce thread count:
```dart
// Limit ONNX threads to reduce CPU/heat
await MobileRag.initialize(
  tokenizerAsset: 'assets/tokenizer.json',
  modelAsset: 'assets/model.onnx',
  embeddingIntraOpNumThreads: 1, // Minimal CPU usage
);
```

---

### macOS: Code Signing Issues

**Symptom:**
```
dyld: Library not loaded: @rpath/libonnxruntime.dylib
```

**Solution:**
1. Enable "Hardened Runtime" in Xcode
2. In `Signing & Capabilities` → Check `Disable Library Validation`

---

## Build Issues

### iOS: Transitive dependencies include statically linked binaries

**Symptom:**
```
[!] The 'Pods-Runner' target has transitive dependencies that include statically linked binaries: (onnxruntime-objc and onnxruntime-c)
```

**Cause:** `mobile_rag_engine` (since 0.19.0) uses `flutter_onnxruntime` which relies on statically linked ONNX Runtime binaries. Flutter's default iOS project uses dynamic frameworks (`use_frameworks!`).

**Solution:** From 0.22.1, run `dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en` again; it applies static linkage and the deployment targets to `ios/` and `macos/`. To change it by hand instead:
1. Open `ios/Podfile` (or `macos/Podfile`)
2. Change `use_frameworks!` to `use_frameworks! :linkage => :static`
3. Run `pod install` again.

The same applies to `The plugin "flutter_onnxruntime" requires a higher minimum iOS deployment version` (or macOS): the host needs iOS 16.0 / macOS 14.0.

---

### Android: release build crashes on the first search

**Symptom:** Debug builds work, but the release APK/AAB aborts during
`MobileRag.initialize()` or the first search with:
```
Pending exception java.lang.ClassNotFoundException: ai.onnxruntime.TensorInfo
```

**Cause:** Flutter release builds shrink the app with R8, which removes ONNX
Runtime classes that its JNI code looks up by name.

**Solution:** Use `mobile_rag_engine` 0.22.2 or later (`rag_engine_flutter` 0.21.1), which ships the keep
rule. On earlier versions, add it to the app yourself:
1. Create `android/app/proguard-rules.pro` with
   `-keep class ai.onnxruntime.** { *; }`
2. In `android/app/build.gradle(.kts)`, inside `buildTypes { release { ... } }`,
   add `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`.

---

### iOS / macOS: release build fails with "Failed to lookup symbol"

**Symptom:** Debug builds work, but an archived app (App Store, TestFlight,
Ad Hoc) or an iOS release build fails in `MobileRag.initialize()` with:
```
Failed to lookup symbol 'frb_get_rust_content_hash': dlsym(RTLD_DEFAULT, frb_get_rust_content_hash): symbol not found
```

**Cause:** With static linkage the Rust library is part of the Runner
executable. Release linking dead-strips the functions Dart looks up by name,
and archiving strips the remaining global symbols.

**Solution:** Use `mobile_rag_engine` 0.22.2 or later (`rag_engine_flutter` 0.21.1), which sets both for the
Runner target. On earlier versions, in Xcode's Runner target build settings:
1. Add `-Wl,-export_dynamic` to **Other Linker Flags** (iOS; macOS already has it).
2. Set **Strip Style** to **Non-Global Symbols** for Release.

---

### iOS: Pod Install Failed

```bash
cd ios
pod deintegrate
pod cache clean --all
pod install --repo-update
```

### Android: NDK Version Mismatch

Check NDK version in `android/app/build.gradle.kts`:
```kotlin
android {
    ndkVersion = flutter.ndkVersion  // or "25.1.8937393"
}
```

---

## Still Having Issues?

1. **Check GitHub Issues**: [github.com/dev07060/mobile_rag_engine/issues](https://github.com/dev07060/mobile_rag_engine/issues)
2. **When creating a new issue**, include:
   - Flutter version (`flutter --version`)
   - Device/OS information
   - Full error message
   - Reproduction code
