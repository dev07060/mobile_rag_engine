# Fully hosted root `0.21.0-dev.11` consumer proof

Date: 2026-08-31 (Asia/Seoul)

## Verdict

`mobile_rag_engine 0.21.0-dev.11` was published from the frozen, qualified
tracked-files-only source and then resolved from hosted pub.dev in a completely
new macOS Flutter app. The default immediate-warmup Model Pack flow completed
setup, integrity check, native/FRB initialization, a source-grounded first
search, and a separate universal release build with the required FRB symbols.

This is a fully hosted proof for the default Model Pack initialization path:
root, native companion, and Flutter Rust Bridge all came from pub.dev. The
consumer had no path package and no dependency override.

One optional-path failure must remain visible. The first profile run used
`deferIndexWarmup: true` and failed during initialization with
`RagError.databaseError(field0: database is locked)`. Removing only that
optional defer setting and using a fresh database made the documented default
flow pass. The published version was not yanked, and no package or native code
was changed during post-publish verification.

## Publication record

- Package: `mobile_rag_engine`
- Version: `0.21.0-dev.11`
- Qualified source commit: `1f55d3f`
- Frozen source tar SHA-256:
  `32912e17eecc09b5da232d103f5c1bebd8c10bc9aa0ef8d756471f71ab11241e`
- Frozen source tar size: `11,950,080` bytes
- Publish command: `flutter pub publish --force`
- Command start: `2026-08-31T01:13:36Z`
- Command finish: `2026-08-31T01:13:47Z`
- Command exit: `0`
- Server result: successfully uploaded
  `https://pub.dev/packages/mobile_rag_engine` version `0.21.0-dev.11`

The two previously recorded exact-pin warnings were accepted deliberately:

- `flutter_rust_bridge: 2.11.1`
- `rag_engine_flutter: 0.20.0-dev.11`

Those constraints were not loosened. No other package was published.

The official exact-version API returned HTTP `200` at
`2026-08-31T01:14:10Z`:

| Field | Value |
| --- | --- |
| Version | `0.21.0-dev.11` |
| Published | `2026-08-31T01:13:46.058229Z` |
| Archive URL | `https://pub.dev/api/archives/mobile_rag_engine-0.21.0-dev.11.tar.gz` |
| Archive SHA-256 | `6e763a0a6470d449033f040b1e032eba5d253f0d729994d64bd9b1ffe9673554` |
| Archive size | `2,300,262` bytes |

Downloading the official archive and hashing it locally reproduced the API
SHA-256 exactly. Its pubspec retained root version `0.21.0-dev.11` and the two
exact hosted dependency pins.

## Fresh consumer and propagation

Evidence root:

```text
/private/tmp/mobile-rag-fully-hosted-root-dev11-consumer.SbtsKd
```

Consumer:

```text
/private/tmp/mobile-rag-fully-hosted-root-dev11-consumer.SbtsKd/consumer
```

The consumer was created with:

```bash
flutter create --platforms=macos \
  --project-name mobile_rag_hosted_root_dev11_consumer \
  /private/tmp/mobile-rag-fully-hosted-root-dev11-consumer.SbtsKd/consumer
```

Its only package declaration was the hosted version:

```yaml
dependencies:
  mobile_rag_engine: 0.21.0-dev.11
```

The first fresh `flutter pub get` ran during package propagation and exited
`1`:

```text
Because mobile_rag_hosted_root_dev11_consumer depends on
mobile_rag_engine 0.21.0-dev.11 which doesn't match any versions,
version solving failed.
```

The official API already exposed the version at that point. Bounded retry
number two completed with exit `0`; no override or fallback source was added.

## Fully hosted lock contract

Mechanical YAML inspection after resolution and again after all builds found:

| Package | Source | Version | Archive SHA-256 |
| --- | --- | --- | --- |
| `mobile_rag_engine` | hosted pub.dev | `0.21.0-dev.11` | `6e763a0a6470d449033f040b1e032eba5d253f0d729994d64bd9b1ffe9673554` |
| `rag_engine_flutter` | hosted pub.dev | `0.20.0-dev.11` | `a76a54423aedbe4940bb823b25f0c0c43feb1c543035edc14e0042707c06698b` |
| `flutter_rust_bridge` | hosted pub.dev | `2.11.1` | `37ef40bc6f863652e865f0b2563ea07f0d3c58d8efad803cc01933a4b2ee067e` |

- Path-sourced packages: `0`
- `dependency_overrides`: absent
- `pubspec_overrides.yaml`: absent

## Host integration and Model Pack

The consumer used only the documented macOS host settings:

- Podfile `platform :osx, '14.0'`
- Runner target `use_frameworks! :linkage => :static`
- Runner Debug/Profile/Release deployment target `14.0`

No consumer-side export, symbol, or linker workaround was added.

The Model Pack commands used Flutter 3.35.5's bundled Dart 3.9.2:

