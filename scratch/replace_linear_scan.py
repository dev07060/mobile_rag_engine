import sys

def main():
    with open("rust_builder/rust/src/api/source_rag.rs", "r") as f:
        content = f.read()

    start_idx = content.find("fn search_chunks_linear_in_collection(")
    end_idx = content.find("pub fn benchmark_search_chunks_linear_in_collection(", start_idx)

    if start_idx == -1 or end_idx == -1:
        print("Could not find function bounds.")
        sys.exit(1)

    new_function = '''fn search_chunks_linear_in_collection(
    collection_id: &str,
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<ChunkSearchResult>, RagError> {
    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let query_norm = l2_norm_f32(&query_embedding);

    #[cfg(feature = "vector_quant_i8")]
    let (query_i8, _query_i8_scale) = quantize_f32_to_i8(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let query_i8_norm = l2_norm_i8(&query_i8);
    #[cfg(feature = "vector_quant_i8")]
    let query_q8 = QueryQ8::new(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let query_vabq = QueryVABQ::new(&query_embedding);

    let mut stmt = match conn.prepare(
        "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, c.embedding_i8, s.metadata, c.mmap_id
         FROM chunks c
         JOIN sources s ON c.source_id = s.id
         WHERE c.collection_id = ?1
           AND COALESCE(s.status, 'completed') = 'completed'",
    ) {
        Ok(stmt) => stmt,
        Err(_) => conn
            .prepare(
                "SELECT c.id, c.source_id, c.chunk_index, c.content, COALESCE(c.chunk_type, 'general'), c.embedding, NULL AS embedding_i8, s.metadata, c.mmap_id
                 FROM chunks c
                 JOIN sources s ON c.source_id = s.id
                 WHERE c.collection_id = ?1
                   AND COALESCE(s.status, 'completed') = 'completed'",
            )
            .map_err(|e| RagError::DatabaseError(e.to_string()))?,
    };

    let rows = stmt
        .query_map(params![collection_id], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get::<_, Vec<u8>>(5)?,
                row.get::<_, Option<Vec<u8>>>(6)?,
                row.get(7)?,
                row.get::<_, Option<i64>>(8).unwrap_or(None),
            ))
        })
        .map_err(|e| RagError::DatabaseError(e.to_string()))?;

    let mut candidates = Vec::new();

    for row in rows {
        let (
            id,
            source_id,
            chunk_index,
            content,
            chunk_type,
            embedding_blob,
            embedding_i8_blob,
            metadata,
            mmap_id,
        ): (
            i64,
            i64,
            i32,
            String,
            String,
            Vec<u8>,
            Option<Vec<u8>>,
            Option<String>,
            Option<i64>,
        ) = row.map_err(|e| RagError::DatabaseError(e.to_string()))?;

        #[cfg(feature = "vector_quant_i8")]
        let mut sim_opt = None;

        #[cfg(feature = "vector_quant_i8")]
        if let Some(mid) = mmap_id {
            if mid > 0 && embedding_i8_blob.as_ref().map_or(true, |b| b.is_empty()) {
                let store = crate::api::mmap_store::MMAP_STORE.read().unwrap();
                if let Some(s) = store.as_ref() {
                    if let Some(data) = s.get(mid as usize) {
                        let qblob = data;
                        if !qblob.is_empty() && qblob[0] == 0x02 {
                            sim_opt = Some(cosine_similarity_vabq(&query_vabq, qblob) as f64);
                        } else if qblob.len() >= query_i8.len() + 4 && query_i8_norm > 0.0 {
                            sim_opt = Some(crate::api::vector_quant::cosine_with_query_norm_i8_blob(&query_i8, query_i8_norm, &qblob[4..]) as f64);
                        } else if !qblob.is_empty() && (qblob.len() == query_i8.len() || qblob.len() % 36 == 0) && query_i8_norm > 0.0 {
                            sim_opt = Some(cosine_similarity_q8(&query_q8, qblob, &query_i8, query_i8_norm) as f64);
                        }
                    }
                }
            }
        }

        #[cfg(not(feature = "vector_quant_i8"))]
        let _ = &embedding_i8_blob;
        #[cfg(not(feature = "vector_quant_i8"))]
        let _ = &mmap_id;

        #[cfg(feature = "vector_quant_i8")]
        let similarity = if let Some(sim) = sim_opt {
            sim
        } else if let Some(qblob) = embedding_i8_blob.as_deref() {
            if !qblob.is_empty() && qblob[0] == 0x02 {
                cosine_similarity_vabq(&query_vabq, qblob) as f64
            } else if qblob.len() >= query_i8.len() + 4 && query_i8_norm > 0.0 {
                crate::api::vector_quant::cosine_with_query_norm_i8_blob(&query_i8, query_i8_norm, &qblob[4..]) as f64
            } else if !qblob.is_empty() && (qblob.len() == query_i8.len() || qblob.len() % 36 == 0) && query_i8_norm > 0.0 {
                cosine_similarity_q8(&query_q8, qblob, &query_i8, query_i8_norm) as f64
            } else if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
                if embedding.len() != query_embedding.len() {
                    continue;
                }
                cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding) as f64
            } else {
                continue;
            }
        } else if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
            if embedding.len() != query_embedding.len() {
                continue;
            }
            cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding) as f64
        } else {
            continue;
        };

        #[cfg(not(feature = "vector_quant_i8"))]
        let similarity = if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
            if embedding.len() != query_embedding.len() {
                continue;
            }
            cosine_with_query_norm_f32(&query_embedding, query_norm, &embedding) as f64
        } else {
            continue;
        };

        candidates.push((
            similarity as f64,
            id,
            source_id,
            chunk_index,
            content,
            chunk_type,
            metadata,
        ));
    }

    candidates.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());

    Ok(candidates
        .into_iter()
        .take(top_k as usize)
        .map(
            |(sim, id, source_id, chunk_index, content, chunk_type, metadata)| ChunkSearchResult {
                chunk_id: id,
                source_id,
                chunk_index,
                content,
                chunk_type,
                similarity: sim,
                metadata,
            },
        )
        .collect())
}

'''

    new_content = content[:start_idx] + new_function + content[end_idx:]
    with open("rust_builder/rust/src/api/source_rag.rs", "w") as f:
        f.write(new_content)

if __name__ == "__main__":
    main()
