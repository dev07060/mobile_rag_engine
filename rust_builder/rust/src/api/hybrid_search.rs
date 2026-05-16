// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Licensed under the MIT License. You may obtain a copy of the License at
// https://opensource.org/licenses/MIT
//
// This software is provided "AS IS", without warranty of any kind, express or
// implied, including but not limited to the warranties of merchantability,
// fitness for a particular purpose, and noninfringement. In no event shall the
// authors or copyright holders be liable for any claim, damages, or other
// liability arising from the use of this software.
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.
//
//! Hybrid Search: Vector + Keyword with Reciprocal Rank Fusion.

use log::{debug, info};
use std::collections::{HashMap, HashSet};

use crate::api::bm25_search::{bm25_search, tokenize_for_bm25, Bm25SearchResult};
use crate::api::db_pool::get_connection;
use crate::api::error::RagError;
use crate::api::hnsw_index::{is_hnsw_index_loaded, search_hnsw_slice, HnswSearchResult};
use crate::api::query_metrics::record_hybrid_result_content_read;
use crate::api::vector_math::{cosine_with_query_norm_f32, decode_f32_embedding, l2_norm_f32};
#[cfg(feature = "vector_quant_i8")]
use crate::api::vector_quant::{cosine_with_query_norm_i8_blob, l2_norm_i8, quantize_f32_to_i8};

