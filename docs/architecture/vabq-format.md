# VABQ packed-vector format

This document defines the on-disk VABQ format used by the Rust retrieval
engine. It is an execution format, not a claim about retrieval quality.

## Current format: tag `0x02`, version `0x01`

Each blob starts with a five-byte header:

| Byte range | Field | Meaning |
| --- | --- | --- |
| `0` | tag | `0x02` identifies VABQ |
| `1` | format version | `0x01` for the self-describing format |
| `2..4` | dimension | little-endian `u16` |
| `4` | variance-profile id | `1`: all-MiniLM-L6-v2 / 384, `2`: all-mpnet-base-v2 / 768, `3`: BGE-M3 / 1024, `4`: BGE-base-en-v1.5 / 768 |

The header is followed by the high-variance INT8 blocks, then the
low-variance INT4 blocks. Each block is stored as a little-endian `f32` scale
followed by its quantized values. High blocks have 16 INT8 values; low blocks
have up to 64 values packed as two signed INT4 values per byte.

Current serialized lengths are 421 bytes (384), 789 bytes (both 768-dim
profiles), and 1109 bytes (1024). `bgeBaseEnV15` is a separate profile ID
(`4`), not an alias for `allMpnetBaseV2` (`2`) despite their shared dimension.
The reader rejects a header whose dimension and profile id do not agree, and a
query only scores a blob with the same profile id.

## Compatibility and migration

Readers continue to accept the historical headerless formats:

| Length | Interpretation |
| --- | --- |
| 397 | legacy 384-dim VABQ; its final 32 low-variance dimensions were not stored |
| 417 | pre-header, full 384-dim VABQ |
| 785 | pre-header 768-dim VABQ |
| 1105 | pre-header 1024-dim VABQ |

New writes always use the versioned header. Rebuild/re-ingest is required to
replace a 397-byte blob; its omitted tail cannot be reconstructed. Headerless
417/785/1105 blobs remain readable and can be rewritten on the next re-ingest.
Unknown dimensions do not enter MMAP HNSW persistence; the save operation
returns an error rather than creating an index that its VABQ query kernel cannot
score.

`research/vabq/production_format.py` is a deliberately separate verification
codec, not the research evaluator's storage layer. It implements this header,
fixed Rust profile permutation, block scales, and low-nibble-first packing.
`test/fixtures/vabq/canonical-v1.json` contains deterministic 384/768/1024
vectors, expected packed bytes, decoded-f32 hashes, and kernel self-cosines.
Both the Rust and Python fixture tests must pass before this format changes.
