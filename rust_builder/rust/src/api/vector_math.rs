// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Shared vector math kernels for retrieval paths.
// Keeping this module allocation-free helps mobile hot paths.

#[inline]
pub fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
    backend::dot_f32(a, b)
}

#[inline]
pub fn l2_norm_f32(v: &[f32]) -> f32 {
    backend::l2_norm_f32(v)
}

#[inline]
pub fn cosine_f32(a: &[f32], b: &[f32]) -> f32 {
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
pub fn cosine_with_query_norm_f32(query: &[f32], query_norm: f32, target: &[f32]) -> f32 {
    backend::cosine_with_query_norm_f32(query, query_norm, target)
}

#[cfg(feature = "vector_faer")]
mod backend {
    use faer::MatRef;

    #[inline]
    pub fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() || a.is_empty() {
            return 0.0;
        }

        let lhs = MatRef::from_column_major_slice(a, a.len(), 1);
        let rhs = MatRef::from_column_major_slice(b, b.len(), 1);
        let dot = lhs.transpose() * rhs;
        dot[(0, 0)]
    }

    #[inline]
    pub fn l2_norm_f32(v: &[f32]) -> f32 {
        if v.is_empty() {
            return 0.0;
        }
        dot_f32(v, v).sqrt()
    }

    #[inline]
    pub fn cosine_with_query_norm_f32(query: &[f32], query_norm: f32, target: &[f32]) -> f32 {
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
    pub fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() || a.is_empty() {
            return 0.0;
        }
        a.iter().zip(b.iter()).map(|(x, y)| x * y).sum()
    }

    #[inline]
    pub fn l2_norm_f32(v: &[f32]) -> f32 {
        if v.is_empty() {
            return 0.0;
        }
        v.iter().map(|x| x * x).sum::<f32>().sqrt()
    }

    #[inline]
    pub fn cosine_with_query_norm_f32(query: &[f32], query_norm: f32, target: &[f32]) -> f32 {
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
