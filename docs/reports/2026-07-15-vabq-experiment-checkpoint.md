# VABQ Experiment Checkpoint: Production Correctness Proven, Performance Advantage Unproven

Date: 2026-07-15
Audience: `mobile_rag_engine` maintainers and benchmark reviewers
Package snapshot: `mobile_rag_engine 0.21.0-dev.10`, `rag_engine_flutter 0.20.0-dev.10`
Evidence window: retained research, package, and `local-gemma-macos` artifacts through 2026-07-13

## Technical summary

This checkpoint separates three questions that had previously been mixed together:

1. Does production VABQ have a real, model-specific persisted format rather than silently using Q8?
2. Does it preserve retrieval quality while reducing stored vector payload?
3. Does it improve end-to-end indexing, search latency, or process memory relative to Q8?

The current evidence answers the first two questions positively and the third negatively or inconclusively.

- Production correctness is established. Versioned VABQ records are written, reloaded, scored from persisted VEC/HNSW storage, and rejected on profile mismatch. BGE-base-en-v1.5 has a dedicated calibrated profile, Rust profile ID `4`, dimension `768`, high/low layout `512/256`, and fingerprint `f32+vabq:bgeBaseEnV15`. Q8 fallback is not accepted as VABQ success.
- Retrieval quality is effectively preserved in the controlled production-path measurements. The strongest BGE-M3 comparison recorded identical Hit@10 `92.0%` and macro Recall@10 `91.25%` for current Q8 and current VABQ. MiniLM also produced the same Hit@1/5/10 and Recall@10 across Q8/VABQ/Q8.
- Quantized payload is smaller, but the reduction is modest: `2.55%` for MiniLM 384d, `8.68%` for BGE-base 768d, and `3.73%` for BGE-M3 1024d. Persisted HNSW file reductions observed in the model-specific runs were approximately `1.7%`, `7.0%`, and `3.2%`, respectively.
- A repeatable search-speed advantage has not been established. In the official counterbalanced BGE-M3 comparison, VABQ mean search was `2.12%` slower than current Q8. A separate warm BGE-M3 pair showed VABQ about `4.4%` faster, so the direction changes across runs. MiniLM variance was much larger than the codec difference.
- Indexing and rebuild are at practical parity. The official BGE-M3 averages showed VABQ ingestion `0.52%` faster and rebuild `2.71%` slower. These differences are too small to support a product claim.
- A process-memory advantage has not been demonstrated. VABQ RSS was similar to or higher than the available Q8 controls. Persisted payload savings must not be relabeled as RSS savings.
- All current-profile results are local path builds with `release_comparable=false`. They are technical validation artifacts, not released-package or mobile-device performance claims.

The appropriate checkpoint decision is:

> Keep VABQ as a production storage/profile capability because its format, persistence, quality preservation, and modest payload reduction are demonstrated. Freeze claims that VABQ is faster or uses less process memory than Q8 until an isolated kernel experiment and repeated same-binary end-to-end experiment establish those effects.

## Reproduction baseline and checkpoint status

This is a local research checkpoint, not a release candidate. Its retained
artifacts were collected from local-path builds and therefore remain
`release_comparable=false`. The exact checks that protect this source baseline
are:

```sh
flutter analyze
flutter test test/unit
flutter test test/native
flutter test example/test/profiling/vabq_measurement_config_test.dart
cargo test --manifest-path rust_builder/rust/Cargo.toml --lib -- --test-threads=1
python3 research/vabq/test_production_format.py
```

For a new measurement, select the profile explicitly rather than inferring it
from the ONNX file or its dimension, for example:

```sh
flutter drive --dart-define=VABQ_PROFILE=bgeBaseEnV15 \
  --dart-define=DOCS_PER_COLLECTION=5000 \
  --target=integration_test/query_profile_measure_test.dart
```

The comparison contract remains `Q8_0 -> VABQ -> Q8_0` with one commit,
native binary, device, corpus bytes, model, query set, HNSW/BM25/RRF settings,
and preserved manifests. Do not compare a changed workload, a profile that
falls back to Q8, or a different native binary as a VABQ speed or RSS result.

## Evidence classes and comparison rules

The retained artifacts do not all answer the same question. This report uses the following evidence classes.

