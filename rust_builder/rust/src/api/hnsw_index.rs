// Copyright 2026 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT

use crate::api::custom_hnsw::{HnswBuilder, MmapHnswSearcher};
use log::{debug, info, warn};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::RwLock;

/// Embedding point wrapper for FRB compatibility (legacy support).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EmbeddingPoint {
    pub id: i64,
    pub embedding: Vec<f32>,
    pub norm: f32,
}

impl EmbeddingPoint {
    pub fn new(id: i64, embedding: Vec<f32>) -> Self {
        let norm = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();
        Self {
            id,
            embedding,
            norm,
        }
    }
}

/// Global HNSW search index (read-only mmap).
pub static HNSW_INDEX: Lazy<RwLock<Option<MmapHnswSearcher>>> = Lazy::new(|| RwLock::new(None));

/// Global HNSW builder (in-memory, during rebuild).
pub static HNSW_BUILDER: Lazy<RwLock<Option<HnswBuilder>>> = Lazy::new(|| RwLock::new(None));

fn hnsw_build_params(count: usize) -> (usize, usize, usize, &'static str) {
    if count > 10_000 {
        (24, 48, 200, "large (>10K)")
    } else if count > 1_000 {
        (20, 40, 150, "medium (1K-10K)")
    } else {
        (16, 32, 100, "small (<1K)")
    }
}

/// Build HNSW index from an iterator of embedding points.
pub(crate) fn build_hnsw_index_streaming<I>(
    point_count_hint: usize,
    points: I,
) -> anyhow::Result<usize>
where
    I: IntoIterator<Item = (i64, Vec<f32>)>,
{
    info!(
        "[hnsw] Building index with {} point capacity hint",
        point_count_hint
    );

    let capacity = point_count_hint.max(1);
    let (m, m0, ef_construction, _size_category) = hnsw_build_params(capacity);

    debug!(
        "[hnsw] Using M={}, M0={}, efConstruction={}",
        m, m0, ef_construction
    );

    let mut builder = HnswBuilder::new(m, m0, ef_construction);
    let mut inserted = 0usize;

    for (id, embedding) in points {
        if embedding.is_empty() {
            continue;
        }
        builder.insert(id, embedding);
        inserted += 1;
    }

    if inserted == 0 {
        warn!("[hnsw] No points provided");
        return Ok(0);
    }

    let mut builder_guard = HNSW_BUILDER.write().unwrap();
    *builder_guard = Some(builder);

    info!(
        "[hnsw] Index build complete (inserted={}, M={}, M0={}, efC={})",
        inserted, m, m0, ef_construction
    );
    Ok(inserted)
}

pub fn build_hnsw_index(points: Vec<(i64, Vec<f32>)>) -> anyhow::Result<()> {
    let point_count = points.len();
    let _ = build_hnsw_index_streaming(point_count, points)?;
    Ok(())
}

/// Save HNSW index to disk.
pub fn save_hnsw_index(base_path: &str) -> anyhow::Result<()> {
    info!("[hnsw] Saving index to {}", base_path);

    let builder_guard = HNSW_BUILDER.read().unwrap();
    let builder = match builder_guard.as_ref() {
        Some(b) => b,
        None => {
            warn!("[hnsw] Builder not initialized, skipping save");
            return Ok(());
        }
    };

    if builder.nodes.is_empty() {
        warn!("[hnsw] Index is empty, skipping save to avoid crash");
        return Ok(());
    }

    let file_path = format!("{}.hnsw", base_path);
    builder.save_to_disk(&file_path)?;

    info!("[hnsw] Index saved successfully to {}", file_path);

    // Attempt to load it into HNSW_INDEX immediately
    drop(builder_guard);
    load_hnsw_index(base_path)?;

    // Free the in-memory builder since we now use the MMAP index
    {
        let mut write_guard = HNSW_BUILDER.write().unwrap();
        *write_guard = None;
        info!("[hnsw] Freed in-memory builder after saving to disk");
    }

    Ok(())
}

/// Load HNSW index from disk.
pub fn load_hnsw_index(base_path: &str) -> anyhow::Result<bool> {
    let file_path = format!("{}.hnsw", base_path);
    let path = Path::new(&file_path);

    if !path.exists() {
        debug!("[hnsw] No index file found at {:?}", path);
        return Ok(false);
    }

    info!("[hnsw] Loading index from {}", file_path);

    match MmapHnswSearcher::new(&file_path) {
        Ok(searcher) => {
            let mut index_guard = HNSW_INDEX.write().unwrap();
            *index_guard = Some(searcher);
            info!("[hnsw] Index loaded successfully");
            Ok(true)
        }
        Err(e) => {
            println!("[hnsw] Failed to load index: {}. Rebuild required.", e);
            warn!("[hnsw] Failed to load index: {}. Rebuild required.", e);
            Ok(false)
        }
    }
}

/// HNSW search result containing doc ID and distance.
#[derive(Debug)]
pub struct HnswSearchResult {
    pub id: i64,
    pub distance: f32,
}

pub fn search_hnsw(
    query_embedding: Vec<f32>,
    top_k: usize,
) -> anyhow::Result<Vec<HnswSearchResult>> {
    search_hnsw_slice(&query_embedding, top_k)
}

pub fn search_hnsw_slice(
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

    let neighbors = neighbors
        .ok_or_else(|| anyhow::anyhow!("HNSW index not initialized (neither MMAP nor Builder)"))?;

    let mut results: Vec<HnswSearchResult> = neighbors
        .into_iter()
        .map(|(id, distance)| HnswSearchResult { id, distance })
        .collect();

    results.sort_by(|a, b| a.distance.partial_cmp(&b.distance).unwrap());
    results.truncate(top_k);

    debug!("[hnsw] Returning {} results", results.len());
    Ok(results)
}

pub fn is_hnsw_index_loaded() -> bool {
    let index_guard = HNSW_INDEX.read().unwrap();
    if index_guard.is_some() {
        return true;
    }
    let builder_guard = HNSW_BUILDER.read().unwrap();
    builder_guard.is_some()
}

pub fn clear_hnsw_index() {
    let mut index_guard = HNSW_INDEX.write().unwrap();
    *index_guard = None;
    let mut builder_guard = HNSW_BUILDER.write().unwrap();
    *builder_guard = None;
    info!("[hnsw] Index cleared");
}
