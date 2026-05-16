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

### For development (building from source)

If prebuilt binaries are not available for your platform, you need:

- [Rust toolchain](https://rustup.rs/) (stable)
- Platform-specific build tools (Xcode for iOS/macOS, Android NDK for Android)

### For users (with prebuilt binaries)

No additional requirements - binaries are downloaded automatically.

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| iOS | arm64 | ✅ |
| iOS Simulator | arm64, x86_64 | ✅ |
| macOS | arm64, x86_64 | ✅ |
| Android | arm64-v8a, armeabi-v7a, x86 | ✅ |
| Linux | x86_64 | 🚧 Coming soon |
| Windows | x86_64 | 🚧 Coming soon |

The published package is intended for iOS, Android, and macOS consumers today. Linux and Windows source configs may exist in the repository while support is being prepared, but they are not part of the supported prebuilt-binary surface yet.

## License

MIT
