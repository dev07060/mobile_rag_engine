use crate::api::vector_math::{dot_f32, l2_norm_f32};
use crate::api::vector_quant::{
    cosine_similarity_active_quantized, quantize_f32_for_active_profile, ActiveQuantizedQuery,
};
use anyhow::{Context, Result};
use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};
use flutter_rust_bridge::frb;
use memmap2::{Mmap, MmapOptions};
use rand::Rng;
use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::fs::File;
use std::io::Cursor;
use std::io::{BufWriter, Write};
use std::path::Path;

#[cfg(test)]
fn cosine_distance(a: &[f32], b: &[f32]) -> f32 {
    let mut dot = 0.0;
    let mut norm_a = 0.0;
    let mut norm_b = 0.0;
    for i in 0..a.len() {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }
    if norm_a == 0.0 || norm_b == 0.0 {
        return 1.0;
    }
    let sim = dot / (norm_a.sqrt() * norm_b.sqrt());
    1.0 - sim.max(-1.0).min(1.0)
}

#[derive(Clone)]
pub struct Node {
    pub id: i64,
    pub vector: Vec<f32>,
    pub max_layer: usize,
    pub connections: Vec<Vec<usize>>,
}

#[derive(Clone, Copy)]
struct DistNode {
    index: usize,
    dist: f32,
}

impl PartialEq for DistNode {
    fn eq(&self, other: &Self) -> bool {
        self.dist == other.dist
    }
}
impl Eq for DistNode {}
impl PartialOrd for DistNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        self.dist.partial_cmp(&other.dist)
    }
}
impl Ord for DistNode {
    fn cmp(&self, other: &Self) -> Ordering {
        self.partial_cmp(other).unwrap_or(Ordering::Equal)
    }
}

/// Visited marks for one search, one bit per node index.
struct VisitedSet(Vec<u64>);

impl VisitedSet {
    fn new(len: usize) -> Self {
        Self(vec![0; len.div_ceil(64)])
    }

    /// Marks `index` and returns true if it was not visited before.
    fn insert(&mut self, index: usize) -> bool {
        let (word, bit) = (index / 64, 1u64 << (index % 64));
        if word >= self.0.len() {
            self.0.resize(word + 1, 0);
        }
        let fresh = self.0[word] & bit == 0;
        self.0[word] |= bit;
        fresh
    }
}

/// Beam state for one HNSW layer search: a min-heap of candidates to expand and
/// a max-heap holding the best `ef` results, so each step is O(log ef).
struct BeamFrontier {
    ef: usize,
    candidates: BinaryHeap<std::cmp::Reverse<DistNode>>,
    results: BinaryHeap<DistNode>,
}

impl BeamFrontier {
    fn new(ef: usize) -> Self {
        let ef = ef.max(1);
        Self {
            ef,
            candidates: BinaryHeap::new(),
            results: BinaryHeap::with_capacity(ef + 1),
        }
    }

    fn furthest(&self) -> f32 {
        if self.results.len() >= self.ef {
            self.results.peek().map_or(f32::MAX, |n| n.dist)
        } else {
            f32::MAX
        }
    }

    /// Adds a visited node if it can still improve the results.
    fn offer(&mut self, index: usize, dist: f32) {
        if self.results.len() < self.ef || dist < self.furthest() {
            let node = DistNode { index, dist };
            self.candidates.push(std::cmp::Reverse(node));
            self.results.push(node);
            if self.results.len() > self.ef {
                self.results.pop();
            }
        }
    }

    /// The closest unexpanded candidate, or None once it is further than every result.
    fn next_candidate(&mut self) -> Option<DistNode> {
        let std::cmp::Reverse(c) = self.candidates.pop()?;
        if c.dist > self.furthest() {
            None
        } else {
            Some(c)
        }
    }

    fn into_sorted(self) -> Vec<DistNode> {
        self.results.into_sorted_vec()
    }
}

#[frb(ignore)]
pub struct HnswBuilder {
    pub nodes: Vec<Node>,
    pub entry_point: Option<usize>,
    pub max_layer: usize,
    pub m: usize,
    pub m0: usize,
    pub ef_construction: usize,
    ml: f32,
    // L2 norm of each node's vector, parallel to `nodes`. Rebuilt on insert
    // when `nodes` was assigned directly.
    norms: Vec<f32>,
}