| Class | Evidence | What it can establish |
|---|---|---|
| A | BGE-M3 `A B C C B A` MS MARCO matrix, matching model/tokenizer/corpus/query contract | Controlled current-Q8 versus current-VABQ quality, payload, and local end-to-end timing |
| B | MiniLM Q8/VABQ/Q8, BGE-base dedicated VABQ, additional BGE-M3 Q8/VABQ/Q8 runs | Model coverage, format correctness, quality direction, storage size, and performance hypotheses |
| C | Python research evaluator and native microbenchmarks | Algorithm exploration or isolated kernel context; not production-path performance proof |
| Quarantined | Contaminated early current run, misnamed version artifacts, altered workload experiments | Failure analysis only; excluded from performance aggregation |
| Adjacent | Migration/rollback probes and Qdrant diagnostics | Lifecycle or backend diagnostic evidence; not VABQ-versus-Q8 codec evidence |

No single aggregate chart is included. The experiments have different models, dimensions, binaries, run order, lifecycle state, and measurement surfaces; normalizing them into one chart would imply comparability that the artifacts do not support. Exact tables retain those boundaries.

## Scope and metric definitions

The hardened production-path MS MARCO workload uses:

- 10,000 documents
- 13,588 chunks for the fixed 500-character, 30-character-overlap workload
- 200 queries
- top-K `10`
- vector/BM25 RRF weights `0.2/0.8`
- profile-mode macOS execution
- persisted VEC and HNSW validation before the full run
- clear/reload and vector-positive search gates

Metrics in this report mean:

- `Hit@K`: fraction of queries with at least one relevant passage in the first K results.
- `macro Recall@10`: average per-query relevant-passage recall at K=10.
- `MRR@10`: reciprocal rank of the first relevant result, averaged over queries.
- `Mean/P50/P95 search`: end-to-end measured query path in the sample harness. It is not an isolated quantized dot-product kernel benchmark.
- `Blob`: encoded quantized payload bytes per stored vector.
- `HNSW bytes`: persisted graph/index artifact size. It includes more than the quantized vector payload.
- `RSS`: sampled resident process memory. It includes the model runtime, graph, file-backed pages, allocators, and application state; it is not equivalent to encoded vector bytes.

At 200 queries, one query changes a hit-rate aggregate by `0.5 percentage points`. The workload is suitable for regression discovery but too small for a narrow non-inferiority claim without a larger query set or repeated paired analysis.

## The strongest controlled result shows quality and payload parity, not speed improvement

The official BGE-M3 matrix used exact `0.20.0` Q8 as arm A, current Q8 as arm B, and current VABQ as arm C in `A1 B1 C1 C2 B2 A2` order. The direct VABQ decision is B versus C because those arms share the current package generation and model contract.

| Two-run average | Current Q8 (B) | Current VABQ (C) | VABQ versus Q8 |
|---|---:|---:|---:|
| Index total | 2,500.21 s | 2,488.94 s | `-0.45%` |
| Ingestion | 2,447.95 s | 2,435.26 s | `-0.52%` |
| Rebuild | 52.26 s | 53.68 s | `+2.71%` |
| Mean search | 122.37 ms | 124.97 ms | `+2.12%` |
| P50 search | 122.01 ms | 122.36 ms | `+0.29%` |
| P95 search | 126.95 ms | 135.83 ms | `+7.00%` |
| Hit@10 | 92.0% | 92.0% | equal |
| Macro Recall@10 | 91.25% | 91.25% | equal |
| MRR@10 | 0.46409 | 0.46692 | `+0.00283` |
| Quantized blob | 1,152 B | 1,109 B | `-3.73%` |

The B runs were stable at `122.34-122.39 ms` mean search. The C runs ranged from `121.32` to `128.61 ms`, including a C2 maximum of `311.73 ms`. In the first adjacent ordering VABQ was faster for 162 of 200 queries; in the reversed ordering it was faster for only 29. Run order and tail variation were larger than the measured codec effect.

This result supports the claim that BGE-M3 VABQ preserves quality with a smaller payload. It does not support claims that VABQ accelerates search, indexing, or rebuild.

## Cross-dimension production evidence is consistent on quality and inconsistent on speed

### 384d MiniLM: exact quality parity, small storage reduction, unstable timing

| Metric | Q8 A1 | VABQ B1 | Q8 A2 |
|---|---:|---:|---:|
| Total indexing | 375.70 s | 345.38 s | 270.73 s |
| Mean search | 35.70 ms | 39.25 ms | 13.83 ms |
| P50 search | 34.68 ms | 38.16 ms | 8.31 ms |
| Hit@1/5/10 | 30/77/92% | 30/77/92% | 30/77/92% |
| Macro Recall@10 | 91.25% | 91.25% | 91.25% |
| Blob | 432 B | 421 B | 432 B |
| HNSW file | 8,736,944 B | 8,589,204 B | 8,740,876 B |

