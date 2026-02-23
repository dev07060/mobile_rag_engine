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
//! Incremental Vector Index with Dual-Index Strategy (buffer + HNSW).

use crate::api::hnsw_index::{is_hnsw_index_loaded, search_hnsw};
#[cfg(not(feature = "vector_quant_i8"))]
use crate::api::vector_math::{cosine_with_query_norm_f32, l2_norm_f32};
#[cfg(feature = "vector_quant_i8")]
use crate::api::vector_quant::{cosine_with_query_norm_i8, l2_norm_i8, quantize_f32_to_i8};
use log::{debug, info, warn};
use once_cell::sync::Lazy;
use std::sync::RwLock;

const BUFFER_THRESHOLD: usize = 100;

static RECENT_BUFFER: Lazy<RwLock<Vec<BufferEntry>>> = Lazy::new(|| RwLock::new(Vec::new()));

#[derive(Clone, Debug)]
struct BufferEntry {
    id: i64,
    embedding: Vec<f32>,
    #[cfg(not(feature = "vector_quant_i8"))]
    norm: f32,
    #[cfg(feature = "vector_quant_i8")]
    embedding_i8: Vec<i8>,
    #[cfg(feature = "vector_quant_i8")]
    i8_norm: f32,
}

impl BufferEntry {
    fn new(id: i64, embedding: Vec<f32>) -> Self {
        #[cfg(not(feature = "vector_quant_i8"))]
        let norm = l2_norm_f32(&embedding);
        #[cfg(feature = "vector_quant_i8")]
        let (embedding_i8, _embedding_i8_scale) = quantize_f32_to_i8(&embedding);
        #[cfg(feature = "vector_quant_i8")]
        let i8_norm = l2_norm_i8(&embedding_i8);
        Self {
            id,
            embedding,
            #[cfg(not(feature = "vector_quant_i8"))]
            norm,
            #[cfg(feature = "vector_quant_i8")]
            embedding_i8,
            #[cfg(feature = "vector_quant_i8")]
            i8_norm,
        }
    }

    #[cfg(not(feature = "vector_quant_i8"))]
    fn cosine_distance(&self, other: &[f32], other_norm: f32) -> f32 {
        if self.norm == 0.0 || other_norm == 0.0 {
            return 1.0;
        }
        1.0 - cosine_with_query_norm_f32(other, other_norm, &self.embedding)
    }

    #[cfg(feature = "vector_quant_i8")]
    fn cosine_distance_i8(&self, query_i8: &[i8], query_i8_norm: f32) -> f32 {
        if self.i8_norm == 0.0 || query_i8_norm == 0.0 {
            return 1.0;
        }
        1.0 - cosine_with_query_norm_i8(query_i8, query_i8_norm, &self.embedding_i8)
    }
}

/// Add a single vector to buffer (immediately searchable).
pub fn incremental_add(doc_id: i64, embedding: Vec<f32>) {
    let entry = BufferEntry::new(doc_id, embedding);
    let mut buffer = RECENT_BUFFER.write().unwrap();
    buffer.push(entry);
    let buffer_size = buffer.len();
    debug!(
        "[incremental] Added doc {} to buffer, size: {}",
        doc_id, buffer_size
    );
    if buffer_size >= BUFFER_THRESHOLD {
        warn!(
            "[incremental] Buffer threshold reached ({}), consider calling merge_buffer()",
            buffer_size
        );
    }
}

/// Add multiple vectors to buffer.
pub fn incremental_add_batch(docs: Vec<(i64, Vec<f32>)>) {
    let mut buffer = RECENT_BUFFER.write().unwrap();
    for (doc_id, embedding) in docs {
        buffer.push(BufferEntry::new(doc_id, embedding));
    }
    info!(
        "[incremental] Added batch to buffer, total size: {}",
        buffer.len()
    );
}

/// Remove a document from buffer.
pub fn incremental_remove(doc_id: i64) {
    let mut buffer = RECENT_BUFFER.write().unwrap();
    let initial_len = buffer.len();
    buffer.retain(|entry| entry.id != doc_id);
    if buffer.len() < initial_len {
        debug!("[incremental] Removed doc {} from buffer", doc_id);
    }
}

#[derive(Debug, Clone)]
pub struct IncrementalSearchResult {
    pub doc_id: i64,
    pub distance: f32,
    pub source: String,
}

/// Search both buffer and HNSW.
pub fn incremental_search(
    query_embedding: Vec<f32>,
    top_k: usize,
) -> anyhow::Result<Vec<IncrementalSearchResult>> {
    #[cfg(not(feature = "vector_quant_i8"))]
    let query_norm = l2_norm_f32(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let (query_i8, _query_i8_scale) = quantize_f32_to_i8(&query_embedding);
    #[cfg(feature = "vector_quant_i8")]
    let query_i8_norm = l2_norm_i8(&query_i8);
    let mut all_results: Vec<(i64, f32, &str)> = Vec::new();

    {
        let buffer = RECENT_BUFFER.read().unwrap();
        for entry in buffer.iter() {
            #[cfg(feature = "vector_quant_i8")]
            let distance = entry.cosine_distance_i8(&query_i8, query_i8_norm);
            #[cfg(not(feature = "vector_quant_i8"))]
            let distance = entry.cosine_distance(&query_embedding, query_norm);
            all_results.push((entry.id, distance, "buffer"));
        }
    }

    if is_hnsw_index_loaded() {
        let hnsw_results = search_hnsw(query_embedding.clone(), top_k * 2)?;
        for result in hnsw_results {
            all_results.push((result.id, result.distance, "hnsw"));
        }
    }

    all_results.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));

    let mut seen = std::collections::HashSet::new();
    let results: Vec<IncrementalSearchResult> = all_results
        .into_iter()
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

/// Clear buffer.
pub fn clear_buffer() {
    let mut buffer = RECENT_BUFFER.write().unwrap();
    buffer.clear();
    info!("[incremental] Buffer cleared");
}

/// Check if buffer needs merging.
pub fn needs_merge() -> bool {
    RECENT_BUFFER.read().unwrap().len() >= BUFFER_THRESHOLD
}

/// Get buffer entries for HNSW rebuild.
pub fn get_buffer_for_merge() -> Vec<(i64, Vec<f32>)> {
    RECENT_BUFFER
        .read()
        .unwrap()
        .iter()
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
        clear_buffer();
        incremental_add(1, make_embedding(1.0));
        incremental_add(2, make_embedding(2.0));
        let results = incremental_search(make_embedding(1.0), 3).unwrap();
        assert_eq!(results[0].doc_id, 1);
        clear_buffer();
    }
}