impl HnswBuilder {
    pub fn new(m: usize, m0: usize, ef_construction: usize) -> Self {
        let ml = 1.0 / (m as f32).ln();
        Self {
            nodes: Vec::new(),
            entry_point: None,
            max_layer: 0,
            m,
            m0,
            ef_construction,
            ml,
            norms: Vec::new(),
        }
    }

    fn node_norm(&self, idx: usize) -> f32 {
        match self.norms.get(idx) {
            Some(&norm) if self.norms.len() == self.nodes.len() => norm,
            _ => l2_norm_f32(&self.nodes[idx].vector),
        }
    }

    /// Cosine distance from `query` (with precomputed `query_norm`) to node `idx`.
    fn distance_to(&self, query: &[f32], query_norm: f32, idx: usize) -> f32 {
        let node_norm = self.node_norm(idx);
        if query_norm == 0.0 || node_norm == 0.0 {
            return 1.0;
        }
        let sim = dot_f32(query, &self.nodes[idx].vector) / (query_norm * node_norm);
        1.0 - sim.clamp(-1.0, 1.0)
    }

    fn random_layer(&self) -> usize {
        let mut rng = rand::thread_rng();
        let r: f32 = rng.gen_range(0.0001..1.0);
        (-r.ln() * self.ml) as usize
    }

    fn search_layer(
        &self,
        query: &[f32],
        query_norm: f32,
        entry_points: &[usize],
        ef: usize,
        lc: usize,
    ) -> Vec<DistNode> {
        let mut visited = VisitedSet::new(self.nodes.len());
        let mut frontier = BeamFrontier::new(ef);

        for &ep in entry_points {
            if visited.insert(ep) {
                frontier.offer(ep, self.distance_to(query, query_norm, ep));
            }
        }

        while let Some(c) = frontier.next_candidate() {
            for &neighbor in &self.nodes[c.index].connections[lc] {
                if visited.insert(neighbor) {
                    frontier.offer(neighbor, self.distance_to(query, query_norm, neighbor));
                }
            }
        }

        frontier.into_sorted()
    }

    pub fn insert(&mut self, id: i64, vector: Vec<f32>) {
        let layer = self.random_layer();
        let new_idx = self.nodes.len();
        if self.norms.len() != self.nodes.len() {
            self.norms = self.nodes.iter().map(|n| l2_norm_f32(&n.vector)).collect();
        }
        let vector_norm = l2_norm_f32(&vector);

        let mut new_connections = vec![Vec::new(); layer + 1];

        if self.entry_point.is_none() {
            self.entry_point = Some(new_idx);
            self.max_layer = layer;
            self.norms.push(vector_norm);
            self.nodes.push(Node {
                id,
                vector,
                max_layer: layer,
                connections: new_connections,
            });
            return;
        }

        let mut curr_ep = self.entry_point.unwrap();
        let curr_max_layer = self.max_layer;

        // Phase 1: greedy search down to layer + 1
        for lc in (layer + 1..=curr_max_layer).rev() {
            let mut curr_dist = self.distance_to(&vector, vector_norm, curr_ep);
            let mut changed = true;
            while changed {
                changed = false;
                for &neighbor in &self.nodes[curr_ep].connections[lc] {
                    let d = self.distance_to(&vector, vector_norm, neighbor);
                    if d < curr_dist {
                        curr_dist = d;
                        curr_ep = neighbor;
                        changed = true;
                    }
                }
            }
        }

        let start_layer = layer.min(curr_max_layer);
        let mut eps = vec![curr_ep];

        for lc in (0..=start_layer).rev() {
            let m_max = if lc == 0 { self.m0 } else { self.m };
            // search_layer returns the results sorted by distance.
            let mut best_n = self.search_layer(&vector, vector_norm, &eps, self.ef_construction, lc);
            best_n.truncate(m_max);

            for n in &best_n {
                new_connections[lc].push(n.index);
            }

            eps = best_n.into_iter().map(|n| n.index).collect();
        }

        // Add node
        self.norms.push(vector_norm);
        self.nodes.push(Node {
            id,
            vector: vector.clone(),
            max_layer: layer,
            connections: new_connections.clone(),
        });

        // Add reverse connections
        for lc in 0..=start_layer {
            let m_max = if lc == 0 { self.m0 } else { self.m };
            for &n_idx in &new_connections[lc] {
                self.nodes[n_idx].connections[lc].push(new_idx);

                // Prune
                if self.nodes[n_idx].connections[lc].len() > m_max {
                    let node = &self.nodes[n_idx];
                    let node_norm = self.node_norm(n_idx);
                    let mut dists: Vec<_> = node.connections[lc]
                        .iter()
                        .map(|&idx| DistNode {
                            index: idx,
                            dist: self.distance_to(&node.vector, node_norm, idx),
                        })
                        .collect();
                    dists.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
                    dists.truncate(m_max);
                    self.nodes[n_idx].connections[lc] =
                        dists.into_iter().map(|d| d.index).collect();
                }
            }
        }

        if layer > curr_max_layer {
            self.max_layer = layer;
            self.entry_point = Some(new_idx);
        }
    }

