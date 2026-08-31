# Root `0.21.0-dev.11` release qualification

Date: 2026-08-31 (Asia/Seoul)

## Verdict

`mobile_rag_engine 0.21.0-dev.11` passed the tracked-only functional and fresh
consumer qualification boundary. The candidate resolves the native companion
and Flutter Rust Bridge from hosted pub.dev, reproduces canonical generated
outputs, passes the Flutter and Rust suites, completes a source-grounded first
search in a fresh macOS consumer, and builds a universal release app with the
required FRB exports.

The root package is **not yet fully hosted proof**. This qualification uses the
root as a clean path package and keeps `rag_engine_flutter` and
`flutter_rust_bridge` hosted. A fully hosted root proof can happen only after
explicitly approved publication.

The non-force publish dry-run found zero validation errors but returned exit
`65` because pub treats the two deliberately exact dependency constraints as
warnings. Loosening those pins would violate the release contract, so the
warnings are retained. No `--force` or actual publication was attempted. Any
approved publication must therefore acknowledge these two warnings and use
`--force` from the frozen clean source.

## Frozen source and preservation boundary

- Branch: `feats/root-dev11-onboarding-release`
- Qualified source commit: `1f55d3f` (`chore(release): prepare root 0.21.0-dev.11`)
- Preceding documentation commit: `442eccb`
  (`docs(onboarding): align model pack quick start`)
- Source archive:
  `/private/tmp/mobile-rag-root-dev11-qualification.FpECJq/source.tar`
- `git archive HEAD` SHA-256:
  `32912e17eecc09b5da232d103f5c1bebd8c10bc9aa0ef8d756471f71ab11241e`
- Source tar size: `11,950,080` bytes
- The archive contains tracked files only and has no `.git`,
  `dependency_overrides` in the root pubspec, or `pubspec_overrides.yaml`.

All generation, validation, packaging, and consumer inputs came from separate
extractions of that archive under `/private/tmp`. The dirty checkout was not a
build, generation, test, dry-run, or consumer input.

At task start the checkout contained 26 user-owned modified tracked files and
24 user-owned untracked files. Their unstaged binary diff SHA-256 remained
`9a1424c2780e45ca32d815411fd16ef0722e9a056ea61414bd3c43188b62bde4`
after the release qualification. They were not overwritten, formatted,
stashed, reset, checked out, staged, or committed.

## Version and dependency contract

The official exact-version endpoint
`https://pub.dev/api/packages/mobile_rag_engine/versions/0.21.0-dev.11`
returned HTTP `404` at `2026-08-31T00:37:27Z` with
`Could not find version "0.21.0-dev.11"`. Recheck immediately before any
approved publication.

Clean `flutter pub get` completed with exit `0`. The root lockfile was
byte-for-byte unchanged and mechanically resolved:

| Package | Source | Version | Archive SHA-256 |
| --- | --- | --- | --- |
| `rag_engine_flutter` | hosted pub.dev | `0.20.0-dev.11` | `a76a54423aedbe4940bb823b25f0c0c43feb1c543035edc14e0042707c06698b` |
| `flutter_rust_bridge` | hosted pub.dev | `2.11.1` | `37ef40bc6f863652e865f0b2563ea07f0d3c58d8efad803cc01933a4b2ee067e` |

The root package does not appear in its own lockfile; its version/source was
verified in the fresh consumer lock below.

## Toolchain and canonical generation

- Flutter `3.35.5`
- Dart `3.9.2`
- `flutter_rust_bridge_codegen 2.11.1`
- Freezed `3.2.4`
- build_runner `2.10.5`
- rustc/cargo `1.91.1`

The clean snapshot ran:

```bash
flutter pub get
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
flutter pub run build_runner build --delete-conflicting-outputs
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart format lib/src/rust
```

All 18 adopted generated outputs and the four core FRB outputs were
byte-for-byte identical to the frozen archive. The four core hashes were:

| File | SHA-256 |
| --- | --- |
| `lib/src/rust/frb_generated.dart` | `cd2336044a5c3dd58e0d8a42587d7314791554140805d999453a67c09ef0af12` |
| `lib/src/rust/frb_generated.io.dart` | `a02958fb27c017cc6e949d95e62b186037de3e40c79564d26a0c19fc3fdbd48b` |
| `lib/src/rust/frb_generated.web.dart` | `62bb418c4db9f8a5e22c0a2ee20ff9ad3263f1b43b0e89455b0ee39c67c310a4` |
| `rust_builder/rust/src/frb_generated.rs` | `b6ffa3f452904adc49c4653495bbfc95d8acb43aaad469494fff13c30351d987` |

Dart and Rust both retained content hash `-941343322`;
`loaded_hnsw_node_count` remained Rust dispatcher ID `102`. The only other
tracked-file change created by dependency resolution was the temporary
`example/pubspec.lock` refresh (root path version dev.10 to dev.11 and the
previously stale `crypto 3.0.7` transitive entry). It was not adopted.

## Test results

| Gate | Result |
| --- | --- |
| `flutter analyze lib test` | exit `0`; no issues |
| `flutter test test/unit` | `69` passed, `0` failed |
| focused Source RAG tests | `9` passed, `0` failed |
| `example/` `flutter test test` | `33` passed, `0` failed |
| serial shipped-feature Rust suite | lib `185` passed / `10` ignored; doctest `1` passed / `1` ignored; `0` failed |