#[derive(Debug, Clone)]
pub struct SearchFilter {
    pub source_ids: Option<Vec<i64>>,
    pub metadata_like: Option<String>, // SQL LIKE pattern
    pub collection_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct HybridSearchResult {
    pub doc_id: i64,
    pub content: String,
    pub score: f64,
    pub vector_rank: u32,
    pub bm25_rank: u32,
    pub source_id: i64,
    pub metadata: Option<String>,
    pub chunk_index: u32,
}

#[derive(Debug, Clone)]
pub struct RrfConfig {
    pub k: u32,
    pub vector_weight: f64,
    pub bm25_weight: f64,
}

impl Default for RrfConfig {
    fn default() -> Self {
        Self {
            k: 60,
            vector_weight: 0.5,
            bm25_weight: 0.5,
        }
    }
}

fn rrf_score(rank: usize, k: u32) -> f64 {
    1.0 / (k as f64 + rank as f64)
}

/// Perform hybrid search combining vector and keyword search.
///
/// Owned-vector entrypoint kept stable for the flutter_rust_bridge
/// surface; internal Rust callers should prefer [`search_hybrid_inner`]
/// to avoid cloning the query embedding when it is already held by
/// reference (e.g. inside `search_meta_hybrid`'s retry loop).
pub fn search_hybrid(
    query_text: String,
    query_embedding: Vec<f32>,
    top_k: u32,
    config: Option<RrfConfig>,
    filter: Option<SearchFilter>,
) -> Result<Vec<HybridSearchResult>, RagError> {
    search_hybrid_inner(query_text, &query_embedding, top_k, config, filter)
}

/// Slice-based variant of [`search_hybrid`]. The query embedding is
/// borrowed for the lifetime of the call so retry loops and scoped
/// thread spawns can reuse it without per-attempt `Vec<f32>` clones.
pub(crate) fn search_hybrid_inner(
    query_text: String,
    query_embedding: &[f32],
    top_k: u32,
    config: Option<RrfConfig>,
    filter: Option<SearchFilter>,
) -> Result<Vec<HybridSearchResult>, RagError> {
    let config = config.unwrap_or_default();
    info!("[hybrid] Starting hybrid search, top_k: {}", top_k);

    // Fetch more candidates if filtering is active to maintain recall
    let multiplier = if filter.is_some() { 4 } else { 2 };
    let candidate_k = (top_k * multiplier) as usize;

    let use_exact_source_scan = filter.as_ref().is_some_and(|f| {
        f.source_ids
            .as_ref()
            .map(|sids| !sids.is_empty())
            .unwrap_or(false)
            || f.metadata_like
                .as_ref()
                .map(|pattern| !pattern.trim().is_empty())
                .unwrap_or(false)
    });

    let mut vector_results = Vec::new();
    let mut bm25_results = Vec::new();
    if !use_exact_source_scan {
        // 1. Parallel Execution: Run Vector and BM25 search simultaneously
        let (vec_res, bm25_res) = std::thread::scope(|s| {
            let handle_vec = s.spawn(|| {
                if is_hnsw_index_loaded() {
                    search_hnsw_slice(query_embedding, candidate_k).unwrap_or_else(|e| {
                        log::error!("[hybrid] Vector search failed: {}", e);
                        vec![]
                    })
                } else {
                    debug!("[hybrid] HNSW index not loaded, skipping vector search");
                    vec![]
                }
            });

            let handle_bm25 = s.spawn(|| bm25_search(query_text.clone(), candidate_k as u32));

            let vec_res = handle_vec.join().unwrap_or_else(|e| {
                log::error!("[hybrid] Vector search thread panicked: {:?}", e);
                vec![]
            });

            let bm25_res = handle_bm25.join().unwrap_or_else(|e| {
                log::error!("[hybrid] BM25 search thread panicked: {:?}", e);
                vec![]
            });

            (vec_res, bm25_res)
        });

        vector_results = vec_res;
        bm25_results = bm25_res;
        info!(
            "[hybrid] Raw candidates - Vector: {}, BM25: {}",
            vector_results.len(),
            bm25_results.len()
        );
    }

    // 2. Filter-Aware Search Strategy
    // If filtering by source_id or metadata, performing a global candidate search and
    // post-filtering can be inefficient and low-recall for small scoped subsets.
    // In that case, perform an exact scan over the scoped chunks and compute
    // both vector and BM25 ranks directly.
    let mut used_exact_source_scan = false;
    if let Some(f) = &filter {
        if use_exact_source_scan {
            used_exact_source_scan = true;
            info!(
                    "[hybrid] Scoped exact filter active (source_ids={:?}, metadata_like={:?}), switching to exact scan",
                    f.source_ids, f.metadata_like
                );

            let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
            let mut exact_conditions = Vec::new();

            if let Some(collection_id) = &f.collection_id {
                if !collection_id.trim().is_empty() {
                    exact_conditions.push(format!(
                        "c.collection_id = '{}'",
                        collection_id.replace("'", "''")
                    ));
                }
            }

            if let Some(sids) = &f.source_ids {
                if !sids.is_empty() {
                    let sids_str = sids
                        .iter()
                        .map(|id| id.to_string())
                        .collect::<Vec<_>>()
                        .join(",");
                    exact_conditions.push(format!("c.source_id IN ({})", sids_str));
                }
            }

            if let Some(pattern) = &f.metadata_like {
                exact_conditions.push(format!("s.metadata LIKE '{}'", pattern.replace("'", "''")));
            }

            // Fetch ALL chunks for this scoped set for exact vector + BM25 scoring.
            let query_with_i8 = format!(
                "SELECT c.id, c.embedding, {}, c.content
                     FROM chunks c
                     LEFT JOIN sources s ON c.source_id = s.id
                     WHERE {}",
                "c.embedding_i8",
                exact_conditions.join(" AND ")
            );
            let query_without_i8 = format!(
                "SELECT c.id, c.embedding, {}, c.content
                     FROM chunks c
                     LEFT JOIN sources s ON c.source_id = s.id
                     WHERE {}",
                "NULL AS embedding_i8",
                exact_conditions.join(" AND ")
            );

            let mut stmt = match conn.prepare(&query_with_i8) {
                Ok(stmt) => stmt,
                Err(_) => conn
                    .prepare(&query_without_i8)
                    .map_err(|e| RagError::DatabaseError(e.to_string()))?,
            };
            let chunk_iter = stmt
                .query_map([], |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, Vec<u8>>(1)?,
                        row.get::<_, Option<Vec<u8>>>(2)?,
                        row.get::<_, String>(3)?,
                    ))
                })
                .map_err(|e| RagError::DatabaseError(e.to_string()))?;

