"""
VABQ Plot Results (Step 4)
---------------------------
Generates publication-quality charts from the evaluator JSON results:

  1. Pareto Curve        : Bytes/vector (X) vs. Recall@10 (Y)
  2. Latency vs. Recall  : Recall@10 (X) vs. Mean Scan Latency ms (Y)
  3. Bits per Element    : Storage efficiency comparison bar chart
  4. Recall Distribution : Box plot of per-query recall variance

Usage:
    python plot_results.py --input eval_results.json --output_dir plots/
    python plot_results.py --input eval_results.json --output_dir plots/ --format pdf
"""

from __future__ import annotations

import argparse
import json
import os
from typing import List

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
import seaborn as sns


# ─────────────────────────────────────────────────────────────────────────────
# Style configuration
# ─────────────────────────────────────────────────────────────────────────────

STYLE = {
    "font.family": "DejaVu Sans",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "grid.linestyle": "--",
    "figure.dpi": 150,
}

# Color palette: one color per method family
COLORS = {
    "uniform": "#e74c3c",   # red
    "q8_0":    "#e67e22",   # orange
    "pq":      "#3498db",   # blue
    "vabq":    "#27ae60",   # green (proposed)
}

MARKERS = {
    "uniform": "X",
    "q8_0":    "s",
    "pq":      "o",
    "vabq":    "*",
}

MARKER_SIZES = {
    "uniform": 9,
    "q8_0":    9,
    "pq":      9,
    "vabq":    14,
}


def classify_result(name: str) -> str:
    """Map result name to a method family for color coding."""
    n = name.lower()
    if "vabq" in n:
        return "vabq"
    elif "uniform" in n:
        return "uniform"
    elif "q8_0" in n or "q8" in n:
        return "q8_0"
    elif "pq" in n:
        return "pq"
    return "pq"


# ─────────────────────────────────────────────────────────────────────────────
# Plot 1: Pareto Curve (Memory vs. Recall)
# ─────────────────────────────────────────────────────────────────────────────

def plot_pareto_curve(results: List[dict], ax: plt.Axes, n_dims: int | None = None):
    """
    X: bytes_per_vector (storage cost)
    Y: recall_at_10

    Also draws the f32 baseline (exact recall=1.0) as a reference horizontal line.
    """
    ax.set_title("Pareto Curve: Memory Footprint vs. Recall@10", fontsize=13, fontweight="bold", pad=10)
    ax.set_xlabel("Storage per Vector (bytes)", fontsize=11)
    ax.set_ylabel("Recall@10", fontsize=11)
    ax.set_ylim(0.0, 1.05)

    # Draw f32 exact baseline
    if n_dims:
        f32_bytes = n_dims * 4
        ax.axvline(x=f32_bytes, color="gray", linestyle=":", linewidth=1.5, alpha=0.7, label=f"F32 exact ({f32_bytes}B)")

    ax.axhline(y=1.0, color="gray", linestyle="--", linewidth=1.0, alpha=0.5, label="Perfect recall (1.0)")

    # Scatter all points
    for r in results:
        family = classify_result(r["name"])
        ax.scatter(
            r["bytes_per_vector"],
            r["recall_at_10"],
            color=COLORS[family],
            marker=MARKERS[family],
            s=MARKER_SIZES[family] ** 2,
            zorder=5,
            label=r["name"],
        )
        # Annotate VABQ points more prominently
        if family == "vabq":
            ax.annotate(
                f"  {r['recall_at_10']:.3f}",
                (r["bytes_per_vector"], r["recall_at_10"]),
                fontsize=7.5,
                color=COLORS["vabq"],
                fontweight="bold",
            )

    # Highlight the Pareto frontier (max recall for each byte count)
    from collections import defaultdict
    family_points: dict[str, list] = defaultdict(list)
    for r in results:
        family = classify_result(r["name"])
        family_points[family].append((r["bytes_per_vector"], r["recall_at_10"]))

    # Draw best-frontier curve for VABQ
    if "vabq" in family_points:
        pts = sorted(family_points["vabq"], key=lambda x: x[0])
        xs, ys = zip(*pts)
        ax.plot(xs, ys, color=COLORS["vabq"], linewidth=1.5, linestyle="-", alpha=0.6, zorder=3)

    # Legend (deduplicated by family)
    handles = [
        mpatches.Patch(color=COLORS["uniform"], label="Uniform Q8 (Legacy)"),
        mpatches.Patch(color=COLORS["q8_0"], label="Q8_0 (Fixed Block)"),
        mpatches.Patch(color=COLORS["pq"], label="Product Quantization (PQ)"),
        mpatches.Patch(color=COLORS["vabq"], label="VABQ (Proposed ⭐)"),
    ]
    ax.legend(handles=handles, loc="lower right", fontsize=9)


