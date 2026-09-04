# Hosted companion qualification — blocked at macOS process ABI

**Verdict:** do **not** request approval to publish `rag_engine_flutter
0.20.0-dev.11`.  The final package dry-run, canonical FRB reproducibility, and
the arm64 static-library export pass.  However, a fresh macOS consumer using
the explicit local-candidate override builds but cannot resolve
`frb_get_rust_content_hash` from its process.  Initialization therefore stops
before document ingestion/search and never prints `MODEL_PACK_FIRST_SEARCH_OK`.

## Source boundary

- Qualification branch/HEAD: `feats/hosted-companion-qualification` /
  `9dfe7c81b0a8194081895ee59894d5cf0bd308c3`.
- Candidate preparation commit: `621adef7a0cdc1ff7c3b4cc80a3d37486d0d3a39`;
  companion version: `0.20.0-dev.11`.
- Every package/build input was a tracked-files-only `git archive` snapshot
  under `/private/tmp`.  The active checkout's LOC-144 changes and untracked
  files were neither copied nor used as release input.
- No push, PR, merge, tag, publish, or credential use occurred.

## Canonical code generation

The root constrains `flutter_rust_bridge` to exactly `2.11.1`; the installed
generator was also `2.11.1`.  The canonical release formatter was explicitly
selected with `PATH=/Users/dev_bh/flutter/bin:$PATH`:

```text
Flutter 3.35.5 / Dart 3.9.2
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

Two completed independent runs on fresh clean snapshots left all required
outputs byte-for-byte unchanged:

| Output | SHA-256 |
| --- | --- |
| `lib/src/rust/frb_generated.dart` | `cd2336044a5c3dd58e0d8a42587d7314791554140805d999453a67c09ef0af12` |
| `lib/src/rust/frb_generated.io.dart` | `a02958fb27c017cc6e949d95e62b186037de3e40c79564d26a0c19fc3fdbd48b` |
| `lib/src/rust/frb_generated.web.dart` | `62bb418c4db9f8a5e22c0a2ee20ff9ad3263f1b43b0e89455b0ee39c67c310a4` |
| `rust_builder/rust/src/frb_generated.rs` | `b6ffa3f452904adc49c4653495bbfc95d8acb43aaad469494fff13c30351d987` |

The generated Dart and Rust sides retain codegen version `2.11.1` and content
hash `-941343322`.  The shell-default `/opt/homebrew/bin/dart` is Dart 3.4.4,
so it is not a release-proof formatter; the command above deliberately avoids
that ambiguity.

## Final companion package dry-run

From the clean snapshot's `rust_builder` directory,
`flutter pub publish --dry-run` completed with no blocking error and **0
warnings**.  It would publish `rag_engine_flutter 0.20.0-dev.11`, includes
`CHANGELOG.md`, and reported a **234 KB** compressed archive.  The archive
contains package metadata, Android/iOS/macOS plugin files, Cargokit tooling,
and the Rust source, lockfile, and generated Rust binding.  This was a dry-run
only; it did not publish anything.

## Native artifact and ABI

The clean snapshot example completed a macOS profile build.  Its final arm64
static library was:

```text
example/build/macos/Build/Products/Profile/rag_engine_flutter/librag_engine_flutter.a
116 MB, arm64 archive
```

`nm -gU` reports:

```text
0000000000019fc4 T _frb_get_rust_content_hash
```

The profile app was a universal macOS executable.  This proves the candidate
archive contains the required symbol, but not that the app process exports it
to `RTLD_DEFAULT`.

## Fresh local-candidate consumer — failed gate

A new `/private/tmp/mobile_rag_session9_consumer` macOS Flutter app used:

- `mobile_rag_engine`: clean-snapshot path;
- `dependency_overrides.rag_engine_flutter`: clean snapshot
  `rust_builder` path, resolving `0.20.0-dev.11`;
- `flutter_rust_bridge`: hosted exact `2.11.1`;
- `integration_test` and `assets/mobile_rag/`.

This is explicitly a pre-publish **local path override** proof, not hosted or
override-free proof.  Model installation and verification both succeeded:
`MODEL_PACK_READY` and `MODEL_PACK_VERIFIED`.

The generated consumer needed both `platform :osx, '14.0'` plus all three
Runner `MACOSX_DEPLOYMENT_TARGET = 14.0` settings, and
`use_frameworks! :linkage => :static`.  Without the Runner settings, the
initial build failed because `flutter_onnxruntime` requires macOS 14.0.

After that correction, `flutter drive --profile -d macos` built the consumer
app (151.3 MB), connected to it, and failed at `MobileRag.initialize`:

```text
Failed to lookup symbol 'frb_get_rust_content_hash':
dlsym(RTLD_DEFAULT, frb_get_rust_content_hash): symbol not found
```

`nm` confirms the final static library exports the symbol, while the app
executable has no corresponding global export.  Thus the required native
process ABI gate fails.  No document was added, index rebuilt, or search run;
hits, context length, and `MODEL_PACK_FIRST_SEARCH_OK` do not exist.

## Unperformed gates and next action

Because the required local-candidate first-search gate failed, this run does
not claim a consumer release build or the remaining clean-snapshot regression
suite.  The earlier `2026-08-09-hosted-companion-prepublish.md` is superseded
only for its former codegen-drift stop condition: canonical codegen now passes.
It remains useful historical evidence; this report records the later, blocking
macOS process-linkage failure.

Repair the macOS linkage so the final process makes
`frb_get_rust_content_hash` discoverable by `RTLD_DEFAULT`, then repeat from a
new clean candidate snapshot: profile first search with non-empty source
evidence, separate `flutter build macos --release`, and the requested
analysis/unit/example/native regressions.  Only after those pass may the owner
separately authorize an actual pub.dev publish; this report is not that
authorization.
