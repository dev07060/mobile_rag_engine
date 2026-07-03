// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.

#[cfg(feature = "allocator_mimalloc")]
use mimalloc::MiMalloc;

#[cfg(feature = "allocator_mimalloc")]
#[global_allocator]
static GLOBAL_ALLOCATOR: MiMalloc = MiMalloc;

pub mod api;
mod frb_generated;

// Bench-only public surface. Gated behind the `bench` feature so it never
// affects production builds or flutter_rust_bridge codegen (FRB only scans
// `api/`). Lets `benches/vector_math.rs` reach the pub(crate) kernels.
#[cfg(feature = "bench")]
pub mod bench_api;
