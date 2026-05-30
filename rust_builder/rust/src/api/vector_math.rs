// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Shared vector math kernels for retrieval paths.
//
// The fallback backend is allocation-free. The shipped `vector_faer` backend
// trades a small per-call result allocation for SIMD gemm kernels that measure
// 2-8x faster on the retrieval hot path (see docs/perf/vector-math-refactor).

/// Decode a SQLite `BLOB` column previously written as a native-endian
/// f32 byte stream back into a `Vec<f32>`. Returns `None` when the
/// stored length is not a multiple of 4, which would indicate a corrupt
/// or unexpected payload.
///
/// Endianness: embeddings are stored/read in **native** byte order (the
/// encode sites use `f32::to_ne_bytes`). All supported targets (iOS/Android
/// arm64, desktop x86_64) are little-endian, so the on-disk format is
/// effectively little-endian; moving a DB across a big-endian boundary is
/// unsupported. `chunks_exact(4) + from_ne_bytes` is also the alignment-safe
/// decode — SQLite blob buffers are not guaranteed 4-byte aligned, so a
/// zero-copy `&[u8] -> &[f32]` cast would be unsound.
#[inline]
pub(crate) fn decode_f32_embedding(blob: &[u8]) -> Option<Vec<f32>> {
    if blob.len() % 4 != 0 {
        return None;
    }
    Some(
        blob.chunks_exact(4)
            .map(|chunk| f32::from_ne_bytes(chunk.try_into().unwrap()))
            .collect(),
    )
}

/// Decode like [`decode_f32_embedding`], but log a warning when the blob is
/// corrupt (length not a multiple of 4) instead of silently yielding nothing.
/// Returns an empty `Vec` on failure so existing "drop empty embeddings"
/// filters at call sites keep their behaviour — the only change is that the
/// corruption becomes visible in logs (keyed by `row_id`).
#[inline]
pub(crate) fn decode_f32_embedding_or_warn(blob: &[u8], row_id: i64) -> Vec<f32> {
    match decode_f32_embedding(blob) {
        Some(v) => v,
        None => {
            log::warn!(
                "decode_f32_embedding: corrupt embedding blob (len={} not a multiple of 4) for row id={}; skipping",
                blob.len(),
                row_id
            );
            Vec::new()
        }
    }
}

#[inline]
pub(crate) fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
    backend::dot_f32(a, b)
}

#[inline]
pub(crate) fn l2_norm_f32(v: &[f32]) -> f32 {
    backend::l2_norm_f32(v)
}

#[inline]
pub(crate) fn cosine_f32(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }

    let norm_a = l2_norm_f32(a);
    let norm_b = l2_norm_f32(b);
    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }

    dot_f32(a, b) / (norm_a * norm_b)
}

#[inline]
pub(crate) fn cosine_with_query_norm_f32(query: &[f32], query_norm: f32, target: &[f32]) -> f32 {
    backend::cosine_with_query_norm_f32(query, query_norm, target)
}

#[cfg(feature = "vector_faer")]
mod backend {
    use faer::MatRef;

    #[inline]
    pub(super) fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() || a.is_empty() {
            return 0.0;
        }

