# Troubleshooting Guide

Solutions for common issues when using `mobile_rag_engine`.

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
// Verify file exists
final file = File(modelPath);
if (!await file.exists()) {
  throw Exception('Model file not found: $modelPath');
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
