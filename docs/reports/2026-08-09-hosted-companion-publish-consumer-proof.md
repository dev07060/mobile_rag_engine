# Hosted companion publish and consumer proof — blocked before publish

**Verdict:** `rag_engine_flutter 0.20.0-dev.11` was **not published**. The
required tracked-files-only clean-snapshot preflight found a real Flutter Rust
Bridge generated-source drift, so this session stopped before `flutter pub
publish`, hosted-consumer setup, model installation, or macOS builds. No
published package has been yanked or otherwise changed.

## Scope and source boundary

- Branch: `feats/publish-companion-dev11`.
- Clean source commit: `a1f97cd752850f6fbca0f9ee22553539eb4c775a`
  (`2026-08-09 20:13:17 +0900`).
- All release inputs were taken only from
  `git archive HEAD` extracted at
  `/private/tmp/mobile-rag-dev11-clean`. The repository's pre-existing dirty
  LOC-144 generated bindings and other user files were neither copied into
  that snapshot nor used as release input.
- The clean companion pubspec declares `rag_engine_flutter 0.20.0-dev.11`.
  The root pubspec declares exact `rag_engine_flutter: 0.20.0-dev.11` and
  exact `flutter_rust_bridge: 2.11.1`; its local override is not a release
  input for the companion package.

## Pre-publish availability and toolchain

At the pre-publish check, the pub.dev package API listed versions through
`0.20.0-dev.10`; `0.20.0-dev.11` was absent. This did not authorize a publish
because the remaining clean-snapshot gate below failed.

The validation toolchain was Flutter `3.35.5`, Dart `3.9.2`, and
`flutter_rust_bridge_codegen 2.11.1`. The committed Rust generated artifact
reports codegen `2.11.1` and content hash `-941343322`.

## Blocking clean-codegen result

The clean snapshot initially had the expected four generated-file SHA-256
values:

| File | Initial SHA-256 |
| --- | --- |
| `lib/src/rust/frb_generated.dart` | `cd2336044a5c3dd58e0d8a42587d7314791554140805d999453a67c09ef0af12` |
| `lib/src/rust/frb_generated.io.dart` | `a02958fb27c017cc6e949d95e62b186037de3e40c79564d26a0c19fc3fdbd48b` |
| `lib/src/rust/frb_generated.web.dart` | `62bb418c4db9f8a5e22c0a2ee20ff9ad3263f1b43b0e89455b0ee39c67c310a4` |
| `rust_builder/rust/src/frb_generated.rs` | `b6ffa3f452904adc49c4653495bbfc95d8acb43aaad469494fff13c30351d987` |

After `flutter_rust_bridge_codegen generate --config-file
flutter_rust_bridge.yaml` completed and exited, the Rust artifact remained at
the listed hash but all three Dart artifacts changed to:

| File | Post-generation SHA-256 |
| --- | --- |
| `lib/src/rust/frb_generated.dart` | `16f2f08163e3231322f57f9827403328fd9d02c11e943817044c9900f17008c9` |
| `lib/src/rust/frb_generated.io.dart` | `99b373b9853d387950dc6a5067de12af651da765daa44c95022c676c298fac40` |
| `lib/src/rust/frb_generated.web.dart` | `cf3867e59fe96b1da07e997e08b93b25652d0a78873151a41c725c966d15e926` |

This is semantic drift, not formatter-only drift: the generated Dart API adds
`crateApiHnswIndexLoadedHnswNodeCount`, its `usize` codecs, shifts subsequent
FRB function IDs, and changes the Dart-side content hash from `-394558992` to
`-941343322`. Therefore the clean archive at the stated commit cannot satisfy
the mandatory codegen zero-diff condition.

## Gates not run

To avoid presenting an unqualified artifact as release-ready, this session did
not run `flutter pub publish --dry-run`, actual publish, post-publish pub.dev
polling, or a new hosted companion consumer. Consequently there is no dry-run
archive size/warning result, hosted lockfile, Model Pack sentinel/hash, first
search result, release build, or executable symbol/runtime `dlsym` result for
this session.

## Required next action

Publish may be reconsidered only after a commit makes the tracked generated
files reproducible from the clean source with the pinned generator. That
change is outside this session's allowed release-only scope because it would
adopt the currently dirty LOC-144 generated bindings (or otherwise alter the
release source). It requires separate user direction. After that, rebuild the
clean archive and repeat every preflight and hosted-consumer gate before a
real companion publish.

## Explicit non-actions

No root `mobile_rag_engine` publish, git push, pull request, merge, tag,
pub.dev yank, or consumer-side manual linker/symbol workaround occurred.
