# Hosted companion publish and macOS consumer proof — `rag_engine_flutter 0.20.0-dev.11`

## Verdict

**Success.** `rag_engine_flutter 0.20.0-dev.11` was published to pub.dev from
a tracked-files-only archive of source commit
`724408d04de8863ef0eb1d09365487a0390a57fb`.  A completely new macOS Flutter
consumer then resolved that companion from hosted pub.dev (not a path override),
initialized the Q8_0 MiniLM Model Pack, completed its first source-grounded
search, and built a release macOS Runner that exports the required FRB symbols.

This evidence does **not** prove a fully hosted `mobile_rag_engine` root package:
the root was deliberately used as a clean path snapshot.  It proves the hosted
native companion boundary only.

## Scope and immutable inputs

- Source checkout at start: `feats/adopt-canonical-generated-dev11`, HEAD
  `724408d04de8863ef0eb1d09365487a0390a57fb`.
- Evidence branch: `feats/publish-companion-dev11-final`.
- Publication and all validation inputs: `/private/tmp/mobile-rag-hosted-companion-dev11-clean`, created by
  `git archive HEAD`; no dirty tracked or untracked workspace file was used.
- Snapshot contract: companion version `0.20.0-dev.11`; root exact
  `rag_engine_flutter: 0.20.0-dev.11` and
  `flutter_rust_bridge: 2.11.1`; generated content hash `-941343322`;
  `loaded_hnsw_node_count` dispatcher ID `102`.
- The pre-publish API check returned latest version `0.19.2` and confirmed that
  `0.20.0-dev.11` was absent.

## Publish record

The final snapshot command was:

```bash
cd /private/tmp/mobile-rag-hosted-companion-dev11-clean/rust_builder
flutter pub publish --force
```

- Start: `2026-08-10T14:03:55Z`
- Finish: `2026-08-10T14:04:00Z`
- Exit: `0`
- Server result: `Successfully uploaded https://pub.dev/packages/rag_engine_flutter version 0.20.0-dev.11`.
- Final dry-run: exit `0`, compressed archive `234 KB`, package warnings `0`,
  package errors `0`.

The post-publish official version endpoint returned `200` at
`2026-08-10T14:04:10Z` with:

| Field | Value |
| --- | --- |
| Version | `0.20.0-dev.11` |
| Published | `2026-08-10T14:03:59.036903Z` |
| Archive | `https://pub.dev/api/archives/rag_engine_flutter-0.20.0-dev.11.tar.gz` |
| SHA-256 | `a76a54423aedbe4940bb823b25f0c0c43feb1c543035edc14e0042707c06698b` |
| Hosted metadata | package name/version and macOS ffiPlugin declaration match the snapshot |

The first fresh consumer `flutter pub get` began during propagation and could
not initially see the version.  The second bounded attempt at
`2026-08-10T14:06:02Z` succeeded without any override.

## Fresh override-free consumer

Consumer: `/private/tmp/mobile-rag-hosted-companion-dev11-consumer`.
It was created with `flutter create --platforms=macos`; it has neither a
`dependency_overrides` block nor `pubspec_overrides.yaml`.  Its only local
package input is the clean root path snapshot:

```yaml
mobile_rag_engine:
  path: /private/tmp/mobile-rag-hosted-companion-dev11-clean
```

Its lockfile mechanically resolves:

| Package | Source | Version |
| --- | --- | --- |
| `mobile_rag_engine` | path clean snapshot | `0.21.0-dev.10` |
| `rag_engine_flutter` | hosted `https://pub.dev` | `0.20.0-dev.11` |
| `flutter_rust_bridge` | hosted `https://pub.dev` | `2.11.1` |

The lockfile's companion SHA-256 is identical to the official archive SHA-256
above.  The root snapshot's development override does not cross the consumer
package boundary.

## Model Pack and runtime proof

The consumer used the documented public default only; VABQ was not enabled:

```bash
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart run mobile_rag_engine:setup \
  --preset stable-minilm-l6-v2-arm64-en
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart run mobile_rag_engine:setup \
  --preset stable-minilm-l6-v2-arm64-en --check
```

The commands printed `MODEL_PACK_READY` then `MODEL_PACK_VERIFIED`.
The resulting manifest is Q8_0 and the installed assets verify as:

| Asset | SHA-256 |
| --- | --- |
| `model.onnx` | `4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474` |
| `tokenizer.json` | `be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037` |
| `model-pack.json` | `89f2bbf47e02d48f68c69149e41bed2193833a576916878b2f21f306e1f77c74` |

Flutter Driver does not support non-web release execution; its direct
`flutter drive --release -d macos` attempt exited `1` with that message.  The
actual native runtime test therefore ran in profile mode:

```bash
flutter drive --profile -d macos \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/model_pack_first_search_test.dart
```

It initialized `MobileRag` from the Model Pack, added `Flutter builds
applications from one Dart codebase.`, rebuilt/warmed the index, searched
`What does Flutter build?`, and asserted non-empty chunks, context, and source
content.  The profile run logged ONNX setup, native connection-pool
initialization, and:

```text
MODEL_PACK_HOSTED_FIRST_SEARCH_OK hits=1 context_chars=107
All tests passed.
```

This successful profile initialization is the runtime proof that the FRB
process lookup/bridge initialization worked with the hosted companion.

## Release build and exported symbols

`flutter build macos --release` succeeded and produced a `181.7MB` universal
arm64/x86_64 app at:

```text
build/macos/Build/Products/Release/mobile_rag_hosted_companion_dev11_consumer.app
```

The final Runner executable was checked with `nm -gU`.  It exports
`_frb_get_rust_content_hash` (count `1`) and representative
`_frbgen_mobile_rag_engine_rust_arc_*` bridge symbols (count `4`).

## Minimal macOS consumer setup

The fresh consumer needed only the normal ONNX-runtime/macOS integration
settings:

- `platform :osx, '14.0'` and `MACOSX_DEPLOYMENT_TARGET = 14.0`;
- `use_frameworks! :linkage => :static` in its Podfile.

No consumer-specific native symbol or linker workaround was added.  The
published plugin podspec supplies the native linkage configuration.

## Non-actions and workspace preservation

Only `rag_engine_flutter 0.20.0-dev.11` was published.  This session did not
publish the root package, push, create or merge a PR, create a tag, or yank a
version.  Existing user-owned dirty tracked/untracked files were not formatted,
modified, staged, or committed; their starting unstaged diff SHA-256 was
`9a1424c2780e45ca32d815411fd16ef0722e9a056ea61414bd3c43188b62bde4` and
their starting porcelain-status SHA-256 was
`86f5f4e5e5706b0abf6ab3a2883724ad32bf332afb2fd18c5015efb88f41cca9`.

The next decision is whether to release/publish the root package.  Any actual
root publication and any PR merge each require separate explicit approval.