# ─────────────────────────────────────────────────────────────────────────────
# Plot 2: Latency vs. Recall
# ─────────────────────────────────────────────────────────────────────────────

def plot_latency_vs_recall(results: List[dict], ax: plt.Axes):
    """
    X: recall_at_10
    Y: mean_latency_ms

    Lower-left is ideal (high recall AND low latency).
    VABQ should dominate (leftmost = fast) at a given recall level.
    """
    ax.set_title("Latency vs. Recall@10", fontsize=13, fontweight="bold", pad=10)
    ax.set_xlabel("Recall@10", fontsize=11)
    ax.set_ylabel("Mean Exact-Scan Latency (ms)", fontsize=11)

    # Add shaded "ideal zone"
    ax.axvspan(0.9, 1.02, alpha=0.05, color="green", label="High-recall zone")

    for r in results:
        family = classify_result(r["name"])
        ax.scatter(
            r["recall_at_10"],
            r["mean_latency_ms"],
            color=COLORS[family],
            marker=MARKERS[family],
            s=MARKER_SIZES[family] ** 2,
            zorder=5,
        )
        if family == "vabq":
            ax.annotate(
                f"  {r['mean_latency_ms']:.2f}ms",
                (r["recall_at_10"], r["mean_latency_ms"]),
                fontsize=7.5,
                color=COLORS["vabq"],
                fontweight="bold",
            )

    # Arrow annotation
    ax.annotate(
        "Ideal direction\n(High recall, Low latency)",
        xy=(0.95, ax.get_ylim()[0] * 1.05 if ax.get_ylim()[0] > 0 else 0.5),
        fontsize=8,
        color="darkgreen",
        style="italic",
    )

    handles = [
        mpatches.Patch(color=COLORS["uniform"], label="Uniform Q8 (Legacy)"),
        mpatches.Patch(color=COLORS["q8_0"], label="Q8_0 (Fixed Block)"),
        mpatches.Patch(color=COLORS["pq"], label="Product Quantization (PQ)"),
        mpatches.Patch(color=COLORS["vabq"], label="VABQ (Proposed ⭐)"),
    ]
    ax.legend(handles=handles, loc="upper left", fontsize=9)


# ─────────────────────────────────────────────────────────────────────────────
# Plot 3: Compression Ratio Bar Chart
# ─────────────────────────────────────────────────────────────────────────────

def plot_compression_ratio(results: List[dict], ax: plt.Axes, n_dims: int):
    """Bar chart comparing bytes per vector for each method."""
    f32_bytes = n_dims * 4
    ax.set_title("Storage Footprint per Vector", fontsize=13, fontweight="bold", pad=10)
    ax.set_ylabel("Bytes per Vector", fontsize=11)

    # Select representative configs (best recall for each family)
    representatives = {}
    for r in results:
        family = classify_result(r["name"])
        if family not in representatives or r["recall_at_10"] > representatives[family]["recall_at_10"]:
            representatives[family] = r
    reps = [representatives[f] for f in ["uniform", "q8_0", "pq", "vabq"] if f in representatives]
    # Add f32 reference
    reps_with_f32 = [{"name": "F32 (Exact)", "bytes_per_vector": f32_bytes, "_family": "ref"}] + reps

    names = [r.get("name", "F32") for r in reps_with_f32]
    bytes_vals = [r["bytes_per_vector"] for r in reps_with_f32]
    colors = ["#95a5a6" if r.get("_family") == "ref" else COLORS[classify_result(r["name"])] for r in reps_with_f32]

    bars = ax.bar(names, bytes_vals, color=colors, width=0.6, edgecolor="white", linewidth=0.8)
    ax.axhline(y=f32_bytes, color="gray", linestyle="--", linewidth=1.0, alpha=0.6, label=f"F32 baseline ({f32_bytes}B)")

    # Ratio annotations
    for bar, bval in zip(bars, bytes_vals):
        ratio = bval / f32_bytes
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bval + f32_bytes * 0.01,
            f"{ratio:.2f}×\n({bval}B)",
            ha="center", va="bottom", fontsize=8.5,
        )

    ax.set_xticks(range(len(names)))
    ax.set_xticklabels(names, rotation=20, ha="right", fontsize=9)
    ax.legend(fontsize=9)


# ─────────────────────────────────────────────────────────────────────────────
# Plot 4: Recall Distribution (box plot approximation from min/mean/max/std)
# ─────────────────────────────────────────────────────────────────────────────