    pub fn search(&self, query: &[f32], ef: usize) -> Vec<(i64, f32)> {
        if self.nodes.is_empty() || self.entry_point.is_none() {
            return Vec::new();
        }

        let mut curr_ep = self.entry_point.unwrap();
        let curr_max_layer = self.max_layer;
        let query_norm = l2_norm_f32(query);

        // Phase 1: greedy search down to layer + 1
        for lc in (1..=curr_max_layer).rev() {
            let mut curr_dist = self.distance_to(query, query_norm, curr_ep);
            let mut changed = true;
            while changed {
                changed = false;
                for &neighbor in &self.nodes[curr_ep].connections[lc] {
                    let d = self.distance_to(query, query_norm, neighbor);
                    if d < curr_dist {
                        curr_dist = d;
                        curr_ep = neighbor;
                        changed = true;
                    }
                }
            }
        }

        // Phase 2: search layer 0 with ef
        let eps = vec![curr_ep];
        self.search_layer(query, query_norm, &eps, ef, 0)
            .into_iter()
            .map(|n| (self.nodes[n.index].id, n.dist))
            .collect()
    }

    pub fn save_to_disk(&self, file_path: &str) -> Result<()> {
        let path = Path::new(file_path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let tmp_path = format!("{}.tmp", file_path);

        // Block to ensure file is closed and flushed before rename
        {
            let file = File::create(&tmp_path)?;
            let mut writer = BufWriter::new(file);

            // Header
            writer.write_all(b"HNSW")?;
            writer.write_u8(1)?; // version
            writer.write_u32::<LittleEndian>(self.entry_point.unwrap_or(0) as u32)?;
            writer.write_u8(self.max_layer as u8)?;
            writer.write_u32::<LittleEndian>(self.nodes.len() as u32)?;
            let f32_dim = if self.nodes.is_empty() {
                0
            } else {
                self.nodes[0].vector.len()
            };
            if self.nodes.iter().any(|node| node.vector.len() != f32_dim) {
                anyhow::bail!("HNSW index contains mixed embedding dimensions");
            }
            let blob_len = if f32_dim > 0 {
                quantize_f32_for_active_profile(&self.nodes[0].vector)
                    .map_err(|error| anyhow::anyhow!(error.to_string()))?
                    .0
                    .len()
            } else {
                0
            };
            writer.write_u32::<LittleEndian>(blob_len as u32)?;

            if !self.nodes.is_empty() {
                // Compute offsets for each node data
                let mut current_offset = 4 + 1 + 4 + 1 + 4 + 4 + (self.nodes.len() * 4) as u32; // Header + Directory
                let mut directory = Vec::with_capacity(self.nodes.len());

                for node in &self.nodes {
                    directory.push(current_offset);
                    let mut node_size = 8 + 1 + blob_len; // DataID (8), MaxLayer (1), Vector (dim*4)
                    for lc in (0..=node.max_layer).rev() {
                        node_size += 2 + node.connections[lc].len() * 4; // NumConnections (2) + IDs (4 each)
                    }
                    current_offset += node_size as u32;
                }

                // Write Directory
                for offset in directory {
                    writer.write_u32::<LittleEndian>(offset)?;
                }

                // Write Node Data
                for node in &self.nodes {
                    writer.write_i64::<LittleEndian>(node.id)?;
                    let (quantized_blob, _scale) = quantize_f32_for_active_profile(&node.vector)
                        .map_err(|error| anyhow::anyhow!(error.to_string()))?;
                    writer.write_all(&quantized_blob)?;
                    writer.write_u8(node.max_layer as u8)?;
                    for lc in (0..=node.max_layer).rev() {
                        writer.write_u16::<LittleEndian>(node.connections[lc].len() as u16)?;
                        for &neighbor in &node.connections[lc] {
                            writer.write_u32::<LittleEndian>(neighbor as u32)?;
                        }
                    }
                }
            }
            writer.flush()?;
            // writer goes out of scope and flushes, file closes
        }

        std::fs::rename(&tmp_path, file_path)?;

        Ok(())
    }
}

// ---------------------------------------------------------
// MMAP HNSW Searcher
// ---------------------------------------------------------

#[frb(ignore)]
pub struct MmapHnswSearcher {
    mmap: Mmap,
    entry_point: u32,
    max_layer: u8,
    num_nodes: u32,
    blob_len: u32,
}

impl MmapHnswSearcher {
    pub fn new(path: &str) -> Result<Self> {
        let file = File::open(path).context("Failed to open custom HNSW file")?;
        let mmap = unsafe { MmapOptions::new().map(&file)? };

        if mmap.len() < 18 {
            anyhow::bail!("Invalid HNSW file: too small");
        }

        let mut cursor = Cursor::new(&mmap[..18]);
        let mut magic = [0u8; 4];
        std::io::Read::read_exact(&mut cursor, &mut magic)?;
        if &magic != b"HNSW" {
            anyhow::bail!("Invalid HNSW file: bad magic");
        }

        let version = cursor.read_u8()?;
        if version != 1 {
            anyhow::bail!("Invalid HNSW file: unsupported version");
        }

        let entry_point = cursor.read_u32::<LittleEndian>()?;
        let max_layer = cursor.read_u8()?;
        let num_nodes = cursor.read_u32::<LittleEndian>()?;
        let blob_len = cursor.read_u32::<LittleEndian>()?;

        let searcher = Self {
            mmap,
            entry_point,
            max_layer,
            num_nodes,
            blob_len,
        };
        searcher.validate_layout()?;
        Ok(searcher)
    }

