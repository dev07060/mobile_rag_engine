// rust/src/api/incremental_index.rs
//! Incremental Vector Index with Dual-Index Strategy
//!
//! This module provides real-time indexing by combining:
//! - Main HNSW index: Pre-built for efficient search
//! - Buffer index: Recent documents stored in a linear buffer
//!
//! When the buffer reaches a threshold, it's merged into the main index.

use std::sync::RwLock;
use once_cell::sync::Lazy;
use log::{info, debug, warn};
use crate::api::hnsw_index::{
    build_hnsw_index, search_hnsw, is_hnsw_index_loaded, 
    clear_hnsw_index, EmbeddingPoint, HnswSearchResult
};

/// Configuration for the incremental index
const BUFFER_THRESHOLD: usize = 100;  // Auto-merge when buffer reaches this size

/// Global buffer for recent documents (before HNSW merge)
/// Stores (doc_id, embedding) pairs for linear scan
static RECENT_BUFFER: Lazy<RwLock<Vec<BufferEntry>>> = 
    Lazy::new(|| RwLock::new(Vec::new()));

/// Buffer entry for recent documents
#[derive(Clone, Debug)]
struct BufferEntry {
    id: i64,
    embedding: Vec<f32>,
    /// Pre-computed norm for efficient distance calculation
    norm: f32,
}

impl BufferEntry {
    fn new(id: i64, embedding: Vec<f32>) -> Self {
        let norm = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();
        Self { id, embedding, norm }
    }

    /// Calculate cosine distance to another embedding
    fn cosine_distance(&self, other: &[f32], other_norm: f32) -> f32 {
        if self.norm == 0.0 || other_norm == 0.0 {
            return 1.0;  // Maximum distance
        }

        let dot: f32 = self.embedding.iter()
            .zip(other.iter())
            .map(|(a, b)| a * b)
            .sum();

        1.0 - (dot / (self.norm * other_norm))
    }
}

/// Add a single vector to the index immediately (incremental)
/// 
/// The vector is added to the buffer and becomes searchable immediately.
/// When buffer reaches threshold, triggers background merge to HNSW.
pub fn incremental_add(doc_id: i64, embedding: Vec<f32>) {
    let entry = BufferEntry::new(doc_id, embedding);
    
    let mut buffer = RECENT_BUFFER.write().unwrap();
    buffer.push(entry);
    
    let buffer_size = buffer.len();
    debug!("[incremental] Added doc {} to buffer, size: {}", doc_id, buffer_size);
    
    // Check if merge is needed (but don't block - actual merge happens separately)
    if buffer_size >= BUFFER_THRESHOLD {
        warn!("[incremental] Buffer threshold reached ({}), consider calling merge_buffer()", buffer_size);
    }
}

/// Add multiple vectors to index (batch incremental)
pub fn incremental_add_batch(docs: Vec<(i64, Vec<f32>)>) {
    let mut buffer = RECENT_BUFFER.write().unwrap();
    
    for (doc_id, embedding) in docs {
        let entry = BufferEntry::new(doc_id, embedding);
        buffer.push(entry);
    }
    
    info!("[incremental] Added {} docs to buffer, total size: {}", 
          buffer.len(), buffer.len());
}

/// Remove a document from the index
/// 
/// Note: Removes from buffer immediately, but HNSW removal requires rebuild
pub fn incremental_remove(doc_id: i64) {
    let mut buffer = RECENT_BUFFER.write().unwrap();
    let initial_len = buffer.len();
    buffer.retain(|entry| entry.id != doc_id);
    
    if buffer.len() < initial_len {
        debug!("[incremental] Removed doc {} from buffer", doc_id);
    }
    
    // Note: Cannot remove from HNSW without rebuild
    // The document will be filtered out during content fetch
}

/// Search result from incremental index
#[derive(Debug, Clone)]
pub struct IncrementalSearchResult {
    pub doc_id: i64,
    pub distance: f32,
    /// Source: 'buffer' or 'hnsw'
    pub source: String,
}

