# Troubleshooting Guide

Solutions for common issues when using `mobile_rag_engine`.

---

## Install and First Build

### `setup` command or `RagModelPack` not found

**Cause:** Your app resolved 0.20.x. The Model Pack `setup` command and
`RagModelPack` exist only in 0.21.0 and later.

**Solution:** Use `mobile_rag_engine: ^0.24.0`, or stay on 0.20.x and follow
the
[`v0.20.1` README](https://github.com/dev07060/mobile_rag_engine/blob/v0.20.1/README.md#installation),
which downloads the model files manually and initializes with
`tokenizerAsset` + `modelAsset`.

---

### First build fails in Cargokit

0.21.0+ ships signed, pre-compiled native binaries for Android, iOS and macOS,
and 0.22.0+ also for Windows x64.
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
  to `^0.24.0`.

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

### `flutter build web` fails inside `mobile_rag_engine`

**Symptom:** The app builds for iOS or Android, but `flutter build web` stops
with errors in the package's own files, such as:
```
…/mobile_rag_engine-0.23.0/lib/services/rag_engine.dart:152:14:
Error: The argument type 'int' can't be assigned to the parameter type 'BigInt'.
Error: Compilation failed.
```

**Cause:** Web is not supported. The package's native bindings do not compile
for the web, so any import of `package:mobile_rag_engine` that the web build
can reach breaks it.

**Solution:** Import the package only in code that the web build does not
compile, with a conditional import; see
[Does it support Web?](faq.md#q-does-it-support-web) for the example and for
keeping the model files out of the web build.

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
// The engine copies modelAsset to <app storage directory>/<basename>:
// the application documents directory, or the application support
// directory on Windows (0.22.0 and later).
// Verify the resolved file the engine actually loads.
final dir = Platform.isWindows
    ? await getApplicationSupportDirectory()
    : await getApplicationDocumentsDirectory();
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

### Search fails after changing the model (`embeddingFingerprintMismatch`)

**Symptom:** After the app ships a different embedding model (or a different
export of the same model), `search`, `addDocument` and the other search and
ingest calls throw:
```
RagError.embeddingFingerprintMismatch(field0: model.onnx|384|f32+vabq:none|sha256:e924..., field1: model.onnx|384|f32+vabq:none|sha256:fd68..., field2: 5)
```
`field0` is the model that produced the stored vectors, `field1` is the model
loaded now, and `field2` is the number of chunks still to re-embed.

**Cause:** The stored vectors were produced by another model and cannot be
compared with the new model's query vectors. 0.23.0 and later detect this in
`MobileRag.initialize` from the model file's name, dimension and content hash,
and lock search and ingestion instead of returning wrong results.
`MobileRag.initialize` itself succeeds.

**Solution:** Check the lock after `initialize`, then either keep the
documents or start over.

```dart
final rag = MobileRag.instance;
if (rag.isEmbeddingFingerprintLocked) {
  // Keeps every document. Embeds the stored chunks again with the new model
  // and resumes after an app restart.
  await rag.reembedAll(
    onProgress: (p) => debugPrint('re-embedding ${p.done}/${p.total}'),
  );
}
```

```dart
if (rag.isEmbeddingFingerprintLocked) {
  // Or delete every document, chunk and index, then add the documents again.
  await rag.clearAllData();
}
```

`regenerateAllEmbeddings()` and `rebuildIndex()` do **not** remove the lock.
See
[Data Migration & Re-embedding](../features/index_management.md#3-data-migration--re-embedding)
for `clearAndRestart()`.

Releases before 0.23.0 identify the model by file name and dimension only;
see [Switching an existing database from MiniLM](model_setup.md#4-switching-an-existing-database-from-minilm).

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

### iOS 27: the app exits right after launch

**Symptom:** An app built with Xcode 27 closes as soon as it starts on an
iOS 27 device, before any Dart code runs. The crash report shows
`EXC_BREAKPOINT (SIGTRAP)` in UIKit's
`_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`. With a
debugger attached (`flutter run`, `flutter drive`), the app stops instead and
the tool waits for a Dart VM it never finds.

**Cause:** iOS 27 ends apps that have not adopted the UIScene lifecycle. The
Flutter 3.35 `flutter create` template has no scene manifest in
`ios/Runner/Info.plist`. This is not caused by `mobile_rag_engine`, and
`setup` does not change `Info.plist`.

**Solution:** Add a scene manifest that uses Flutter's `FlutterSceneDelegate`
to `ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
	<key>UIApplicationSupportsMultipleScenes</key>
	<false/>
	<key>UISceneConfigurations</key>
	<dict>
		<key>UIWindowSceneSessionRoleApplication</key>
		<array>
			<dict>
				<key>UISceneClassName</key>
				<string>UIWindowScene</string>
				<key>UISceneConfigurationName</key>
				<string>flutter</string>
				<key>UISceneDelegateClassName</key>
				<string>FlutterSceneDelegate</string>
				<key>UISceneStoryboardFile</key>
				<string>Main</string>
			</dict>
		</array>
	</dict>
</dict>
```

The example app ships this manifest. It was checked with Flutter 3.35.5 and
Xcode 27.1 on an iPhone 17 (iOS 27.0.1), with the template `AppDelegate.swift`
unchanged. If your `Info.plist` already has `UIApplicationSceneManifest` (for
example your own scene delegate), this is not the cause.

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

### Xcode 27: "deployment target ... is set to 9.0, but the range of supported deployment target versions is 15.0 to 27.1.x"

**Symptom:** With Xcode 27, `flutter build ios` (device or `--simulator`)
stops with `Encountered error while building for simulator.` (or for device)
after a list of lines like:
```
Target Integrity (Xcode): The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 9.0, but the range of supported deployment target versions is 15.0 to 27.1.x.
```

**Cause:** Some pods set their own deployment target (9.0 to 13.0), and
Xcode 27 no longer builds targets below 15.0. The `platform :ios, '16.0'`
line that `setup` writes applies to your app, not to each pod.

**Solution:** In `ios/Podfile`, raise every pod to the app's deployment target
in the existing `post_install` block, then run `pod install` again:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0' }
  end
end
```

The example app's `ios/Podfile` does this.

---

### iOS Simulator: "building for iOS Simulator, but linking in object file built for iOS" after switching to static linkage

**Symptom:** The app also uses a plugin that ships separate prebuilt `.a`
libraries for devices and for the simulator. Device builds work, but after
`setup` (or you) switched the Podfile to `use_frameworks! :linkage => :static`,
the simulator build stops at the app's link step:
```
ld: building for 'iOS-simulator', but linking in object file (…/libflac_iOS-device.a[2](bitmath.o)) built for 'iOS'
clang: error: linker command failed with exit code 1
```
Older Xcode versions word it `building for iOS Simulator, but linking in
object file built for iOS`. The example comes from `flutter_soloud` 3.5.4,
whose `ios/libs` has `lib*_iOS-device.a` and `lib*_iOS-simulator.a` for each
audio codec.

**Cause:** The plugin's podspec lists only the device libraries as
`vendored_libraries` and adds the simulator ones through SDK-conditional
linker flags on its own target. With static linkage the plugin becomes part of
the app executable, and CocoaPods adds every vendored library to the app
target's `OTHER_LDFLAGS` (`Pods-Runner.*.xcconfig`) without an SDK condition,
so simulator builds link the device libraries.

**Solution:** Keep static linkage: `mobile_rag_engine` needs it because ONNX
Runtime (through `flutter_onnxruntime`) is a static binary. In `ios/Podfile`,
add this to the existing `post_install` block, after
`flutter_additional_ios_build_settings`. It moves the device libraries from
the app's linker flags into a setting that applies only to device builds, and
links the simulator libraries of the same name for the simulator:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end

  # Link prebuilt *_iOS-device libraries only for devices and their
  # *_iOS-simulator counterparts only for the simulator.
  installer.aggregate_targets.each do |aggregate|
    aggregate.xcconfigs.each do |config_name, config|
      device_libs = config.libraries.select { |lib| lib.end_with?('_iOS-device') }
      next if device_libs.empty?
      device_libs.each { |lib| config.libraries.delete(lib) }
      config.other_linker_flags[:simple] << '$(SDK_VENDORED_LIBS)'
      config.attributes['SDK_VENDORED_LIBS[sdk=iphoneos*]'] =
        device_libs.map { |lib| %(-l"#{lib}") }.join(' ')
      config.attributes['SDK_VENDORED_LIBS[sdk=iphonesimulator*]'] =
        device_libs.map { |lib| %(-l"#{lib.sub('_iOS-device', '_iOS-simulator')}") }.join(' ')
      config.save_as(aggregate.xcconfig_path(config_name))
    end
  end
end
```

Then run `pod install` (or build again). In
`ios/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig`,
`OTHER_LDFLAGS` should no longer contain `-l"…_iOS-device"`, and
`SDK_VENDORED_LIBS[sdk=iphoneos*]` / `SDK_VENDORED_LIBS[sdk=iphonesimulator*]`
should list the two sets.

For another plugin, look at its `ios/*.podspec` and `ios/libs`: if the
library names end in something other than `_iOS-device` / `_iOS-simulator`,
change the two suffixes in the snippet. If the plugin's simulator libraries
are not in a directory that its podspec puts on the library search path, the
link fails with `library '…' not found` instead; ask the plugin to ship an
XCFramework, which carries both builds and needs no workaround.

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

### iOS / macOS: Pod Install Failed

**`pod install` fails on `onnxruntime-objc` after upgrading**

**Symptom:** After you upgrade `mobile_rag_engine` or `flutter_onnxruntime`,
`flutter build` or `pod install` stops with one of:
```
[!] CocoaPods could not find compatible versions for pod "onnxruntime-objc"
[!] CocoaPods's specs repository is too out-of-date to satisfy dependencies.
```

**Cause:** Each `flutter_onnxruntime` release depends on one exact
`onnxruntime-objc` version (1.24.2 in 1.8.0, 1.23.0 in 1.8.1 to 1.8.4, 1.28.0
in 1.9.0). The `Podfile.lock` written before the upgrade still pins the
earlier one.

**Solution:** Update only the two ONNX Runtime pods, once, in each host
directory your app has:
```bash
cd ios && pod update onnxruntime-objc onnxruntime-c && cd ..
cd macos && pod update onnxruntime-objc onnxruntime-c && cd ..
```

**Other `pod install` failures**

```bash
cd ios   # or macos
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