    /// Walk the directory and every node record once so a truncated or
    /// corrupted file is rejected here: `search` reads with unchecked offsets
    /// and would otherwise panic on an out-of-bounds slice.
    fn validate_layout(&self) -> Result<()> {
        let len = self.mmap.len();
        let num_nodes = self.num_nodes as usize;
        let data_start = 18 + num_nodes * 4;
        if data_start > len {
            anyhow::bail!("Invalid HNSW file: truncated node directory");
        }
        if num_nodes == 0 {
            return Ok(());
        }
        if self.entry_point as usize >= num_nodes {
            anyhow::bail!("Invalid HNSW file: entry point out of range");
        }

        let read_u16 = |pos: usize| u16::from_le_bytes([self.mmap[pos], self.mmap[pos + 1]]);
        let mut expected = data_start;
        for index in 0..self.num_nodes {
            if self.get_node_offset(index) != expected {
                anyhow::bail!("Invalid HNSW file: node directory does not match node data");
            }
            let mut pos = expected + 8 + self.blob_len as usize;
            if pos >= len {
                anyhow::bail!("Invalid HNSW file: truncated node record");
            }
            let node_max_layer = self.mmap[pos];
            if node_max_layer > self.max_layer {
                anyhow::bail!("Invalid HNSW file: node layer above index max layer");
            }
            pos += 1;
            for _ in 0..=node_max_layer {
                if pos + 2 > len {
                    anyhow::bail!("Invalid HNSW file: truncated node connections");
                }
                let num_conn = read_u16(pos) as usize;
                pos += 2;
                let end = pos + num_conn * 4;
                if end > len {
                    anyhow::bail!("Invalid HNSW file: truncated node connections");
                }
                for conn in (pos..end).step_by(4) {
                    let neighbor = u32::from_le_bytes([
                        self.mmap[conn],
                        self.mmap[conn + 1],
                        self.mmap[conn + 2],
                        self.mmap[conn + 3],
                    ]);
                    if neighbor >= self.num_nodes {
                        anyhow::bail!("Invalid HNSW file: neighbor index out of range");
                    }
                }
                pos = end;
            }
            expected = pos;
        }
        if expected != len {
            anyhow::bail!("Invalid HNSW file: unexpected trailing bytes");
        }
        Ok(())
    }

    pub fn get_num_nodes(&self) -> u32 {
        self.num_nodes
    }

    fn get_node_offset(&self, index: u32) -> usize {
        let dir_offset = 18 + (index as usize) * 4;
        let mut cursor = Cursor::new(&self.mmap[dir_offset..dir_offset + 4]);
        cursor.read_u32::<LittleEndian>().unwrap() as usize
    }