/// Search the incremental index (both buffer and HNSW)
/// 
/// Combines results from:
/// 1. Linear scan of buffer (for recently added docs)
/// 2. HNSW search (for pre-indexed docs)
pub fn incremental_search(query_embedding: Vec<f32>, top_k: usize) -> anyhow::Result<Vec<IncrementalSearchResult>> {
    let query_norm = query_embedding.iter().map(|x| x * x).sum::<f32>().sqrt();
    
    let mut all_results: Vec<(i64, f32, &str)> = Vec::new();
    
    // 1. Search buffer (linear scan)
    {
        let buffer = RECENT_BUFFER.read().unwrap();
        for entry in buffer.iter() {
            let distance = entry.cosine_distance(&query_embedding, query_norm);
            all_results.push((entry.id, distance, "buffer"));
        }
    }
    
    // 2. Search HNSW (if loaded)
    if is_hnsw_index_loaded() {
        let hnsw_results = search_hnsw(query_embedding.clone(), top_k * 2)?;
        for result in hnsw_results {
            all_results.push((result.id, result.distance, "hnsw"));
        }
    }
    
    // 3. Sort by distance and return top_k
    all_results.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    
    // Deduplicate by doc_id (keep lowest distance)
    let mut seen = std::collections::HashSet::new();
    let results: Vec<IncrementalSearchResult> = all_results.into_iter()
        .filter(|(id, _, _)| seen.insert(*id))
        .take(top_k)
        .map(|(doc_id, distance, source)| IncrementalSearchResult {
            doc_id,
            distance,
            source: source.to_string(),
        })
        .collect();
    
    debug!("[incremental] Search returned {} results", results.len());
    Ok(results)
}

/// Get buffer statistics
#[derive(Debug, Clone)]
pub struct BufferStats {
    pub buffer_size: usize,
    pub threshold: usize,
    pub hnsw_loaded: bool,
}

pub fn get_buffer_stats() -> BufferStats {
    let buffer = RECENT_BUFFER.read().unwrap();
    BufferStats {
        buffer_size: buffer.len(),
        threshold: BUFFER_THRESHOLD,
        hnsw_loaded: is_hnsw_index_loaded(),
    }
}

/// Clear the buffer (useful after manual HNSW rebuild)
pub fn clear_buffer() {
    let mut buffer = RECENT_BUFFER.write().unwrap();
    buffer.clear();
    info!("[incremental] Buffer cleared");
}

/// Check if buffer needs merging
pub fn needs_merge() -> bool {
    let buffer = RECENT_BUFFER.read().unwrap();
    buffer.len() >= BUFFER_THRESHOLD
}

/// Get all buffer entries for HNSW rebuild
/// 
/// Returns (doc_id, embedding) pairs to be combined with DB data for rebuild
pub fn get_buffer_for_merge() -> Vec<(i64, Vec<f32>)> {
    let buffer = RECENT_BUFFER.read().unwrap();
    buffer.iter()
        .map(|entry| (entry.id, entry.embedding.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_embedding(seed: f32) -> Vec<f32> {
        (0..384).map(|i| (seed + i as f32).sin()).collect()
    }

    #[test]
    fn test_incremental_add_and_search() {
        // Clear any existing state
        clear_buffer();
        
        // Add some documents
        incremental_add(1, make_embedding(1.0));
        incremental_add(2, make_embedding(2.0));
        incremental_add(3, make_embedding(3.0));
        
        // Search
        let results = incremental_search(make_embedding(1.0), 3).unwrap();
        
        assert!(!results.is_empty());
        // First result should be doc 1 (most similar to query)
        assert_eq!(results[0].doc_id, 1);
        assert_eq!(results[0].source, "buffer");
        
        // Clean up
        clear_buffer();
    }

    #[test]
    fn test_buffer_stats() {
        clear_buffer();
        
        let stats = get_buffer_stats();
        assert_eq!(stats.buffer_size, 0);
        assert_eq!(stats.threshold, BUFFER_THRESHOLD);
        
        incremental_add(1, make_embedding(1.0));
        
        let stats = get_buffer_stats();
        assert_eq!(stats.buffer_size, 1);
        
        clear_buffer();
    }
}
