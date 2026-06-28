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
//! HNSW (Hierarchical Navigable Small Worlds) vector indexing module.

use hnsw_rs::hnswio::*;
use hnsw_rs::prelude::*;
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

/// Global HNSW index (thread-safe in-memory cache).
static HNSW_INDEX: Lazy<RwLock<Option<Hnsw<'static, f32, DistCosine>>>> =
    Lazy::new(|| RwLock::new(None));

/// Build HNSW index from embedding points.
///
/// Parameters are tuned for optimal recall vs speed tradeoff:
/// - M (max connections per node): 16-24 based on dataset size
/// - M0 (layer 0 connections): 2*M for better recall
/// - efConstruction: 100-200 based on dataset size
pub fn build_hnsw_index(points: Vec<(i64, Vec<f32>)>) -> anyhow::Result<()> {
    info!("[hnsw] Building index with {} points", points.len());

    if points.is_empty() {
        warn!("[hnsw] No points provided");
        return Ok(());
    }

    let count = points.len();

    // Adaptive parameters based on dataset size
    // - Small datasets (<1000): faster build, adequate recall
    // - Large datasets (>10000): higher quality, better recall
    let (m, m0, ef_construction, _size_category) = if count > 10_000 {
        (24, 48, 200, "large (>10K)")
    } else if count > 1_000 {
        (20, 40, 150, "medium (1K-10K)")
    } else {
        (16, 32, 100, "small (<1K)")
    };

    // Debug output for Flutter console (only in debug builds)
    #[cfg(debug_assertions)]
    {
        println!("[HNSW] Dataset size: {} points ({})", count, _size_category);
        println!(
            "[HNSW] Parameters: M={}, M0={}, efConstruction={}",
            m, m0, ef_construction
        );
        println!(
            "[HNSW] Expected recall: ~{}%",
            if count > 10_000 {
                "97"
            } else if count > 1_000 {
                "95"
            } else {
                "92"
            }
        );
    }

    debug!(
        "[hnsw] Using M={}, M0={}, efConstruction={}",
        m, m0, ef_construction
    );

    let hnsw = Hnsw::new(m, count, m0, ef_construction, DistCosine);

    for (id, embedding) in points {
        hnsw.insert((&embedding, id as usize));
    }

    let mut index_guard = HNSW_INDEX.write().unwrap();
    *index_guard = Some(hnsw);

    #[cfg(debug_assertions)]
    println!("[HNSW] ✅ Index build complete");

    info!(
        "[hnsw] Index build complete (M={}, M0={}, efC={})",
        m, m0, ef_construction
    );
    Ok(())
}

/// Save HNSW index to disk using hnsw_rs persistence.
///
/// This saves the full graph and data to a directory specified by [base_path].
pub fn save_hnsw_index(base_path: &str) -> anyhow::Result<()> {
    info!("[hnsw] Saving index to {}", base_path);

    let index_guard = HNSW_INDEX.read().unwrap();

    let index = match index_guard.as_ref() {
        Some(idx) => idx,
        None => {
            warn!("[hnsw] Index not initialized (empty), skipping save");
            return Ok(());
        }
    };

    if index.get_nb_point() == 0 {
        warn!("[hnsw] Index is empty, skipping save to avoid crash");
        return Ok(());
    }

    let path = Path::new(base_path);
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Invalid base path"))?;
    let file_stem = path
        .file_stem()
        .ok_or_else(|| anyhow::anyhow!("Invalid filename"))?;
    // Convert OsStr to String, which file_dump expects for filename base
    let filename = file_stem
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid UTF-8 filename"))?;

    // Create directory if it doesn't exist
    std::fs::create_dir_all(parent)?;

    // hnsw_rs 0.3 file_dump takes (directory, filename_base)
    index.file_dump(parent, filename)?;

    info!("[hnsw] Index saved successfully");
    Ok(())
}

