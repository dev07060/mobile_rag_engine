# Decision: model onboarding before VABQ rollout

## 1. Decision

**Do not resume VABQ product development or present it as a public default or
release headline; keep Q8_0 as the public default and freeze VABQ as an
explicit, advanced research opt-in while the next session proves an
override-free first search with a hosted native companion built from the clean
generated ABI contract.**

This is a prioritization decision, not a deletion decision. The VABQ format and
profile implementation remain useful research assets. They must not consume the
next delivery session while a new consumer cannot complete the basic
install-to-first-search path.

## 2. Why now

| Evidence | What is established | What is not established | Product consequence |
| --- | --- | --- | --- |
| VABQ checkpoint (2026-07-15) | Versioned persisted format, profile mismatch rejection, and effectively preserved controlled quality. BGE-M3 Hit@10 was 92.0% and macro Recall@10 91.25% for both current Q8 and current VABQ. | A repeatable advantage over Q8_0: official mean search was 2.12% slower for VABQ; a separate warm pair was about 4.4% faster. Indexing/rebuild were practical parity and RSS was not lower. | There is no basis for a VABQ default, speed/RSS claim, or release headline. |
| VABQ storage result | Vector payload reductions were 2.55% (MiniLM 384d), 8.68% (BGE-base 768d), and 3.73% (BGE-M3 1024d); corresponding observed HNSW reductions were about 1.7%, 7.0%, and 3.2%. | That these savings solve a user storage problem or materially reduce process memory. All current-profile results are local-path builds with `release_comparable=false`. | Preserve VABQ research; do not spend the next session productizing a modest, unvalidated user benefit. |
| Immutable MiniLM Model Pack consumer proof (2026-08-09) | In an override-free macOS Flutter consumer, setup emitted `MODEL_PACK_READY` and `MODEL_PACK_VERIFIED`; the 23,026,053-byte ONNX and 466,247-byte tokenizer matched their manifest SHA-256 values. The consumer built in profile and release mode. The preset explicitly uses Q8_0 and leaves VABQ inactive. | The required first search: `MODEL_PACK_FIRST_SEARCH_OK` was never printed, and no hit/context count exists. | The immediate user value gap is not model-file installation; it is completing retrieval with the dependency a consumer actually receives. |
| Hosted native boundary | Pinning `flutter_rust_bridge` to 2.11.1 resolved the earlier codegen/runtime 2.11.1/2.12.0 mismatch. The root clean snapshot's generated Dart and Rust sources both state codegen 2.11.1 and content hash `-941343322`. | The hosted `rag_engine_flutter 0.20.0-dev.10` binary lacks `frb_get_rust_content_hash`; initialization fails before ingestion and search. The test used a clean root path snapshot, so it is not a fully hosted root-package proof. | The primary blocker is hosted native ABI/distribution, not VABQ and not the installer. |
| macOS generated-app setup | The consumer could build after setting macOS 14.0 and CocoaPods static framework linkage. | A no-manual-configuration onboarding path. These settings are still real friction, but they did not stop the build after being supplied. | Treat platform settings as the next secondary onboarding check, after ABI-compatible first search works. Do not design an automatic fixer in this decision. |

The current public guidance already matches this decision: README and the Model
Setup Guide select Q8_0 for ordinary initialization and require an explicit
`VabqProfile` for experimental VABQ. The Model Pack v1 preset is fixed to
Q8_0; a model name or embedding dimension never enables VABQ.

## 3. Current product state

| State | Facts and boundary |
| --- | --- |
| Shipped/publicly resolvable | The hosted companion resolved as `rag_engine_flutter 0.20.0-dev.10`, and the normal public/documented storage path is Q8_0. The consumer proof does **not** show a fully hosted `mobile_rag_engine 0.21.0-dev.10`; that root was a clean tracked-files-only path snapshot. |
| Committed in this local stack | `ffaddd4` VABQ checkpoint, `26a8188` Q8_0 public-default wording, `5ffb5d4` clean example startup, `0738b52` immutable MiniLM setup, `af8a243` Model Pack runtime lane, `86f279a` exact FRB 2.11.1 pin, and `5b40b5b` consumer ABI proof. The stack adds both VABQ research/profile work and the Model Pack path; it does not contain a compatible hosted native companion release. |
| Proven | VABQ codec/profile persistence and quality parity within the stated local research boundary; immutable MiniLM installation/integrity verification; profile/release macOS build after the two manual platform settings; and the exact hosted ABI failure. |
| Not proven | VABQ latency or RSS benefit, VABQ release comparability, a user demand for the saved bytes, Model Pack first-search success, a fully hosted root-package integration, or a release-mode `flutter drive` integration run (Flutter Driver refuses non-web release mode). |
| Blocked | `dlsym(RTLD_DEFAULT, frb_get_rust_content_hash): symbol not found` from the hosted companion blocks initialization before document ingestion/search. The current dirty LOC-144 generated bindings must not be treated as a deployment input or workaround. |

