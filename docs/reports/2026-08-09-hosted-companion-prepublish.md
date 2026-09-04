# Hosted companion prepublish proof — blocked by clean codegen drift

**Verdict:** do **not** request publish approval.  The candidate version is
available on pub.dev, and the committed Rust generated binding has the expected
FRB ABI/content hash.  However, regenerating FRB from the candidate's own
tracked-files-only source changes all committed generated Dart bindings.  The
release boundary requires stopping on that unexpected diff, so package
dry-run-on-final-commit, native artifact validation, local consumer first
search, release build, and regression are intentionally not claimed.

## Scope and source boundary

- Start branch/HEAD: `feats/onboarding-vabq-decision` /
  `3766ff6e8cbbb140b62d345b22851157014b3827`.
- Candidate branch: `feats/hosted-companion-prep`.
- Candidate preparation commit:
  `621adef7a0cdc1ff7c3b4cc80a3d37486d0d3a39`
  (`chore: prepare aligned native companion prerelease`).
- Candidate inputs are only its tracked files, freshly archived with
  `git archive` to
  `/private/tmp/mobile_rag_hosted_companion_final_jRebX8/mobile_rag_engine_snapshot_621adef`.
  The active checkout's LOC-144 generated bindings and untracked material were
  not copied, read as release input, staged, or changed.
- No push, PR, merge, tag, root-package publish, companion publish, or
  credential use occurred.

## Candidate selection

At `2026-08-09T19:25:40+09:00`, the public
`https://pub.dev/api/packages/rag_engine_flutter` response reported latest
stable `0.19.2` (published `2026-07-03T04:43:10.242009Z`) and the following
published versions:

```text
0.1.0, 0.2.0, 0.3.0, 0.4.0, 0.5.0, 0.5.1, 0.6.0, 0.6.1, 0.7.0, 0.7.5,
0.7.6, 0.8.0, 0.9.0, 0.9.1, 0.10.0, 0.10.1, 0.10.2, 0.11.0, 0.12.0,
0.13.0, 0.14.0, 0.14.1, 0.14.2, 0.15.0, 0.16.0, 0.17.0, 0.18.0,
0.18.1, 0.18.2, 0.18.3, 0.18.4, 0.19.2, 0.20.0-dev.1,
0.20.0-dev.2, 0.20.0-dev.3, 0.20.0-dev.4, 0.20.0-dev.5,
0.20.0-dev.6, 0.20.0-dev.7, 0.20.0-dev.8, 0.20.0-dev.10
```

`0.20.0-dev.11` was absent, so it is the selected unused prerelease candidate.
The preparation commit changes only:

- `rust_builder/pubspec.yaml`: companion version `0.20.0-dev.11`.
- `pubspec.yaml`: exact normal dependency
  `rag_engine_flutter: 0.20.0-dev.11`; its development-only path override is
  unchanged and is not consumer proof.
- `pubspec.lock` and `example/pubspec.lock`: mechanical path-version update.
- `rust_builder/CHANGELOG.md`: one entry required by package validation.

## Clean ABI and code-generation check

The candidate root has `flutter_rust_bridge: 2.11.1` exactly.  In the clean
archive, dependency resolution selected `flutter_rust_bridge 2.11.1`, and
`flutter_rust_bridge_codegen --version` was `2.11.1`.

Committed generated artifacts declare the same ABI values:

| Artifact | Codegen version | Content hash |
| --- | --- | ---: |
| `lib/src/rust/frb_generated.dart` | `2.11.1` | `-941343322` |
| `rust_builder/rust/src/frb_generated.rs` | `2.11.1` | `-941343322` |

The committed Rust generator output exactly matches a fresh clean-snapshot
generation.  The generated Dart files do not:

```text
DIFF lib/src/rust/frb_generated.dart
DIFF lib/src/rust/frb_generated.io.dart
DIFF lib/src/rust/frb_generated.web.dart
MATCH rust_builder/rust/src/frb_generated.rs
```

The observed Dart differences begin with formatter/layout-only changes (for
example multiline argument formatting and indentation); the codegen version
and content hash remain `2.11.1` and `-941343322`.  Nonetheless, the required
clean-generation check is not a zero diff, so no generated Dart file was
copied back or staged and all further publish qualification stopped.

## Companion packaging observation

An earlier tracked-files-only snapshot of the same candidate version
(`9a87000`, before the CHANGELOG warning was fixed) ran:

```bash
cd rust_builder
flutter pub publish --dry-run
```

It assembled `rag_engine_flutter 0.20.0-dev.11` as a 234 KB archive containing
the package metadata, Android/iOS/macOS plugins, Cargokit build tooling, and
the Rust source/lockfile/generated Rust binding.  It had no blocking package
error, but warned that `CHANGELOG.md` did not mention `0.20.0-dev.11`.
`621adef` adds that single changelog entry.  A final-commit dry-run is **not
claimed**, because the subsequent mandatory clean codegen check stopped the
workflow before that step.

The package builds its macOS static Rust library through the Cargokit pod
script (`cargokit/build_pod.sh`) and force-loads
`librag_engine_flutter.a` from the podspec.  Native `nm`/`otool` symbol proof
for `frb_get_rust_content_hash` was not run after the stop condition.

## Unperformed gates and required next action

The following remain unverified, not failed product claims:

- final-commit companion `flutter pub publish --dry-run`;
- clean snapshot macOS arm64 release/profile native build and exported
  `frb_get_rust_content_hash` proof;
- new `/private/tmp` macOS 14.0/static-linkage consumer with its explicitly
  labeled path override, Model Pack setup/check, and
  `MODEL_PACK_FIRST_SEARCH_OK` with non-empty hits/context;
- separate `flutter build macos --release` for that consumer;
- clean-snapshot `flutter analyze lib test`, `flutter test test/unit`, example
  tests, native tests/build, and final `git diff --check`.

Before resuming, the owner must decide whether the clean 2.11.1-generated Dart
formatting drift should be adopted in a separate, reviewed generated-binding
commit.  Only after that committed snapshot regenerates with zero diff should
the remaining gates run.  If every gate then passes, a separate explicit user
approval is still required for the actual `rag_engine_flutter 0.20.0-dev.11`
publish; this report is neither hosted proof nor publish authorization.
