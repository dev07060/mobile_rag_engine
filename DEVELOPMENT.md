# Development Guide

This document provides instructions for building, testing, and troubleshooting the `mobile_rag_engine` package.

## Prerequisites
- Flutter SDK
- Rust (stable toolchain)
- Xcode (for macOS/iOS support)
- Android Studio / NDK (for Android support)

## Building the Project
The project uses `flutter_rust_bridge` to connect Dart and Rust.

### Standard Build
When you modify Dart code only:
```bash
flutter run -d macos
```

### Modifying Rust Code
When you modify Rust code (`rust_builder/rust/src/**`), you generally just run:
```bash
flutter run -d macos
```
The build system is configured to detect Rust changes and rebuild the library automatically.

### Code Generation
If you modify `rust_builder/rust/src/api/**` (the FFI boundary), you **MUST** run codegen:
```bash
flutter_rust_bridge_codegen generate
```
This updates the Dart `frb_generated.dart` and Rust `frb_generated.rs` files.

## Release Order

This repository publishes two related packages:

1. `rag_engine_flutter` in `rust_builder/`
2. `mobile_rag_engine` at the repository root

When a change modifies the Rust FFI surface or native runtime behavior, publish them in this order:

```bash
# 1) Validate and publish the native package first
cd rust_builder
flutter pub publish --dry-run

# 2) After rag_engine_flutter is live on pub.dev, update the root dependency
cd ..
flutter pub get
flutter pub publish --dry-run
```

The root package should only bump its `rag_engine_flutter` dependency after the matching native package version is available on pub.dev. This keeps CI and package resolution valid between the two releases.

## Troubleshooting

### Error: "Content hash on Dart side is different from Rust side"
**Reason:** The Dart code expects a specific version of the Rust library, but the loaded binary (`.dylib` or `.framework`) is older and doesn't match. This often happens because Xcode caches the old binary and doesn't realize Rust code has changed.

**Solution 1: Clean build (Recommended)**
Use the provided helper script to strictly clean all native artifacts:
```bash
./scripts/clean_native_build.sh
flutter run -d macos
```

**Solution 2: Manual Clean**
```bash
cd example/macos
rm -rf Pods Podfile.lock Flutter/ephemeral
pod install
cd ../..
flutter run -d macos
```

### Symbol Not Found (e.g. `frb_get_rust_content_hash`)
**Reason:** Similar to above, the binary loaded doesn't contain the symbols expected by Dart.
**Solution:** Follow the **Clean build** steps above.

### Build Script Issues
If the Rust library isn't rebuilding even after cleaning:
1. Check `macos/rag_engine_flutter.podspec` or `ios/rag_engine_flutter.podspec`.
2. Ensure the `script_phase` for "Build Rust library" is not commented out.
3. We have intentionally disabled input/output file checks in the podspec to force the build script to run every time to improve reliability.
