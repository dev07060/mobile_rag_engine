"""
VABQ Evaluator (Step 3)
------------------------
Runs exhaustive evaluation of all quantization baselines on a synthetic
or pre-embedded dataset, measuring:
  - recall@10 vs. exact f32 cosine similarity ground truth
  - exact-scan latency (ms) for a batch of query vectors
  - bytes per vector (storage cost)

The evaluator sweeps across multiple configurations to generate the data
for the Pareto Curve and Latency vs. Recall plots.

Usage (standalone):
    python vabq_evaluator.py
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import List, Tuple

import numpy as np
from sentence_transformers import SentenceTransformer
from datasets import load_dataset
from tqdm import tqdm

from vabq_quantizer import (
    UniformQuantizer,
    Q8_0Quantizer,
    ProductQuantizer,
    VABQQuantizer,
    build_vabq_from_train_data,
)


# ─────────────────────────────────────────────────────────────────────────────
# Result data structure
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class EvalResult:
    name: str
    bytes_per_vector: int
    recall_at_10: float
    mean_latency_ms: float
    p50_latency_ms: float
    p95_latency_ms: float
    p99_latency_ms: float
    extra: dict = field(default_factory=dict)


# ─────────────────────────────────────────────────────────────────────────────
# Data loading / embedding
# ─────────────────────────────────────────────────────────────────────────────

def load_and_embed(
    model_name: str = "sentence-transformers/all-MiniLM-L6-v2",
    n_db: int = 20000,
    n_queries: int = 200,
    n_train: int = 5000,
    dataset_name: str = "microsoft/ms_marco",
    seed: int = 42,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Load passages from MSMARCO, embed them, and return:
        (train_vectors, db_vectors, query_vectors)
    where train_vectors is a subset used to fit PQ / compute variance.
    """
    np.random.seed(seed)
    total_needed = n_db + n_queries + n_train

    print(f"\n=== Data Loading & Embedding ===")
    print(f"Model: {model_name}")
    print(f"DB size: {n_db:,} | Queries: {n_queries:,} | Train: {n_train:,}")

    # ── Collect passages ──────────────────────────────────────────────────────
    print("Loading MSMARCO...")
    ds = load_dataset(dataset_name, "v2.1", split="train", streaming=True, trust_remote_code=True)

    passages = []
    seen = set()
    for item in tqdm(ds, desc="Collecting passages", total=total_needed):
        for p in item.get("passages", {}).get("passage_text", []):
            s = p.strip()
            if s and s not in seen:
                seen.add(s)
                passages.append(s)
        if len(passages) >= total_needed:
            break

    passages = passages[:total_needed]
    print(f"Collected {len(passages):,} passages.")

    # ── Embed ─────────────────────────────────────────────────────────────────
    print(f"Embedding with '{model_name}'...")
    model = SentenceTransformer(model_name)
    batch_size = 512
    all_embs = []
    for i in tqdm(range(0, len(passages), batch_size), desc="Embedding"):
        batch = passages[i: i + batch_size]
        embs = model.encode(batch, convert_to_numpy=True, normalize_embeddings=False).astype(np.float32)
        all_embs.append(embs)
    all_embs = np.vstack(all_embs)

    idx = np.random.permutation(len(all_embs))
    train_vectors = all_embs[idx[:n_train]]
    db_vectors = all_embs[idx[n_train: n_train + n_db]]
    query_vectors = all_embs[idx[n_train + n_db: n_train + n_db + n_queries]]

    print(f"Train: {train_vectors.shape}, DB: {db_vectors.shape}, Queries: {query_vectors.shape}")
    return train_vectors, db_vectors, query_vectors