            let query_norm = l2_norm_f32(query_embedding);
            #[cfg(feature = "vector_quant_i8")]
            let (query_i8, _query_i8_scale) = quantize_f32_to_i8(query_embedding);
            #[cfg(feature = "vector_quant_i8")]
            let query_i8_norm = l2_norm_i8(&query_i8);
            let query_tokens = tokenize_for_bm25(&query_text);
            let query_token_set: HashSet<String> = query_tokens.iter().cloned().collect();

            let mut scoped_doc_count = 0usize;
            let mut scoped_total_doc_length = 0usize;
            let mut scoped_doc_lengths: HashMap<i64, usize> = HashMap::new();
            let mut scoped_doc_freqs: HashMap<String, usize> = HashMap::new();
            let mut scoped_term_freqs: HashMap<i64, HashMap<String, u32>> = HashMap::new();

            // Replace global candidate sets with scoped exact scan results.
            vector_results.clear();
            bm25_results.clear();

            for row in chunk_iter {
                if let Ok((id, embedding_blob, embedding_i8_blob, content)) = row {
                    #[cfg(not(feature = "vector_quant_i8"))]
                    let _ = &embedding_i8_blob;
                    #[cfg(feature = "vector_quant_i8")]
                    let sim = if let Some(qblob) = embedding_i8_blob.as_deref() {
                        if qblob.len() == query_i8.len() && query_i8_norm > 0.0 {
                            cosine_with_query_norm_i8_blob(&query_i8, query_i8_norm, qblob)
                        } else if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
                            if embedding.len() != query_embedding.len() {
                                continue;
                            }
                            cosine_with_query_norm_f32(query_embedding, query_norm, &embedding)
                        } else {
                            continue;
                        }
                    } else if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
                        if embedding.len() != query_embedding.len() {
                            continue;
                        }
                        cosine_with_query_norm_f32(query_embedding, query_norm, &embedding)
                    } else {
                        continue;
                    };

                    #[cfg(not(feature = "vector_quant_i8"))]
                    let sim = if let Some(embedding) = decode_f32_embedding(&embedding_blob) {
                        if embedding.len() != query_embedding.len() {
                            continue;
                        }
                        cosine_with_query_norm_f32(query_embedding, query_norm, &embedding)
                    } else {
                        continue;
                    };

                    vector_results.push(HnswSearchResult {
                        id,
                        distance: (1.0 - sim) as f32, // lower is better
                    });

