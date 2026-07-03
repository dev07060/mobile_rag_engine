# Mimalloc Allocator A/B Results

Status: feature-gated candidate, not default-enable.

## Scope Correction

The current allocator indexing macro is text-scale based:

- `ALLOCATOR_INDEXING_TEXT_MB=5,10,25`
- 500-char generated chunks.
- 30-char overlap metadata.
- 384-dim stub embeddings.

That maps to 10k/20k/50k generated chunks. Older run artifacts in this folder
used a legacy `docs` field with 32-dim embeddings and roughly 50-byte synthetic
chunks. In those older artifacts, `docs` means chunk/vector-point count, not
source-document count.

## Decision

Keep `allocator_mimalloc` behind a feature gate. The repeated iOS and macOS
legacy macro runs show a consistent rebuild-time win, but peak RSS rises with
mimalloc and those runs used the older 32-dim synthetic corpus.

Do not default-enable mimalloc until the current realistic macro has paired
physical-device results:

- 5/10/25 MB text scale, mapping to 10k/20k/50k chunks.
- Physical iOS and Android profile runs.
- Warm query/search/hydrate regression guard.

## Legacy Repeated Indexing Macro Medians

Each row uses 5 runs per variant. These are legacy synthetic runs retained as
allocator-pressure evidence, not final product-scale evidence.

### iPad 10, iOS 26.5

Run folder:
`docs/perf/mimalloc-allocator-ab/runs/ios-ipad10-repeat-20260629-034322/`

| Chunks | System total ms | Mimalloc total ms | Delta | System peak RSS MiB | Mimalloc peak RSS MiB | Peak delta |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 1345.418 | 1158.844 | -13.9% | 83.66 | 94.50 | +13.0% |
| 20,000 | 3816.418 | 3217.003 | -15.7% | 113.55 | 133.63 | +17.7% |
| 50,000 | 10483.004 | 8393.048 | -19.9% | 182.02 | 218.25 | +19.9% |

### macOS

Run folder:
`docs/perf/mimalloc-allocator-ab/runs/macos-repeat-20260629-032925/`

| Chunks | System total ms | Mimalloc total ms | Delta | System peak RSS MiB | Mimalloc peak RSS MiB | Peak delta |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 1006.692 | 881.308 | -12.5% | 139.11 | 146.61 | +5.4% |
| 20,000 | 2997.313 | 2796.225 | -6.7% | 175.25 | 181.44 | +3.5% |
| 50,000 | 7975.187 | 6565.609 | -17.7% | 253.64 | 268.45 | +5.8% |

## Interpretation

The timing win is concentrated in HNSW rebuild. That makes mimalloc a valid
candidate for activation/indexing/reindexing pressure, but the RSS tradeoff is
real enough that the branch should not convert it into a default release choice
yet.

The safer near-term optimization is to reduce peak allocation in the rebuild
pipeline itself instead of relying only on allocator behavior.

### HNSW Streaming Platform Gate

The realistic system-allocator HNSW A/B changed the HNSW streaming conclusion:
it is not a universal package optimization.

Benchmark shape: 384-dim f32 stub embeddings, 500-char chunks, 10k/20k/50k
chunk counts, five-run median, app/profile mode, system allocator only.

macOS matched the expected memory model. Removing the intermediate
`Vec<(i64, Vec<f32>)>` lowered peak RSS by 4.5% / 5.4% / 8.6% at
10k / 20k / 50k chunks, with runtime neutral to slightly better.

iPad 10 did not match that model. Streaming was slower by 10.4% / 1.5% / 7.4%
and peak RSS increased at all measured scales, including a 50k peak increase
from 740.9 MiB to 821.9 MiB. Treat this as platform-specific interaction among
row iteration, blob decode, per-row allocation, HNSW insertion timing, allocator
retention, SQLite/cache accounting, and iOS RSS sampling.

Decision: keep HNSW streaming as a macOS default memory-pressure optimization
and as an opt-in experiment elsewhere via the `hnsw_streaming_rebuild` Rust
feature. Keep iOS, Android, and other unvalidated targets on the existing
collect-based rebuild path by default. Do not describe HNSW streaming as a
mobile-wide or package-wide improvement.

## Safe Optimization Shortlist

1. Keep HNSW rebuild streaming platform-gated.
   macOS can stream rows by default because the realistic system-allocator A/B
   showed lower peak RSS. iOS, Android, and unvalidated targets should keep the
   collect-based path unless `hnsw_streaming_rebuild` is explicitly enabled for
   an experiment.

2. Stream BM25 rebuild rows instead of collecting `Vec<(i64, String)>`.
   Add each document to the in-memory BM25 index as rows are read from SQLite.

3. Reduce BM25 tokenization allocation.
   Build per-document term frequencies without first materializing a full
   `Vec<String>` and then cloning tokens into a second map.

4. Run the current realistic indexing macro.
   The harness now emits text scale, chunk count, 500-char chunk size, 384-dim
   embedding payload, allocator label, feature label, rebuild timings, and RSS.

5. Evaluate SQLite PRAGMAs as a separate track.
   `mmap_size`, `cache_size`, `temp_store`, WAL, and checkpoint behavior should
   be A/B tested separately. Do not wire a SQLite custom allocator to mimalloc
   in this branch; it is process-global and higher risk on Apple platforms.