The focused Source RAG gate reran
`source_rag_search_regression_test.dart` and
`source_rag_ingestion_decision_test.dart`. The example suite emitted the known
nine diagnostics for corpus/eval asset directories excluded from the archive;
the command still passed. Its tracked example override means it is local
companion source-compatibility evidence, not hosted-companion evidence.

The exact Rust command was:

```bash
cargo test \
  --manifest-path rust_builder/rust/Cargo.toml \
  --features 'vector_faer,vector_quant_i8' \
  -- \
  --test-threads=1
```

It completed with errors `0`. Cargo displayed four lib warnings and five
lib-test warnings (three duplicates); no warning was promoted to an error.

## Root publish dry-run

From a separate clean extraction:

```bash
flutter pub publish --dry-run
```

- Included files: `212`
- Reported compressed archive size: `2 MB` (pub's rounded display)
- Validation errors: `0`
- Validation warnings: `2`
- Command exit: `65`
- Log SHA-256:
  `3801c3019c2c31b9558a9be21373a12702e98f0617a148f5ed6e00d3355fad46`
- Retained log:
  `/private/tmp/mobile-rag-root-dev11-qualification.FpECJq/root-publish-dry-run.log`

Both warnings ask the package to allow more than one dependency version:

1. change exact `flutter_rust_bridge: 2.11.1` to `^2.11.1`;
2. change exact `rag_engine_flutter: 0.20.0-dev.11` to
   `^0.20.0-dev.11`.

Those suggestions were not applied because exact native/FRB alignment is an
explicit release requirement. The final wrapper message was
`Failed to update packages.` / `Package has 2 warnings.` No `--force` was run.

## Fresh macOS clean-root consumer

Consumer:
`/private/tmp/mobile-rag-root-dev11-qualification.FpECJq/consumer`

The app was created with `flutter create --platforms=macos`. It had no
`dependency_overrides` and no `pubspec_overrides.yaml`. Its only path package
was the root extracted from the frozen source tar. The lockfile mechanically
resolved:

| Package | Source | Version |
| --- | --- | --- |
| `mobile_rag_engine` | clean root path | `0.21.0-dev.11` |
| `rag_engine_flutter` | hosted pub.dev | `0.20.0-dev.11` |
| `flutter_rust_bridge` | hosted pub.dev | `2.11.1` |

The hosted archive hashes matched the root-lock table above. The consumer used
the documented platform contract: `platform :osx, '14.0'`,
`use_frameworks! :linkage => :static`, and Runner Debug/Profile/Release
deployment targets `14.0`. It added no `-export_dynamic` or other native
workaround.

The host PATH exposed an unrelated Dart `3.4.4`, which could not solve this
package's Dart `^3.9.2` constraint. The same documented setup commands were
therefore run with Flutter 3.35.5's bundled Dart 3.9.2, matching the qualified
toolchain:

```bash
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart run mobile_rag_engine:setup \
  --preset stable-minilm-l6-v2-arm64-en
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart run mobile_rag_engine:setup \
  --preset stable-minilm-l6-v2-arm64-en --check
```

They printed `MODEL_PACK_READY` and `MODEL_PACK_VERIFIED`. The manifest remained
Q8_0 with runtime fingerprint `vabq:none`.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `model.onnx` | `23,026,053` | `4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474` |
| `tokenizer.json` | `466,247` | `be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037` |
| `model-pack.json` | `649` | `89f2bbf47e02d48f68c69149e41bed2193833a576916878b2f21f306e1f77c74` |

The direct non-web release Driver attempt returned the expected exit `1`:

```text
Flutter Driver (non-web) does not support running in release mode.
```

The runtime proof therefore used profile mode. It initialized from the Model
Pack, added `Flutter builds applications from one Dart codebase.`, rebuilt and
warmed the index, searched `What does Flutter build?`, and asserted non-empty
chunks, context, and source content. It exited `0` with:

```text
MODEL_PACK_HOSTED_FIRST_SEARCH_OK hits=1 context_chars=107
All tests passed.
```

A non-fatal integration-test plugin-detection warning appeared during teardown;
the driver captured the successful results and exited `0`.

The separate release build exited `0`:

- Flutter-reported app size: `181.4 MB`
- On-disk app size: `177,236 KiB` (`173M` by `du -sh`)
- Runner executable: `122,479,776` bytes
- Architectures: universal `x86_64 arm64`
- `_frb_get_rust_content_hash`: `1` exported symbol
- `_frbgen_mobile_rag_engine_rust_arc_*`: `4` exported symbols

This proves the clean-path root plus hosted-companion boundary. It does not
claim a release-mode Driver run or a fully hosted root installation.

## Actions not taken

- Root publish: not run
- `--force`: not run
- Push / PR creation / PR merge: not run
- Rebase / force-push: not run
- Tag / yank: not run
- Existing dirty files staged or committed: none

The next action is an explicit user decision on publishing
`mobile_rag_engine 0.21.0-dev.11` from the frozen source commit/archive while
accepting the two exact-pin pub warnings. Recheck the official version endpoint
immediately before any approved publish.
