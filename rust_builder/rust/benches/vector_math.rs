// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Microbenchmarks for the vector_math retrieval kernels.
//
// Purpose (PR1): capture a faer-vs-fused baseline BEFORE faer is removed in PR2.
// Run both backends and compare:
//   cargo bench --manifest-path rust_builder/rust/Cargo.toml --features bench
//   cargo bench --manifest-path rust_builder/rust/Cargo.toml --features "bench,vector_faer"
// The compiled backend is printed via bench_api::BACKEND.

use std::time::Duration;

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use rag_engine_flutter::bench_api;

const DIMS: [usize; 4] = [384, 768, 1024, 1536];
const SCAN_DIM: usize = 768;
const SCAN_N: usize = 2000;

// Deterministic pseudo-random vector — same generator as the parity test, so
// bench inputs are reproducible run-to-run without a rand dependency.
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

fn to_blob(v: &[f32]) -> Vec<u8> {
    let mut b = Vec::with_capacity(v.len() * 4);
    for x in v {
        b.extend_from_slice(&x.to_ne_bytes());
    }
    b
}

fn bench_cosine(c: &mut Criterion) {
    let mut g = c.benchmark_group(format!("cosine_with_query_norm[{}]", bench_api::BACKEND));
    for &dim in &DIMS {
        let q = pseudo_vec(dim, 1);
        let t = pseudo_vec(dim, 2);
        let qn = bench_api::l2_norm_f32(&q);
        g.throughput(Throughput::Elements(dim as u64));
        g.bench_with_input(BenchmarkId::from_parameter(dim), &dim, |b, _| {
            b.iter(|| bench_api::cosine_with_query_norm_f32(black_box(&q), black_box(qn), black_box(&t)))
        });
    }
    g.finish();
}

fn bench_dot(c: &mut Criterion) {
    let mut g = c.benchmark_group(format!("dot[{}]", bench_api::BACKEND));
    for &dim in &DIMS {
        let a = pseudo_vec(dim, 3);
        let b_vec = pseudo_vec(dim, 4);
        g.throughput(Throughput::Elements(dim as u64));
        g.bench_with_input(BenchmarkId::from_parameter(dim), &dim, |b, _| {
            b.iter(|| bench_api::dot_f32(black_box(&a), black_box(&b_vec)))
        });
    }
    g.finish();
}

fn bench_decode(c: &mut Criterion) {
    let mut g = c.benchmark_group(format!("decode[{}]", bench_api::BACKEND));
    for &dim in &DIMS {
        let blob = to_blob(&pseudo_vec(dim, 5));
        g.throughput(Throughput::Bytes(blob.len() as u64));
        g.bench_with_input(BenchmarkId::from_parameter(dim), &dim, |b, _| {
            b.iter(|| bench_api::decode_f32_embedding(black_box(&blob)))
        });
    }
    g.finish();
}

// Realistic exact-scan inner loop: one query vs N candidate blobs, decoding and
// scoring each — the path where faer's per-call Mat allocation accumulates.
fn bench_scan(c: &mut Criterion) {
    let q = pseudo_vec(SCAN_DIM, 1);
    let qn = bench_api::l2_norm_f32(&q);
    let blobs: Vec<Vec<u8>> = (0..SCAN_N)
        .map(|i| to_blob(&pseudo_vec(SCAN_DIM, 100 + i as u32)))
        .collect();

    let mut g = c.benchmark_group(format!("exact_scan[{}]", bench_api::BACKEND));
    g.throughput(Throughput::Elements(SCAN_N as u64));
    g.bench_function(BenchmarkId::new("decode_then_cosine", SCAN_N), |b| {
        b.iter(|| {
            let mut best = f32::MIN;
            for blob in &blobs {
                if let Some(emb) = bench_api::decode_f32_embedding(black_box(blob)) {
                    let s = bench_api::cosine_with_query_norm_f32(&q, qn, &emb);
                    if s > best {
                        best = s;
                    }
                }
            }
            black_box(best)
        })
    });
    g.finish();
}

#[cfg(feature = "vector_quant_i8")]
fn bench_cosine_i8(c: &mut Criterion) {
    let mut g = c.benchmark_group("cosine_i8");
    for &dim in &DIMS {
        let (qi, _) = bench_api::quantize_f32_to_i8(&pseudo_vec(dim, 1));
        let (ti, _) = bench_api::quantize_f32_to_i8(&pseudo_vec(dim, 2));
        let qn = bench_api::l2_norm_i8(&qi);
        let tblob = bench_api::i8_blob_from_slice(&ti);
        g.throughput(Throughput::Elements(dim as u64));
        g.bench_with_input(BenchmarkId::from_parameter(dim), &dim, |b, _| {
            b.iter(|| {
                bench_api::cosine_with_query_norm_i8_blob(
                    black_box(&qi),
                    black_box(qn),
                    black_box(&tblob),
                )
            })
        });
    }
    g.finish();
}
#[cfg(not(feature = "vector_quant_i8"))]
fn bench_cosine_i8(_c: &mut Criterion) {}

