use crate::api::vector_quant::{cosine_similarity_vabq, quantize_f32_to_vabq, QueryVABQ};
use anyhow::{Context, Result};
use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};
use flutter_rust_bridge::frb;
use memmap2::{Mmap, MmapOptions};
use rand::Rng;
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashSet};
use std::fs::File;
use std::io::Cursor;
use std::io::{BufWriter, Write};
use std::path::Path;

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

#[frb(ignore)]
pub struct HnswBuilder {
    pub nodes: Vec<Node>,
    pub entry_point: Option<usize>,
    pub max_layer: usize,
    pub m: usize,
    pub m0: usize,
    pub ef_construction: usize,
    ml: f32,
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
        }
    }

    fn random_layer(&self) -> usize {
        let mut rng = rand::thread_rng();
        let r: f32 = rng.gen_range(0.0001..1.0);
        (-r.ln() * self.ml) as usize
    }

    fn search_layer(
        &self,
        query: &[f32],
        entry_points: &[usize],
        ef: usize,
        lc: usize,
    ) -> Vec<DistNode> {
        let mut visited = HashSet::new();
        let mut candidates = BinaryHeap::new();
        let mut top_results = Vec::new();

        for &ep in entry_points {
            if visited.insert(ep) {
                let dist = cosine_distance(query, &self.nodes[ep].vector);
                candidates.push(std::cmp::Reverse(DistNode { index: ep, dist }));
                top_results.push(DistNode { index: ep, dist });
            }
        }

        while let Some(std::cmp::Reverse(c)) = candidates.pop() {
            top_results.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
            let furthest_dist = if top_results.len() >= ef {
                top_results.last().unwrap().dist
            } else {
                f32::MAX
            };

            if c.dist > furthest_dist {
                break;
            }

            for &neighbor in &self.nodes[c.index].connections[lc] {
                if visited.insert(neighbor) {
                    let d = cosine_distance(query, &self.nodes[neighbor].vector);
                    let furthest_dist = if top_results.len() >= ef {
                        top_results.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
                        top_results.last().unwrap().dist
                    } else {
                        f32::MAX
                    };

                    if top_results.len() < ef || d < furthest_dist {
                        candidates.push(std::cmp::Reverse(DistNode {
                            index: neighbor,
                            dist: d,
                        }));
                        top_results.push(DistNode {
                            index: neighbor,
                            dist: d,
                        });
                        top_results.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
                        if top_results.len() > ef {
                            top_results.pop();
                        }
                    }
                }
            }
        }

        top_results
    }

    pub fn insert(&mut self, id: i64, vector: Vec<f32>) {
        let layer = self.random_layer();
        let new_idx = self.nodes.len();

        let mut new_connections = vec![Vec::new(); layer + 1];

        if self.entry_point.is_none() {
            self.entry_point = Some(new_idx);
            self.max_layer = layer;
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
            let mut curr_dist = cosine_distance(&vector, &self.nodes[curr_ep].vector);
            let mut changed = true;
            while changed {
                changed = false;
                for &neighbor in &self.nodes[curr_ep].connections[lc] {
                    let d = cosine_distance(&vector, &self.nodes[neighbor].vector);
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
            let neighbors = self.search_layer(&vector, &eps, self.ef_construction, lc);

            let mut best_n = neighbors.clone();
            best_n.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
            best_n.truncate(m_max);

            for n in &best_n {
                new_connections[lc].push(n.index);
            }

            eps = best_n.into_iter().map(|n| n.index).collect();
        }

        // Add node
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
                    let mut dists: Vec<_> = self.nodes[n_idx].connections[lc]
                        .iter()
                        .map(|&idx| DistNode {
                            index: idx,
                            dist: cosine_distance(
                                &self.nodes[n_idx].vector,
                                &self.nodes[idx].vector,
                            ),
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

        // Phase 1: greedy search down to layer + 1
        for lc in (1..=curr_max_layer).rev() {
            let mut curr_dist = cosine_distance(query, &self.nodes[curr_ep].vector);
            let mut changed = true;
            while changed {
                changed = false;
                for &neighbor in &self.nodes[curr_ep].connections[lc] {
                    let d = cosine_distance(query, &self.nodes[neighbor].vector);
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
        let mut neighbors = self.search_layer(query, &eps, ef, 0);

        neighbors.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());

        neighbors
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
            let blob_len = if f32_dim > 0 {
                quantize_f32_to_vabq(&self.nodes[0].vector).0.len()
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
                    let (vabq_blob, _scale) = quantize_f32_to_vabq(&node.vector);
                    writer.write_all(&vabq_blob)?;
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

        Ok(Self {
            mmap,
            entry_point,
            max_layer,
            num_nodes,
            blob_len,
        })
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

    pub fn search(&self, query_vabq: &QueryVABQ, ef: usize) -> Vec<(i64, f32)> {
        let distance_fn = |offset: usize| -> f32 {
            let vec = self.get_node_vector(offset);
            cosine_similarity_vabq(query_vabq, vec)
        };

        if self.num_nodes == 0 {
            return Vec::new();
        }

        let mut curr_ep = self.entry_point;

        let ep_offset = self.get_node_offset(curr_ep);

        // Phase 1: greedy search down to layer 1
        for lc in (1..=self.max_layer).rev() {
            let mut curr_dist = distance_fn(ep_offset);
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
                    let d = distance_fn(n_offset);
                    if d < curr_dist {
                        curr_dist = d;
                        curr_ep = neighbor_idx;
                        changed = true;
                    }
                }
            }
        }

        // Phase 2: search layer 0
        let mut visited = HashSet::new();
        let mut candidates = BinaryHeap::new();
        let mut top_results = Vec::new();

        visited.insert(curr_ep);

        let ep_offset = self.get_node_offset(curr_ep);
        let dist = distance_fn(ep_offset);

        candidates.push(std::cmp::Reverse(DistNode {
            index: curr_ep as usize,
            dist,
        }));
        top_results.push(DistNode {
            index: curr_ep as usize,
            dist,
        });

        while let Some(std::cmp::Reverse(c)) = candidates.pop() {
            top_results.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
            let furthest_dist = if top_results.len() >= ef {
                top_results.last().unwrap().dist
            } else {
                f32::MAX
            };

            if c.dist > furthest_dist {
                break;
            }

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

                if visited.insert(neighbor_idx) {
                    let n_offset = self.get_node_offset(neighbor_idx);
                    let d = distance_fn(n_offset);

                    let furthest_dist = if top_results.len() >= ef {
                        top_results.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
                        top_results.last().unwrap().dist
                    } else {
                        f32::MAX
                    };

                    if top_results.len() < ef || d < furthest_dist {
                        candidates.push(std::cmp::Reverse(DistNode {
                            index: neighbor_idx as usize,
                            dist: d,
                        }));
                        top_results.push(DistNode {
                            index: neighbor_idx as usize,
                            dist: d,
                        });
                        top_results.sort_by(|a, b| a.dist.partial_cmp(&b.dist).unwrap());
                        if top_results.len() > ef {
                            top_results.pop();
                        }
                    }
                }
            }
        }

        // Map indices to DataIDs
        top_results
            .into_iter()
            .map(|n| {
                let offset = self.get_node_offset(n.index as u32);
                let data_id = Cursor::new(&self.mmap[offset..offset + 8])
                    .read_i64::<LittleEndian>()
                    .unwrap();
                (data_id, n.dist)
            })
            .collect()
    }
}
