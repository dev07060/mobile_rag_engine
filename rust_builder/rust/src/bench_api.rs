// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Bench-only re-export surface (feature = "bench").
//
// The vector_math kernels are `pub(crate)`, so an external benchmark crate in
// `benches/` cannot call them directly. These thin `#[inline]` wrappers forward
// to the real kernels; the indirection is compiled away. This module is only
// compiled under `--features bench` and is invisible to production builds and
// to flutter_rust_bridge (which scans `api/`, not the crate root).

use crate::api::vector_math;

#[inline]
pub fn cosine_with_query_norm_f32(query: &[f32], query_norm: f32, target: &[f32]) -> f32 {
    vector_math::cosine_with_query_norm_f32(query, query_norm, target)
}

#[inline]
pub fn dot_f32(a: &[f32], b: &[f32]) -> f32 {
    vector_math::dot_f32(a, b)
}

#[inline]
pub fn l2_norm_f32(v: &[f32]) -> f32 {
    vector_math::l2_norm_f32(v)
}

#[inline]
pub fn decode_f32_embedding(blob: &[u8]) -> Option<Vec<f32>> {
    vector_math::decode_f32_embedding(blob)
}

#[cfg(feature = "vector_quant_i8")]
use crate::api::vector_quant;

#[cfg(feature = "vector_quant_i8")]
#[inline]
pub fn quantize_f32_to_i8(input: &[f32]) -> (Vec<i8>, f32) {
    vector_quant::quantize_f32_to_i8(input)
}

#[cfg(feature = "vector_quant_i8")]
#[inline]
pub fn l2_norm_i8(v: &[i8]) -> f32 {
    vector_quant::l2_norm_i8(v)
}

#[cfg(feature = "vector_quant_i8")]
#[inline]
pub fn i8_blob_from_slice(input: &[i8]) -> Vec<u8> {
    vector_quant::i8_blob_from_slice(input)
}

#[cfg(feature = "vector_quant_i8")]
#[inline]
pub fn cosine_with_query_norm_i8_blob(query: &[i8], query_norm: f32, target_blob: &[u8]) -> f32 {
    vector_quant::cosine_with_query_norm_i8_blob(query, query_norm, target_blob)
}

#[cfg(feature = "vector_quant_i8")]
#[inline]
pub fn quantize_f32_to_i8_blockwise(input: &[f32]) -> (Vec<i8>, Vec<f32>) {
    vector_quant::quantize_f32_to_i8_blockwise(input)
}

#[cfg(feature = "vector_quant_i8")]
pub use crate::api::vector_quant::{
    cosine_similarity_q8, cosine_similarity_vabq, quantize_f32_to_vabq, QueryQ8, QueryVABQ,
};

/// Which backend this build compiled (for labelling bench output).
pub const BACKEND: &str = if cfg!(feature = "vector_faer") {
    "faer"
} else {
    "fused"
};
