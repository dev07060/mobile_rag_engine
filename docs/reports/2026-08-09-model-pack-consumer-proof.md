# Model Pack consumer proof — blocked at hosted native ABI

**Verdict:** the immutable MiniLM Model Pack installs and verifies in a new
override-free macOS Flutter consumer, and the app builds in profile and release
mode.  The required first search is **not achieved**: the published
`rag_engine_flutter 0.20.0-dev.10` native library does not export the Flutter
Rust Bridge ABI symbol required by this package snapshot.  Consequently
`MODEL_PACK_FIRST_SEARCH_OK` was not printed; no hit or context count exists.

## Scope and environment

- Verified package commit: `86f279a57811b2f4b4696470eae8745ecb1b3964`
  (`fix: constrain flutter rust bridge runtime`).
- The only product change in that commit is the exact
  `flutter_rust_bridge: 2.11.1` pin.  The prior `^2.11.1` constraint resolved
  `2.12.0` in a fresh consumer even though the generated bindings declare
  codegen `2.11.1`.
- Host: macOS 26.5.2 (25F84), arm64; Flutter 3.35.5; Flutter Dart 3.9.2.
  The shell-default `dart` was 3.4.4 and cannot solve the package's `^3.9.2`
  SDK constraint, so setup used Flutter's Dart SDK explicitly.
- Clean snapshot: `/private/tmp/mobile_rag_model_pack_consumer_UZ59R8/mobile_rag_engine_snapshot_86f279a`
- New consumer app: `/private/tmp/mobile_rag_model_pack_consumer_UZ59R8/consumer_app`
- Model binaries and the consumer app remain only in `/private/tmp`; neither is
  copied into this repository.

## Dependency boundary

The consumer `pubspec.yaml` has no `dependency_overrides` block and no
`pubspec_overrides.yaml`.  Its final lockfile resolves:

| Package | Source | Resolved version | Evidence |
| --- | --- | --- | --- |
| `mobile_rag_engine` | path | `0.21.0-dev.10` | `../mobile_rag_engine_snapshot_86f279a` |
| `rag_engine_flutter` | hosted (`https://pub.dev`) | `0.20.0-dev.10` | transitive |
| `flutter_rust_bridge` | hosted (`https://pub.dev`) | `2.11.1` | transitive |

This is deliberately not a fully hosted `mobile_rag_engine` proof: the root
package is a clean, tracked-files-only path snapshot.  It **does** prove that
the native companion resolves as hosted, not as a path dependency.  The
snapshot's own development-only `rag_engine_flutter` override does not cross
the consumer package boundary.

## Model Pack installation

The new consumer ran:

```bash
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --check
```

Actual sentinels were `MODEL_PACK_READY` and then `MODEL_PACK_VERIFIED`.
The installed manifest and independently recomputed files agree:

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `model.onnx` | 23,026,053 | `4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474` |
| `tokenizer.json` | 466,247 | `be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037` |

The manifest is the `stable-minilm-l6-v2-arm64-en` arm64, 384-dimension preset
at revision `1110a243fdf4706b3f48f1d95db1a4f5529b4d41`.  It states
`vectorStorage: Q8_0`; Model Pack v1 has no VABQ profile, so VABQ is inactive.

## Native test attempt and exact blocker

A new minimal `integration_test` initializes
`MobileRag` with `RagModelPack.asset('assets/mobile_rag/model-pack.json')`,
adds `Flutter builds applications from one Dart codebase.`, rebuilds and warms
the index, then searches `What does Flutter build?`.  It asserts non-empty
chunks/context, source evidence in both, and prints
`MODEL_PACK_FIRST_SEARCH_OK hits=<n> context_chars=<n>` only after success.

The requested command was attempted exactly:

```bash
flutter drive --release -d macos \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/model_pack_first_search_test.dart
```

Flutter 3.35.5 refuses it before build: `Flutter Driver (non-web) does not
support running in release mode.`  A `flutter drive --profile` native run was
therefore used only to diagnose the product path; it is not reported as a
release integration success.  `flutter build macos --release` did succeed and
produced `consumer_app.app` (125.0 MB), but it cannot execute the integration
assertions.

The profile runner first exposed the independent broad-constraint failure:

```text
rag_engine_flutter's codegen version (2.11.1) should be the same as runtime version (2.12.0)
```

After the exact `2.11.1` pin, the hosted native library built and launched, but
initialization failed before ingestion/search:

```text
Failed to lookup symbol 'frb_get_rust_content_hash':
dlsym(RTLD_DEFAULT, frb_get_rust_content_hash): symbol not found
```

The hosted package directory was searched for that exported FRB content-hash
symbol and has no match.  No path/native override workaround was used, and no
publish or version bump was attempted.  A compatible hosted
`rag_engine_flutter` release is required before retrying first search.

## macOS consumer onboarding friction

The untouched `flutter create --platforms=macos` app failed CocoaPods because
hosted `flutter_onnxruntime 1.8.3` requires macOS 14.0 while the generated app
targets 10.15.  The temporary consumer therefore needed:

- `platform :osx, '14.0'` and `MACOSX_DEPLOYMENT_TARGET = 14.0`;
- `use_frameworks! :linkage => :static`, because the default dynamic framework
  configuration rejects ONNX Runtime's statically linked transitive binaries.

These are temporary consumer settings, not changes to this package.

## Clean-snapshot regression results

The exact-pin snapshot passed:

- `flutter analyze lib test` — no issues;
- `flutter test test/unit` — 69 tests passed;
- `cd example && flutter test` — 33 tests passed.

For completeness, broad `flutter analyze` also scans vendored Cargokit tooling
whose own package dependencies are not resolved by the root pubspec (77
issues), and broad `flutter test` includes native benchmarks that plain Dart
VM cannot load as a macOS framework (71 passed, 11 failed).  Those commands
are not regressions caused by the exact pin; the package's supported Dart
analysis/unit scope above is clean.

## Reproduction

```bash
# From a tracked-files-only archive of 86f279a...
flutter create --platforms=macos /private/tmp/consumer_app
# Add the snapshot path dependency, integration_test, and assets/mobile_rag/.
flutter pub get
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --check
flutter drive --profile -d macos \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/model_pack_first_search_test.dart
flutter build macos --release
```

Do not substitute the root package's local native override for the hosted
`rag_engine_flutter` dependency when reproducing the blocker.
