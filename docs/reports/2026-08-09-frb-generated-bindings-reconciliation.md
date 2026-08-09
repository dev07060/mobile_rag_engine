# FRB generated bindings reconciliation — dirty output not adoptable

**Conclusion: B — do not adopt the existing dirty generated bindings.**

The canonical clean output (B) is not byte-for-byte equal to the current
working-tree generated files (C).  In particular C removes an API which is
present in the tracked Rust input, changes the generated content hash, and
therefore cannot be paired with a native library built from the current source.
No generated/API dirty file was edited, formatted, staged, or committed by this
session.

## Scope and reproducible environment

- Start branch / commit: `feats/publish-companion-dev11` at
  `881929afe2d6e46992b2a78ebb001bd54ed515e7`.
- Diagnostic branch: `feats/reconcile-frb-bindings-dev11`, created from that
  commit while preserving the pre-existing dirty working tree.
- B is a `git archive HEAD` snapshot extracted at
  `/private/tmp/mobile-rag-frb-reconcile-jpyY7y`; no worktree or clone was
  created and no dirty file was copied into it.
- Canonical toolchain: Flutter `3.35.5`, Dart `3.9.2`,
  `flutter_rust_bridge_codegen 2.11.1`.
- B command, read only after it exited successfully: `flutter_rust_bridge_codegen
  generate --config-file flutter_rust_bridge.yaml`.

`881929a` is a documentation-only child of the clean input recorded by the
prior blocked preflight (`a1f97cd`); `git diff a1f97cd..HEAD` contains only that
prior report.  Thus this rerun used unchanged code-generation input from that
preflight, but it does **not** reproduce its reported primary-binding drift.
The direct, completed 2.11.1 generation below is the current diagnostic
evidence.

## A/B/C file comparison

Definitions: A is `HEAD`, B is the completed clean-snapshot generation, and C
is the existing working-tree file.  Hashes are SHA-256. `A=B` means codegen did
not change the tracked file; `B=C` is false for every dirty generated file.