The VABQ blob is `2.55%` smaller and the HNSW file is approximately `1.7%` smaller than the mean Q8 file. Search timing does not show a VABQ advantage: Q8 itself changed from `35.70` to `13.83 ms`. The dominant signal is run-state variation, not quantizer selection.

An earlier standalone MiniLM VABQ run reported a much lower P50, but it is not part of the controlled sequence and is not used for the conclusion.

### 768d BGE-base: dedicated format proven, performance comparison not isolated

The dedicated BGE-base VABQ full run processed all 10,000 documents and 200 queries with:

- 13,588 VEC records and 13,588 HNSW nodes
- profile ID `4`
- header `02 01 00 03 04`
- blob size `789 B`
- persisted reload success
- Hit@10 `87.5%`, macro Recall@10 `87.0%`, MRR@10 `0.42566`

The corrected historical Q8 baseline used the same model/tokenizer hashes and workload, with blob `864 B`, Hit@10 `86.5%`, macro Recall@10 `86.0%`, and MRR@10 `0.43099`.

| Storage metric | Historical Q8 | Dedicated VABQ | Difference |
|---|---:|---:|---:|
| Blob | 864 B | 789 B | `-8.68%` |
| HNSW file | 14,613,680 B | 13,594,634 B | `-6.97%` |
| VEC file | 16,777,216 B | 16,777,216 B | unchanged preallocation |

The historical Q8 and dedicated VABQ runs used different native `__TEXT,__text` hashes. The package and harness had changed between them. Their large indexing and latency differences therefore cannot be attributed to VABQ. The valid conclusions are format/persistence success, quality proximity, and storage reduction.

The three-document BGE-base preflight additionally proved that every VEC/HNSW record was VABQ profile ID `4`, persisted reload completed, and a vector-only search returned positive vector ranks. This is the direct evidence that Q8 fallback did not satisfy the VABQ gate.

### 1024d BGE-M3: a warm pair suggests a small gain, but the official matrix reverses it

An additional Q8/VABQ/Q8 sequence produced a warm VABQ B2 versus Q8 A2 comparison:

| Metric | VABQ B2 | Q8 A2 | VABQ versus Q8 |
|---|---:|---:|---:|
| Total indexing | 2,382.02 s | 2,352.36 s | `+1.26%` |
| Mean search | 114.67 ms | 119.92 ms | `-4.38%` |
| P50 search | 114.42 ms | 119.72 ms | `-4.43%` |
| Hit@10 | 92.0% | 92.0% | equal |
| Macro Recall@10 | 91.25% | 91.25% | equal |
| Blob | 1,109 B | 1,152 B | `-3.73%` |
| HNSW file | 17,936,718 B | 18,523,288 B | `-3.17%` |

The first Q8 A1 in that sequence was much slower: `5,982 s` total indexing and `733 ms` mean search. Because VABQ B2 and Q8 A2 converged while A1 was the outlier, A1 primarily records cold/run-state cost rather than Q8 codec cost.

The approximately `4.4%` warm-pair signal is not independently repeatable: the stronger two-run official matrix measured VABQ `2.12%` slower on mean search. The combined conclusion is steady-state parity within the current run variance.

## Persisted payload savings have not translated into lower RSS

The retained model-specific runs do not show a process-memory benefit:

- MiniLM VABQ search peak was about `395.36 MB`; Q8 peaks were about `374.81 MB` and `394.89 MB`.
- BGE-M3 VABQ B2 search peak was about `1,613.73 MB`; warm Q8 A2 was about `1,568.53 MB`.
- BGE-base VABQ search peak was about `549.34 MB`; the historical Q8 run was about `504.16 MB`, but that pair is not same-binary comparable.

These values do not prove that VABQ inherently increases memory. They prove only that an RSS reduction is not visible at the current workload and measurement resolution. Model weights, ONNX Runtime state, HNSW adjacency, allocators, and file-backed residency are much larger than the few-percent encoded-payload delta.

The `.vec` files also use capacity preallocation. An unchanged 16 MiB file does not mean the logical record is unchanged, and a smaller logical blob does not guarantee a smaller allocated file. Future storage reporting must separate logical payload, written length, allocated blocks, HNSW graph bytes, SQLite/WAL, and stale artifacts.

