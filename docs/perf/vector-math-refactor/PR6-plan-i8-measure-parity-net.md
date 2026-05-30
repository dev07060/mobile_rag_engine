# PR6 — i8 출시 핫패스 측정 + ε/recall 안전망 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the shipped int8 retrieval hot path with a benchmark baseline + a numeric ε kernel-parity net + two quantization-quality gates (recall@k floor + cosine fidelity), all fail-closed in CI — without changing any kernel.

**Architecture:** Non-destructive "measure before changing" PR (PR1 pattern, applied to the i8 path). Add tests to the already-`vector_quant_i8`-gated `vector_quant.rs` test module, add i8 benches via the `bench` re-export surface, and wire a fail-closed i8 test step into `scripts/test_ci.sh` on the shipped `vector_faer,vector_quant_i8` compile tree.

**Tech Stack:** Rust, criterion (dev-dep, `bench` feature), cargo feature flags (`vector_faer`, `vector_quant_i8`, `bench`), bash CI script.

**Spec:** [PR6-spec-i8-measure-parity-net.md](PR6-spec-i8-measure-parity-net.md) · **Linear:** [LOC-64](https://linear.app/loceract/issue/LOC-64) · **Branch:** `feat/loc-64-i8-measure-parity-net` (already created off `main` @ `1217123`).

**Verification note (why Task 2 looks the way it does):** an adversarial pre-flight (running the real kernel) found i8 per-vector quantization at dim 768 is too accurate to reorder a top-10 — recall@10 ≈ 0.997 and cannot be pushed into a "sensitive band" without abandoning the shipped settings. So the quality gate **locks that high baseline** (`recall ≥ baseline − margin`) and adds a genuinely sensitive, fully-deterministic **cosine-fidelity** backstop. Ground-truth cosine is computed in **f64** so the recall boundary can't flip on x86-vs-ARM ULP jitter.

**Conventions (this repo):**
- Rust tests run with `-- --test-threads=1` (shared-SQLite parallelism; convention).
- Commits authored solely by the user — **NO** `Co-Authored-By` / Claude footer.
- Open PR, stop at CI green; **user merges**.
- All `cargo` commands use `--manifest-path rust_builder/rust/Cargo.toml`.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `rust_builder/rust/src/api/vector_quant.rs` | Modify (`mod tests` only) | ε kernel-parity net + recall@k floor + cosine-fidelity net + shared deterministic test helpers. **No non-test code touched.** |
| `rust_builder/rust/src/bench_api.rs` | Modify | `#[cfg(feature="vector_quant_i8")]` i8 re-export wrappers for the bench crate. |
| `rust_builder/rust/benches/vector_math.rs` | Modify | `bench_cosine_i8` + `bench_scan_i8` (cfg-stubbed when feature off) + targets list. |
| `scripts/test_ci.sh` | Modify (`native` case) | Fail-closed i8 test run on the shipped `vector_faer,vector_quant_i8` tree, with per-net name guards. |
| `docs/perf/vector-math-refactor/PR6.md` | Create | Journal entry: bench numbers, recall baseline/FLOOR, fidelity bound, decisions. |
| `docs/perf/vector-math-refactor/README.md` | Modify | Add PR6 row to the status table. |

---

## Task 1: Numeric ε net (i8 kernel correctness)

Mirror of [`faer_parity_tests`](../../../rust_builder/rust/src/api/vector_math.rs#L208): assert the shipped i8 cosine kernel agrees with an **independent f64 reference of the same i8 inputs** within a tight ε. The i8 dot and squared-norms are exact integer sums, so the only divergence is the final `sqrt` + division → `1e-4` catches logic/SIMD-rewrite bugs while tolerating the f32 cast.

**Files:**
- Modify: `rust_builder/rust/src/api/vector_quant.rs` (inside existing `#[cfg(test)] mod tests`, after line 197 / before the closing `}` at line 198)

- [ ] **Step 1: Add shared deterministic test helpers + the ε test**

Insert into `mod tests` (before its closing brace):

```rust
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
```

- [ ] **Step 2: Run the test — expect PASS (net green on current kernel)**

Run: `cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features vector_quant_i8 i8_blob_cosine_matches_independent_reference -- --test-threads=1`
Expected: `test result: ok. 1 passed`

- [ ] **Step 3: Prove the net has teeth (temporary mutation → red → revert)**

Temporarily change `EPS` to `1e-12` and re-run Step 2.
Expected: FAIL (`kernel=... ref=...`) — confirms the assertion is live, not vacuous.
Then **revert `EPS` back to `1e-4`** and re-run Step 2 → PASS.

- [ ] **Step 4: Commit**

```bash
git add rust_builder/rust/src/api/vector_quant.rs
git commit -m "test(vector_quant): i8 cosine kernel ε-parity vs independent f64 reference (LOC-64)"
```

---

## Task 2: Quantization-quality nets — recall@k floor + cosine fidelity (measure-first)

Two complementary nets that reflect the **shipped path** (768-dim, per-vector scale):
1. **recall@k floor** — top-k(i8) vs top-k(f32-true) overlap, gated `≥ measured baseline − margin`. (Baseline ~0.997; we lock the real high quality, we do NOT force an artificial band.)
2. **cosine fidelity** — `max|cosine_i8 − cosine_f32_true| ≤ ε_q`. Fully deterministic (no ranking/boundary), the genuinely sensitive gate against a lossier future quantizer.

Ground-truth cosine is f64 (kills x86/ARM boundary jitter). `const _` guards prevent shipping a vacuous threshold if calibration is skipped.

**Files:**
- Modify: `rust_builder/rust/src/api/vector_quant.rs` (same `mod tests`, append after Task 1's helpers)

- [ ] **Step 1: Add corpus generator + generic comparator + f64 reference**

Append into `mod tests`:

```rust
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
    // blend of that cluster's center and per-vector noise, normalized. Realistic
    // "few near, most far" structure (not a sensitivity knob — see verification
    // note: i8@768 stays ~0.997 regardless; we lock that, not a forced band).
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

    // Total order: score descending, then index ascending. Deterministic ties.
    // Generic so it serves both the f64 ground truth and the f32 i8 ranking.
    fn order_desc<T: PartialOrd>(a: &(usize, T), b: &(usize, T)) -> std::cmp::Ordering {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.0.cmp(&b.0))
    }

    // True cosine of the ORIGINAL f32 vectors, accumulated in f64. f64 makes the
    // top-k boundary gap >> any x86-vs-ARM f32 ULP jitter, so the recall ranking
    // is cross-platform stable; also the reference for cosine fidelity.
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
```

- [ ] **Step 2: Add the recall@k floor test (f64 ground truth)**

Append into `mod tests`:

```rust
    #[test]
    fn i8_topk_recall_matches_f32_within_floor() {
        const N: usize = 2000;
        const Q: usize = 32;
        const DIM: usize = 768;
        const K: usize = 10;
        const CLUSTERS: usize = 16;
        const WEIGHT: f32 = 0.85;
        // Locked from the measured baseline recall@10 = 0.996875 (deterministic:
        // f64 GT + integer-exact i8 => bit-identical across x86/ARM). FLOOR =
        // floor(0.9969 - 0.02) = 0.98, margin ~0.017 (~5 hits of 320). The const
        // guard forbids a vacuous (<0.5) floor. Confirm in Step 4.
        const MIN_RECALL: f32 = 0.98;
        const _: () = assert!(MIN_RECALL >= 0.5, "MIN_RECALL must be a real floor");

        let corpus = clustered_corpus(N, DIM, CLUSTERS, WEIGHT, 5_000);
        let queries = clustered_corpus(Q, DIM, CLUSTERS, WEIGHT, 9_000);
        let corpus_blob: Vec<Vec<u8>> = corpus
            .iter()
            .map(|v| i8_blob_from_slice(&quantize_f32_to_i8(v).0))
            .collect();

        let mut recall_sum = 0.0f32;
        for query in &queries {
            // f64 ground-truth top-K (f64 removes x86/ARM ULP boundary jitter).
            let mut gt_scores: Vec<(usize, f64)> = corpus
                .iter()
                .enumerate()
                .map(|(i, c)| (i, cosine_f64_true(query, c)))
                .collect();
            gt_scores.sort_by(order_desc);
            let gt: std::collections::HashSet<usize> =
                gt_scores.iter().take(K).map(|(i, _)| *i).collect();

            // i8 top-K (shipped kernel) with the identical total order.
            let (qi, _) = quantize_f32_to_i8(query);
            let qn_i8 = l2_norm_i8(&qi);
            let mut i8_scores: Vec<(usize, f32)> = corpus_blob
                .iter()
                .enumerate()
                .map(|(i, blob)| (i, cosine_with_query_norm_i8_blob(&qi, qn_i8, blob)))
                .collect();
            i8_scores.sort_by(order_desc);
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
```

- [ ] **Step 3: Add the cosine-fidelity backstop test (deterministic, sensitive)**

Append into `mod tests`:

```rust
    #[test]
    fn i8_cosine_fidelity_vs_true_f32() {
        const N: usize = 2000;
        const Q: usize = 32;
        const DIM: usize = 768;
        const CLUSTERS: usize = 16;
        const WEIGHT: f32 = 0.85;
        // Locked from the measured max error 0.00121 (deterministic: i8 dot
        // integer-exact, GT in f64 => ~1e-12 platform jitter). 0.005 ~= 4x the
        // baseline: sensitive to a lossier future quantizer yet never flaky.
        // The const guard forbids a vacuous (>=0.1) bound. Confirm in Step 4.
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
```

- [ ] **Step 4: Run & confirm the (pre-measured, deterministic) baselines**

The thresholds above are already locked from an empirical planning-time run (macOS arm64). Confirm they hold — the metrics are deterministic (f64 GT + integer-exact i8), so they should match bit-for-bit:

Run: `cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features "vector_quant_i8,vector_faer" vector_quant -- --test-threads=1 --nocapture`
Expected: all `vector_quant` tests PASS and print:
- `PR6 recall@10 (...) = 0.996875` (gate `MIN_RECALL=0.98` → pass, margin ~0.017)
- `PR6 max|cosine_i8 - cosine_f32_true| (...) = 0.00121...` (gate `MAX_COS_ERR=0.005` → pass, ~4× margin)

NOTE: `cargo test` takes ONE positional substring filter — `"a|b|c"` matches literally (0 tests). Use the module substring `vector_quant` (runs all 7) as above.

If your measured `X`/`M` differ materially (they shouldn't — deterministic), recompute `MIN_RECALL = floor(X − 0.02 to 2dp)` and `MAX_COS_ERR ≈ 4 × M` (keep the const guards satisfied) and note the deviation in PR6.md.

- [ ] **Step 5: Prove both gates have teeth**

Temporarily set `MIN_RECALL = 0.999` → recall test FAILs (0.996875 < 0.999); revert to `0.98`.
Temporarily set `MAX_COS_ERR = 1e-9` → fidelity test FAILs; revert to `0.005`.
Re-run Step 4 → both PASS.

- [ ] **Step 6: Commit**

```bash
git add rust_builder/rust/src/api/vector_quant.rs
git commit -m "test(vector_quant): i8 recall@10 floor + cosine-fidelity gates vs f64 truth (LOC-64)"
```

---

## Task 3: i8 microbench + scan bench

Expose the i8 kernel to the bench crate and add an i8 microbench + an i8 scan bench (shipped hot loop). When `vector_quant_i8` is off, the i8 bench fns compile as no-op stubs so `criterion_group!` is feature-agnostic.

**Files:**
- Modify: `rust_builder/rust/src/bench_api.rs` (append after line 32, before the `BACKEND` doc comment)
- Modify: `rust_builder/rust/benches/vector_math.rs` (add fns + extend `targets`)

- [ ] **Step 1: Add i8 re-export wrappers to `bench_api.rs`**

Insert after line 32 (`}` of `decode_f32_embedding`), before the `BACKEND` doc comment:

```rust
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
```

- [ ] **Step 2: Verify `bench_api` compiles under the i8 feature**

Run: `cargo build --manifest-path rust_builder/rust/Cargo.toml --features "bench,vector_quant_i8"`
Expected: builds clean. (`api/mod.rs:29` declares `#[cfg(feature="vector_quant_i8")] pub(crate) mod vector_quant;` and the kernel fns are `pub`, so the crate-internal path `crate::api::vector_quant::*` resolves from `bench_api`. The `use` and wrappers share the same `vector_quant_i8` gate, so nothing dangles when the feature is off.)

- [ ] **Step 3: Add i8 bench fns + extend targets in `benches/vector_math.rs`**

Insert after `bench_scan` (line 107), before the `criterion_group!`:

```rust
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
```

Then change the `criterion_group!` `targets` line (line 115) from:

```rust
    targets = bench_cosine, bench_dot, bench_decode, bench_scan
```

to:

```rust
    targets = bench_cosine, bench_dot, bench_decode, bench_scan, bench_cosine_i8, bench_scan_i8
```

- [ ] **Step 4: Run the shipped-tree bench (i8 + f32-faer side by side)**

Run: `cargo bench --manifest-path rust_builder/rust/Cargo.toml --features "bench,vector_faer,vector_quant_i8" -- exact_scan`
Expected: reports both `exact_scan[faer]` (f32 decode+cosine) and `exact_scan_i8/i8_blob_cosine` (shipped i8). Record both medians + the i8/f32 ratio. (Group names `cosine_i8`/`exact_scan_i8` carry the `_i8` suffix to distinguish from the f32 groups, which is the §3 "distinguish f32 vs i8" intent.)

Also run the i8 microbench: `cargo bench --manifest-path rust_builder/rust/Cargo.toml --features "bench,vector_faer,vector_quant_i8" -- cosine_i8` and record per-dim numbers.

- [ ] **Step 5: Verify the no-op stubs compile with the feature OFF**

Run: `cargo build --manifest-path rust_builder/rust/Cargo.toml --features "bench"`
Expected: builds clean (i8 bench fns are no-op stubs; `criterion_group!` still references them).

- [ ] **Step 6: Commit**

```bash
git add rust_builder/rust/src/bench_api.rs rust_builder/rust/benches/vector_math.rs
git commit -m "bench(vector_math): add i8 hot-kernel + i8 scan benches (LOC-64)"
```

---

## Task 4: CI fail-closed gate on the shipped i8 tree

Add an i8 test step to `scripts/test_ci.sh`, mirroring the existing faer step: run the `vector_quant` tests (ε + recall + fidelity nets) on the **shipped** `vector_faer,vector_quant_i8` tree. Fail closed on zero matches AND if any **named** net is missing (a broad-filter + N≥1 guard alone would stay green on the 4 legacy tests if a net were renamed/cfg-excluded).

**Files:**
- Modify: `scripts/test_ci.sh` (`native` case, after the faer `vector_math` block ending at line 50, before the `# Compile-check the actual shipped feature combo` comment at line 51)

- [ ] **Step 1: Insert the i8 test step**

After line 50 (the faer block's closing `fi`), before line 51's comment, insert:

```bash
    echo "[ci] Running i8 quant kernels + ε/recall/fidelity safety nets on the SHIPPED faer+quant tree"
    # The shipped per-candidate hot path is i8 (cosine_with_query_norm_i8_blob),
    # not the f32 faer kernels. Run the vector_quant tests on the exact shipped
    # feature combo and fail closed on zero matches.
    if ! quant_out="$(cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features "vector_quant_i8,vector_faer" vector_quant -- --test-threads=1 2>&1)"; then
      echo "$quant_out"
      echo "[ci] ERROR: i8 vector_quant tests failed" >&2
      exit 1
    fi
    echo "$quant_out"
    if ! grep -Eq 'test result: ok\. [1-9][0-9]* passed' <<<"$quant_out"; then
      echo "[ci] ERROR: i8 vector_quant matched 0 tests (renamed/cfg-excluded?); failing closed" >&2
      exit 1
    fi
    # Fail closed if any specific safety net was renamed/cfg-excluded (a broad
    # filter + N>=1 alone would stay green on the legacy i8 tests).
    for net in i8_blob_cosine_matches_independent_reference \
               i8_topk_recall_matches_f32_within_floor \
               i8_cosine_fidelity_vs_true_f32; do
      if ! grep -Eq "${net} .* ok" <<<"$quant_out"; then
        echo "[ci] ERROR: i8 safety net '${net}' did not run/pass (renamed/cfg-excluded?); failing closed" >&2
        exit 1
      fi
    done
```

- [ ] **Step 2: Run the inserted command directly (fast local check)**

Run: `cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features "vector_quant_i8,vector_faer" vector_quant -- --test-threads=1`
Expected: `test result: ok. N passed` with N ≥ 6 (4 legacy + ε + recall + fidelity = 7), and the output contains `... ok` lines for all three named nets.

(Full `./scripts/test_ci.sh native` also runs flutter/PDF steps that need the local toolchain; if unavailable, the direct command above is the meaningful check for this task.)

- [ ] **Step 3: Commit**

```bash
git add scripts/test_ci.sh
git commit -m "ci(vector_quant): run i8 ε/recall/fidelity nets on shipped faer+quant tree (LOC-64)"
```

---

## Task 5: Journal — PR6.md + README status row

**Files:**
- Create: `docs/perf/vector-math-refactor/PR6.md`
- Modify: `docs/perf/vector-math-refactor/README.md` (status table)

- [ ] **Step 1: Create `PR6.md` with the measured results**

Create `docs/perf/vector-math-refactor/PR6.md` (fill `<...>` from Task 2 Step 5 and Task 3 Step 4):

```markdown
# PR6 — i8 출시 핫패스 측정 + ε/recall/fidelity 안전망 (N: 측정 먼저)

- 브랜치: `feat/loc-64-i8-measure-parity-net`
- Linear: [LOC-64](https://linear.app/loceract/issue/LOC-64)
- 상태: 🟦 진행 (PR 열림, CI green 대기)
- 설계: [PR6-spec-i8-measure-parity-net.md](PR6-spec-i8-measure-parity-net.md)

## 스코프 (비파괴 — 커널/양자화 0줄 변경)
출시 핫패스(i8 `cosine_with_query_norm_i8_blob`)에 PR1 패턴 적용: 측정 + 수치 ε 네트 + recall@k floor + 코사인 fidelity 네트 + CI fail-closed.

## 결과 (측정)
- **i8 핫커널 마이크로벤치** (dim별, ns): 384=<...> / 768=<...> / 1024=<...> / 1536=<...>
- **스캔(2000×768) 비교**: `exact_scan[faer]`(f32 decode+cosine)=<...> µs vs `exact_scan_i8`(i8 blob)=<...> µs → i8가 f32-faer 대비 **<...>×**.
- **수치 ε 네트**: 차원 {1,2,3,16,384,768,1024,1536}에서 kernel ≈ f64 참조, ε=1e-4 green.
- **핵심 발견**: i8 per-vector 양자화는 768d에서 **recall@10 ≈ 0.997**(=319/320, 거의 무손실) — '민감 밴드'는 출시 설정에서 도달 불가이며 강제 시 비대표적. 따라서 게이트는 이 높은 baseline을 잠금.
- **recall@k floor 네트**: N=2000, Q=32, dim=768, k=10, clusters=16 → 측정 recall@10 = **0.996875**(dev arm64, CI 확인), FLOOR = **0.98** (= floor(X−0.02)). GT는 f64(플랫폼 jitter 제거), 전순서 `(score desc, index asc)`.
- **코사인 fidelity 네트**: `max|cosine_i8 − cosine_f32_true|` = **0.00121**, 게이트 = **0.005** (≈4× baseline). 완전 결정론적·민감.
- **CI**: `--features "vector_quant_i8,vector_faer" -- --test-threads=1` fail-closed + 3개 네트 이름별 가드 (N=<...> passed).

## 받은 피드백 (리뷰 / 사전검증)
- 설계 리뷰: N=2000/k=10, 전순서 타이브레이크, 출시 트리(faer+quant) CI.
- **사전 적대적 검증이 잡은 것**: recall@10이 768d에서 포화(~0.997)→'민감 밴드' 불가 → **recall floor + cosine fidelity 백스톱**으로 재설계; f32 GT의 1-ULP 경계 jitter → **f64 GT**; vacuous floor 위험 → `const _` 컴파일 가드 + CI 이름별 가드.

## 리스크 / 롤백
- 비파괴(커널 0줄) → 동작 변경 없음. 롤백: PR revert.
- 결정론: i8 dot 정수 정확 + f64 GT → 플랫폼 무관. fidelity는 ranking 무관(경계 jitter 0).
- vacuous 게이트: `const _: () = assert!(...)` 가드로 컴파일 차단 + CI 이름별 fail-closed.

## 결정 로그
- 출시 핫패스가 i8임을 확정(이전 세션) → 측정/검증 초점을 f32(폴백)에서 i8로 이동.
- 품질 게이트는 측정 baseline에서 FLOOR/ε_q 도출(측정 먼저). 코퍼스는 출시 설정(768d·per-vector) 유지 — 강제 민감화 안 함.
```

- [ ] **Step 2: Add the PR6 row to `README.md`**

In `docs/perf/vector-math-refactor/README.md`, add after the PR5 row line:

```markdown
| PR6 | i8 출시 핫패스 **측정 + ε/recall/fidelity 안전망** | i8 검증갭 | 낮음(비파괴) | main(#67) | [LOC-64](https://linear.app/loceract/issue/LOC-64) | 🟦 진행([PR6.md](PR6.md)) |
```

- [ ] **Step 3: Commit**

```bash
git add docs/perf/vector-math-refactor/PR6.md docs/perf/vector-math-refactor/README.md
git commit -m "docs(perf): PR6 journal entry + status row, i8 measure/parity results (LOC-64)"
```

---

## Task 6: Full verification + open PR (stop at CI green)

**Files:** none (verification + PR)

- [ ] **Step 1: Full shipped-tree test run (all nets)**

Run: `cargo test --manifest-path rust_builder/rust/Cargo.toml --lib --features "vector_quant_i8,vector_faer" -- --test-threads=1`
Expected: `test result: ok.` with the ε + recall + fidelity tests among the passed set, 0 failed.

- [ ] **Step 2: Confirm non-shipped trees still build/test (no regressions)**

Run: `cargo test --manifest-path rust_builder/rust/Cargo.toml --lib -- --test-threads=1` (default features)
Expected: `test result: ok.` (vector_quant tests are cfg-excluded here — fine; the i8 nets only run under the feature).
Run: `cargo build --manifest-path rust_builder/rust/Cargo.toml --features "bench"` and `--features "bench,vector_faer,vector_quant_i8"`
Expected: both build clean (stub + real i8 benches).

- [ ] **Step 3: Push branch and open PR**

```bash
git push -u origin feat/loc-64-i8-measure-parity-net
gh pr create --base main --head feat/loc-64-i8-measure-parity-net \
  --title "PR6 — i8 hot-path measure + ε/recall/fidelity safety net (LOC-64)" \
  --body "$(cat <<'BODY'
Applies the PR1 "measure before changing" pattern to the SHIPPED int8 hot path (every prior review/bench scrutinized only the f32 fallback). Non-destructive — kernels unchanged.

- **Measure**: i8 micro + i8 scan benches (vs f32-faer). Numbers in PR6.md.
- **Numeric ε net**: i8 cosine kernel ≈ independent f64 reference, ε=1e-4.
- **recall@k floor**: top-k(i8) vs top-k(f32, f64 ground truth) recall@10 ≥ measured baseline − margin. (Finding: i8@768 is ~lossless for recall@10.)
- **cosine fidelity**: max|cosine_i8 − cosine_f32_true| ≤ measured bound — deterministic, sensitive backstop.
- **CI fail-closed**: nets run on the shipped `vector_faer,vector_quant_i8` tree, with per-net name guards.

Spec: docs/perf/vector-math-refactor/PR6-spec-i8-measure-parity-net.md · Journal: PR6.md
BODY
)"
```

- [ ] **Step 4: Watch CI to green; hand off for user merge**

Run: `gh pr checks <PR#> --watch` (re-poll on transient network error).
Expected: all checks pass. **Do NOT merge** — report "PR opened, CI green" and let the user merge. After merge: PR6.md status → 🟩, README PR6 row → 🟩 (follow-up).

---

## Self-Review (filled by plan author)

- **Spec coverage**: §3 bench → Task 3; §4 ε net → Task 1; §5 quality net → Task 2 (recall floor + fidelity, per the approved Net-2 redesign); §6 CI → Task 4; §7 tracking → Task 5 + issue created; §8 acceptance → Tasks 1–6; non-goal (0 kernel changes) → only `mod tests`, `bench_api`, `benches`, CI, docs touched. ✅ (Spec §5/§8/§9/§10 updated to the recall-floor + fidelity design.)
- **Placeholders**: `MIN_RECALL`/`MAX_COS_ERR`/bench numbers are *measure-first outputs* with exact derivation + compile-time `const _` guards (Task 2 Steps 4–5), not vague TODOs. PR6.md `<...>` are explicitly "fill from measured results." ✅
- **Type consistency**: `order_desc<T: PartialOrd>` used on both `(usize,f64)` (GT) and `(usize,f32)` (i8); `cosine_f64_true`/`ref_cosine_i8_f64`/`clustered_corpus`/`quantize_f32_to_i8`/`l2_norm_i8`/`i8_blob_from_slice`/`cosine_with_query_norm_i8_blob` match real `vector_quant.rs` signatures (verified). bench_api wrappers match. ✅
- **Verification-driven fixes applied**: f64 GT (jitter), recall-floor not forced-band (saturation), const guards + CI name guards (vacuous gate), `pub(crate) mod` wording, flat `X−0.02` floor. ✅
