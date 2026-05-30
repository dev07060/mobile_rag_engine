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

#[inline]
pub fn dequantize_i8_to_f32(input: &[i8], scale: f32) -> Vec<f32> {
    if input.is_empty() {
        return Vec::new();
    }
    input.iter().map(|v| (*v as f32) * scale).collect()
}

#[inline]
pub fn i8_blob_from_slice(input: &[i8]) -> Vec<u8> {
    input.iter().map(|v| *v as u8).collect()
}

/// Quantize an `f32` embedding directly into the SQLite `BLOB`
/// representation, skipping the intermediate `Vec<i8>` that
/// [`quantize_f32_to_i8`] + [`i8_blob_from_slice`] would otherwise
/// produce. Returns the quantized bytes together with the scale used
/// to dequantize them later. Behaviour is bit-for-bit equivalent to
/// calling the two helpers sequentially.
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

#[cfg(test)]
mod tests {
    use super::*;

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
        // quantize_f32_to_i8 + i8_blob_from_slice.
        let inputs: &[&[f32]] = &[
            &[],
            &[0.0],
            &[0.1, -0.25, 0.5, 1.0, -1.2, 2.3],
            &[-3.4, 0.0, 3.4, -1.7, 1.7],
        ];

        for input in inputs {
            let (direct_blob, direct_scale) = quantize_f32_to_u8_blob(input);
            let (i8_vec, two_step_scale) = quantize_f32_to_i8(input);
            let two_step_blob = i8_blob_from_slice(&i8_vec);
            assert_eq!(direct_scale, two_step_scale);
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
}
