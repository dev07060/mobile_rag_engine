// rust/src/api/hybrid_search.rs
//! Hybrid Search: Vector + Keyword with Reciprocal Rank Fusion
//!
//! Combines HNSW vector search with BM25 keyword search using RRF.
//! Abstracted from the underlying HNSW implementation to prevent bottlenecks
//! when migrating to incremental indexing.

use std::collections::HashMap;
use log::{info, debug};
use rusqlite::{params, Connection};

use crate::api::hnsw_index::{search_hnsw, is_hnsw_index_loaded};
use crate::api::bm25_search::{bm25_search, Bm25SearchResult};

/// Hybrid search result with combined ranking
#[derive(Debug, Clone)]
pub struct HybridSearchResult {
    /// Document ID
    pub doc_id: i64,
    /// Document content
    pub content: String,
    /// Combined RRF score
    pub score: f64,
    /// Original vector search rank (0 if not found)
    pub vector_rank: u32,
    /// Original BM25 rank (0 if not found)
    pub bm25_rank: u32,
}

/// Reciprocal Rank Fusion parameters
#[derive(Debug, Clone)]
pub struct RrfConfig {
    /// RRF constant k (default: 60, higher = more smoothing)
    pub k: u32,
    /// Weight for vector search (0.0 - 1.0)
    pub vector_weight: f64,
    /// Weight for BM25 search (0.0 - 1.0)
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

/// Calculate RRF score for a single rank
/// RRF(d) = 1 / (k + rank)
fn rrf_score(rank: usize, k: u32) -> f64 {
    1.0 / (k as f64 + rank as f64)
}

/// Perform hybrid search combining vector and keyword search
/// 
/// # Arguments
/// * `db_path` - Path to SQLite database
/// * `query_text` - Original query text for BM25
/// * `query_embedding` - Query embedding for vector search
/// * `top_k` - Number of results to return
/// * `config` - RRF configuration (optional, uses default if None)
pub fn search_hybrid(
    db_path: String,
    query_text: String,
    query_embedding: Vec<f32>,
    top_k: u32,
    config: Option<RrfConfig>,
) -> anyhow::Result<Vec<HybridSearchResult>> {
    let config = config.unwrap_or_default();
    
    info!("[hybrid] Starting hybrid search, top_k: {}", top_k);
    
    // Fetch more candidates for reranking (2x top_k from each source)
    let candidate_k = (top_k * 2) as usize;
    
    // 1. Vector search (HNSW)
    let vector_results = if is_hnsw_index_loaded() {
        search_hnsw(query_embedding, candidate_k)?
    } else {
        debug!("[hybrid] HNSW index not loaded, skipping vector search");
        vec![]
    };
    
    // 2. BM25 keyword search
    let bm25_results: Vec<Bm25SearchResult> = bm25_search(query_text.clone(), candidate_k as u32);
    
    info!("[hybrid] Vector results: {}, BM25 results: {}", 
          vector_results.len(), bm25_results.len());
    
    // 3. Build rank maps
    let mut vector_ranks: HashMap<i64, usize> = HashMap::new();
    for (rank, result) in vector_results.iter().enumerate() {
        vector_ranks.insert(result.id, rank + 1); // 1-indexed
    }
    
    let mut bm25_ranks: HashMap<i64, usize> = HashMap::new();
    for (rank, result) in bm25_results.iter().enumerate() {
        bm25_ranks.insert(result.doc_id, rank + 1); // 1-indexed
    }
    
    // 4. Collect all unique document IDs
    let mut all_doc_ids: Vec<i64> = vector_ranks.keys()
        .chain(bm25_ranks.keys())
        .copied()
        .collect();
    all_doc_ids.sort();
    all_doc_ids.dedup();
    
    if all_doc_ids.is_empty() {
        return Ok(vec![]);
    }
    
    // 5. Calculate RRF scores
    let mut rrf_scores: Vec<(i64, f64, u32, u32)> = Vec::new();
    
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
    
    // Sort by combined score (descending)
    rrf_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    rrf_scores.truncate(top_k as usize);
    
    // 6. Fetch content from database
    let conn = Connection::open(&db_path)?;
    let mut results: Vec<HybridSearchResult> = Vec::new();
    
    for (doc_id, score, vec_rank, bm25_rank) in rrf_scores {
        // Try 'docs' table first, then 'chunks' table
        let content: Option<String> = conn
            .query_row(
                "SELECT content FROM docs WHERE id = ?1",
                params![doc_id],
                |row| row.get(0),
            )
            .ok()
            .or_else(|| {
                conn.query_row(
                    "SELECT content FROM chunks WHERE id = ?1",
                    params![doc_id],
                    |row| row.get(0),
                )
                .ok()
            });
        
        if let Some(content) = content {
            results.push(HybridSearchResult {
                doc_id,
                content,
                score,
                vector_rank: vec_rank,
                bm25_rank: bm25_rank,
            });
        }
    }
    
    info!("[hybrid] Returning {} results", results.len());
    Ok(results)
}

/// Simplified hybrid search that returns only content strings
/// Compatible with existing search_similar API
pub fn search_hybrid_simple(
    db_path: String,
    query_text: String,
    query_embedding: Vec<f32>,
    top_k: u32,
) -> anyhow::Result<Vec<String>> {
    let results = search_hybrid(db_path, query_text, query_embedding, top_k, None)?;
    Ok(results.into_iter().map(|r| r.content).collect())
}

/// Search with custom weights
/// 
/// # Arguments
/// * `vector_weight` - Weight for vector search (0.0 - 1.0)
/// * `bm25_weight` - Weight for BM25 search (0.0 - 1.0)
/// 
/// # Example
/// - Pure vector search: vector_weight=1.0, bm25_weight=0.0
/// - Balanced: vector_weight=0.5, bm25_weight=0.5
/// - Keyword-heavy: vector_weight=0.3, bm25_weight=0.7
pub fn search_hybrid_weighted(
    db_path: String,
    query_text: String,
    query_embedding: Vec<f32>,
    top_k: u32,
    vector_weight: f64,
    bm25_weight: f64,
) -> anyhow::Result<Vec<HybridSearchResult>> {
    let config = RrfConfig {
        k: 60,
        vector_weight: vector_weight.clamp(0.0, 1.0),
        bm25_weight: bm25_weight.clamp(0.0, 1.0),
    };
    
    search_hybrid(db_path, query_text, query_embedding, top_k, Some(config))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rrf_score() {
        // Rank 1 with k=60: 1/(60+1) ≈ 0.0164
        let score = rrf_score(1, 60);
        assert!((score - 0.0164).abs() < 0.001);
        
        // Higher rank = lower score
        let score_10 = rrf_score(10, 60);
        assert!(score > score_10);
    }

    #[test]
    fn test_rrf_config_default() {
        let config = RrfConfig::default();
        assert_eq!(config.k, 60);
        assert_eq!(config.vector_weight, 0.5);
        assert_eq!(config.bm25_weight, 0.5);
    }
}