/// Load HNSW index from disk.
///
/// Returns true if the index was successfully loaded into memory.
pub fn load_hnsw_index(base_path: &str) -> anyhow::Result<bool> {
    // Check if the primary data file exists to avoid unnecessary log noise
    // hnsw_rs adds .hnsw.data and .hnsw.graph to the base name (which is the file stem)
    let path = Path::new(base_path);
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Invalid base path"))?;
    let file_stem = path
        .file_stem()
        .ok_or_else(|| anyhow::anyhow!("Invalid filename"))?;
    let filename = file_stem
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid UTF-8 filename"))?;

    let data_path = parent.join(format!("{}.hnsw.data", filename));

    if !data_path.exists() {
        debug!("[hnsw] No index files found at {:?}", data_path);
        return Ok(false);
    }

    info!("[hnsw] Loading index from {}", base_path);

    // hnsw_rs 0.3 load_hnsw is a method of HnswIo
    let hnswio = HnswIo::new(parent, filename);

    // We need to extend the lifetime of hnswio to 'static because HNSW_INDEX is static.
    // Hnsw<'b> borrows from HnswIo if mmap is used (or is tied to it by signature).
    // By leaking the Box, we get a &'static mut HnswIo, allowing load_hnsw to return Hnsw<'static>.
    let hnswio = Box::leak(Box::new(hnswio));

    // hnsw_rs load_hnsw reconstructs the index from files
    // DistCosine must match the one used during build
    match hnswio.load_hnsw::<f32, DistCosine>() {
        Ok(hnsw) => {
            let mut index_guard = HNSW_INDEX.write().unwrap();
            *index_guard = Some(hnsw);
            info!("[hnsw] Index loaded successfully");
            Ok(true)
        }
        Err(e) => {
            // If loading fails, we technically leaked hnswio memory, but this happens rarely (only on error)
            // and it's a small struct (path + options), so it's acceptable for this use case.
            // Ideally we would reconstruct the box and drop it, but error handling complexity outweighs benefit here.
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

/// Search in HNSW index.
///
/// Owned-vector entrypoint kept stable for the flutter_rust_bridge surface;
/// delegates to the slice-based implementation so internal Rust callers can
/// avoid `Vec<f32>` allocations on hot paths.
///
/// ef_search parameter controls accuracy vs speed:
/// - Higher ef_search = better recall but slower
/// - Lower ef_search = faster but may miss relevant results
///
/// Current tuning targets ~95% recall for most use cases.
pub fn search_hnsw(
    query_embedding: Vec<f32>,
    top_k: usize,
) -> anyhow::Result<Vec<HnswSearchResult>> {
    search_hnsw_slice(&query_embedding, top_k)
}

/// Slice-based variant of [`search_hnsw`]. Internal Rust callers should
/// prefer this entrypoint when the query embedding is already held by
/// reference (e.g. inside `std::thread::scope` closures or retry loops)
/// so the vector does not need to be cloned per call.
pub fn search_hnsw_slice(
    query_embedding: &[f32],
    top_k: usize,
) -> anyhow::Result<Vec<HnswSearchResult>> {
    debug!("[hnsw] Starting search, top_k: {}", top_k);

    let index_guard = HNSW_INDEX.read().unwrap();
    let index = index_guard
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("HNSW index not initialized"))?;

    // ef_search should be >= top_k, higher values improve recall
    // Rule of thumb: ef_search = max(100, top_k * 5) for ~95% recall
    let ef_search = core::cmp::max(100, top_k * 5);

    #[cfg(debug_assertions)]
    println!(
        "[HNSW] Search: top_k={}, ef_search={} (recall target: ~95%)",
        top_k, ef_search
    );

    debug!("[hnsw] Using ef_search={}", ef_search);

    let neighbors = index.search(query_embedding, top_k, ef_search);

    let results: Vec<HnswSearchResult> = neighbors
        .iter()
        .map(|neighbor| HnswSearchResult {
            id: neighbor.d_id as i64,
            distance: neighbor.distance,
        })
        .collect();

    #[cfg(debug_assertions)]
    println!("[HNSW] Found {} results", results.len());

    debug!("[hnsw] Returning {} results", results.len());
    Ok(results)
}

/// Check if HNSW index is loaded.
pub fn is_hnsw_index_loaded() -> bool {
    let index_guard = HNSW_INDEX.read().unwrap();
    index_guard.is_some()
}

/// Clear HNSW index from memory.
pub fn clear_hnsw_index() {
    let mut index_guard = HNSW_INDEX.write().unwrap();
    *index_guard = None;
    info!("[hnsw] Index cleared");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_random_embedding(seed: u64, dims: usize) -> Vec<f32> {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        (0..dims)
            .map(|i| {
                let mut h = DefaultHasher::new();
                (seed + i as u64).hash(&mut h);
                (h.finish() as f32 / u64::MAX as f32) * 2.0 - 1.0
            })
            .collect()
    }

    #[test]
    fn test_build_empty_index() {
        let result = build_hnsw_index(vec![]);
        assert!(result.is_ok());
        assert!(!is_hnsw_index_loaded());
    }

    #[test]
    fn test_build_and_search() {
        clear_hnsw_index();
        let points: Vec<(i64, Vec<f32>)> = (0..100)
            .map(|i| (i, make_random_embedding(i as u64, 384)))
            .collect();
        build_hnsw_index(points).unwrap();
        assert!(is_hnsw_index_loaded());

        let query = make_random_embedding(0, 384);
        let results = search_hnsw(query, 5).unwrap();
        assert_eq!(results.len(), 5);
        // Same embedding should return itself as closest
        assert_eq!(results[0].id, 0);
        clear_hnsw_index();
    }

    #[test]
    fn test_clear_index() {
        let points = vec![(1, make_random_embedding(1, 384))];
        build_hnsw_index(points).unwrap();
        assert!(is_hnsw_index_loaded());
        clear_hnsw_index();
        assert!(!is_hnsw_index_loaded());
    }
}