        let lhs = MatRef::from_column_major_slice(a, a.len(), 1);
        let rhs = MatRef::from_column_major_slice(b, b.len(), 1);
        let dot = lhs.transpose() * rhs;
        dot[(0, 0)]
    }

    #[inline]
    pub(super) fn l2_norm_f32(v: &[f32]) -> f32 {
        if v.is_empty() {
            return 0.0;
        }
        dot_f32(v, v).sqrt()
    }

    #[inline]
    pub(super) fn cosine_with_query_norm_f32(
        query: &[f32],
        query_norm: f32,
        target: &[f32],
    ) -> f32 {
        if query.len() != target.len() || query.is_empty() || query_norm == 0.0 {
            return 0.0;
        }

        let target_norm = l2_norm_f32(target);
        if target_norm == 0.0 {
            0.0
        } else {
            dot_f32(query, target) / (query_norm * target_norm)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dot_and_norm_basic() {
        let a = [1.0f32, 2.0, 3.0];
        let b = [4.0f32, 5.0, 6.0];
        assert!((dot_f32(&a, &b) - 32.0).abs() < 1e-6);
        assert!((l2_norm_f32(&a) - (14.0f32).sqrt()).abs() < 1e-6);
    }

    #[test]
    fn cosine_matches_precomputed_query_norm_path() {
        let q = [0.2f32, -0.1, 0.3, 0.5];
        let t = [0.1f32, -0.2, 0.4, 0.4];
        let direct = cosine_f32(&q, &t);
        let precomputed = cosine_with_query_norm_f32(&q, l2_norm_f32(&q), &t);
        assert!((direct - precomputed).abs() < 1e-6);
    }

    #[test]
    fn invalid_inputs_return_zero() {
        let a = [1.0f32, 2.0];
        let b = [3.0f32];
        assert_eq!(dot_f32(&a, &b), 0.0);
        assert_eq!(cosine_f32(&a, &b), 0.0);
        assert_eq!(cosine_with_query_norm_f32(&a, 1.0, &b), 0.0);
    }
}

#[cfg(not(feature = "vector_faer"))]
mod backend {
    #[inline]
    pub(super) fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() || a.is_empty() {
            return 0.0;
        }
        a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
    }

    #[inline]
    pub(super) fn l2_norm_f32(v: &[f32]) -> f32 {
        if v.is_empty() {
            return 0.0;
        }
        v.iter().map(|x| x * x).sum::<f32>().sqrt()
    }

    #[inline]
    pub(super) fn cosine_with_query_norm_f32(
        query: &[f32],
        query_norm: f32,
        target: &[f32],
    ) -> f32 {
        if query.len() != target.len() || query.is_empty() || query_norm == 0.0 {
            return 0.0;
        }

        let mut dot = 0.0f32;
        let mut target_sq_sum = 0.0f32;
        for (q, t) in query.iter().zip(target.iter()) {
            dot += q * t;
            target_sq_sum += t * t;
        }

        let target_norm = target_sq_sum.sqrt();
        if target_norm == 0.0 {
            0.0
        } else {
            dot / (query_norm * target_norm)
        }
    }
}

// Parity safety net for PR2 (faer removal). Only compiled with the faer backend.
// Asserts the shipped faer-backed kernels agree with an independent fused
// reference within a generous epsilon across representative dims, so swapping
// the backend out in PR2 is provably behaviour-preserving. CI never enables
// `vector_faer`, so this runs locally via `cargo test --features vector_faer`.
#[cfg(all(test, feature = "vector_faer"))]
mod faer_parity_tests {
    use super::*;

    // Independent reference: the fused single-pass algorithm (identical to the
    // non-faer backend), inlined here so both implementations are in scope.
    fn fused_dot(a: &[f32], b: &[f32]) -> f32 {
        a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
    }
    fn fused_cosine(query: &[f32], query_norm: f32, target: &[f32]) -> f32 {
        if query.len() != target.len() || query.is_empty() || query_norm == 0.0 {
            return 0.0;
        }
        let mut dot = 0.0f32;
        let mut tsq = 0.0f32;
        for (q, t) in query.iter().zip(target.iter()) {
            dot += q * t;
            tsq += t * t;
        }
        let tn = tsq.sqrt();
        if tn == 0.0 {
            0.0
        } else {
            dot / (query_norm * tn)
        }
    }

    // Deterministic pseudo-random vector (no rand dep; reproducible run-to-run).
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

    #[test]
    fn faer_matches_fused_within_eps() {
        // f32 worst-case accumulation error at dim 1536 is ~n*eps ~ 2e-4, so a
        // 1e-3 bound catches algorithmic divergence while tolerating the
        // reassociation difference between faer's matmul and the fused loop.
        const EPS: f32 = 1e-3;
        for &dim in &[1usize, 2, 3, 16, 384, 768, 1024, 1536] {
            let q = pseudo_vec(dim, 1);
            let t = pseudo_vec(dim, 2);
            let qn = l2_norm_f32(&q);

            let dot_faer = dot_f32(&q, &t);
            let dot_ref = fused_dot(&q, &t);
            assert!(
                (dot_faer - dot_ref).abs() <= EPS * (1.0 + dot_ref.abs()),
                "dot dim={dim}: faer={dot_faer} fused={dot_ref}"
            );

            let cos_faer = cosine_with_query_norm_f32(&q, qn, &t);
            let cos_ref = fused_cosine(&q, qn, &t);
            assert!(
                (cos_faer - cos_ref).abs() <= EPS,
                "cosine dim={dim}: faer={cos_faer} fused={cos_ref}"
            );
        }
    }
}
