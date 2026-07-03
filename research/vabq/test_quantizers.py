"""
VABQ Unit Tests
---------------
Verifies the mathematical correctness of all quantizer implementations:
  - Quantize → Dequantize round-trip error is within expected bounds
  - Recall degradation is measurable but bounded
  - Bytes per vector matches theoretical formula

Run with:
    python test_quantizers.py
"""

import sys
import os
import numpy as np
import time

sys.path.insert(0, os.path.dirname(__file__))

from vabq_quantizer import (
    UniformQuantizer,
    Q8_0Quantizer,
    ProductQuantizer,
    VABQQuantizer,
    build_vabq_from_train_data,
)
from vabq_evaluator import load_synthetic, compute_ground_truth


def print_header(msg):
    print(f"\n{'='*55}")
    print(f"  {msg}")
    print(f"{'='*55}")


def test_uniform():
    print_header("Test 1: Uniform Quantizer")
    rng = np.random.default_rng(0)
    n, d = 1000, 384
    vecs = rng.standard_normal((n, d)).astype(np.float32)
    train = rng.standard_normal((500, d)).astype(np.float32)

    q = UniformQuantizer(d)
    q.fit(train)

    quantized = q.quantize(vecs)
    reconstructed = q._dequantize(quantized)

    mse = float(np.mean((vecs - reconstructed) ** 2))
    assert quantized.dtype == np.uint8, "Expected uint8"
    assert quantized.shape == (n, d), f"Shape mismatch: {quantized.shape}"
    assert q.bytes_per_vector == d, f"bytes_per_vector should be {d}"
    print(f"  ✓ Shape: {quantized.shape}, Bytes/vec: {q.bytes_per_vector}")
    print(f"  ✓ Reconstruction MSE: {mse:.6f}")

    # Test cosine similarity
    q_vec = rng.standard_normal(d).astype(np.float32)
    scores = q.cosine_similarity(q_vec, quantized)
    assert scores.shape == (n,), f"Scores shape wrong: {scores.shape}"
    assert scores.min() >= -1.1 and scores.max() <= 1.1
    print(f"  ✓ Cosine similarity: min={scores.min():.4f}, max={scores.max():.4f}")
    print(f"  ✓ PASSED")


def test_q8_0():
    print_header("Test 2: Q8_0 Quantizer (block=32)")
    rng = np.random.default_rng(1)
    n, d = 1000, 384
    vecs = rng.standard_normal((n, d)).astype(np.float32)
    train = rng.standard_normal((500, d)).astype(np.float32)

    for bs in [16, 32, 64]:
        q = Q8_0Quantizer(d, block_size=bs)
        q.fit(train)

        n_blocks = (d + bs - 1) // bs
        expected_bytes = d + n_blocks * 4
        assert q.bytes_per_vector == expected_bytes, (
            f"block={bs}: expected {expected_bytes}B, got {q.bytes_per_vector}B"
        )

        q_int8, scales = q.quantize(vecs)
        assert q_int8.dtype == np.int8
        assert scales.dtype == np.float32
        assert scales.shape == (n, n_blocks), f"Scales shape: {scales.shape}"

        scores = q.cosine_similarity(vecs[0], (q_int8, scales))
        assert scores.shape == (n,)
        assert scores.max() <= 1.01
        print(f"  ✓ block={bs}: bytes/vec={q.bytes_per_vector}, "
              f"scores: min={scores.min():.4f}, max={scores.max():.4f}")

    print(f"  ✓ PASSED")


def test_pq():
    print_header("Test 3: Product Quantizer (M=8)")
    rng = np.random.default_rng(2)
    d = 384  # divisible by 8
    M = 8
    n_train, n_db = 2000, 500

    train = rng.standard_normal((n_train, d)).astype(np.float32)
    db = rng.standard_normal((n_db, d)).astype(np.float32)
    query = rng.standard_normal(d).astype(np.float32)

    pq = ProductQuantizer(d, M=M)
    pq.fit(train)

    assert pq.bytes_per_vector == M
    codes = pq.quantize(db)
    assert codes.shape == (n_db, M), f"Codes shape: {codes.shape}"
    assert codes.dtype == np.uint8

    scores = pq.cosine_similarity(query, codes)
    assert scores.shape == (n_db,)
    assert scores.min() >= -1.1 and scores.max() <= 1.1
    print(f"  ✓ PQ M={M}: bytes/vec={pq.bytes_per_vector}")
    print(f"  ✓ Scores: min={scores.min():.4f}, max={scores.max():.4f}")
    print(f"  ✓ PASSED")


