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

### Pre-compiled binaries (default, 0.20.0+)

Signed binaries for every supported target are published to this repository's
GitHub releases. When the build machine has no `rustup`, Cargokit downloads the
binary for the target, verifies its signature against the public key in
`rust/cargokit.yaml`, and links it. No Rust toolchain is needed; the first
build of each platform needs access to `github.com`.

Versions before 0.20.0 did not ship binaries and always build from source.

### Building from source

If `rustup` is installed, Cargokit builds from source instead of downloading.
That needs:

- [Rust toolchain](https://rustup.rs/) (stable)
- Platform-specific build tools (Xcode for iOS/macOS, Android SDK with
  `cmdline-tools` for Android; Cargokit installs a missing NDK)

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| iOS | arm64 | ✅ |
| iOS Simulator | arm64, x86_64 | ✅ |
| macOS | arm64, x86_64 | ✅ |
| Android | arm64-v8a, armeabi-v7a, x86_64, x86 | ✅ |
| Windows | x86_64 | ✅ (0.21.0+) |

Linux and Windows on ARM64 are not supported.

## License

MIT
