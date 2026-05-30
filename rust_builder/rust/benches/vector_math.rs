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

criterion_group! {
    name = benches;
    config = Criterion::default()
        .sample_size(30)
        .warm_up_time(Duration::from_millis(500))
        .measurement_time(Duration::from_secs(2));
    targets = bench_cosine, bench_dot, bench_decode, bench_scan
}
criterion_main!(benches);