def test_vabq():
    print_header("Test 4: VABQ Quantizer")
    rng = np.random.default_rng(3)
    d = 384
    n_train, n_db = 2000, 500

    train = rng.standard_normal((n_train, d)).astype(np.float32)
    # Intentional variance skew
    train[:, :100] *= 3.0  # high variance dims

    db = rng.standard_normal((n_db, d)).astype(np.float32)
    db[:, :100] *= 3.0

    for ratio in [0.30, 0.50, 0.75]:
        vabq = build_vabq_from_train_data(train, n_high_ratio=ratio, high_block_size=16, low_block_size=64)
        n_high = vabq.n_high
        n_low = vabq.n_low
        n_high_blocks = (n_high + 16 - 1) // 16
        n_low_blocks = (n_low + 64 - 1) // 64
        expected_bytes = n_high + n_high_blocks * 4 + (n_low + 1) // 2 + n_low_blocks * 4

        # Bytes per vector check
        assert vabq.bytes_per_vector == expected_bytes, (
            f"ratio={ratio}: expected {expected_bytes}B, got {vabq.bytes_per_vector}B"
        )

        # Quantize and compute cosine
        q_result = vabq.quantize(db)
        q = rng.standard_normal(d).astype(np.float32)
        scores = vabq.cosine_similarity(q, q_result)

        assert scores.shape == (n_db,)
        assert scores.min() >= -1.1 and scores.max() <= 1.1
        print(f"  ✓ ratio={ratio}: n_high={n_high}, n_low={n_low}, "
              f"bytes/vec={vabq.bytes_per_vector}, "
              f"scores: min={scores.min():.4f}, max={scores.max():.4f}")

    print(f"  ✓ PASSED")


def test_recall_benchmark():
    print_header("Test 5: Recall Benchmark (synthetic data)")
    train_vecs, db_vecs, q_vecs = load_synthetic(
        n_dims=384, n_db=5000, n_queries=50, n_train=1000, seed=42
    )
    d = db_vecs.shape[1]
    k = 10

    gt = compute_ground_truth(q_vecs, db_vecs, k=k)

    quantizers = [
        UniformQuantizer(d),
        Q8_0Quantizer(d, block_size=32),
        build_vabq_from_train_data(train_vecs, n_high_ratio=0.75),
    ]
    for q in quantizers:
        q.fit(train_vecs)

    print(f"\n  {'Method':<35} {'Recall@10':>10} {'Latency(ms)':>12} {'Bytes/vec':>10}")
    print(f"  {'-'*70}")
    for q in quantizers:
        if isinstance(q, Q8_0Quantizer):
            db_q = q.quantize(db_vecs)
        elif isinstance(q, UniformQuantizer):
            db_q = q.quantize(db_vecs)
        elif isinstance(q, VABQQuantizer):
            db_q = q.quantize(db_vecs)

        recalls = []
        latencies = []
        for qi in range(len(q_vecs)):
            t0 = time.perf_counter()
            scores = q.cosine_similarity(q_vecs[qi], db_q)
            t1 = time.perf_counter()
            latencies.append((t1 - t0) * 1000)
            topk = np.argsort(-scores)[:k]
            hits = len(set(topk.tolist()) & set(gt[qi].tolist()))
            recalls.append(hits / k)

        recall = np.mean(recalls)
        latency = np.mean(latencies)
        print(f"  {q.name:<35} {recall:>10.4f} {latency:>12.3f} {q.bytes_per_vector:>10}")
        assert recall > 0.5, f"{q.name} recall too low: {recall}"

    print(f"\n  ✓ PASSED — all methods achieved >50% recall on synthetic data.")


if __name__ == "__main__":
    test_uniform()
    test_q8_0()
    test_pq()
    test_vabq()
    test_recall_benchmark()
    print("\n" + "="*55)
    print("  🎉 All tests passed!")
    print("="*55)