## Research simulation supports exploration, not the current product claim

The Python research evaluator and the production codec are different evidence surfaces. The evaluator is useful for recall/storage exploration, but its Python latency cannot be projected onto the Rust persisted scorer.

Representative 384d research results were:

| Dataset/method | Bytes/vector | Recall@10 | Mean evaluator latency |
|---|---:|---:|---:|
| Synthetic Q8_0 block 32 | 432 | 0.9907 | 11.33 ms |
| Synthetic VABQ 288 high / 96 low, block 32 | 380 | 0.9857 | 41.26 ms |
| Synthetic legacy uniform Q8 | 384 | 0.9787 | 12.16 ms |
| MS MARCO Q8_0 block 32 | 432 | 0.9984 | 37.44 ms |
| MS MARCO VABQ 288 high / 96 low, block 32 | 380 | 0.9836 | 202.50 ms |
| MS MARCO VABQ 345 high / 39 low, block 32 | 413 | 0.9904 | 204.41 ms |

On synthetic data, one VABQ configuration improved recall over the legacy uniform-Q8 control while using approximately the same bytes, but it did not exceed Q8_0. In the retained MS MARCO research artifact, Q8_0 had higher recall than the tested VABQ configurations. The artifact also lacks enough run provenance to support a production benchmark claim.

This is a negative but useful result: variance-aware bit allocation has not yet demonstrated superiority to Q8_0 at the same byte budget on the retained MS MARCO research evaluator. The next research comparison must include a same-byte uniform control, a random-permutation control, and exact-f32 score/rank error rather than relying only on end-to-end Hit/Recall.

## The BGE-base profile has real calibration provenance, with a generalization limitation

The checked-in BGE-base calibration binds the profile to:

- model family `BAAI/bge-base-en-v1.5`
- model SHA-256 `4e8fae771f7050180b28e694455d7f6f5aaaabeaba9fdf8be1bc364eb53ea83b`
- tokenizer SHA-256 `be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037`
- 10,000 MS MARCO passages
- corpus SHA-256 `554ede24d6f618f0756027105a80ed1adee71f27357832052e17178dff5fd783`
- a complete dedicated 768-dimension permutation

The production contract is not an alias of the 768d MPNet profile. The canonical fixture independently identifies BGE-base with profile ID `4`, header `0201000304`, encoded size `789 B`, and self-cosine `0.999139369` after decode.

The calibration corpus SHA matches the retained 10k MS MARCO benchmark corpus. This is appropriate for in-domain production validation, but it is not a held-out generalization test. It can hide profile degradation on another corpus or on query embeddings whose distribution differs from passage embeddings.

Also, the production profile is model/corpus-adaptive but not per-vector dynamic. It uses one fixed calibrated permutation and a coarse `512 high / 256 low` allocation for every BGE-base vector. A flat variance spectrum, query/passage distribution mismatch, covariance-dominated information, or high-variance but retrieval-irrelevant common directions can all reduce the expected advantage.

## Production persistence and migration are functional, with lifecycle work remaining

The available persistence evidence includes:

- versioned VABQ encode/decode and canonical cross-language fixtures
- persisted VEC scoring and HNSW save/load for MiniLM, BGE-base, and BGE-M3 profiles
- dimension and profile-ID mismatch rejection
- active-profile rejection of Q8 blobs rather than silent fallback
- BGE-M3 three-document Q8-to-VABQ re-embedding followed by successful search
- restart with fingerprint `model.onnx|1024|f32+vabq:bgeM3`, no lock, and three persisted search results
- interrupted migration/resume and exact-0.20.0 rollback recovery in the retained migration matrix

The July 12 migration artifact also recorded a `clearAllData()` failure: an in-process fingerprint lock remained, legacy HNSW files survived, and an empty current VEC file remained. This report does not revalidate whether subsequent package work fixed that issue. Until a fresh focused check says otherwise, it remains an unresolved lifecycle item rather than a closed result.

The migration probes used three documents. They establish state-machine behavior, not 10k migration time, peak temporary disk usage, power-loss safety, low-disk behavior, or mobile lifecycle robustness.

## Historical and contaminated results that must not be reused

### Early current MS MARCO run

An early benchmark used a `.db` database name while native code derived the VEC path through a literal `.sqlite -> .vec` replacement. SQLite and vector paths collided; all 13,588 chunks had empty vector storage, no persistent HNSW existed, and retrieval was effectively BM25-only with repeated activation/rebuild attempts.

