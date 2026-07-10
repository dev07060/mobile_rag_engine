import sys

def main():
    with open("rust_builder/rust/src/api/hnsw_index.rs", "r") as f:
        content = f.read()

    # Update search_hnsw_slice
    old_search = '''pub fn search_hnsw_slice(
    query_embedding: &[f32],
    top_k: usize,
) -> anyhow::Result<Vec<HnswSearchResult>> {
    debug!("[hnsw] Starting search, top_k: {}", top_k);

    let index_guard = HNSW_INDEX.read().unwrap();
    let index = index_guard
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("HNSW index not initialized"))?;

    let ef_search = core::cmp::max(100, top_k * 5);
    debug!("[hnsw] Using ef_search={}", ef_search);

    let query_vabq = crate::api::vector_quant::QueryVABQ::new(query_embedding);
    let neighbors = index.search(&query_vabq, ef_search);

    let mut results: Vec<HnswSearchResult> = neighbors
        .into_iter()
        .map(|(id, distance)| HnswSearchResult {
            id,
            distance,
        })
        .collect();

    results.sort_by(|a, b| a.distance.partial_cmp(&b.distance).unwrap());
    results.truncate(top_k);

    debug!("[hnsw] Returning {} results", results.len());
    Ok(results)
}'''

    new_search = '''pub fn search_hnsw_slice(
    query_embedding: &[f32],
    top_k: usize,
) -> anyhow::Result<Vec<HnswSearchResult>> {
    debug!("[hnsw] Starting search, top_k: {}", top_k);

    let ef_search = core::cmp::max(100, top_k * 5);
    debug!("[hnsw] Using ef_search={}", ef_search);

    let mut neighbors = None;

    {
        let index_guard = HNSW_INDEX.read().unwrap();
        if let Some(index) = index_guard.as_ref() {
            let query_vabq = crate::api::vector_quant::QueryVABQ::new(query_embedding);
            neighbors = Some(index.search(&query_vabq, ef_search));
        }
    }

    if neighbors.is_none() {
        let builder_guard = HNSW_BUILDER.read().unwrap();
        if let Some(builder) = builder_guard.as_ref() {
            debug!("[hnsw] MMAP index not found, searching in-memory builder");
            neighbors = Some(builder.search(query_embedding, ef_search));
        }
    }

    let neighbors = neighbors.ok_or_else(|| anyhow::anyhow!("HNSW index not initialized (neither MMAP nor Builder)"))?;

    let mut results: Vec<HnswSearchResult> = neighbors
        .into_iter()
        .map(|(id, distance)| HnswSearchResult {
            id,
            distance,
        })
        .collect();

    results.sort_by(|a, b| a.distance.partial_cmp(&b.distance).unwrap());
    results.truncate(top_k);

    debug!("[hnsw] Returning {} results", results.len());
    Ok(results)
}'''
    content = content.replace(old_search, new_search)

    # Update is_hnsw_index_loaded
    old_is_loaded = '''pub fn is_hnsw_index_loaded() -> bool {
    let index_guard = HNSW_INDEX.read().unwrap();
    index_guard.is_some()
}'''
    new_is_loaded = '''pub fn is_hnsw_index_loaded() -> bool {
    let index_guard = HNSW_INDEX.read().unwrap();
    if index_guard.is_some() {
        return true;
    }
    let builder_guard = HNSW_BUILDER.read().unwrap();
    builder_guard.is_some()
}'''
    content = content.replace(old_is_loaded, new_is_loaded)

    with open("rust_builder/rust/src/api/hnsw_index.rs", "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()
