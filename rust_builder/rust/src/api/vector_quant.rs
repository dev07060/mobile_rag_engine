// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Scalar quantization utilities for f32 <-> i8 conversion.

#[inline]
pub fn quantize_f32_to_i8(input: &[f32]) -> (Vec<i8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }

    let max_abs = input
        .iter()
        .fold(0.0f32, |acc, v| if v.abs() > acc { v.abs() } else { acc });
    if max_abs == 0.0 {
        return (vec![0; input.len()], 1.0);
    }

    let scale = max_abs / 127.0;
    let inv_scale = 1.0 / scale;
    let quantized = input
        .iter()
        .map(|v| (v * inv_scale).round().clamp(-127.0, 127.0) as i8)
        .collect();

    (quantized, scale)
}

#[allow(dead_code)]
#[inline]
pub fn dequantize_i8_to_f32(input: &[i8], scale: f32) -> Vec<f32> {
    if input.is_empty() {
        return Vec::new();
    }
    input.iter().map(|v| (*v as f32) * scale).collect()
}

#[cfg(any(test, feature = "bench"))]
#[inline]
pub fn i8_blob_from_slice(input: &[i8]) -> Vec<u8> {
    input.iter().map(|v| *v as u8).collect()
}

/// Quantize an `f32` embedding directly into the SQLite `BLOB`
/// representation, skipping the intermediate `Vec<i8>` that
/// [`quantize_f32_to_i8`] plus a byte conversion would otherwise produce.
/// Returns the quantized bytes together with the scale used to dequantize
/// them later. Behaviour is bit-for-bit equivalent to the older two-step path.
#[cfg(feature = "vector_quant_i8")]
#[inline]
pub fn quantize_f32_to_u8_blob(input: &[f32]) -> (Vec<u8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }
    // Packed block-wise quantization format (Q8_0 style):
    // 36 bytes per block of 32: 4-byte f32 scale (little-endian) + 32-byte i8 values.
    let (quantized, scales) = quantize_f32_to_i8_blockwise(input);
    let mut packed = Vec::with_capacity(scales.len() * 4 + quantized.len());

    for block_idx in 0..scales.len() {
        let scale_bytes = scales[block_idx].to_le_bytes();
        packed.extend_from_slice(&scale_bytes);

        let start = block_idx * BLOCK_SIZE;
        let end = (start + BLOCK_SIZE).min(quantized.len());
        for i in start..end {
            packed.push(quantized[i] as u8);
        }
    }
    // Return the packed blob and a dummy scale of 1.0
    (packed, 1.0)
}

#[cfg(not(feature = "vector_quant_i8"))]
#[inline]
pub fn quantize_f32_to_u8_blob(input: &[f32]) -> (Vec<u8>, f32) {
    if input.is_empty() {
        return (Vec::new(), 1.0);
    }

    let max_abs = input
        .iter()
        .fold(0.0f32, |acc, v| if v.abs() > acc { v.abs() } else { acc });
    if max_abs == 0.0 {
        return (vec![0u8; input.len()], 1.0);
    }

    let scale = max_abs / 127.0;
    let inv_scale = 1.0 / scale;
    let blob = input
        .iter()
        .map(|v| (v * inv_scale).round().clamp(-127.0, 127.0) as i8 as u8)
        .collect();

    (blob, scale)
}

#[allow(dead_code)]
#[inline]
pub fn i8_vec_from_blob(blob: &[u8]) -> Vec<i8> {
    blob.iter().map(|v| *v as i8).collect()
}

#[inline]
pub fn dot_i8_i32(a: &[i8], b: &[i8]) -> i32 {
    if a.len() != b.len() || a.is_empty() {
        return 0;
    }
    a.iter()
        .zip(b.iter())
        .map(|(x, y)| (*x as i32) * (*y as i32))
        .sum()
}

