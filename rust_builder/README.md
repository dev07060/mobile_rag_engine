# rag_engine_flutter

Native Rust FFI plugin for [mobile_rag_engine](https://github.com/dev07060/mobile_rag_engine).

## Overview

This package provides the native Rust components for the mobile_rag_engine package:

- **High-performance tokenization** using HuggingFace tokenizers
- **HNSW vector indexing** for O(log n) similarity search
- **SQLite integration** for persistent vector storage
- **Semantic text chunking** with Unicode boundary detection

## Installation

This package is automatically included as a dependency of `mobile_rag_engine`. You don't need to add it directly.

```yaml
dependencies:
  mobile_rag_engine:
```

## Requirements

Published versions do not include pre-compiled binaries yet. Cargokit builds
the Rust crate from source during `flutter build`, so you need:

- [Rust toolchain](https://rustup.rs/) (stable, installed with rustup; Cargokit
  adds the required targets)
- Platform-specific build tools (Xcode for iOS/macOS, Android SDK for Android,
  Visual Studio 2022 with "Desktop development with C++" for Windows; Cargokit
  installs a missing NDK with the SDK's `cmdline-tools`)

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| iOS | arm64 | ✅ |
| iOS Simulator | arm64, x86_64 | ✅ |
| macOS | arm64, x86_64 | ✅ |
| Android | arm64-v8a, armeabi-v7a, x86 | ✅ |
| Linux | x86_64 | ❌ Not supported yet |
| Windows | x86_64 | ✅ |

The published package supports iOS, Android, macOS, and Windows (x64). The Linux source config exists in the repository but is excluded from the published archive.

## License

MIT
