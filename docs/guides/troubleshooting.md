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
| Wrong file path | Use absolute path |
| Wrong file format | Must be HuggingFace `tokenizer.json` (not SentencePiece) |
| Corrupted file | Re-download |

```dart
// ✅ Correct: absolute path
final dir = await getApplicationDocumentsDirectory();
await initTokenizer(tokenizerPath: '${dir.path}/tokenizer.json');

// ❌ Wrong: relative path
await initTokenizer(tokenizerPath: 'assets/tokenizer.json');
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

### "Embedding dimension mismatch"

**Symptom:**
```
Exception: Vector dimension mismatch (expected 384, got 1024)
```

**Cause:** Mixing embeddings from different models

**Solution:**
1. Delete the database file and restart
2. Or delete all sources manually if you handle DB path:

```dart
// Clear existing data by removing DB file
final dbPath = MobileRag.instance.dbPath;
// ... delete file at dbPath ...
await MobileRag.initialize(...); // Re-initialize
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

1. **Limit file size** (50MB recommended):
   ```dart
   final bytes = await file.readAsBytes();
   if (bytes.length > 50 * 1024 * 1024) {
     throw Exception('File too large');
   }
   ```

2. **Process in chunks**:
   ```dart
   await MobileRag.instance.addDocument(
     text,
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