Its latency, quality, indexing, and RSS values are excluded from all VABQ conclusions.

### Misnamed version result

The artifact named `benchmark_results_current-0.18.3.json` actually resolved `mobile_rag_engine 0.18.6` and `rag_engine_flutter 0.18.4`. It is not a `0.18.3` result.

### Changed-workload experiment

`current-exp-d-4` used vector/BM25 weights `0.5/0.5` and produced 24,742 chunks rather than the fixed 13,588. It is a tuning experiment and is not included in codec comparisons.

### Historical performance report

`VABQ_PERFORMANCE_REPORT.md` contains useful native microbenchmark context, including sub-10-microsecond per-comparison numbers on an iPad 10. It compares an isolated native quantized scorer with broad f32/Python baselines and makes memory/OOM/marketing claims that the current production experiments do not establish.

In particular, a roughly 75% reduction from f32 is a quantized-versus-f32 statement, not a VABQ-versus-Q8 advantage. The file must not be cited as proof that production VABQ is faster, safer, or lower-RSS than production Q8.

### Qdrant diagnostic

The Qdrant D1/D2 diagnostic observed similar quality and lower same-process warm latency than a current-Q8 anchor, but candidate pools differed and public close/reopen returned zero records. It remains useful backend diagnostic evidence, not VABQ evidence or production-readiness proof.

## Why a theoretically useful variance-aware scheme can look neutral here

The current results are compatible with the theory; they do not yet isolate its expected benefit.

1. The theoretical benefit is lower distortion at a fixed bit budget. Most production comparisons use Q8_0 as the baseline, which is already high fidelity, while VABQ saves only `2.5-8.7%` of blob bytes.
2. BGE-base keeps two thirds of dimensions in the high group. Even under a fully memory-bandwidth-bound scorer, an `8.7%` payload reduction puts a small upper bound on end-to-end improvement before decode overhead.
3. End-to-end search includes query embedding, graph traversal, random memory access, BM25, RRF, and result materialization. VABQ changes only part of that path.
4. Marginal variance is not retrieval importance. High-variance common directions may contribute little to relevant-versus-irrelevant separation, while lower-variance directions may be discriminative.
5. A fixed global permutation cannot adapt to each vector, and passage-only calibration may not match query embeddings.
6. Cold page faults, model/runtime initialization, foreground churn, and run order have already produced differences larger than the codec effect.

The important distinction is whether variance is spatially scattered or spectrally flat. Scattered high-variance coordinate positions are not a problem because the permutation groups them. A flat sorted variance spectrum, weak top-versus-bottom separation, or covariance/relevance structure not captured by marginal variance would directly reduce the value of the current high/low allocation.

## Recommended next experimental branch

The next phase should stop adding long end-to-end runs until the codec mechanism is isolated.

### Gate 1: determine whether the calibrated permutation beats controls

Use precomputed f32 query/document embeddings and a fixed candidate matrix. Compare:

- exact f32
- production Q8_0
- production VABQ
- a uniform quantizer constrained to the same bytes as VABQ
- VABQ layout with a deterministic random permutation
- VABQ layout with reversed high/low importance as a negative control

Record encoded bytes, encode/decode time, warm `ns/vector`, score MAE/P95/P99 versus f32, top-K rank flips, and recall against the exact-f32 top-K. If calibrated VABQ does not beat same-byte uniform and random-permutation controls, the current variance ranking is not adding measurable retrieval value.

### Gate 2: measure whether the variance signal is usable

For passages and queries separately, record:

- sorted per-dimension variance and second moment
- top-group variance share; for BGE-base, compare top-512 share with the uniform reference `66.7%`
- top/bottom mean ratio, coefficient of variation, and Gini coefficient
- query/document importance-rank correlation
- positive-versus-negative dot-product contribution by dimension
- covariance or PCA concentration where marginal variance is insufficient

Run the analysis on the calibration corpus and on at least one held-out corpus. The exact MS MARCO calibration corpus must not be the only evaluation set.

### Gate 3: repeat same-binary end-to-end measurements only after kernel evidence

Build one native binary that selects Q8 or VABQ through the public profile API. Separate:

- cold A1: fresh equivalent cache/process state
- warm A2: explicit model, query, index, and scorer warmup before timing

Use counterbalanced orders such as Q8/VABQ and VABQ/Q8, at least five repetitions per warm arm, paired query deltas, medians, dispersion, and confidence intervals. Record page faults, foreground state, thermal/power state, and stage timings for embedding, HNSW candidate/scoring, BM25, and merge.

