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

## Safe Optimization Shortlist

1. Stream HNSW rebuild rows instead of collecting `Vec<(i64, Vec<f32>)>`.
   Count rows first to size the HNSW index, then insert while iterating SQLite
   rows. This targets peak RSS directly.

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