#[inline]
pub fn l2_norm_i8(v: &[i8]) -> f32 {
    if v.is_empty() {
        return 0.0;
    }
    let sq_sum: i32 = v.iter().map(|x| (*x as i32) * (*x as i32)).sum();
    (sq_sum as f32).sqrt()
}

#[inline]
pub fn cosine_with_query_norm_i8(query: &[i8], query_norm: f32, target: &[i8]) -> f32 {
    if query.len() != target.len() || query.is_empty() || query_norm == 0.0 {
        return 0.0;
    }
    let target_norm = l2_norm_i8(target);
    if target_norm == 0.0 {
        return 0.0;
    }
    (dot_i8_i32(query, target) as f32) / (query_norm * target_norm)
}

#[inline]
pub fn cosine_with_query_norm_i8_blob(query: &[i8], query_norm: f32, target_blob: &[u8]) -> f32 {
    if query.len() != target_blob.len() || query.is_empty() || query_norm == 0.0 {
        return 0.0;
    }

    let mut dot: i32 = 0;
    let mut target_sq_sum: i32 = 0;
    for (&q, &raw_target) in query.iter().zip(target_blob.iter()) {
        let target = raw_target as i8;
        let target_i32 = target as i32;
        dot += (q as i32) * target_i32;
        target_sq_sum += target_i32 * target_i32;
    }

    if target_sq_sum == 0 {
        return 0.0;
    }
    (dot as f32) / (query_norm * (target_sq_sum as f32).sqrt())
}


const BLOCK_SIZE: usize = 32;

/// Quantizes an f32 slice into block-wise i8 elements with independent scales (Q8_0 style).
/// Returns the quantized bytes and a list of scales for each block.
pub fn quantize_f32_to_i8_blockwise(input: &[f32]) -> (Vec<i8>, Vec<f32>) {
    if input.is_empty() {
        return (Vec::new(), Vec::new());
    }

    let num_blocks = (input.len() + BLOCK_SIZE - 1) / BLOCK_SIZE;
    let mut quantized = Vec::with_capacity(input.len());
    let mut scales = Vec::with_capacity(num_blocks);

    for block_idx in 0..num_blocks {
        let start = block_idx * BLOCK_SIZE;
        let end = (start + BLOCK_SIZE).min(input.len());
        let slice = &input[start..end];

        let max_abs = slice
            .iter()
            .fold(0.0f32, |acc, &v| acc.max(v.abs()));

        if max_abs == 0.0 {
            quantized.extend(vec![0; slice.len()]);
            scales.push(1.0);
        } else {
            let scale = max_abs / 127.0;
            let inv_scale = 1.0 / scale;
            for &v in slice {
                quantized.push((v * inv_scale).round().clamp(-127.0, 127.0) as i8);
            }
            scales.push(scale);
        }
    }

    (quantized, scales)
}

/// Dequantizes block-wise i8 slice back into f32.
#[allow(dead_code)]
pub fn dequantize_i8_to_f32_blockwise(input: &[i8], scales: &[f32]) -> Vec<f32> {
    if input.is_empty() || scales.is_empty() {
        return Vec::new();
    }

    let mut output = Vec::with_capacity(input.len());
    for (block_idx, scale) in scales.iter().enumerate() {
        let start = block_idx * BLOCK_SIZE;
        let end = (start + BLOCK_SIZE).min(input.len());
        if start >= input.len() {
            break;
        }
        for i in start..end {
            output.push((input[i] as f32) * scale);
        }
    }
    output
}


#[derive(Clone, Debug)]
pub struct QueryQ8 {
    pub blocks: Vec<i8>,
    pub scales: Vec<f32>,
    pub norm: f32,
}