### Gate 4: measure storage and memory at the correct layers

Report separately:

- logical quantized bytes per vector
- VEC written length and allocated filesystem blocks
- HNSW vector payload and graph/adjacency bytes
- SQLite, WAL, and migration temporary bytes
- stale legacy artifacts
- RSS plus anonymous/private/file-backed mappings

This prevents logical payload savings from being mistaken for file-size or process-memory savings.

### Gate 5: close lifecycle and device coverage

- Revalidate `clearAllData()` in one process and after restart.
- Run a 10k Q8-to-VABQ migration soak with interruption, low-disk, peak disk, and peak RSS evidence.
- Repeat the final controlled experiment on at least one iOS and one Android device before making mobile product claims.
- Add the missing full MPNet 768d control or explicitly drop it from the supported performance matrix.

## Decision criteria for the next checkpoint

Use the isolated results to choose one of three paths.

| Observation | Decision |
|---|---|
| VABQ beats same-byte uniform/random controls and the kernel is faster, but end-to-end is neutral | Keep VABQ and optimize the surrounding search/embedding path; do not blame the codec |
| VABQ improves rank fidelity or storage but not kernel speed | Position VABQ as a quality-per-byte/persistence option, not a latency optimization |
| VABQ does not beat same-byte uniform/random controls | Revisit variance scoring, query-aware calibration, layout, or a learned/rotated importance basis before more product benchmarks |

A search-speed claim should require a stable same-direction improvement across counterbalanced warm repetitions, with the interval excluding zero and no material quality loss. A memory claim should require lower measured mappings/RSS, not only a smaller blob. A release claim requires hosted/released binaries and `release_comparable=true`.

## Open questions

- How concentrated is the BGE-base sorted variance spectrum, especially the top-512 share relative to `66.7%`?
- Does passage-derived importance correlate with BGE query embeddings and relevant-versus-irrelevant score contribution?
- Is marginal variance the correct objective, or would second moment, quantization sensitivity, covariance rotation, or retrieval-labeled importance perform better?
- How much of end-to-end latency is query embedding versus HNSW scoring for each model dimension?
- Is the July 12 `clearAllData()` lifecycle defect fixed in the current checkout?
- Does the payload reduction become material at larger collections where vector bytes dominate model/runtime memory?
- Do mobile memory bandwidth and cache sizes produce a stronger effect than the current macOS runs?

## Evidence inventory

Package repository:

- `research/vabq/results/eval_results.json`
- `research/vabq/results_msmarco/eval_results.json`
- `research/vabq/calibration/bge-base-en-v1.5.json`
- `test/fixtures/vabq/canonical-v1.json`
- `test/native/vabq_bench_test.dart`
- `test/unit/vabq_profile_config_test.dart`
- `VABQ_PERFORMANCE_REPORT.md`

External sample evidence root:

```text
/Users/dev_bh/Desktop/toys/samples/local-gemma-macos
```

Primary documents and artifacts:

- `docs/benchmarks/2026-07-11-msmarco-contamination-audit.md`
- `docs/benchmarks/2026-07-12-vabq-msmarco-benchmark-summary.md`
- `docs/benchmarks/2026-07-13-qdrant-msmarco-comparison.md`
- `benchmark_manifest_abc-guard.json`
- `benchmark_results_current-local-bge-m3-q8_abc-guard-b1.json`
- `benchmark_results_current-local-bge-m3-q8_abc-guard-b2.json`
- `benchmark_results_current-local-bge-m3-vabq_abc-guard-c1.json`
- `benchmark_results_current-local-bge-m3-vabq_abc-guard-c2.json`
- `benchmark_results_current-local-minilm-q8_minilm-q8-a1.json`
- `benchmark_results_current-local-minilm-vabq_minilm-vabq-b1.json`
- `benchmark_results_current-local-minilm-q8_minilm-q8-a2.json`
- `benchmark_preflight_current-local-bge-base-vabq_bge-vabq-preflight-5.json`
- `benchmark_results_current-local-bge-base-vabq_bge-vabq-full-5.json`
- `benchmark_migration_current_vabq_reembed.json`
- `benchmark_migration_current_vabq_restart.json`

This report was assembled from retained artifacts without rerunning long benchmarks. Current working-tree state, unresolved lifecycle defects, and released-package comparability require separate fresh verification before publication.