def load_synthetic(
    n_dims: int = 384,
    n_db: int = 20000,
    n_queries: int = 200,
    n_train: int = 5000,
    seed: int = 42,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Generates synthetic embeddings following a mixed-Gaussian distribution
    with intentional variance skew across dimensions (mirrors real text embeddings).
    Used for fast unit tests when the MSMARCO download is not available.
    """
    rng = np.random.default_rng(seed)
    total = n_db + n_queries + n_train

    # Create dimension-varying variance to simulate real embedding behavior
    # High-variance dims: first 30% of dimensions
    n_high = int(n_dims * 0.30)
    n_low = n_dims - n_high

    high_var = rng.standard_normal((total, n_high)) * 2.0  # var ≈ 4.0
    low_var = rng.standard_normal((total, n_low)) * 0.3   # var ≈ 0.09

    all_embs = np.concatenate([high_var, low_var], axis=1).astype(np.float32)

    # Add structured cluster signal
    n_clusters = 20
    centers = rng.standard_normal((n_clusters, n_dims)).astype(np.float32)
    cluster_ids = rng.integers(0, n_clusters, total)
    all_embs += centers[cluster_ids] * 0.5

    train_vectors = all_embs[:n_train]
    db_vectors = all_embs[n_train: n_train + n_db]
    query_vectors = all_embs[n_train + n_db: n_train + n_db + n_queries]

    print(f"[Synthetic] Train: {train_vectors.shape}, DB: {db_vectors.shape}, Queries: {query_vectors.shape}")
    return train_vectors, db_vectors, query_vectors


# ─────────────────────────────────────────────────────────────────────────────
# Ground truth computation
# ─────────────────────────────────────────────────────────────────────────────

def compute_ground_truth(
    queries: np.ndarray, db: np.ndarray, k: int = 10
) -> np.ndarray:
    """
    Exact f32 cosine similarity search. Returns top-k indices per query.
    Shape: (n_queries, k)
    """
    q_normed = queries / (np.linalg.norm(queries, axis=1, keepdims=True) + 1e-9)
    db_normed = db / (np.linalg.norm(db, axis=1, keepdims=True) + 1e-9)
    scores = q_normed @ db_normed.T  # (n_queries, n_db)
    gt = np.argsort(-scores, axis=1)[:, :k]
    return gt.astype(np.int32)


# ─────────────────────────────────────────────────────────────────────────────
# Single-quantizer evaluation
# ─────────────────────────────────────────────────────────────────────────────

def evaluate_quantizer(
    quantizer,
    db_vectors: np.ndarray,
    query_vectors: np.ndarray,
    ground_truth: np.ndarray,
    k: int = 10,
    n_warmup: int = 5,
) -> EvalResult:
    """
    Evaluates a quantizer by:
    1. Quantizing all DB vectors.
    2. For each query, running cosine_similarity() over all DB vectors.
    3. Computing recall@k vs. ground truth.
    4. Measuring per-query scan latency.
    """
    print(f"\n  Evaluating: {quantizer.name}")

    # Quantize DB
    t_q_start = time.perf_counter()
    db_q = quantizer.quantize(db_vectors)
    t_q_end = time.perf_counter()
    print(f"    Quantization time: {(t_q_end - t_q_start)*1000:.1f}ms | "
          f"Bytes/vec: {quantizer.bytes_per_vector}")

    n_queries = query_vectors.shape[0]
    latencies_ms = []
    recall_scores = []

    # Warmup
    for _ in range(n_warmup):
        _ = quantizer.cosine_similarity(query_vectors[0], db_q)

    # Main evaluation loop
    for qi in range(n_queries):
        q = query_vectors[qi]
        t0 = time.perf_counter()
        scores = quantizer.cosine_similarity(q, db_q)
        t1 = time.perf_counter()

        latencies_ms.append((t1 - t0) * 1000.0)

        # Top-k approximate results
        approx_topk = np.argsort(-scores)[:k]
        gt_topk = set(ground_truth[qi].tolist())
        hits = len(set(approx_topk.tolist()) & gt_topk)
        recall_scores.append(hits / k)

    latencies_arr = np.array(latencies_ms)
    recall_arr = np.array(recall_scores)

    result = EvalResult(
        name=quantizer.name,
        bytes_per_vector=quantizer.bytes_per_vector,
        recall_at_10=float(recall_arr.mean()),
        mean_latency_ms=float(latencies_arr.mean()),
        p50_latency_ms=float(np.percentile(latencies_arr, 50)),
        p95_latency_ms=float(np.percentile(latencies_arr, 95)),
        p99_latency_ms=float(np.percentile(latencies_arr, 99)),
        extra={
            "recall_std": float(recall_arr.std()),
            "recall_min": float(recall_arr.min()),
            "recall_max": float(recall_arr.max()),
        },
    )

    print(f"    recall@{k}={result.recall_at_10:.4f} | "
          f"mean_lat={result.mean_latency_ms:.3f}ms | "
          f"p95={result.p95_latency_ms:.3f}ms")
    return result


# ─────────────────────────────────────────────────────────────────────────────
# Full sweep across configurations
# ─────────────────────────────────────────────────────────────────────────────

def run_full_sweep(
    train_vectors: np.ndarray,
    db_vectors: np.ndarray,
    query_vectors: np.ndarray,
    n_dims: int,
    k: int = 10,
    pq_m_values: List[int] = None,
    vabq_ratios: List[float] = None,
) -> List[EvalResult]:
    """
    Runs evaluation of all baselines and VABQ across multiple configurations.
    Returns a list of EvalResult objects for plotting.
    """
    if pq_m_values is None:
        pq_m_values = [8, 16, 24, 32, 48] if n_dims % 48 == 0 else [8, 16]
        # Auto-adjust for dimensions that must be divisible by M
        pq_m_values = [m for m in pq_m_values if n_dims % m == 0]
    if vabq_ratios is None:
        vabq_ratios = [0.30, 0.50, 0.75, 0.90]

    gt = compute_ground_truth(query_vectors, db_vectors, k=k)
    print(f"\nGround truth computed for {len(query_vectors)} queries, top-{k}.")

    results: List[EvalResult] = []

    # ── Baseline 1: Uniform Quantization ─────────────────────────────────────
    u = UniformQuantizer(n_dims)
    u.fit(train_vectors)
    results.append(evaluate_quantizer(u, db_vectors, query_vectors, gt, k=k))

    # ── Baseline 2: Q8_0 with various block sizes ─────────────────────────────
    for bs in [16, 32, 64]:
        q8 = Q8_0Quantizer(n_dims, block_size=bs)
        q8.fit(train_vectors)
        results.append(evaluate_quantizer(q8, db_vectors, query_vectors, gt, k=k))

    # ── Baseline 3: PQ with various M values ─────────────────────────────────
    for M in pq_m_values:
        pq = ProductQuantizer(n_dims, M=M)
        pq.fit(train_vectors)
        results.append(evaluate_quantizer(pq, db_vectors, query_vectors, gt, k=k))

    # ── Proposed: VABQ with various n_high ratios ─────────────────────────────
    for ratio in vabq_ratios:
        for high_bs, low_bs in [(16, 64), (32, 64)]:
            vabq = VABQQuantizer.from_runtime_variance(
                vectors=train_vectors,
                n_high_ratio=ratio,
                high_block_size=high_bs,
                low_block_size=low_bs,
            )
            vabq.fit(train_vectors)
            results.append(evaluate_quantizer(vabq, db_vectors, query_vectors, gt, k=k))

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Standalone entry point
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import json
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="sentence-transformers/all-MiniLM-L6-v2")
    parser.add_argument("--n_db", type=int, default=20000)
    parser.add_argument("--n_queries", type=int, default=200)
    parser.add_argument("--n_train", type=int, default=5000)
    parser.add_argument("--k", type=int, default=10)
    parser.add_argument("--output", default="eval_results.json")
    parser.add_argument(
        "--synthetic",
        action="store_true",
        help="Use synthetic data instead of downloading MSMARCO",
    )
    args = parser.parse_args()

    if args.synthetic:
        n_dims = 384
        train_vecs, db_vecs, q_vecs = load_synthetic(
            n_dims=n_dims, n_db=args.n_db, n_queries=args.n_queries, n_train=args.n_train
        )
    else:
        train_vecs, db_vecs, q_vecs = load_and_embed(
            model_name=args.model,
            n_db=args.n_db,
            n_queries=args.n_queries,
            n_train=args.n_train,
        )
        n_dims = db_vecs.shape[1]

    results = run_full_sweep(
        train_vectors=train_vecs,
        db_vectors=db_vecs,
        query_vectors=q_vecs,
        n_dims=n_dims,
        k=args.k,
    )

    # Save results
    out = [
        {
            "name": r.name,
            "bytes_per_vector": r.bytes_per_vector,
            "recall_at_10": r.recall_at_10,
            "mean_latency_ms": r.mean_latency_ms,
            "p50_latency_ms": r.p50_latency_ms,
            "p95_latency_ms": r.p95_latency_ms,
            "p99_latency_ms": r.p99_latency_ms,
            "extra": r.extra,
        }
        for r in results
    ]

    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)
    print(f"\n✅ Results saved to {args.output}")
