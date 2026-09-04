// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.

/// Simple greeting function for FRB demo.
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

/// Initialize FRB utilities.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Initialize CombinedLogger (Dart Stream + Native Print)
    let _ = crate::api::logger::init_logger();

    flutter_rust_bridge::setup_default_user_utils();
}

/// Runs a micro-benchmark for VABQ similarity computation on the device.
/// Returns the average nanoseconds per computation.
#[flutter_rust_bridge::frb(sync)]
pub fn benchmark_vabq_device(dim: usize, iterations: u32) -> u64 {
    use crate::api::vector_quant::{
        cosine_similarity_vabq as similarity, quantize_f32_to_vabq, QueryVABQ,
    };
    use std::time::Instant;

    let raw_query: Vec<f32> = (0..dim).map(|i| (i as f32) * 0.01).collect();
    let query_vabq = QueryVABQ::new(&raw_query);

    let raw_doc: Vec<f32> = (0..dim).map(|i| (i as f32) * 0.02).collect();
    let (target_blob, _scale) = quantize_f32_to_vabq(&raw_doc);

    // Warmup
    for _ in 0..100 {
        std::hint::black_box(similarity(&query_vabq, &target_blob));
    }

    let start = Instant::now();
    for _ in 0..iterations {
        std::hint::black_box(similarity(&query_vabq, &target_blob));
    }
    let elapsed = start.elapsed().as_nanos();

    (elapsed / iterations as u128) as u64
}
