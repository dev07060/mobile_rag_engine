import sys

def main():
    with open("rust_builder/rust/src/api/source_rag.rs", "r") as f:
        content = f.read()

    # Restore inline rebuild in search_chunks_in_collection
    target = '''    if !is_hnsw_index_loaded() || !is_active_hnsw_collection(&collection_id) {
        debug!(
            "[search_chunks] HNSW index not loaded or different collection active for {}. Falling back to linear scan.",
            collection_id
        );
        return search_chunks_linear_in_collection(&collection_id, query_embedding, top_k);
    }'''

    replacement = '''    if !is_hnsw_index_loaded() || !is_active_hnsw_collection(&collection_id) {
        debug!(
            "[search_chunks] HNSW missing or different collection active. Rebuilding for {}",
            collection_id
        );
        rebuild_chunk_hnsw_index_for_collection(collection_id.clone())?;
    }

    if !is_hnsw_index_loaded() {
        debug!("[search_chunks] Falling back to linear scan (rebuild failed or yielded no points)");
        return search_chunks_linear_in_collection(&collection_id, query_embedding, top_k);
    }'''

    if target in content:
        content = content.replace(target, replacement)
    else:
        print("Target not found in source_rag.rs")
        sys.exit(1)

    with open("rust_builder/rust/src/api/source_rag.rs", "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()
