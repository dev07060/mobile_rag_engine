# Code Analysis: `src/api/source_rag.rs`

This file implements the **Advanced RAG Architecture**, creating a hierarchical "Source -> Chunk" relationship. This is critical for mobile RAG as it allows retrieving "context windows" (adjacent chunks) rather than just isolated text snippets.

| Line Range | Type     | Name                       | Technical Logic (Stack-Specific)                                                                                                                                     | Role in Mobile RAG                                                                                                                                                |
|:-----------|:---------|:---------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 19-58      | Function | `init_source_db`           | Executes `rusqlite` SQL to create `sources` (parent) and `chunks` (child) tables with `FOREIGN KEY` constraints.                                                     | Sets up the persistent relational schema for the on-device knowledge base.                                                                                        |
| 70-113     | Function | `add_source`               | Computes `SHA256` hash of content to prevent duplicates before insertion. Returns `AddSourceResult`.                                                                 | Specific Ingestion entry point. Handles deduplication to save mobile storage space.                                                                               |
| 127-164    | Function | `add_chunks`               | Uses `rusqlite::Transaction` for atomicity. Manually serializes `Vec<f32>` embeddings into `Vec<u8>` (BLOB) using `to_ne_bytes` to avoid overhead.                   | **Critical Path**: Efficiently writes batch embeddings to disk. The transaction ensures data integrity if the app crashes during sync.                            |
| 167-194    | Function | `rebuild_chunk_hnsw_index` | Reads **all** embeddings from SQLite, deserializes BLOBs to `f32`, and feeds them into `hnsw_index::build_hnsw_index`.                                               | **Memory Bottleneck**: Loads the entire vector dataset into RAM to build the search graph. High memory pressure risk on startup.                                  |
| 207-251    | Function | `search_chunks`            | Checks if the HNSW index is loaded (`is_hnsw_index_loaded`). If not, triggers a synchronous rebuild. Performs retrieval and joins results with SQL to fetch content. | The main retrieval entry point. The auto-rebuild logic implies the first search after launch will be significantly slower (cold start).                           |
| 253-305    | Function | `search_chunks_linear`     | Uses `ndarray::Array1` to calculate cosine similarity via dot product. Iterates through the entire SQL result set.                                                   | **Fallback Mechanism**: Ensures search works even if index build fails, but is O(N) and CPU-intensive. Valid only for small datasets (<1k chunks).                |
| 355-385    | Function | `get_adjacent_chunks`      | SQl query filtering by `source_id` and a `chunk_index` range.                                                                                                        | **Context Expansion**: Allows the LLM to see text *surrounding* the match, improving answer quality (e.g., retrieving the full paragraph of a matching sentence). |

### Summary

1.  **Core Responsibility:** Implements the persistent layer of the RAG engine, managing the lifecycle of Documents (Sources) and their Vector Embeddings (Chunks), and bridging the gap between disk storage (SQLite) and high-speed in-memory search (HNSW).
2.  **Mobile Optimization Check:**
    *   **Efficient:** Embedding storage as raw BLOBs (`Vec<u8>`) minimizes disk usage and serialization overhead compared to JSON.
    *   **Risk (Memory):** `rebuild_chunk_hnsw_index` loads *all* chunks into RAM at once. On a low-end Android device with a large knowledge base (e.g., 50k chunks), this could trigger an OOM (Out of Memory) crash.
    *   **Risk (Latency):** The synchronous call to `rebuild` inside `search_chunks` means the first search operation effectively blocks until the entire index is built. This should ideally be moved to an asynchronous background initialization task in Flutter.



RAG Engine Optimization Walkthrough
Goal
Resolve Memory (OOM) and Latency risks in the mobile RAG engine (rust/src/api/).

Changes
1. Library Replacement
Old: instant-distance.
Issue: Compilation failure in version 0.6.x (broken internal dependency on BigArray when serde enabled).
New: hnsw_rs (Version 0.3).
Benefit: Actively maintained, better features.
2. Memory Optimization (Implemented)
Refactored build_hnsw_index to consume the input vectors (Vec<Vec<f32>>) instead of cloning them.
Impact: Removes the need to hold 2x the dataset size in RAM during index construction. This significantly lowers the risk of OOM on mobile devices.
// Old (implicit clone in map)
let embedding_points: Vec<EmbeddingPoint> = points.iter().map(...).collect();
// New (move-based consumption without the extra clone)
for (id, embedding) in points {
    hwns.insert((&embedding, u_id)); // inserts owned/referenced slice
}
3. Latency Optimization (Persistence)
Goal: Save HNSW index to disk (.hnsw files) to avoid rebuilding on every app launch.
Status: Disabled.
Reason: hnsw_rs loading API (HnswIo::load_hnsw) returns a structure that borrows from the IO loader, which conflicts with the 'static lifetime required by the global static HNSW_INDEX.
Workaround: Code infrastructure for save/load is present but loading returns false, gracefully falling back to (optimized) in-memory rebuild.
Verification
Build: Passed (cargo build).
Dependencies: successfully updated Cargo.toml.
