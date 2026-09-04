#!/usr/bin/env python3
"""
VABQ Pipeline Runner
--------------------
Orchestrates the full VABQ research pipeline:
  1. Embed data from MSMARCO (or use synthetic data)
  2. Run evaluation of all quantizers
  3. Generate paper-ready plots

Usage:
    # Quick smoke test with synthetic data (~2 minutes)
    python run_pipeline.py --mode synthetic

    # Full MSMARCO run (recommended for paper; ~30-60 mins depending on hardware)
    python run_pipeline.py --mode msmarco --model sentence-transformers/all-MiniLM-L6-v2

    # Large-scale run with BGE-M3
    python run_pipeline.py --mode msmarco --model BAAI/bge-m3 --n_db 100000
"""

import argparse
import json
import os
import sys
import time

# Make sure local modules are importable
sys.path.insert(0, os.path.dirname(__file__))

from vabq_evaluator import (
    load_and_embed,
    load_synthetic,
    run_full_sweep,
)
from plot_results import main as plot_main


def run_pipeline(args):
    os.makedirs(args.output_dir, exist_ok=True)
    results_path = os.path.join(args.output_dir, "eval_results.json")
    plots_dir = os.path.join(args.output_dir, "plots")

    t_total = time.time()

    # ── Step 1 & 2: Load/embed data ───────────────────────────────────────────
    print("\n" + "=" * 60)
    print("  VABQ Research Pipeline")
    print("=" * 60)
    print(f"  Mode:      {args.mode}")
    print(f"  Output:    {args.output_dir}")
    print(f"  DB size:   {args.n_db:,}")
    print(f"  Queries:   {args.n_queries:,}")
    print("=" * 60)

    if args.mode == "synthetic":
        n_dims = 384
        print("\n[MODE] Using synthetic embeddings (fast, no downloads needed).")
        train_vecs, db_vecs, q_vecs = load_synthetic(
            n_dims=n_dims,
            n_db=args.n_db,
            n_queries=args.n_queries,
            n_train=args.n_train,
        )
    else:
        train_vecs, db_vecs, q_vecs = load_and_embed(
            model_name=args.model,
            n_db=args.n_db,
            n_queries=args.n_queries,
            n_train=args.n_train,
        )
        n_dims = db_vecs.shape[1]

    # ── Step 3: Run full evaluation sweep ──────────────────────────────────────
    print("\n" + "=" * 60)
    print("  Running quantizer evaluation sweep...")
    print("=" * 60)

    # Auto-pick valid PQ M values that divide n_dims evenly
    pq_m_values = [m for m in [8, 12, 16, 24, 32, 48, 64] if n_dims % m == 0][:5]
    vabq_ratios = [0.30, 0.50, 0.75, 0.90]

    results = run_full_sweep(
        train_vectors=train_vecs,
        db_vectors=db_vecs,
        query_vectors=q_vecs,
        n_dims=n_dims,
        k=args.k,
        pq_m_values=pq_m_values,
        vabq_ratios=vabq_ratios,
    )

    # ── Step 4: Save results ──────────────────────────────────────────────────
    out_data = [
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
    with open(results_path, "w") as f:
        json.dump(out_data, f, indent=2)
    print(f"\n✅ Evaluation results saved: {results_path}")

    # ── Step 5: Print summary table ───────────────────────────────────────────
    print("\n" + "=" * 70)
    print(f"  {'Method':<35} {'Bytes/Vec':>10} {'Recall@10':>12} {'Latency(ms)':>13}")
    print("-" * 70)
    for r in sorted(results, key=lambda x: -x.recall_at_10):
        star = " ⭐" if "VABQ" in r.name else ""
        print(f"  {r.name+star:<35} {r.bytes_per_vector:>10} {r.recall_at_10:>12.4f} {r.mean_latency_ms:>13.3f}")
    print("=" * 70)

    # ── Step 6: Generate plots ────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print("  Generating paper plots...")
    print("=" * 60)
    plot_main(results_path, plots_dir, fmt="png", n_dims=n_dims)
    # Also generate PDF versions for paper submission
    plot_main(results_path, plots_dir, fmt="pdf", n_dims=n_dims)

    elapsed = time.time() - t_total
    print(f"\n🎉 Pipeline completed in {elapsed:.1f}s")
    print(f"   Results: {results_path}")
    print(f"   Plots:   {plots_dir}/")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VABQ Research Pipeline Runner")
    parser.add_argument(
        "--mode",
        choices=["synthetic", "msmarco"],
        default="synthetic",
        help="Data source: 'synthetic' for fast smoke-test, 'msmarco' for real data",
    )
    parser.add_argument(
        "--model",
        default="sentence-transformers/all-MiniLM-L6-v2",
        help="Embedding model (only used in msmarco mode)",
    )
    parser.add_argument("--n_db", type=int, default=20000, help="Number of database vectors")
    parser.add_argument("--n_queries", type=int, default=200, help="Number of query vectors")
    parser.add_argument("--n_train", type=int, default=5000, help="Vectors used for PQ training / variance computation")
    parser.add_argument("--k", type=int, default=10, help="Top-K for recall evaluation")
    parser.add_argument("--output_dir", default="results", help="Directory to store eval JSON and plots")
    args = parser.parse_args()

    run_pipeline(args)
