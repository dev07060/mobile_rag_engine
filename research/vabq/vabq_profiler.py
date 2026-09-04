"""
VABQ Profiler (Step 1)
----------------------
Computes per-dimension variance across a large representative text corpus
and exports a sorted dimension-index mapping for use in the VABQ quantizer.

This script is run ONCE offline. The resulting mapping is then hardcoded
into the VABQ quantizer to avoid any on-device computation overhead.

Usage:
    python vabq_profiler.py --model all-MiniLM-L6-v2 --n_samples 100000 --output variance_maps/
    python vabq_profiler.py --model BAAI/bge-m3 --n_samples 100000 --output variance_maps/
"""

import argparse
import json
import os
import time

import numpy as np
from datasets import load_dataset
from sentence_transformers import SentenceTransformer
from tqdm import tqdm


def compute_variance_map(model_name: str, n_samples: int, output_dir: str, batch_size: int = 256):
    """
    Loads n_samples passages from MSMARCO, embeds them with the given model,
    computes per-dimension variance, and exports the sorted index map.

    Returns:
        variance_map: dict with 'sorted_indices', 'variances', 'model_name', 'n_dims'
    """
    print(f"\n=== VABQ Profiler ===")
    print(f"Model:      {model_name}")
    print(f"N Samples:  {n_samples:,}")
    print(f"Output dir: {output_dir}")
    print("=" * 40)

    # ── 1. Load dataset ──────────────────────────────────────────────────────
    print("\n[1/4] Loading MSMARCO dataset...")
    dataset = load_dataset(
        "microsoft/ms_marco",
        "v2.1",
        split="train",
        streaming=True,
        trust_remote_code=True,
    )

    passages = []
    seen = set()
    for item in tqdm(dataset, desc="Collecting passages", total=n_samples):
        for p in item.get("passages", {}).get("passage_text", []):
            stripped = p.strip()
            if stripped and stripped not in seen:
                seen.add(stripped)
                passages.append(stripped)
        if len(passages) >= n_samples:
            break

    passages = passages[:n_samples]
    print(f"  Collected {len(passages):,} unique passages.")

    # ── 2. Embed passages ─────────────────────────────────────────────────────
    print(f"\n[2/4] Embedding with '{model_name}'...")
    model = SentenceTransformer(model_name)

    embeddings_list = []
    t0 = time.time()
    for i in tqdm(range(0, len(passages), batch_size), desc="Embedding"):
        batch = passages[i : i + batch_size]
        batch_emb = model.encode(batch, convert_to_numpy=True, normalize_embeddings=False)
        embeddings_list.append(batch_emb.astype(np.float32))

    embeddings = np.vstack(embeddings_list)
    elapsed = time.time() - t0
    print(f"  Embedding shape: {embeddings.shape} | Time: {elapsed:.1f}s")

    n_dims = embeddings.shape[1]

    # ── 3. Compute per-dimension variance ─────────────────────────────────────
    print("\n[3/4] Computing per-dimension variance...")
    variances = np.var(embeddings, axis=0)  # shape: (n_dims,)

    # Sort dimensions by variance (descending: high variance first)
    sorted_indices = np.argsort(variances)[::-1].tolist()

    var_stats = {
        "max": float(variances.max()),
        "min": float(variances.min()),
        "mean": float(variances.mean()),
        "std": float(variances.std()),
        "high_var_threshold_50pct": float(np.percentile(variances, 50)),
        "high_var_threshold_25pct": float(np.percentile(variances, 25)),
    }
    print(f"  Variance stats: max={var_stats['max']:.4f}, mean={var_stats['mean']:.4f}, "
          f"min={var_stats['min']:.4f}")

    # ── 4. Export ─────────────────────────────────────────────────────────────
    print(f"\n[4/4] Exporting variance map...")
    os.makedirs(output_dir, exist_ok=True)

    # Safe model name for filename
    safe_model_name = model_name.replace("/", "_").replace("-", "_")

    variance_map = {
        "model_name": model_name,
        "n_samples": n_samples,
        "n_dims": n_dims,
        "sorted_indices": sorted_indices,
        "variances_sorted": [float(variances[i]) for i in sorted_indices],
        "stats": var_stats,
    }

    output_path = os.path.join(output_dir, f"variance_map_{safe_model_name}.json")
    with open(output_path, "w") as f:
        json.dump(variance_map, f, indent=2)

    # Also export as numpy for fast loading in the quantizer
    np_path = os.path.join(output_dir, f"sorted_indices_{safe_model_name}.npy")
    np.save(np_path, np.array(sorted_indices, dtype=np.int32))

    var_path = os.path.join(output_dir, f"variances_{safe_model_name}.npy")
    np.save(var_path, variances)

    print(f"  Saved: {output_path}")
    print(f"  Saved: {np_path}")
    print(f"  Saved: {var_path}")
    print("\n✅ Profiling complete!")

    return variance_map


def print_variance_analysis(variance_map: dict):
    """Prints a summary showing where the top high-variance dimensions are."""
    n_dims = variance_map["n_dims"]
    variances_sorted = variance_map["variances_sorted"]

    # Cumulative variance coverage
    total_var = sum(variances_sorted)
    cumulative = 0.0
    thresholds = [0.50, 0.75, 0.90, 0.95]
    th_idx = 0

    print("\n=== Cumulative Variance Coverage ===")
    print(f"{'Top-N Dims':<15} {'Cum. Variance %':<20}")
    print("-" * 35)

    for i, v in enumerate(variances_sorted):
        cumulative += v
        frac = cumulative / total_var
        if th_idx < len(thresholds) and frac >= thresholds[th_idx]:
            print(f"{i+1:<15} {frac*100:.1f}% ← covers {thresholds[th_idx]*100:.0f}% of total variance")
            th_idx += 1
        if th_idx >= len(thresholds):
            break

    # Recommendation for N_high split
    n_high_50 = next(
        i + 1
        for i, v in enumerate(np.cumsum(variances_sorted) / total_var)
        if v >= 0.75
    )
    print(f"\n📌 Recommended N_high (covering 75% of variance): {n_high_50} / {n_dims} dimensions")
    print(f"   → High-variance segment: dims 0..{n_high_50-1} → INT8, block_size=16")
    print(f"   → Low-variance segment:  dims {n_high_50}..{n_dims-1} → INT4, block_size=64")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VABQ Variance Profiler")
    parser.add_argument(
        "--model",
        type=str,
        default="sentence-transformers/all-MiniLM-L6-v2",
        help="HuggingFace model name",
    )
    parser.add_argument(
        "--n_samples", type=int, default=50000, help="Number of passages to embed"
    )
    parser.add_argument(
        "--output", type=str, default="variance_maps", help="Output directory"
    )
    parser.add_argument("--batch_size", type=int, default=256, help="Embedding batch size")
    args = parser.parse_args()

    variance_map = compute_variance_map(
        model_name=args.model,
        n_samples=args.n_samples,
        output_dir=args.output,
        batch_size=args.batch_size,
    )
    print_variance_analysis(variance_map)