def plot_recall_distribution(results: List[dict], ax: plt.Axes):
    """Simulates a distribution box using mean ± std from the evaluator."""
    ax.set_title("Recall@10 Distribution per Method", fontsize=13, fontweight="bold", pad=10)
    ax.set_ylabel("Recall@10", fontsize=11)
    ax.set_ylim(0.0, 1.1)

    names, means, stds = [], [], []
    colors_list = []
    for r in results:
        names.append(r["name"])
        means.append(r["recall_at_10"])
        stds.append(r.get("extra", {}).get("recall_std", 0.02))
        colors_list.append(COLORS[classify_result(r["name"])])

    x = np.arange(len(names))
    ax.bar(x, means, yerr=stds, color=colors_list, alpha=0.75, capsize=4,
           edgecolor="white", linewidth=0.8, width=0.6)
    ax.axhline(y=1.0, color="gray", linestyle="--", linewidth=1.0, alpha=0.5, label="Perfect recall")
    ax.set_xticks(x)
    ax.set_xticklabels(names, rotation=30, ha="right", fontsize=7.5)
    ax.legend(fontsize=9)


# ─────────────────────────────────────────────────────────────────────────────
# Main: load results and generate all plots
# ─────────────────────────────────────────────────────────────────────────────

def main(input_path: str, output_dir: str, fmt: str = "png", n_dims: int | None = None):
    with open(input_path) as f:
        results = json.load(f)

    print(f"Loaded {len(results)} results from {input_path}")

    # Auto-detect n_dims from the uniform quantizer entry
    if n_dims is None:
        for r in results:
            if "uniform" in r["name"].lower():
                # bytes_per_vector = n_dims for Uniform
                n_dims = r["bytes_per_vector"]
                break
        if n_dims is None:
            n_dims = 384  # fallback

    os.makedirs(output_dir, exist_ok=True)

    plt.rcParams.update(STYLE)

    # ── Figure 1: Pareto Curve ────────────────────────────────────────────────
    fig, ax = plt.subplots(figsize=(9, 6))
    plot_pareto_curve(results, ax, n_dims=n_dims)
    plt.tight_layout()
    p1 = os.path.join(output_dir, f"fig1_pareto_curve.{fmt}")
    plt.savefig(p1, bbox_inches="tight")
    print(f"Saved: {p1}")
    plt.close()

    # ── Figure 2: Latency vs. Recall ─────────────────────────────────────────
    fig, ax = plt.subplots(figsize=(9, 6))
    plot_latency_vs_recall(results, ax)
    plt.tight_layout()
    p2 = os.path.join(output_dir, f"fig2_latency_vs_recall.{fmt}")
    plt.savefig(p2, bbox_inches="tight")
    print(f"Saved: {p2}")
    plt.close()

    # ── Figure 3: Compression Ratio Bar Chart ────────────────────────────────
    fig, ax = plt.subplots(figsize=(9, 5))
    plot_compression_ratio(results, ax, n_dims=n_dims)
    plt.tight_layout()
    p3 = os.path.join(output_dir, f"fig3_compression_ratio.{fmt}")
    plt.savefig(p3, bbox_inches="tight")
    print(f"Saved: {p3}")
    plt.close()

    # ── Figure 4: Recall Distribution ────────────────────────────────────────
    fig, ax = plt.subplots(figsize=(12, 5))
    plot_recall_distribution(results, ax)
    plt.tight_layout()
    p4 = os.path.join(output_dir, f"fig4_recall_distribution.{fmt}")
    plt.savefig(p4, bbox_inches="tight")
    print(f"Saved: {p4}")
    plt.close()

    # ── Combined 2×2 figure (for paper appendix) ─────────────────────────────
    fig, axes = plt.subplots(2, 2, figsize=(16, 11))
    plot_pareto_curve(results, axes[0, 0], n_dims=n_dims)
    plot_latency_vs_recall(results, axes[0, 1])
    plot_compression_ratio(results, axes[1, 0], n_dims=n_dims)
    plot_recall_distribution(results, axes[1, 1])
    fig.suptitle("VABQ: Variance-aware Adaptive Block Quantization\nEvaluation Summary", fontsize=15, fontweight="bold")
    plt.tight_layout(rect=[0, 0, 1, 0.96])
    p5 = os.path.join(output_dir, f"fig0_combined.{fmt}")
    plt.savefig(p5, bbox_inches="tight")
    print(f"Saved: {p5}")
    plt.close()

    print(f"\n✅ All plots saved to: {output_dir}/")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VABQ Result Plotter")
    parser.add_argument("--input", default="eval_results.json")
    parser.add_argument("--output_dir", default="plots")
    parser.add_argument("--format", default="png", choices=["png", "pdf", "svg"])
    parser.add_argument("--n_dims", type=int, default=None)
    args = parser.parse_args()
    main(args.input, args.output_dir, fmt=args.format, n_dims=args.n_dims)