                    if !query_token_set.is_empty() {
                        let doc_tokens = tokenize_for_bm25(&content);
                        let doc_length = doc_tokens.len();
                        if doc_length > 0 {
                            scoped_doc_count += 1;
                            scoped_total_doc_length += doc_length;
                            scoped_doc_lengths.insert(id, doc_length);

                            let mut term_freqs: HashMap<String, u32> = HashMap::new();
                            for token in doc_tokens {
                                if query_token_set.contains(&token) {
                                    *term_freqs.entry(token).or_insert(0) += 1;
                                }
                            }
                            for term in term_freqs.keys() {
                                *scoped_doc_freqs.entry(term.clone()).or_insert(0) += 1;
                            }
                            if !term_freqs.is_empty() {
                                scoped_term_freqs.insert(id, term_freqs);
                            }
                        }
                    }
                }
            }

            // Sort by distance ASCENDING (best match first)
            vector_results.sort_by(|a, b| {
                a.distance
                    .partial_cmp(&b.distance)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            vector_results.truncate(candidate_k);

            if !query_tokens.is_empty() && scoped_doc_count > 0 {
                let avg_doc_length = scoped_total_doc_length as f64 / scoped_doc_count as f64;
                let k1 = 1.2;
                let b = 0.75;
                let mut scoped_bm25_scores: Vec<Bm25SearchResult> = Vec::new();

                for (doc_id, term_freqs) in scoped_term_freqs {
                    let Some(doc_len) = scoped_doc_lengths.get(&doc_id) else {
                        continue;
                    };
                    let mut score = 0.0;
                    for token in &query_tokens {
                        let Some(tf) = term_freqs.get(token) else {
                            continue;
                        };
                        let Some(df) = scoped_doc_freqs.get(token) else {
                            continue;
                        };

                        let n = *df as f64;
                        let idf = ((scoped_doc_count as f64 - n + 0.5) / (n + 0.5) + 1.0).ln();
                        let tf_f = *tf as f64;
                        let doc_len_f = *doc_len as f64;
                        let tf_component = (tf_f * (k1 + 1.0))
                            / (tf_f + k1 * (1.0 - b + b * (doc_len_f / avg_doc_length.max(1.0))));
                        score += idf * tf_component;
                    }
                    if score > 0.0 {
                        scoped_bm25_scores.push(Bm25SearchResult { doc_id, score });
                    }
                }

                scoped_bm25_scores.sort_by(|a, b| {
                    b.score
                        .partial_cmp(&a.score)
                        .unwrap_or(std::cmp::Ordering::Equal)
                });
                scoped_bm25_scores.truncate(candidate_k);
                bm25_results = scoped_bm25_scores;
            }

            info!(
                    "[hybrid] Exact scan candidates (collection={:?}, source_ids={:?}) - Vector: {}, BM25: {}",
                    f.collection_id,
                    f.source_ids,
                    vector_results.len(),
                    bm25_results.len()
                );
        }
    }

    // Standard global search post-filtering (skip when exact source scan already scoped).
    if !used_exact_source_scan {
        if let Some(f) = &filter {
            let mut all_doc_ids: Vec<i64> = vector_results
                .iter()
                .map(|r| r.id)
                .chain(bm25_results.iter().map(|r| r.doc_id))
                .collect();
            all_doc_ids.sort();
            all_doc_ids.dedup();

            if !all_doc_ids.is_empty() {
                let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
                let id_list = all_doc_ids
                    .iter()
                    .map(|id| id.to_string())
                    .collect::<Vec<_>>()
                    .join(",");

                let mut sql_conditions = Vec::new();
                sql_conditions.push(format!("c.id IN ({})", id_list));

                if let Some(sids) = &f.source_ids {
                    if !sids.is_empty() {
                        let sids_str = sids
                            .iter()
                            .map(|id| id.to_string())
                            .collect::<Vec<_>>()
                            .join(",");
                        sql_conditions.push(format!("c.source_id IN ({})", sids_str));
                    }
                }

                if let Some(pattern) = &f.metadata_like {
                    sql_conditions
                        .push(format!("s.metadata LIKE '{}'", pattern.replace("'", "''")));
                }

                if let Some(collection_id) = &f.collection_id {
                    if !collection_id.trim().is_empty() {
                        sql_conditions.push(format!(
                            "c.collection_id = '{}'",
                            collection_id.replace("'", "''")
                        ));
                    }
                }

                let query = format!(
                    "SELECT c.id FROM chunks c
                     LEFT JOIN sources s ON c.source_id = s.id
                     WHERE {}",
                    sql_conditions.join(" AND ")
                );

                debug!("[hybrid] Filter query: {}", query);

                let mut stmt = conn
                    .prepare(&query)
                    .map_err(|e| RagError::DatabaseError(e.to_string()))?;
                let valid_ids: HashSet<i64> = stmt
                    .query_map([], |row| row.get(0))
                    .map_err(|e| RagError::DatabaseError(e.to_string()))?
                    .filter_map(|r| r.ok())
                    .collect();

                info!(
                    "[hybrid] Filter maintained {}/{} candidates",
                    valid_ids.len(),
                    all_doc_ids.len()
                );

                vector_results.retain(|r| valid_ids.contains(&r.id));
                bm25_results.retain(|r| valid_ids.contains(&r.doc_id));
            }
        }
    }

    // 3. RRF Ranking
    let mut vector_ranks: HashMap<i64, usize> = HashMap::new();
    for (rank, result) in vector_results.iter().enumerate() {
        vector_ranks.insert(result.id, rank + 1);
    }

    let mut bm25_ranks: HashMap<i64, usize> = HashMap::new();
    for (rank, result) in bm25_results.iter().enumerate() {
        bm25_ranks.insert(result.doc_id, rank + 1);
    }

    let mut all_doc_ids: Vec<i64> = vector_ranks
        .keys()
        .chain(bm25_ranks.keys())
        .copied()
        .collect();
    all_doc_ids.sort();
    all_doc_ids.dedup();

    if all_doc_ids.is_empty() {
        return Ok(vec![]);
    }

    let mut rrf_scores: Vec<(i64, f64, u32, u32)> = Vec::with_capacity(all_doc_ids.len());
    for doc_id in &all_doc_ids {
        let vec_rank = vector_ranks.get(doc_id).copied();
        let bm25_rank = bm25_ranks.get(doc_id).copied();

        let mut combined_score = 0.0;
        if let Some(rank) = vec_rank {
            combined_score += config.vector_weight * rrf_score(rank, config.k);
        }
        if let Some(rank) = bm25_rank {
            combined_score += config.bm25_weight * rrf_score(rank, config.k);
        }

        rrf_scores.push((
            *doc_id,
            combined_score,
            vec_rank.unwrap_or(0) as u32,
            bm25_rank.unwrap_or(0) as u32,
        ));
    }

    rrf_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    rrf_scores.truncate(top_k as usize);

    // 4. Batch Content Fetch
    if rrf_scores.is_empty() {
        return Ok(vec![]);
    }

    let target_ids: Vec<String> = rrf_scores
        .iter()
        .map(|(id, _, _, _)| id.to_string())
        .collect();
    let id_list = target_ids.join(",");

    let conn = get_connection().map_err(|e| RagError::DatabaseError(e.to_string()))?;
    // Map: id -> (content, source_id, metadata, chunk_index)
    let mut content_map: HashMap<i64, (String, i64, Option<String>, u32)> = HashMap::new();

    // First try docs table (Simple RAG) - assume source_id=id, metadata=None, chunk_index=0
    // BUT if filter was active, we likely filtered these out.
    if filter.is_none() {
        let query_docs = format!("SELECT id, content FROM docs WHERE id IN ({})", id_list);
        if let Ok(mut stmt) = conn.prepare(&query_docs) {
            let found_docs = stmt.query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            });
            if let Ok(rows) = found_docs {
                for row in rows {
                    if let Ok((id, content)) = row {
                        record_hybrid_result_content_read(content.len() as u64);
                        content_map.insert(id, (content, id, None, 0));
                    }
                }
            }
        }
    }

    // If missing, try chunks table
    let missing_ids: Vec<String> = rrf_scores
        .iter()
        .filter(|(id, _, _, _)| !content_map.contains_key(id))
        .map(|(id, _, _, _)| id.to_string())
        .collect();

    if !missing_ids.is_empty() {
        let missing_list = missing_ids.join(",");
        let query_chunks = format!(
            "SELECT c.id, c.content, c.source_id, s.metadata, c.chunk_index 
             FROM chunks c 
             LEFT JOIN sources s ON c.source_id = s.id 
             WHERE c.id IN ({})",
            missing_list
        );

        if let Ok(mut stmt) = conn.prepare(&query_chunks) {
            let found_chunks = stmt.query_map([], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, u32>(4)?,
                ))
            });

            if let Ok(results_iter) = found_chunks {
                for row in results_iter {
                    if let Ok((id, content, source_id, metadata, chunk_index)) = row {
                        record_hybrid_result_content_read(content.len() as u64);
                        content_map.insert(id, (content, source_id, metadata, chunk_index));
                    }
                }
            }
        }
    }

    let mut results: Vec<HybridSearchResult> = Vec::with_capacity(rrf_scores.len());

    for (doc_id, score, vec_rank, bm25_rank) in rrf_scores {
        if let Some((content, source_id, metadata, chunk_index)) = content_map.remove(&doc_id) {
            results.push(HybridSearchResult {
                doc_id,
                content,
                score,
                vector_rank: vec_rank,
                bm25_rank,
                source_id,
                metadata,
                chunk_index,
            });
        }
    }

    info!("[hybrid] Returning {} results", results.len());
    Ok(results)
}