```bash
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart run mobile_rag_engine:setup \
  --preset stable-minilm-l6-v2-arm64-en
/Users/dev_bh/flutter/bin/cache/dart-sdk/bin/dart run mobile_rag_engine:setup \
  --preset stable-minilm-l6-v2-arm64-en --check
```

They printed `MODEL_PACK_READY` and `MODEL_PACK_VERIFIED`.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `model.onnx` | `23,026,053` | `4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474` |
| `tokenizer.json` | `466,247` | `be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037` |
| `model-pack.json` | `649` | `89f2bbf47e02d48f68c69149e41bed2193833a576916878b2f21f306e1f77c74` |

The manifest selected Q8_0. Runtime fingerprinting reported
`model.onnx|384|f32+vabq:none`; VABQ was not enabled.

## Runtime attempts

The non-web release Flutter Driver command was attempted and returned the
known tool boundary, exit `1`:

```text
Flutter Driver (non-web) does not support running in release mode.
Use --profile mode for testing application performance.
```

### First profile attempt: deferred-warmup failure

The first fixture retained the optional initialization argument:

```dart
deferIndexWarmup: true
```

It failed before document ingestion:

```text
RagError.databaseError(field0: database is locked)
#5 RagEngine._resolveFingerprintGate
#6 RagEngine.initialize
#7 MobileRag.initialize
```

The log showed background BM25/HNSW warmup overlapping the fingerprint database
operation. This is a real post-publish observation. It is not dependency
resolution, missing ABI, or missing-symbol evidence, because the hosted native
library had already loaded far enough to execute initialization.

No runtime/package/native fix was made. The verification fixture removed only
the optional defer argument, thereby returning to the documented default
immediate-warmup flow, and used a fresh database filename to avoid partially
initialized state.

### Second profile attempt: default flow success

The fixture then:

1. initialized from `assets/mobile_rag/model-pack.json`;
2. added `Flutter builds applications from one Dart codebase.`;
3. rebuilt and warmed the index;
4. searched `What does Flutter build?`;
5. asserted non-empty chunks and context;
6. fetched the source by ID and asserted both source and chunk content contained
   the original document.

The corrected profile run exited `0` and printed:

```text
MODEL_PACK_FULLY_HOSTED_FIRST_SEARCH_OK hits=1 context_chars=107
All tests passed.
```

The profile app was reported as `207.7MB`.

## Separate release build and FRB exports

`flutter build macos --release` exited `0`.

- Flutter-reported app size: `181.4MB`
- App regular-file logical total: `181,414,627` bytes across `29` files
- Allocated app size: `177,236 KiB` (`181,489,664` bytes; `du -sh` shows `173M`)
- Architectures: universal `x86_64 arm64`
- Runner executable size: `122,481,616` bytes
- Runner SHA-256:
  `4c5bd6d1017d2012fe0724a2eda1aee4121c9337703ded9ba6e5afc6de0717e5`
- `_frb_get_rust_content_hash`: `1` exported symbol
- `_frbgen_mobile_rag_engine_rust_arc_*`: `4` exported symbols

The successful default-flow profile runtime is also process-level proof that
the hosted root and companion supplied a compatible FRB bridge.

## Retained evidence

- Summary:
  `/private/tmp/mobile-rag-fully-hosted-root-dev11-consumer.SbtsKd/results.md`
- Commands:
  `/private/tmp/mobile-rag-fully-hosted-root-dev11-consumer.SbtsKd/commands.md`
- Focused logs:
  `/private/tmp/mobile-rag-fully-hosted-root-dev11-consumer.SbtsKd/logs/`

Log SHA-256 values:

| Log | SHA-256 |
| --- | --- |
| `propagation.log` | `020184be5daaffd6c04e0b87a7015ad40b5749862a5adf48fc5a7f32c54dca04` |
| `lock.log` | `7a5880890b7bc734801dc4678ffabff20c4ba3de0658fe375445661a4b82e07c` |
| `model-pack.log` | `902615fa55c3453c83942fcf0a1270957ebf2975e11c273995ae61bae8b4c3d3` |
| `runtime.log` | `ce645b4ebcfbc4c62c2c4dd61e1c65f7c9c7fb142f488566a624f6bcee12f697` |
| `release.log` | `8f36a43ab2fefdaf76289810f679a7499dde0569289adf651ed0c1679c1318e4` |

## Workspace and release actions

- Root `0.21.0-dev.11` publish: completed
- Companion or other package publish: not run
- Yank: not run
- Push / PR creation / merge: not run
- Rebase / force-push: not run
- Tag: not created
- Package/native implementation change after publish: none
- Existing user-owned dirty files staged or committed: none

The 26 modified tracked files and 24 untracked files present at task start were
not used as release or consumer inputs and remained preserved. The next work
item is not another publication action: it is deciding whether to investigate
the optional deferred-warmup database-lock race and, separately, whether to
push this branch and prepare a PR. Neither is authorized by this report.