Keep the VABQ implementation and the versioned format (`0x02` / version `0x01`)
in place. It is research-frozen: no deletion, default flip, benchmark marketing,
or new model-profile expansion. Any future VABQ test remains explicit opt-in and
must not silently accept Q8_0 fallback as VABQ success.

## 4. Next single-session spec

### Goal

Prepare and, only with approval, publish a **previously unused prerelease** of
`rag_engine_flutter` whose native artifacts are generated and built from one
clean commit and match the root's generated Dart/Rust Flutter Rust Bridge ABI;
then align the root dependency exactly to that companion and rerun the
override-free MiniLM first-search consumer proof. Do not choose or claim a
specific version number until the existing published versions are checked.

### In scope

1. Start from a clean checkout of the committed baseline, not the dirty
   LOC-144 generated bindings. Establish the generated Dart source, generated
   Rust source, FRB codegen version, and content-hash value as one matched
   release input. The clean baseline currently records codegen `2.11.1` and
   content hash `-941343322` on both sides.
2. Produce the companion package/artifacts from that same clean input and
   inspect the resulting macOS native library for the content-hash export
   required by the generated Dart runtime.
3. Change the root package only as needed to resolve the unique hosted
   companion version exactly. Do not retain a root override as the consumer
   solution.
4. In a fresh macOS consumer without `dependency_overrides` or
   `pubspec_overrides.yaml`, install and `--check` the stable MiniLM pack, add
   the one-document fixture, rebuild/warm, and search. Record the success
   sentinel with non-empty hits and context.

### Out of scope

- VABQ code, profile defaults, benchmark reruns, deletion, or release claims.
- Publishing the root package, version-bumping unrelated packages, or using the
  dirty LOC-144 bindings.
- Designing an automatic macOS-target or CocoaPods-linkage modification tool.
  The manual macOS 14.0/static-framework requirements are to be tested and
  documented as onboarding friction only.

### Success conditions and evidence

The session passes only when all of the following are retained in its report:

1. The candidate companion's generated Dart and Rust input show the same FRB
   codegen version and content hash, and its built macOS library exports the
   symbol requested by the consumer runtime.
2. A clean consumer resolves the intended unique hosted companion, has no
   overrides, and does not substitute the repository's local `rust_builder`.
3. `dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en`
   and the same command with `--check` complete successfully.
4. The profile-mode native integration command reaches
   `MODEL_PACK_FIRST_SEARCH_OK` with non-empty hits and context. Label it
   profile-mode native proof, not a release integration result.
5. `flutter build macos --release` succeeds separately. It is a build proof,
   not evidence that the integration assertions ran in release mode.

Run and retain the focused regression scopes from the clean input:

```bash
flutter analyze lib test
flutter test test/unit
(cd example && flutter test)
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en --check
flutter drive --profile -d macos \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/model_pack_first_search_test.dart
flutter build macos --release
```

If ABI alignment or the hosted export is still absent, stop after documenting
the exact clean-input mismatch. Do not mask it with a path dependency, a local
native override, or dirty generated files.

## 5. Authorization boundary

| May proceed locally without further external action | Requires explicit user approval before execution |
| --- | --- |
| Clean-commit inspection, generation/build dry runs, version availability check, local dependency alignment, native-export inspection, and a temporary override-free consumer verification. | Publishing the companion prerelease to pub.dev, publishing the root package, pushing a branch, opening or merging a PR, merging branches, tagging, or any release announcement. |

Local preparation is intentionally separate from publication. A companion
publish must use a unique prerelease rather than reusing an existing published
version; approval is required after its exact version and evidence are known.

## 6. VABQ resume gates

Resume VABQ research or consider productization only if at least one value gate
and its matching proof gate are met:

| Value gate | Required proof before resuming |
| --- | --- |
| Better retrieval quality per byte | On the same corpus and exact-f32 reference, VABQ beats same-byte uniform and deterministic random-permutation controls on rank/score error or retrieval quality. |
| Faster or lower-memory retrieval | Repeated, counterbalanced Q8_0 → VABQ → Q8_0 comparisons on the same native binary, device, corpus, model, query set, and settings show a same-direction latency or RSS benefit. The timing interval must exclude zero without material quality loss; memory evidence must measure mappings/RSS, not blob bytes alone. |
| A real storage need | User or pilot evidence shows that vector storage is a material constraint and the observed saving is large enough in that workload to change the adoption decision. |

A renewed release claim additionally needs hosted/released binaries and
`release_comparable=true`. Until then, VABQ stays a preserved research
capability: explicit opt-in, Q8_0 remains default, and no speed/RSS headline.

## 7. Stop conditions

- Do not call the current result “Model Pack first search success” or “fully
  hosted verified.” Neither occurred.
- Do not treat the successful installer, profile/release build, or smaller VABQ
  payload as substitutes for the missing first search, hosted ABI, or measured
  RSS benefit.
- Do not use the existing dirty generated LOC-144 files as release input,
  staging material, or a shortcut around the native ABI mismatch.
- Do not alter the two macOS manual settings in this session or claim they are
  solved; they are recorded friction after the primary ABI blocker.
