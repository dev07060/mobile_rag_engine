# Root `0.21.0-dev.12` release and fully hosted proof

Date: 2026-09-04 (Asia/Seoul)

## Verdict

`mobile_rag_engine 0.21.0-dev.12` was published from a frozen,
tracked-files-only source archive after clean package and native qualification.
The published package then resolved from pub.dev in a new macOS Flutter app and
passed the complete issue #83 lifecycle:

1. initialize a fresh database with `deferIndexWarmup: true`;
2. wait for deferred warmup;
3. ingest, rebuild, and search;
4. call `clearAllData()`;
5. immediately ingest, rebuild, and search again.

Both the prepublish archive consumer and the fully hosted consumer completed
with `initial_hits=1` and `reset_hits=1`. The hosted consumer also built a
universal release app with the expected Flutter Rust Bridge exports.

## Frozen source

- Branch: `feats/root-dev11-onboarding-release`
- Qualified and published source commit: `359590d`
- Source archive:
  `/private/tmp/mobile-rag-root-dev12-qualification.iFtHja/source.tar`
- `git archive HEAD` SHA-256:
  `8322d285a6fdb1b1a55877d89e3de17dcbf1cf2d2ab881c902517e58348c27da`
- The archive contained no `.git`, `pubspec_overrides.yaml`, or root
  `dependency_overrides`.

The release diff was trimmed before freezing. Scratch files, raw result trees,
generated plots, one-off benchmark harnesses, and unsupported VABQ performance
claims were removed from the release tip. The VABQ implementation and
reproducible research source remain, with VABQ documented as experimental and
opt-in while Q8_0 remains the public default.

## Clean archive qualification

The test extraction of the frozen archive completed:

| Gate | Result |
| --- | --- |
| `flutter analyze lib test --no-fatal-infos` | no issues |
| unit gate | `69` passed, `0` failed |
| tracked PDF Rust smoke | `1` passed, `0` failed |
| faer vector tests | `4` passed, `0` failed |
| i8 vector-quant tests | `21` passed, `0` failed |
| shipped-feature Rust release build | succeeded |
| Flutter native gate | `24` passed, `0` failed |

The separate publish dry-run reported a compressed archive size of `2 MB`, no
validation errors, and exactly two warnings for the intentionally exact
dependency constraints:

- `flutter_rust_bridge: 2.11.1`
- `rag_engine_flutter: 0.20.0-dev.11`

No constraint was loosened. Publication therefore used `--force` as expected.

## Prepublish issue #83 consumer

Consumer:
`/private/tmp/mobile-rag-root-dev12-prepublish.XfbNDz/consumer`

The consumer used the frozen archive extraction as its only path dependency.
Its Model Pack integrity check passed, followed by the full deferred-warmup and
reset lifecycle. The test exited `0` with:

```text
ISSUE83_DEFERRED_WARMUP_AND_RESET_OK initial_hits=1 reset_hits=1
All tests passed!
```

Its separate macOS release build also exited `0` and produced a `181.4 MB`
application.

## Publication record

- Package: `mobile_rag_engine`
- Version: `0.21.0-dev.12`
- Publish command: `flutter pub publish --force`
- Command exit: `0`
- Published: `2026-09-04T02:23:57.863027Z`
- Official archive URL:
  `https://pub.dev/api/archives/mobile_rag_engine-0.21.0-dev.12.tar.gz`
- Official archive SHA-256:
  `294aa2937b925a9dc119cb6f0dc156713f7797cf60ca26d84993c374bb450930`

Downloading the official archive and hashing it locally reproduced the API
SHA-256 exactly. No companion or other package was published.

## Fully hosted consumer

Consumer:
`/private/tmp/mobile-rag-root-dev12-hosted.rBSxLI/consumer`

The first resolution attempts occurred during pub.dev propagation and could
not yet see the new version. After the package-list cache window elapsed, a
fresh isolated cache resolved the release without a fallback source or cache
deletion.

The resulting lockfile contained:

| Package | Source | Version | Archive SHA-256 |
| --- | --- | --- | --- |
| `mobile_rag_engine` | hosted pub.dev | `0.21.0-dev.12` | `294aa2937b925a9dc119cb6f0dc156713f7797cf60ca26d84993c374bb450930` |
| `rag_engine_flutter` | hosted pub.dev | `0.20.0-dev.11` | `a76a54423aedbe4940bb823b25f0c0c43feb1c543035edc14e0042707c06698b` |
| `flutter_rust_bridge` | hosted pub.dev | `2.11.1` | `37ef40bc6f863652e865f0b2563ea07f0d3c58d8efad803cc01933a4b2ee067e` |

- Path-sourced packages: `0`
- `dependency_overrides`: absent
- `pubspec_overrides.yaml`: absent
- macOS deployment target: `14.0`
- CocoaPods linkage: static frameworks
- Consumer linker/export workaround: none

The hosted package's setup and integrity-check commands printed
`MODEL_PACK_READY` and `MODEL_PACK_VERIFIED`. The full issue #83 test then
exited `0` with:

```text
ISSUE83_DEFERRED_WARMUP_AND_RESET_OK initial_hits=1 reset_hits=1
All tests passed!
```

This directly closes the dev.11 post-publication gap: deferred warmup no longer
races fingerprint persistence on a fresh database, and `clearAllData()` no
longer returns before replacement indexes are ready for immediate ingestion.

## Hosted release build

`flutter build macos --release` exited `0`.

- Flutter-reported app size: `181.7 MB`
- Runner executable size: `122,462,336` bytes
- Runner executable SHA-256:
  `adc27f5c96e4699caec789cdc000472d87d20e8ad5f78404487284f5c59a66b5`
- Architectures: `x86_64 arm64`
- `_frb_get_rust_content_hash`: present
- `_frbgen_mobile_rag_engine_rust_arc_*`: four exports present

The build emitted existing ONNX Runtime C++ standard and empty-object warnings;
none was an error.

## Workspace boundary

The pre-release noncanonical working tree remains isolated in
`stash@{0}` and was not used as a qualification, publication, or consumer
input. This report is a post-publication documentation-only addition; the
published package source remains commit `359590d` and the frozen archive above.
