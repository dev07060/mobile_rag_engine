# Mimalloc Allocator A/B Runbook

This runbook validates whether `allocator_mimalloc` should remain feature-gated,
become a default-enable candidate, or be dropped.

## Principle

Compare two builds from the same instrumentation commit:

- System allocator: native Rust features without `allocator_mimalloc`.
- Mimalloc: same features plus `allocator_mimalloc`.

Do not compare `main` against an instrumented branch. The allocator feature must
be the only intended difference between the two measured variants.

## Scope

`#[global_allocator]` affects Rust global allocations in this native crate and
Rust dependencies. It does not replace Dart VM, Flutter engine, ONNX Runtime,
SQLite C pager/cache, OS file cache, or arbitrary C/C++ allocators.

RSS metrics are full-process directional evidence only.

## Required Variants

System allocator expected values:

```bash
--dart-define=EXPECTED_NATIVE_ALLOCATOR=system
--dart-define=EXPECTED_RUST_FEATURES=vector_faer,vector_quant_i8
```

Mimalloc expected values:

```bash
--dart-define=EXPECTED_NATIVE_ALLOCATOR=mimalloc
--dart-define=EXPECTED_RUST_FEATURES=vector_faer,vector_quant_i8,allocator_mimalloc
```

## Measurement Commands

Query profile:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/query_profile_measure_test.dart \
  --profile -d <device-id> \
  --dart-define=EXPECTED_NATIVE_ALLOCATOR=<system|mimalloc> \
  --dart-define=EXPECTED_RUST_FEATURES=<exact-feature-list>
```

Allocator-sensitive indexing macro:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/allocator_indexing_measure_test.dart \
  --profile -d <device-id> \
  --dart-define=EXPECTED_NATIVE_ALLOCATOR=<system|mimalloc> \
  --dart-define=EXPECTED_RUST_FEATURES=<exact-feature-list> \
  --dart-define=ALLOCATOR_INDEXING_TEXT_MB=5,10,25
```

`ALLOCATOR_INDEXING_TEXT_MB` controls generated text scale in decimal MB. The
current macro uses 500-char chunks, 30-char overlap metadata, and 384-dim stub
embeddings. A 5/10/25 MB run maps to 10k/20k/50k generated chunks.

Android arm64 build smoke:

```bash
flutter build apk --profile --target-platform android-arm64
```

## Run Order

Use paired, counterbalanced runs on the same physical device and OS:

```text
system, mimalloc, system, mimalloc, system, mimalloc
```

Collect at least three valid runs per variant.

## Required Evidence

- Device model, OS version, battery/thermal state.
- Git SHA and native artifact hash.
- APK/app/framework size.
- `native_allocator` and exact `rust_features`.
- Query profile CSV/JSON exports.
- `INDEXING_PROFILE` log rows. In older run artifacts, treat the `docs` field
  as chunk/vector-point count, not source-document count.
- Crash, test failure, or FRB content-hash mismatch notes.

## Decision Threshold

`DEFAULT_ENABLE_CANDIDATE` requires all of the following:

- Android physical-device and iOS physical-device profile runs complete.
- No crash, no FRB content-hash mismatch, no test regression.
- At least one allocator-sensitive win:
  - activation p50 improves by at least 10%, or
  - large indexing/reindexing macro time improves by at least 10%, or
  - peak RSS improves by at least 8%.
- Warm `search` and `hydrate` p95 do not regress by more than 5%.
- Binary size delta is acceptable for the package release.

If results are noise-level, keep the feature gate but do not default-enable
mimalloc.