| File | A | B | C | Result |
| --- | --- | --- | --- | --- |
| `lib/src/rust/api/bm25_search.dart` | `6f5ce82ae34f299e999f74f70f73c73e3d72070b0519915a677ebefac9cb6650` | `2cc541bcd1cb05b5b1f0a6215dcbed673fdd99b7f48140493f18c559a2faaf69` | `7af435713720ea050bbfe8ae00c4fddf73728f7fef93f2078a7d6e11f9e72af4` | A!=B, B!=C |
| `lib/src/rust/api/compression_utils.dart` | `a84d76b5c6241810dcfb088627fed8fc252b60f4cc8c4a5148c5ee926d0abc77` | `5c92f93442d5928ab808bc921b3697815ff6804e0306f563902a54fc9b507e37` | `c0624d1f9daf931d88627284ee101fa77a09718d1abb125aa40edd424fb64f39` | A!=B, B!=C |
| `lib/src/rust/api/db_pool.dart` | `5fd7da753c3ce16b7d33ed2b24a0448087459bd1207a33fb872e8e74b953aec7` | `9457c1400a30ec4886b0b8189574f94ce55e1dab1dc22bb8eae87bda66ef073c` | `34ebd01b614fee337093295c372252bc9842eb53ba91539f9adecf90677fa0d7` | A!=B, B!=C |
| `lib/src/rust/api/document_parser.dart` | `c1beefadcb87255130f4b1f981349924878dfccb8a0b4da30af0f59fb0f7cb66` | `dce2dda653a2d5840dd0e474e4ed1047097200ff094ba2e65863c2b8482d8c13` | `0999ee4d22dadee8cf09cdc460b433944cca02b7872a5017f8c7c26ea4341f12` | A!=B, B!=C |
| `lib/src/rust/api/error.dart` | `01ebf5f3fd9ca4a8e0b17403e379f24a2ec1eedad57b92f2b624c83a8f233c53` | `01ebf5f3fd9ca4a8e0b17403e379f24a2ec1eedad57b92f2b624c83a8f233c53` | `edf0b599a2ac0590d3d24970429c61b3195fdaa9b998ccdddcfc1ad799d713ce` | A=B, B!=C |
| `lib/src/rust/api/hnsw_index.dart` | `0f576aa0ebb9d5672ec2d2495d0227cae7e883662281f4e3bd72ebe1b1113a26` | `7a9dc1cfc9b76c8ba105b5424a0f1b47dc608d8c9ccb3bd553ee3f68ff624210` | `5861afb4cdf62ffba93de4192d656a03fc4b52486bc9d58e0a3db35fead6a6b2` | A!=B, B!=C |
| `lib/src/rust/api/hybrid_search.dart` | `9e29e2bb235a9132e75325ff179bc7ddb187591792ef1c8e9cbe54cd9b28c542` | `bb606c904a95dcb65e75b4f2d5593c01f6dfe0c73a188e6dc38e99ce21266f36` | `08f51f6082233eff62fccb9a35afa2567314dea5446160c04a2e9ad15ba3dd52` | A!=B, B!=C |
| `lib/src/rust/api/incremental_index.dart` | `2f3a9a75f5f52ee1738e342531c22122460e7aa9458ed4cf96779a833f9e11e6` | `26e906c63cc5df9a01ebe9ed4bee9f897dacd959d82952cc8d933d91d8d39f7f` | `d3bc54eca0d4e1d772abf699408c1d7ad17a45d9384ff5d8b14513a9285151f2` | A!=B, B!=C |
| `lib/src/rust/api/ingest_session.dart` | `34dfc27d18ec27bd8173e233962979346672481a5964343a8861cf37981527d1` | `b23fff3709bd97c65f974bc5f8af8034c67da392444f9b122f80c69c7f799a0c` | `cf023bd99559aa7f433d487f94c8affa49a93d8436d72678bc44605dff5d8cee` | A!=B, B!=C |
| `lib/src/rust/api/migration_meta.dart` | `369274a9199a70355afd3f1d3458e45a7f4d873c963f10ac95149d5dcb4552c7` | `53059bd19ec1893b5ece340582542250ab19d845d5c659d007a7765ac673fab6` | `a48e69a0182570ce1a28311b61b400a150515de61c2f194a794474888f838c0a` | A!=B, B!=C |
| `lib/src/rust/api/query_metrics.dart` | `2ee1e6479fd4e8c6a2ea39ebb7838e88702832e1273b006a709d0cfeaaa81000` | `d138b9ab1cd2a3fe8d5e6f55ba89786c92adcf2fd70a3f80af6ccee70e91128f` | `d051b30d7c1d164e0cba186a88a732e1368ef148233d56467939d0fed5394dc0` | A!=B, B!=C |
| `lib/src/rust/api/semantic_chunker.dart` | `fb43d30c450aea9bac84d86aa6cba28fac337ae4a7888fa96b2e8f5fc1c0103f` | `8a4161f3398af9b05f8b98e9c6b7d884467c58309785d5fac563e9927b4f35a5` | `87b571e72fb37900de3d7b949707a473ef6c68ce1357de5afa7f790edbbc2c10` | A!=B, B!=C |
| `lib/src/rust/api/simple.dart` | `51adc251c272286424ccfbe57e5e6ec94c0dc3e17d4964938ac6699d03e1c74d` | `51adc251c272286424ccfbe57e5e6ec94c0dc3e17d4964938ac6699d03e1c74d` | `455b61d66428a9fb489b637d5f372c427e902a3267432628db6276e515fe417b` | A=B, B!=C |
| `lib/src/rust/api/simple_rag.dart` | `e28c2d36e0929fdbf5d280680eaa3e252320e1b5cefc39b93ac7403cfb6f007a` | `3c11d91ba6cdde440d3377f11b3d5f16f7f5ab58800c1ed5daffdec1aedbef61` | `9aa800082a8cf93e6f4202885d2b69b53b1782fb9b6551d5ba0e9a74853f9b95` | A!=B, B!=C |
| `lib/src/rust/api/source_rag.dart` | `eaaca31e1ecb3bea808f544fc3acf489f6deaa33b4542bd58e668a74501e0f11` | `61f3589a9b37f4164d3663c72a7b892bff18a84b64e781e4d238ebf9ad3bbcc4` | `5c5ee8b2403a048a56da0cf3a2ee2e95a132182b75a9c08089b12cf91ebb33fb` | A!=B, B!=C |
| `lib/src/rust/api/user_intent.dart` | `b8e14dbd0cfdd8fbce48ee8409957dd80b06d6a9dec8c6a2ecd015de2273b46b` | `b8e14dbd0cfdd8fbce48ee8409957dd80b06d6a9dec8c6a2ecd015de2273b46b` | `f008d76349870f17d382138f53cb536a8521d6547b559504f801c97a9e7a35fe` | A=B, B!=C |
| `lib/src/rust/api/vabq_config.dart` | `8fbf636d5367ef7f479c45c01604121dd6733675a0cc4f6342673933a8891b8b` | `8fbf636d5367ef7f479c45c01604121dd6733675a0cc4f6342673933a8891b8b` | `214db71d8d2c471070db1ba3fb8db58b1c15feb936c610391e0b5ff3ea24bb94` | A=B, B!=C |
| `lib/src/rust/frb_generated.dart` | `cd2336044a5c3dd58e0d8a42587d7314791554140805d999453a67c09ef0af12` | `cd2336044a5c3dd58e0d8a42587d7314791554140805d999453a67c09ef0af12` | `f62d9ca0748770b5ac54ca55eb289a590a29a8603d918c5c63eac17ab46c440c` | A=B, B!=C |
| `lib/src/rust/frb_generated.io.dart` | `a02958fb27c017cc6e949d95e62b186037de3e40c79564d26a0c19fc3fdbd48b` | `a02958fb27c017cc6e949d95e62b186037de3e40c79564d26a0c19fc3fdbd48b` | `f8ec70d62de60c7c1ebb080baedfad20d15256d83def8f07ed37eb6c29a6f68b` | A=B, B!=C |
| `lib/src/rust/frb_generated.web.dart` | `62bb418c4db9f8a5e22c0a2ee20ff9ad3263f1b43b0e89455b0ee39c67c310a4` | `62bb418c4db9f8a5e22c0a2ee20ff9ad3263f1b43b0e89455b0ee39c67c310a4` | `da9a44a44a62de6fe68699d93a3b5aff5707f11efdc95cfd846069b663d94b79` | A=B, B!=C |
| `rust_builder/rust/src/frb_generated.rs` | `b6ffa3f452904adc49c4653495bbfc95d8acb43aaad469494fff13c30351d987` | `b6ffa3f452904adc49c4653495bbfc95d8acb43aaad469494fff13c30351d987` | `541c1402802b87052db366c85d31e0bb323cb5d3b0beb5b94c35c89eda8377e5` | A=B, B!=C |