    // F: distance function taking a DataID
    fn get_node_vector(&self, offset: usize) -> &[u8] {
        let vec_offset = offset + 8;
        let bytes = &self.mmap[vec_offset..vec_offset + (self.blob_len as usize)];
        bytes
    }

    pub(crate) fn search(
        &self,
        query: &ActiveQuantizedQuery,
        ef: usize,
    ) -> Result<Vec<(i64, f32)>> {
        let distance_fn = |offset: usize| -> Result<f32> {
            let vec = self.get_node_vector(offset);
            Ok(1.0
                - cosine_similarity_active_quantized(query, vec)
                    .map_err(|error| anyhow::anyhow!(error.to_string()))?)
        };

        if self.num_nodes == 0 {
            return Ok(Vec::new());
        }

        let mut curr_ep = self.entry_point;

        // Phase 1: greedy search down to layer 1
        for lc in (1..=self.max_layer).rev() {
            let mut curr_dist = distance_fn(self.get_node_offset(curr_ep))?;
            let mut changed = true;

            while changed {
                changed = false;

                let offset = self.get_node_offset(curr_ep);
                let mut cursor = Cursor::new(&self.mmap[offset..]);
                let _id = cursor.read_i64::<LittleEndian>().unwrap();
                cursor.set_position(cursor.position() + self.blob_len as u64); // skip vector
                let node_max_layer = cursor.read_u8().unwrap();

                // Skip layers above lc
                for _ in (lc + 1..=node_max_layer).rev() {
                    let num_conn = cursor.read_u16::<LittleEndian>().unwrap();
                    cursor.set_position(cursor.position() + num_conn as u64 * 4);
                }

                let num_conn = cursor.read_u16::<LittleEndian>().unwrap();
                for _ in 0..num_conn {
                    let neighbor_idx = cursor.read_u32::<LittleEndian>().unwrap();
                    let n_offset = self.get_node_offset(neighbor_idx);
                    let d = distance_fn(n_offset)?;
                    if d < curr_dist {
                        curr_dist = d;
                        curr_ep = neighbor_idx;
                        changed = true;
                    }
                }
            }
        }

        // Phase 2: search layer 0
        let mut visited = VisitedSet::new(self.num_nodes as usize);
        let mut frontier = BeamFrontier::new(ef);

        visited.insert(curr_ep as usize);
        frontier.offer(curr_ep as usize, distance_fn(self.get_node_offset(curr_ep))?);

        while let Some(c) = frontier.next_candidate() {
            let offset = self.get_node_offset(c.index as u32);
            let mut cursor = Cursor::new(&self.mmap[offset..]);
            let _id = cursor.read_i64::<LittleEndian>().unwrap();
            cursor.set_position(cursor.position() + self.blob_len as u64); // skip vector
            let node_max_layer = cursor.read_u8().unwrap();

            for _ in (1..=node_max_layer).rev() {
                let num_conn = cursor.read_u16::<LittleEndian>().unwrap();
                cursor.set_position(cursor.position() + num_conn as u64 * 4);
            }

            // Layer 0 connections
            let num_conn = cursor.read_u16::<LittleEndian>().unwrap();
            for _ in 0..num_conn {
                let neighbor_idx = cursor.read_u32::<LittleEndian>().unwrap();

                if visited.insert(neighbor_idx as usize) {
                    let d = distance_fn(self.get_node_offset(neighbor_idx))?;
                    frontier.offer(neighbor_idx as usize, d);
                }
            }
        }

        // Map indices to DataIDs
        Ok(frontier
            .into_sorted()
            .into_iter()
            .map(|n| {
                let offset = self.get_node_offset(n.index as u32);
                let data_id = Cursor::new(&self.mmap[offset..offset + 8])
                    .read_i64::<LittleEndian>()
                    .unwrap();
                (data_id, n.dist)
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::vector_quant::{active_quantized_query, configure_active_vabq_profile};
    use std::collections::HashSet;
    use tempfile::tempdir;

    #[test]
    fn mmap_search_preserves_builder_top_result_after_save() {
        let query: Vec<f32> = (0..384)
            .map(|index| if index % 2 == 0 { 1.0 } else { -0.5 })
            .collect();
        let near = query.clone();
        let far: Vec<f32> = query.iter().map(|value| -*value).collect();

        let mut builder = HnswBuilder::new(16, 32, 100);
        builder.nodes = vec![
            Node {
                id: 1,
                vector: near,
                max_layer: 0,
                connections: vec![vec![1]],
            },
            Node {
                id: 2,
                vector: far,
                max_layer: 0,
                connections: vec![vec![0]],
            },
        ];
        builder.entry_point = Some(1);
        builder.max_layer = 0;

        let builder_results = builder.search(&query, 2);
        assert_eq!(builder_results.first().map(|result| result.0), Some(1));

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("parity.hnsw");
        builder.save_to_disk(index_path.to_str().unwrap()).unwrap();

        let searcher = MmapHnswSearcher::new(index_path.to_str().unwrap()).unwrap();
        let active_query = active_quantized_query(&query).unwrap();
        let mmap_results = searcher.search(&active_query, 2).unwrap();

        assert_eq!(mmap_results.first().map(|result| result.0), Some(1));
    }

    #[test]
    fn mmap_search_uses_current_entry_point_at_each_upper_layer() {
        let mut query = vec![0.0f32; 384];
        query[0] = 1.0;

        let near = query.clone();
        let mut middle = vec![0.0f32; 384];
        middle[1] = 1.0;
        let mut detour = vec![0.0f32; 384];
        detour[0] = -0.5;
        detour[1] = 0.866_025_4;
        let far: Vec<f32> = query.iter().map(|value| -*value).collect();

        let mut builder = HnswBuilder::new(16, 32, 100);
        builder.nodes = vec![
            Node {
                id: 1,
                vector: near,
                max_layer: 0,
                connections: vec![vec![]],
            },
            Node {
                id: 2,
                vector: middle,
                max_layer: 2,
                connections: vec![vec![0], vec![3], vec![2]],
            },
            Node {
                id: 3,
                vector: far,
                max_layer: 2,
                connections: vec![vec![1], vec![1], vec![1]],
            },
            Node {
                id: 4,
                vector: detour,
                max_layer: 1,
                connections: vec![vec![], vec![]],
            },
        ];
        builder.entry_point = Some(2);
        builder.max_layer = 2;

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("current-entry-point.hnsw");
        builder.save_to_disk(index_path.to_str().unwrap()).unwrap();

        let searcher = MmapHnswSearcher::new(index_path.to_str().unwrap()).unwrap();
        let active_query = active_quantized_query(&query).unwrap();
        let results = searcher.search(&active_query, 1).unwrap();

        assert_eq!(results.first().map(|result| result.0), Some(1));
    }

    // Deterministic pseudo-random unit vectors (no rand seed control in the
    // builder's layer draw, so recall floors below keep a margin).
    fn lcg_vectors(count: usize, dim: usize, seed: u64) -> Vec<Vec<f32>> {
        let mut state = seed;
        (0..count)
            .map(|_| {
                let v: Vec<f32> = (0..dim)
                    .map(|_| {
                        state = state
                            .wrapping_mul(6_364_136_223_846_793_005)
                            .wrapping_add(1_442_695_040_888_963_407);
                        ((state >> 33) as f32 / (1u64 << 31) as f32) * 2.0 - 1.0
                    })
                    .collect();
                let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
                v.into_iter().map(|x| x / norm).collect()
            })
            .collect()
    }

    fn exact_top_k(corpus: &[Vec<f32>], query: &[f32], k: usize) -> Vec<i64> {
        let mut scored: Vec<(i64, f32)> = corpus
            .iter()
            .enumerate()
            .map(|(i, v)| (i as i64, cosine_distance(query, v)))
            .collect();
        scored.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        scored.into_iter().take(k).map(|(id, _)| id).collect()
    }

    fn recall_at_k(expected: &[i64], got: &[(i64, f32)], k: usize) -> f32 {
        let got: HashSet<i64> = got.iter().take(k).map(|(id, _)| *id).collect();
        expected.iter().filter(|id| got.contains(id)).count() as f32 / k as f32
    }

    // Mirrors the production build: hnsw_index::hnsw_build_params picks
    // (M, M0, efConstruction) by corpus size; search uses ef = max(100, 5 * top_k).
    fn build_index(corpus: &[Vec<f32>]) -> HnswBuilder {
        let (m, m0, ef_construction) = if corpus.len() > 10_000 {
            (24, 48, 200)
        } else if corpus.len() > 1_000 {
            (20, 40, 150)
        } else {
            (16, 32, 100)
        };
        let mut builder = HnswBuilder::new(m, m0, ef_construction);
        for (i, v) in corpus.iter().enumerate() {
            builder.insert(i as i64, v.clone());
        }
        builder
    }

    const RECALL_CORPUS: usize = 1500;
    const RECALL_DIM: usize = 384;
    const RECALL_QUERIES: usize = 50;
    const K: usize = 10;
    const PRODUCTION_EF: usize = 100;

    #[test]
    fn builder_recall_at_10_matches_exact_search() {
        let corpus = lcg_vectors(RECALL_CORPUS, RECALL_DIM, 7);
        let queries = lcg_vectors(RECALL_QUERIES, RECALL_DIM, 99);
        let builder = build_index(&corpus);

        let mean_recall = queries
            .iter()
            .map(|q| recall_at_k(&exact_top_k(&corpus, q, K), &builder.search(q, PRODUCTION_EF), K))
            .sum::<f32>()
            / RECALL_QUERIES as f32;
        println!("custom_hnsw builder recall@10 = {mean_recall}");
        assert!(mean_recall >= 0.95, "builder recall@10 {mean_recall} < 0.95");
    }

    // Build-time benchmark at production parameters. Run with:
    // HNSW_BENCH_N=20000 cargo test --release --features vector_faer --lib hnsw_build_benchmark -- --ignored --nocapture
    #[test]
    #[ignore]
    fn hnsw_build_benchmark() {
        let n: usize = std::env::var("HNSW_BENCH_N")
            .ok()
            .and_then(|value| value.parse().ok())
            .unwrap_or(5_000);
        let corpus = lcg_vectors(n, RECALL_DIM, 7);
        let queries = lcg_vectors(RECALL_QUERIES, RECALL_DIM, 99);

        let started = std::time::Instant::now();
        let builder = build_index(&corpus);
        let build = started.elapsed();

        let started = std::time::Instant::now();
        let results: Vec<_> = queries.iter().map(|q| builder.search(q, PRODUCTION_EF)).collect();
        let search = started.elapsed() / RECALL_QUERIES as u32;

        let mean_recall = queries
            .iter()
            .zip(&results)
            .map(|(q, got)| recall_at_k(&exact_top_k(&corpus, q, K), got, K))
            .sum::<f32>()
            / RECALL_QUERIES as f32;
        println!(
            "hnsw_build_benchmark n={n} build={build:?} search={search:?} recall@10={mean_recall}"
        );
    }

    #[test]
    fn mmap_recall_at_10_survives_save_and_load() {
        configure_active_vabq_profile(None, RECALL_DIM as i32).unwrap();
        let corpus = lcg_vectors(RECALL_CORPUS, RECALL_DIM, 7);
        let queries = lcg_vectors(RECALL_QUERIES, RECALL_DIM, 99);
        let builder = build_index(&corpus);

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("recall.hnsw");
        builder.save_to_disk(index_path.to_str().unwrap()).unwrap();
        let searcher = MmapHnswSearcher::new(index_path.to_str().unwrap()).unwrap();
        assert_eq!(searcher.get_num_nodes() as usize, RECALL_CORPUS);

        let mean_recall = queries
            .iter()
            .map(|q| {
                let active = active_quantized_query(q).unwrap();
                recall_at_k(&exact_top_k(&corpus, q, K), &searcher.search(&active, PRODUCTION_EF).unwrap(), K)
            })
            .sum::<f32>()
            / RECALL_QUERIES as f32;
        println!("custom_hnsw mmap (Q8_0) recall@10 = {mean_recall}");
        assert!(mean_recall >= 0.95, "mmap recall@10 {mean_recall} < 0.95");
    }

    #[test]
    fn empty_index_saves_loads_and_returns_no_results() {
        configure_active_vabq_profile(None, 4).unwrap();
        let builder = HnswBuilder::new(16, 32, 100);
        assert!(builder.search(&[1.0, 0.0, 0.0, 0.0], 10).is_empty());

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("empty.hnsw");
        builder.save_to_disk(index_path.to_str().unwrap()).unwrap();
        let searcher = MmapHnswSearcher::new(index_path.to_str().unwrap()).unwrap();
        let query = active_quantized_query(&[1.0, 0.0, 0.0, 0.0]).unwrap();
        assert!(searcher.search(&query, 10).unwrap().is_empty());
    }

    #[test]
    fn save_rejects_mixed_embedding_dimensions() {
        configure_active_vabq_profile(None, 4).unwrap();
        let mut builder = HnswBuilder::new(16, 32, 100);
        builder.insert(1, vec![1.0, 0.0, 0.0, 0.0]);
        builder.insert(2, vec![1.0, 0.0, 0.0]);

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("mixed.hnsw");
        assert!(builder.save_to_disk(index_path.to_str().unwrap()).is_err());
        assert!(!index_path.exists());
    }

    #[test]
    fn load_rejects_bad_magic_version_and_truncated_files() {
        configure_active_vabq_profile(None, RECALL_DIM as i32).unwrap();
        let directory = tempdir().unwrap();
        let corpus = lcg_vectors(50, RECALL_DIM, 3);
        let builder = build_index(&corpus);
        let good_path = directory.path().join("good.hnsw");
        builder.save_to_disk(good_path.to_str().unwrap()).unwrap();
        let good = std::fs::read(&good_path).unwrap();

        let write = |name: &str, bytes: &[u8]| {
            let path = directory.path().join(name);
            std::fs::write(&path, bytes).unwrap();
            path
        };

        let mut bad_magic = good.clone();
        bad_magic[0] = b'X';
        assert!(MmapHnswSearcher::new(write("magic.hnsw", &bad_magic).to_str().unwrap()).is_err());

        let mut bad_version = good.clone();
        bad_version[4] = 9;
        assert!(MmapHnswSearcher::new(write("version.hnsw", &bad_version).to_str().unwrap()).is_err());

        assert!(MmapHnswSearcher::new(write("tiny.hnsw", &good[..10]).to_str().unwrap()).is_err());

        // A file cut inside the node directory or node data must be rejected at
        // load time instead of panicking on an out-of-bounds read during search.
        for cut in [30, good.len() / 2, good.len() - 1] {
            let path = write(&format!("cut-{cut}.hnsw"), &good[..cut]);
            assert!(
                MmapHnswSearcher::new(path.to_str().unwrap()).is_err(),
                "truncated file ({cut} of {} bytes) was accepted",
                good.len()
            );
        }
    }

    #[test]
    fn save_uses_q8_fallback_without_a_vabq_profile() {
        configure_active_vabq_profile(None, 4).unwrap();
        let mut builder = HnswBuilder::new(16, 32, 100);
        builder.nodes = vec![Node {
            id: 1,
            vector: vec![1.0, 0.0, 0.0, 0.0],
            max_layer: 0,
            connections: vec![vec![]],
        }];
        builder.entry_point = Some(0);

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("unsupported-profile.hnsw");
        builder.save_to_disk(index_path.to_str().unwrap()).unwrap();
        let searcher = MmapHnswSearcher::new(index_path.to_str().unwrap()).unwrap();
        let query = active_quantized_query(&[1.0, 0.0, 0.0, 0.0]).unwrap();
        assert_eq!(searcher.search(&query, 1).unwrap()[0].0, 1);
    }

    #[test]
    fn bge_base_profile_survives_hnsw_save_and_load_without_q8_fallback() {
        configure_active_vabq_profile(Some("bgeBaseEnV15".to_string()), 768).unwrap();
        let query: Vec<f32> = (0..768)
            .map(|index| if index % 2 == 0 { 1.0 } else { -0.5 })
            .collect();
        let mut builder = HnswBuilder::new(16, 32, 100);
        builder.nodes = vec![Node {
            id: 41,
            vector: query.clone(),
            max_layer: 0,
            connections: vec![vec![]],
        }];
        builder.entry_point = Some(0);

        let directory = tempdir().unwrap();
        let index_path = directory.path().join("bge-base-vabq.hnsw");
        builder.save_to_disk(index_path.to_str().unwrap()).unwrap();
        let searcher = MmapHnswSearcher::new(index_path.to_str().unwrap()).unwrap();
        assert_eq!(searcher.blob_len, 789);
        let node_offset = searcher.get_node_offset(0);
        assert_eq!(
            &searcher.mmap[node_offset + 8..node_offset + 13],
            &[0x02, 0x01, 0x00, 0x03, 0x04],
        );
        let active_query = active_quantized_query(&query).unwrap();
        assert_eq!(searcher.search(&active_query, 1).unwrap()[0].0, 41);
        configure_active_vabq_profile(None, 0).unwrap();
    }
}