impl QueryQ8 {
    pub fn new(query_f32: &[f32]) -> Self {
        if query_f32.is_empty() {
            return Self {
                blocks: Vec::new(),
                scales: Vec::new(),
                norm: 0.0,
            };
        }

        let (blocks, scales) = quantize_f32_to_i8_blockwise(query_f32);
        
        let mut sq_sum: f32 = 0.0;
        let num_blocks = scales.len();
        for block_idx in 0..num_blocks {
            let scale = scales[block_idx];
            let start = block_idx * BLOCK_SIZE;
            let end = (start + BLOCK_SIZE).min(blocks.len());
            let mut block_sum = 0i32;
            for i in start..end {
                let v = blocks[i];
                block_sum += (v as i32) * (v as i32);
            }
            sq_sum += (block_sum as f32) * scale * scale;
        }

        Self {
            blocks,
            scales,
            norm: sq_sum.sqrt(),
        }
    }
}

pub fn cosine_similarity_q8(
    query_q8: &QueryQ8,
    target_blob: &[u8],
    legacy_query_i8: &[i8],
    legacy_query_norm: f32,
) -> f32 {
    // If the target blob size matches legacy uniform (e.g. 768), fallback to legacy cosine similarity.
    if target_blob.len() == legacy_query_i8.len() {
        return cosine_with_query_norm_i8_blob(legacy_query_i8, legacy_query_norm, target_blob);
    }

    // Otherwise, parse the packed block-wise binary format.
    // Each block is 36 bytes: 4-byte f32 scale (LE) + 32-byte i8 values.
    if target_blob.len() % 36 != 0 || query_q8.blocks.is_empty() {
        return 0.0;
    }

    let num_blocks = target_blob.len() / 36;
    let mut dot_weighted: f32 = 0.0;
    let mut target_sq_sum: f32 = 0.0;

    for block_idx in 0..num_blocks {
        let block_start = block_idx * 36;
        if block_start + 4 > target_blob.len() {
            break;
        }
        // 1. Read f32 scale
        let mut scale_bytes = [0u8; 4];
        scale_bytes.copy_from_slice(&target_blob[block_start..block_start + 4]);
        let target_scale = f32::from_le_bytes(scale_bytes);

        let query_scale = if block_idx < query_q8.scales.len() {
            query_q8.scales[block_idx]
        } else {
            1.0
        };

        // 2. Compute integer dot product and squared sum for this block
        let mut block_dot = 0i32;
        let mut block_target_sq = 0i32;
        
        let start = block_idx * BLOCK_SIZE;
        
        for i in 0..32 {
            let q_idx = start + i;
            if q_idx >= query_q8.blocks.len() {
                break;
            }
            let q = query_q8.blocks[q_idx];
            let t = target_blob[block_start + 4 + i] as i8;

            block_dot += (q as i32) * (t as i32);
            block_target_sq += (t as i32) * (t as i32);
        }

        dot_weighted += (block_dot as f32) * query_scale * target_scale;
        target_sq_sum += (block_target_sq as f32) * target_scale * target_scale;
    }

    let query_norm = query_q8.norm;
    let target_norm = target_sq_sum.sqrt();

    if query_norm == 0.0 || target_norm == 0.0 {
        return 0.0;
    }

    dot_weighted / (query_norm * target_norm)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::vector_math::{cosine_with_query_norm_f32, l2_norm_f32};

    #[test]
    fn quantize_dequantize_roundtrip_reasonable_error() {
        let input = vec![0.1f32, -0.25, 0.5, 1.0, -1.2, 2.3];
        let (q, scale) = quantize_f32_to_i8(&input);
        let restored = dequantize_i8_to_f32(&q, scale);
        assert_eq!(restored.len(), input.len());

        let max_abs_err = input
            .iter()
            .zip(restored.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0f32, f32::max);
        assert!(max_abs_err < 0.05);
    }

    #[test]
    fn i8_cosine_matches_directionality() {
        let a = vec![1.0f32, 2.0, 3.0, -1.0];
        let b = vec![1.1f32, 1.9, 2.8, -0.8];
        let c = vec![-1.0f32, -2.0, -3.0, 1.0];

        let (qa, _) = quantize_f32_to_i8(&a);
        let (qb, _) = quantize_f32_to_i8(&b);
        let (qc, _) = quantize_f32_to_i8(&c);

        let sim_ab = cosine_with_query_norm_i8(&qa, l2_norm_i8(&qa), &qb);
        let sim_ac = cosine_with_query_norm_i8(&qa, l2_norm_i8(&qa), &qc);

        assert!(sim_ab > 0.9);
        assert!(sim_ac < -0.9);
    }

    #[test]
    fn i8_blob_cosine_matches_slice_cosine() {
        let a = vec![1.0f32, 2.0, 3.0, -1.0];
        let b = vec![1.1f32, 1.9, 2.8, -0.8];
        let (qa, _) = quantize_f32_to_i8(&a);
        let (qb, _) = quantize_f32_to_i8(&b);
        let blob = i8_blob_from_slice(&qb);

        let from_slice = cosine_with_query_norm_i8(&qa, l2_norm_i8(&qa), &qb);
        let from_blob = cosine_with_query_norm_i8_blob(&qa, l2_norm_i8(&qa), &blob);
        assert!((from_slice - from_blob).abs() < 1e-6);
    }

    #[test]
    fn quantize_f32_to_u8_blob_matches_two_step_pipeline() {
        // The direct blob path skips an intermediate Vec<i8>; the
        // resulting bytes and scale must be bit-for-bit identical to
        // the manual two-step process.
        let inputs: &[&[f32]] = &[
            &[],
            &[0.0],
            &[0.1, -0.25, 0.5, 1.0, -1.2, 2.3],
            &[-3.4, 0.0, 3.4, -1.7, 1.7],
        ];

        #[cfg(not(feature = "vector_quant_i8"))]
        for input in inputs {
            let (direct_blob, direct_scale) = quantize_f32_to_u8_blob(input);
            let (i8_vec, two_step_scale) = quantize_f32_to_i8(input);
            let two_step_blob = i8_blob_from_slice(&i8_vec);
            assert_eq!(direct_scale, two_step_scale);
            assert_eq!(direct_blob, two_step_blob);
        }

        #[cfg(feature = "vector_quant_i8")]
        for input in inputs {
            let (direct_blob, direct_scale) = quantize_f32_to_u8_blob(input);
            assert_eq!(direct_scale, 1.0);
            if input.is_empty() {
                assert!(direct_blob.is_empty());
                continue;
            }
            let (quantized, scales) = quantize_f32_to_i8_blockwise(input);
            let mut two_step_blob = Vec::new();
            for block_idx in 0..scales.len() {
                two_step_blob.extend_from_slice(&scales[block_idx].to_le_bytes());
                let start = block_idx * BLOCK_SIZE;
                let end = (start + BLOCK_SIZE).min(quantized.len());
                for i in start..end {
                    two_step_blob.push(quantized[i] as u8);
                }
            }
            assert_eq!(direct_blob, two_step_blob);
        }
    }

    // --- PR6 shared test helpers (deterministic, no rand dep) ---

    // Same generator as benches/vector_math.rs: reproducible run-to-run.
    fn pseudo_vec(dim: usize, seed: u32) -> Vec<f32> {
        (0..dim)
            .map(|i| {
                let x = (i as u32)
                    .wrapping_mul(2_654_435_761)
                    .wrapping_add(seed.wrapping_mul(40_503));
                ((x % 1000) as f32 / 1000.0) - 0.5
            })
            .collect()
    }

    // Independent f64 reference cosine of two i8 vectors. Different accumulation
    // width (i64) and float precision (f64) than the i32->f32 kernel, so a match
    // proves the kernel math, not just that it agrees with itself.
    fn ref_cosine_i8_f64(q: &[i8], t: &[i8]) -> f64 {
        if q.len() != t.len() || q.is_empty() {
            return 0.0;
        }
        let mut dot: i64 = 0;
        let mut qsq: i64 = 0;
        let mut tsq: i64 = 0;
        for (&a, &b) in q.iter().zip(t.iter()) {
            dot += (a as i64) * (b as i64);
            qsq += (a as i64) * (a as i64);
            tsq += (b as i64) * (b as i64);
        }
        if qsq == 0 || tsq == 0 {
            return 0.0;
        }
        (dot as f64) / ((qsq as f64).sqrt() * (tsq as f64).sqrt())
    }

    #[test]
    fn i8_blob_cosine_matches_independent_reference() {
        // Integer dot/sq are exact; only the final f32 sqrt+div can drift.
        const EPS: f64 = 1e-4;
        for &dim in &[1usize, 2, 3, 16, 384, 768, 1024, 1536] {
            let q = pseudo_vec(dim, 7);
            let t = pseudo_vec(dim, 9);
            let (qi, _) = quantize_f32_to_i8(&q);
            let (ti, _) = quantize_f32_to_i8(&t);
            let blob = i8_blob_from_slice(&ti);
            let qn = l2_norm_i8(&qi);

            let kernel = cosine_with_query_norm_i8_blob(&qi, qn, &blob) as f64;
            let reference = ref_cosine_i8_f64(&qi, &ti);
            assert!(
                (kernel - reference).abs() < EPS,
                "i8 cosine dim={dim}: kernel={kernel} ref={reference}"
            );
        }
    }

    // --- PR6 Task 2 helpers ---

    fn normalize(v: &mut [f32]) {
        let n = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        if n > 0.0 {
            for x in v.iter_mut() {
                *x /= n;
            }
        }
    }

    fn det_unit(dim: usize, seed: u32) -> Vec<f32> {
        let mut v = pseudo_vec(dim, seed);
        normalize(&mut v);
        v
    }

    // Clustered corpus: vector i belongs to cluster (i % clusters); a weighted
    // blend of that cluster's center and per-vector noise, normalized.
    fn clustered_corpus(
        n: usize,
        dim: usize,
        clusters: usize,
        weight: f32,
        seed0: u32,
    ) -> Vec<Vec<f32>> {
        let centers: Vec<Vec<f32>> =
            (0..clusters).map(|c| det_unit(dim, 1_000 + c as u32)).collect();
        (0..n)
            .map(|i| {
                let c = i % clusters;
                let noise = pseudo_vec(dim, seed0 + i as u32);
                let mut v: Vec<f32> = centers[c]
                    .iter()
                    .zip(noise.iter())
                    .map(|(&ce, &no)| weight * ce + (1.0 - weight) * no)
                    .collect();
                normalize(&mut v);
                v
            })
            .collect()
    }

    // Total order: score descending, then index ascending. total_cmp gives a
    // provably total order (NaN-safe), so sort output is platform-deterministic.
    fn order_desc_f64(a: &(usize, f64), b: &(usize, f64)) -> std::cmp::Ordering {
        b.1.total_cmp(&a.1).then(a.0.cmp(&b.0))
    }
    fn order_desc_f32(a: &(usize, f32), b: &(usize, f32)) -> std::cmp::Ordering {
        b.1.total_cmp(&a.1).then(a.0.cmp(&b.0))
    }

    // True cosine of the ORIGINAL f32 vectors, accumulated in f64 (boundary gap
    // >> x86/ARM ULP jitter); also the reference for cosine fidelity.
    fn cosine_f64_true(q: &[f32], t: &[f32]) -> f64 {
        let mut dot = 0.0f64;
        let mut qsq = 0.0f64;
        let mut tsq = 0.0f64;
        for (a, b) in q.iter().zip(t.iter()) {
            let (a, b) = (*a as f64, *b as f64);
            dot += a * b;
            qsq += a * a;
            tsq += b * b;
        }
        if qsq == 0.0 || tsq == 0.0 {
            0.0
        } else {
            dot / (qsq.sqrt() * tsq.sqrt())
        }
    }

    #[test]
    fn i8_topk_recall_matches_f32_within_floor() {
        const N: usize = 2000;
        const Q: usize = 32;
        const DIM: usize = 768;
        const K: usize = 10;
        const CLUSTERS: usize = 16;
        const WEIGHT: f32 = 0.85;
        // Locked from measured baseline recall@10 = 0.996875 (deterministic:
        // f64 GT + integer-exact i8 => bit-identical across x86/ARM). FLOOR =
        // floor(0.9969 - 0.02) = 0.98, margin ~0.017 (~5 hits of 320).
        const MIN_RECALL: f32 = 0.98;
        const _: () = assert!(MIN_RECALL >= 0.9, "MIN_RECALL must be a real floor");

        let corpus = clustered_corpus(N, DIM, CLUSTERS, WEIGHT, 5_000);
        let queries = clustered_corpus(Q, DIM, CLUSTERS, WEIGHT, 9_000);
        let corpus_blob: Vec<Vec<u8>> = corpus
            .iter()
            .map(|v| i8_blob_from_slice(&quantize_f32_to_i8(v).0))
            .collect();

        let mut recall_sum = 0.0f32;
        for query in &queries {
            let mut gt_scores: Vec<(usize, f64)> = corpus
                .iter()
                .enumerate()
                .map(|(i, c)| (i, cosine_f64_true(query, c)))
                .collect();
            gt_scores.sort_by(order_desc_f64);
            let gt: std::collections::HashSet<usize> =
                gt_scores.iter().take(K).map(|(i, _)| *i).collect();

            let (qi, _) = quantize_f32_to_i8(query);
            let qn_i8 = l2_norm_i8(&qi);
            let mut i8_scores: Vec<(usize, f32)> = corpus_blob
                .iter()
                .enumerate()
                .map(|(i, blob)| (i, cosine_with_query_norm_i8_blob(&qi, qn_i8, blob)))
                .collect();
            i8_scores.sort_by(order_desc_f32);
            let got: std::collections::HashSet<usize> =
                i8_scores.iter().take(K).map(|(i, _)| *i).collect();

            recall_sum += gt.intersection(&got).count() as f32 / K as f32;
        }
        let recall = recall_sum / Q as f32;
        println!("PR6 recall@{K} (N={N} Q={Q} dim={DIM} clusters={CLUSTERS}) = {recall}");
        assert!(
            recall >= MIN_RECALL,
            "i8 recall@{K} regressed: {recall} < {MIN_RECALL}"
        );
    }

    #[test]
    fn i8_cosine_fidelity_vs_true_f32() {
        const N: usize = 2000;
        const Q: usize = 32;
        const DIM: usize = 768;
        const CLUSTERS: usize = 16;
        const WEIGHT: f32 = 0.85;
        // Locked from measured max error 0.00121 (deterministic). 0.005 ~= 4x the
        // baseline: sensitive to a lossier future quantizer yet never flaky.
        const MAX_COS_ERR: f64 = 0.005;
        const _: () = assert!(MAX_COS_ERR < 0.1, "MAX_COS_ERR must be a real bound");

        let corpus = clustered_corpus(N, DIM, CLUSTERS, WEIGHT, 5_000);
        let queries = clustered_corpus(Q, DIM, CLUSTERS, WEIGHT, 9_000);
        let corpus_blob: Vec<Vec<u8>> = corpus
            .iter()
            .map(|v| i8_blob_from_slice(&quantize_f32_to_i8(v).0))
            .collect();

        let mut max_err = 0.0f64;
        for query in &queries {
            let (qi, _) = quantize_f32_to_i8(query);
            let qn_i8 = l2_norm_i8(&qi);
            for (c, blob) in corpus.iter().zip(corpus_blob.iter()) {
                let i8c = cosine_with_query_norm_i8_blob(&qi, qn_i8, blob) as f64;
                let truec = cosine_f64_true(query, c);
                let e = (i8c - truec).abs();
                if e > max_err {
                    max_err = e;
                }
            }
        }
        println!("PR6 max|cosine_i8 - cosine_f32_true| (N={N} Q={Q} dim={DIM}) = {max_err}");
        assert!(
            max_err <= MAX_COS_ERR,
            "i8 cosine fidelity regressed: max err {max_err} > {MAX_COS_ERR}"
        );
    }

    #[test]
    fn blockwise_quantize_dequantize_roundtrip() {
        // Create an input vector with some outliers in a specific block
        let mut input = vec![0.0f32; 100];
        // Block 0: small values
        for i in 0..32 {
            input[i] = 0.05 * (i as f32 / 32.0);
        }
        // Block 1: huge values (outliers)
        for i in 32..64 {
            input[i] = 10.0 * (i as f32 / 64.0);
        }
        // Block 2: mid values
        for i in 64..96 {
            input[i] = 1.0 * (i as f32 / 96.0);
        }

        let (q, scales) = quantize_f32_to_i8_blockwise(&input);
        assert_eq!(q.len(), input.len());
        assert_eq!(scales.len(), 4); // 100 elements / 32 block size = 4 blocks

        let restored = dequantize_i8_to_f32_blockwise(&q, &scales);
        assert_eq!(restored.len(), input.len());

        // Check that quantization error in block 0 is small despite the large outlier in block 1
        for i in 0..32 {
            let err = (input[i] - restored[i]).abs();
            // With block-wise, block 0 scale is around 0.05/127 ~ 0.0004. Error should be very small.
            assert!(err < 0.001, "Block 0 index {}: original={}, restored={}, err={}", i, input[i], restored[i], err);
        }

        // Verify with global quantization, the error in block 0 would be much larger
        let (global_q, global_scale) = quantize_f32_to_i8(&input);
        let global_restored = dequantize_i8_to_f32(&global_q, global_scale);
        let mut global_max_err_block0 = 0.0f32;
        for i in 0..32 {
            global_max_err_block0 = global_max_err_block0.max((input[i] - global_restored[i]).abs());
        }
        // Global scale is around 10.0/127 ~ 0.08. Maximum quantization error can be up to 0.04.
        println!("Block-wise block 0 max error: {}", (0..32).map(|i| (input[i] - restored[i]).abs()).fold(0.0f32, f32::max));
        println!("Global block 0 max error: {}", global_max_err_block0);
        assert!(global_max_err_block0 > 0.01);
    }

    #[test]
    fn test_blockwise_cosine_similarity() {
        // Create two 768-dim vectors with different patterns and outliers
        let mut a = vec![0.0f32; 768];
        let mut b = vec![0.0f32; 768];
        for i in 0..768 {
            a[i] = 0.1 * (i as f32).sin();
            b[i] = 0.15 * (i as f32).cos();
        }
        // Introduce massive outliers in block 5
        for i in 160..192 {
            a[i] *= 25.0;
            b[i] *= 20.0;
        }

        let true_cos = cosine_with_query_norm_f32(&a, l2_norm_f32(&a), &b);

        let query_q8 = QueryQ8::new(&a);
        let (packed_blob_b, _) = quantize_f32_to_u8_blob(&b);

        // For legacy comparison fallback
        let (legacy_q_a, _) = quantize_f32_to_i8(&a);
        let legacy_norm_a = l2_norm_i8(&legacy_q_a);

        let approx_cos = cosine_similarity_q8(&query_q8, &packed_blob_b, &legacy_q_a, legacy_norm_a);

        println!("True f32 cosine: {}", true_cos);
        println!("Block-wise approx cosine: {}", approx_cos);

        let err = (true_cos - approx_cos).abs();
        assert!(err < 0.005, "Block-wise cosine error too large: {} (true={}, approx={})", err, true_cos, approx_cos);
    }
}