B differs from A in 13 Dart API wrappers.  The inspected
`lib/src/rust/api/hnsw_index.dart` diff additionally gains the missing public
`loadedHnswNodeCount` wrapper; the remaining wrapper diffs also require review
rather than being assumed safe formatting.  C modifies all 21 listed files,
and no C file matches B byte-for-byte.  The C blob IDs are not present in any
reachable commit, so this session cannot attribute them to a committed source
state; they are noncanonical for this HEAD regardless of whether they came from
an earlier generator run or manual edits.

## `loaded_hnsw_node_count` origin and ABI contract

The generator input is the tracked Rust function
`rust_builder/rust/src/api/hnsw_index.rs:231`.  `git blame` attributes its
documentation and implementation (lines 229–237) to `ffaddd49` (`feat(vabq):
checkpoint profile-aware storage research`, 2026-08-09 18:31:34 +0900).
That commit also introduced the current canonical generated contract.

In B, the Dart primary binding has
`crateApiHnswIndexLoadedHnswNodeCount`, and the generated Rust dispatcher maps
function ID `102` to `loaded_hnsw_node_count`.  Both B and A declare content
hash `-941343322`.  C omits this API/dispatcher and declares `-394558992` on
both its Dart and Rust generated files; its later dispatcher IDs are shifted.

This explains the apparent Rust result: B's Rust generated artifact is exactly
A because A already contains the source API, dispatcher, codec, function ID,
and `-941343322` hash.  C's Rust artifact is instead stale/noncanonical and
would not match a native library compiled from the current Rust input.  The
content-hash and function-ID changes are therefore contract-significant, not
formatting differences.  A clean native build used B successfully; substituting
C would reintroduce an incompatible Dart/native FRB contract.

## Clean candidate validation

| Check | Result |
| --- | --- |
| `flutter analyze lib test` | Pass — no issues. |
| `flutter test test/unit` | Pass — 69 tests. |
| `flutter test test` in `example/` | Pass — 24 tests. It printed 9 missing corpus/eval asset-directory diagnostics because a tracked-files-only archive excludes those directories; the test command still completed successfully. |
| `cargo test` | Fail — 159 passed, 25 failed, 10 ignored. Failures are existing Rust test isolation/state and VABQ-dimension/database assumptions (for example DB pool/table absence and active VABQ profile expecting 384 dimensions), not a generated-binding compile failure. Six existing compiler warnings were reported. |
| `flutter pub publish --dry-run` in `rust_builder/` | Pass — `rag_engine_flutter 0.20.0-dev.11`, 234 KB compressed archive, 0 package warnings. No actual publish occurred. |

The Rust failures mean this snapshot is not release-qualified; they do not turn
C into a valid input.  The dry-run is package-shape evidence only, not publish
authorization.

## Decision and next approval boundary

**B. The existing dirty generated files cannot be adopted as-is.** They contain
noncanonical changes beyond B, including removal of the source-backed HNSW API,
the old content hash, shifted IDs, and unrelated formatting/output drift across
all 21 generated files.

There is therefore **no approved dirty-file adoption list**. Do not stage any
of the C files. If the owner instead wants a separate, reviewed canonical
generation commit, a new implementation session must regenerate from the same
clean input and start by reviewing only these 13 B-vs-A files:

`lib/src/rust/api/bm25_search.dart`, `compression_utils.dart`, `db_pool.dart`,
`document_parser.dart`, `hnsw_index.dart`, `hybrid_search.dart`,
`incremental_index.dart`, `ingest_session.dart`, `migration_meta.dart`,
`query_metrics.dart`, `semantic_chunker.dart`, `simple_rag.dart`, and
`source_rag.dart` (all under `lib/src/rust/api/`). `hnsw_index.dart` is required
because it exposes the source-backed public wrapper; no Rust API source change
is required because it is already in `ffaddd4`/HEAD.

Before any later publish retry: (1) perform that separate review/adoption or
leave A intact by explicit decision, (2) archive the resulting committed HEAD,
(3) rerun canonical generation to zero diff, (4) resolve the 25 Rust test
failures, (5) rerun analyze/unit/example/cargo/dry-run, and only then request a
separate publish approval. Push, PR, merge, tag, yank, and any pub publish are
outside this session and were not performed.
