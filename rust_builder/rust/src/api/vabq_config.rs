//! Narrow flutter_rust_bridge surface for the host-selected VABQ contract.
//!
//! The quantization kernels intentionally remain internal implementation
//! details; Dart may configure a profile but must not construct production
//! blobs directly.

use crate::api::error::RagError;

/// Sets the explicit VABQ profile chosen by the host after probing its model.
/// Passing `null` selects Q8_0 fallback. A selected profile must match the
/// supplied embedding dimension or initialization fails closed.
pub fn configure_vabq_profile(
    profile: Option<String>,
    embedding_dimension: i32,
) -> Result<(), RagError> {
    crate::api::vector_quant::configure_active_vabq_profile(profile, embedding_dimension)
}