// Shipped exact-scan inner loop: one query vs N candidate i8 blobs, scored with
// zero f32 decode / zero per-row alloc — the actual release hot path.
#[cfg(feature = "vector_quant_i8")]
fn bench_scan_i8(c: &mut Criterion) {
    let (qi, _) = bench_api::quantize_f32_to_i8(&pseudo_vec(SCAN_DIM, 1));
    let qn = bench_api::l2_norm_i8(&qi);
    let blobs: Vec<Vec<u8>> = (0..SCAN_N)
        .map(|i| {
            let (vi, _) = bench_api::quantize_f32_to_i8(&pseudo_vec(SCAN_DIM, 100 + i as u32));
            bench_api::i8_blob_from_slice(&vi)
        })
        .collect();

    let mut g = c.benchmark_group("exact_scan_i8");
    g.throughput(Throughput::Elements(SCAN_N as u64));
    g.bench_function(BenchmarkId::new("i8_blob_cosine", SCAN_N), |b| {
        b.iter(|| {
            let mut best = f32::MIN;
            for blob in &blobs {
                let s = bench_api::cosine_with_query_norm_i8_blob(black_box(&qi), qn, black_box(blob));
                if s > best {
                    best = s;
                }
            }
            black_box(best)
        })
    });
    g.finish();
}
#[cfg(not(feature = "vector_quant_i8"))]
fn bench_scan_i8(_c: &mut Criterion) {}

criterion_group! {
    name = benches;
    config = Criterion::default()
        .sample_size(30)
        .warm_up_time(Duration::from_millis(500))
        .measurement_time(Duration::from_secs(2));
    targets = bench_cosine, bench_dot, bench_decode, bench_scan, bench_cosine_i8, bench_scan_i8,
              bench_scan_q8_0, bench_scan_vabq
}
criterion_main!(benches);

// ── Q8_0 blockwise exact-scan benchmark ─────────────────────────────────────
// Measures native Rust throughput for the Q8_0 block-packed format (36-byte blocks:
// 4-byte f32 scale + 32-byte i8 values), which is the current production hot path.
#[cfg(feature = "vector_quant_i8")]
fn bench_scan_q8_0(c: &mut Criterion) {
    use bench_api::{QueryQ8, cosine_similarity_q8, l2_norm_i8, quantize_f32_to_i8};

    let q_f32 = pseudo_vec(SCAN_DIM, 1);
    let (q_i8, _) = quantize_f32_to_i8(&q_f32);
    let q_norm = l2_norm_i8(&q_i8);
    let query_q8 = QueryQ8::new(&q_f32);

    // Build packed Q8_0 blobs (36 bytes per block: 4-byte scale + 32 i8 values)
    let blobs: Vec<Vec<u8>> = (0..SCAN_N)
        .map(|i| {
            let v = pseudo_vec(SCAN_DIM, 100 + i as u32);
            let (blocks, scales) = bench_api::quantize_f32_to_i8_blockwise(&v);
            let n_blocks = (SCAN_DIM + 31) / 32;
            let mut blob = Vec::with_capacity(n_blocks * 36);
            for b in 0..n_blocks {
                let start = b * 32;
                let end = (start + 32).min(blocks.len());
                blob.extend_from_slice(&scales[b].to_le_bytes());
                for i in start..end {
                    blob.push(blocks[i] as u8);
                }
                // Pad to 32 bytes if last block is partial
                for _ in (end - start)..32 {
                    blob.push(0u8);
                }
            }
            blob
        })
        .collect();

    let mut g = c.benchmark_group("exact_scan_q8_0_blockwise");
    g.throughput(criterion::Throughput::Elements(SCAN_N as u64));
    g.bench_function(
        criterion::BenchmarkId::new("cosine_similarity_q8", SCAN_N),
        |b| {
            b.iter(|| {
                let mut best = f32::MIN;
                for blob in &blobs {
                    let s = cosine_similarity_q8(
                        criterion::black_box(&query_q8),
                        criterion::black_box(blob),
                        &q_i8,
                        q_norm,
                    );
                    if s > best {
                        best = s;
                    }
                }
                criterion::black_box(best)
            })
        },
    );
    g.finish();
}
#[cfg(not(feature = "vector_quant_i8"))]
fn bench_scan_q8_0(_c: &mut Criterion) {}

// ── VABQ scan benchmark (legacy blob path) ───────────────────────────────────
// Uses cosine_similarity_q8 with the legacy 768-byte uniform-quantized blob
// to establish the lower-bound latency when VABQ falls back to the legacy path.
// This validates that the fallback gate does not regress existing performance.
#[cfg(feature = "vector_quant_i8")]
fn bench_scan_vabq(c: &mut Criterion) {
    use bench_api::{QueryQ8, cosine_similarity_q8, l2_norm_i8, quantize_f32_to_i8, i8_blob_from_slice};

    let q_f32 = pseudo_vec(SCAN_DIM, 1);
    let (q_i8, _) = quantize_f32_to_i8(&q_f32);
    let q_norm = l2_norm_i8(&q_i8);
    let query_q8 = QueryQ8::new(&q_f32);

    // Legacy uniform blobs (768 bytes = 768 i8 values cast to u8)
    let legacy_blobs: Vec<Vec<u8>> = (0..SCAN_N)
        .map(|i| {
            let (vi, _) = quantize_f32_to_i8(&pseudo_vec(SCAN_DIM, 100 + i as u32));
            i8_blob_from_slice(&vi)
        })
        .collect();

    let mut g = c.benchmark_group("exact_scan_vabq_legacy_fallback");
    g.throughput(criterion::Throughput::Elements(SCAN_N as u64));
    g.bench_function(
        criterion::BenchmarkId::new("cosine_legacy_blob", SCAN_N),
        |b| {
            b.iter(|| {
                let mut best = f32::MIN;
                for blob in &legacy_blobs {
                    let s = cosine_similarity_q8(
                        criterion::black_box(&query_q8),
                        criterion::black_box(blob),
                        &q_i8,
                        q_norm,
                    );
                    if s > best {
                        best = s;
                    }
                }
                criterion::black_box(best)
            })
        },
    );
    g.finish();
}
#[cfg(not(feature = "vector_quant_i8"))]
fn bench_scan_vabq(_c: &mut Criterion) {}