/// Simplified hybrid search returning content strings only.
pub fn search_hybrid_simple(
    query_text: String,
    query_embedding: Vec<f32>,
    top_k: u32,
) -> Result<Vec<String>, RagError> {
    Ok(
        search_hybrid(query_text, query_embedding, top_k, None, None)?
            .into_iter()
            .map(|r| r.content)
            .collect(),
    )
}

/// Search with custom weights (vector_weight + bm25_weight = 1.0 recommended).
pub fn search_hybrid_weighted(
    query_text: String,
    query_embedding: Vec<f32>,
    top_k: u32,
    vector_weight: f64,
    bm25_weight: f64,
) -> Result<Vec<HybridSearchResult>, RagError> {
    let config = RrfConfig {
        k: 60,
        vector_weight: vector_weight.clamp(0.0, 1.0),
        bm25_weight: bm25_weight.clamp(0.0, 1.0),
    };
    search_hybrid(query_text, query_embedding, top_k, Some(config), None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::bm25_search::{bm25_add_document, bm25_clear_index};
    use crate::api::db_pool::{close_db_pool, get_connection, init_db_pool};
    use crate::api::hnsw_index::{build_hnsw_index, clear_hnsw_index};
    use crate::api::simple_rag::init_db;
    use crate::api::source_rag::init_source_db;
    use rusqlite::params;

    fn embedding_to_blob(values: &[f32]) -> Vec<u8> {
        let mut out = Vec::with_capacity(values.len() * 4);
        for v in values {
            out.extend_from_slice(&v.to_ne_bytes());
        }
        out
    }

    #[test]
    fn test_rrf_score() {
        let score = rrf_score(1, 60);
        assert!((score - 0.0164).abs() < 0.001);
    }

    #[test]
    fn test_rrf_config_default() {
        let config = RrfConfig::default();
        assert_eq!(config.k, 60);
    }

    #[test]
    fn test_hybrid_search_integration() {
        // 1. Setup
        let db_path = std::env::temp_dir().join("test_hybrid_search.db");
        let _ = std::fs::remove_file(&db_path); // Ensure clean state

        // Initialize pool with 1 connection to avoid locking issues in test
        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();

        // Create tables
        init_db().unwrap();

        // Clear indices
        clear_hnsw_index();
        bm25_clear_index();

        // 2. Add Data
        {
            let conn = get_connection().unwrap();
            // We use dummy embedding blobs for DB, as search_hybrid uses HNSW index for vectors
            let dummy_blob = vec![0u8; 4];

            conn.execute("INSERT INTO docs (id, content, content_hash, embedding) VALUES (1, 'Apple iPhone is great', 'h1', ?1)", params![dummy_blob]).unwrap();
            conn.execute("INSERT INTO docs (id, content, content_hash, embedding) VALUES (2, 'Banana is a yellow fruit', 'h2', ?1)", params![dummy_blob]).unwrap();
            conn.execute("INSERT INTO docs (id, content, content_hash, embedding) VALUES (3, 'Apple pie recipe', 'h3', ?1)", params![dummy_blob]).unwrap();
        }

        // 3. Populate Indices
        // Vector:
        // Doc 1 (Apple): [1, 0]
        // Doc 2 (Banana): [0, 1]
        // Doc 3 (Apple): [0.9, 0.1]
        let points = vec![
            (1, vec![1.0, 0.0]),
            (2, vec![0.0, 1.0]),
            (3, vec![0.9, 0.1]),
        ];
        build_hnsw_index(points).unwrap();

        // BM25
        bm25_add_document(1, "Apple iPhone is great".to_string());
        bm25_add_document(2, "Banana is a yellow fruit".to_string());
        bm25_add_document(3, "Apple pie recipe".to_string());

        // 4. Test Search
        // Query: "Apple" with vector [1, 0]
        // Should return Doc 1 and Doc 3 as top results
        let results = search_hybrid(
            "Apple".to_string(),
            vec![1.0, 0.0],
            2,
            None,
            None, // No filter
        )
        .unwrap();

        // Verify results
        assert_eq!(results.len(), 2);
        // Doc 1 should match both Vector and BM25 'Apple'
        assert!(results.iter().any(|r| r.doc_id == 1));
        assert!(results.iter().any(|r| r.doc_id == 3));

        // 5. Cleanup
        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_hybrid_source_filter_exact_scan_keeps_scoped_bm25() {
        let db_path = std::env::temp_dir().join("test_hybrid_source_filter_bm25.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();

        clear_hnsw_index();
        bm25_clear_index();

        {
            let conn = get_connection().unwrap();

            conn.execute(
                "INSERT INTO sources (id, content, content_hash, metadata, name, status) VALUES (1, 's1', 'h_s1', '{\"k\":\"v\"}', 'source-1', 'completed')",
                [],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO sources (id, content, content_hash, metadata, name, status) VALUES (2, 's2', 'h_s2', '{\"k\":\"v\"}', 'source-2', 'completed')",
                [],
            )
            .unwrap();

            // source 1 chunks
            conn.execute(
                "INSERT INTO chunks (id, source_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding)
                 VALUES (?1, 1, 0, 'apple c', 0, 7, 'general', ?2)",
                params![101_i64, embedding_to_blob(&[1.0_f32, 0.0_f32])],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO chunks (id, source_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding)
                 VALUES (?1, 1, 1, 'banana', 8, 14, 'general', ?2)",
                params![102_i64, embedding_to_blob(&[0.0_f32, 1.0_f32])],
            )
            .unwrap();

            // source 2 distractor chunk
            conn.execute(
                "INSERT INTO chunks (id, source_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding)
                 VALUES (?1, 2, 0, 'apple c', 0, 7, 'general', ?2)",
                params![201_i64, embedding_to_blob(&[1.0_f32, 0.0_f32])],
            )
            .unwrap();
        }

        // Global BM25 index still exists, but source filter exact scan should now
        // compute scoped BM25 and keep it in RRF.
        bm25_add_document(101, "apple c".to_string());
        bm25_add_document(102, "banana".to_string());
        bm25_add_document(201, "apple c".to_string());

        let results = search_hybrid(
            "c".to_string(),
            vec![0.0, 1.0],
            2,
            None,
            Some(SearchFilter {
                source_ids: Some(vec![1]),
                metadata_like: None,
                collection_id: None,
            }),
        )
        .unwrap();

        assert!(!results.is_empty());
        assert!(results.iter().all(|r| r.source_id == 1));
        assert!(
            results.iter().any(|r| r.bm25_rank > 0),
            "Scoped source filter path should keep BM25 ranks for exact-keyword matching"
        );

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn test_collection_filter_only_uses_post_filter_not_exact_scan() {
        let db_path = std::env::temp_dir().join("test_hybrid_collection_filter_mode.db");
        let _ = std::fs::remove_file(&db_path);

        init_db_pool(db_path.to_str().unwrap().to_string(), 1).unwrap();
        init_source_db().unwrap();
        clear_hnsw_index();
        bm25_clear_index();

        {
            let conn = get_connection().unwrap();

            conn.execute(
                "INSERT INTO sources (id, content, content_hash, metadata, name, status, collection_id)
                 VALUES (1, 'travel source', 'h_t', NULL, 'travel', 'completed', 'travel')",
                [],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO chunks (id, source_id, collection_id, chunk_index, content, start_pos, end_pos, chunk_type, embedding)
                 VALUES (?1, 1, 'travel', 0, 'apple c', 0, 7, 'general', ?2)",
                params![101_i64, embedding_to_blob(&[1.0_f32, 0.0_f32])],
            )
            .unwrap();
        }

        // With only collection filter, hybrid search should rely on loaded indexes.
        // Since both HNSW and BM25 are empty here, results should be empty.
        // (If collection filter incorrectly triggers exact scan, this would return hits.)
        let results = search_hybrid(
            "apple".to_string(),
            vec![1.0, 0.0],
            5,
            None,
            Some(SearchFilter {
                source_ids: None,
                metadata_like: None,
                collection_id: Some("travel".to_string()),
            }),
        )
        .unwrap();

        assert!(results.is_empty());

        close_db_pool();
        let _ = std::fs::remove_file(db_path);
    }
}
