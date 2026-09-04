# VABQ Research

This directory contains the experimental **Variance-aware Adaptive Block
Quantization (VABQ)** research code. VABQ remains an explicit opt-in; Q8_0 is
the supported public default.

The current checkpoint does not establish a repeatable retrieval-quality,
latency, or RSS advantage over Q8_0. See
[`docs/reports/2026-08-09-onboarding-vs-vabq-decision.md`](../../docs/reports/2026-08-09-onboarding-vs-vabq-decision.md)
for the measured boundary and product decision.

---

## 📁 File Structure

```
research/vabq/
├── README.md               ← This file
├── vabq_profiler.py        ← Step 1: Offline dimension-variance profiler
├── vabq_quantizer.py       ← Step 2: All quantizer implementations (Uniform, Q8_0, PQ, VABQ)
├── vabq_evaluator.py       ← Step 3: Recall@10 + latency evaluator
├── plot_results.py         ← Step 4: Publication-quality plot generator
├── run_pipeline.py         ← 🚀 Master pipeline runner (runs all steps)
├── test_quantizers.py      ← ✅ Unit tests for mathematical correctness
├── variance_maps/          ← Generated locally: variance maps (JSON + .npy)
└── results/                ← Generated locally: eval_results.json + plots/
```

---

## 🚀 Quick Start

### Option A: Synthetic Data (Fast, ~2 minutes)
```bash
# Run full pipeline with synthetic embeddings
cd /path/to/mobile_rag_engine
.venv/bin/python research/vabq/run_pipeline.py --mode synthetic

# Output: research/vabq/results/eval_results.json
#         research/vabq/results/plots/*.png
#         research/vabq/results/plots/*.pdf
```

### Option B: Real MSMARCO Data
```bash
# Small scale (20k vectors, all-MiniLM)
.venv/bin/python research/vabq/run_pipeline.py \
    --mode msmarco \
    --model sentence-transformers/all-MiniLM-L6-v2 \
    --n_db 20000

# Larger exploratory run (100k vectors, BGE-M3)
.venv/bin/python research/vabq/run_pipeline.py \
    --mode msmarco \
    --model BAAI/bge-m3 \
    --n_db 100000 \
    --n_queries 500 \
    --n_train 10000
```

---

## 🔬 Algorithm: VABQ (Proposed Method)

VABQ observes that **not all embedding dimensions carry equal semantic information**. By profiling the per-dimension variance across a large corpus:

1. **High-variance dimensions** (covering 75% of total variance) are quantized to **INT8** with fine-grained block size 16.
2. **Low-variance dimensions** are quantized to **INT4** with coarse block size 64.

This dual-precision strategy is being evaluated as a storage tradeoff. The
checked-in research code must not be treated as proof that VABQ outperforms
Q8_0. Reproduce results against the same model, corpus, byte budget, binary,
and device before drawing a quality or performance conclusion.

---

## ✅ Running Unit Tests

```bash
.venv/bin/python research/vabq/test_quantizers.py
```

---

## 📊 Generated Figures

- `fig1_pareto_curve.pdf` — Memory vs. Recall@10 Pareto curve
- `fig2_latency_vs_recall.pdf` — Latency vs. Recall scatterplot
- `fig3_compression_ratio.pdf` — Bytes/vector bar chart
- `fig4_recall_distribution.pdf` — Recall distribution per method
- `fig0_combined.pdf` — Combined 2×2 figure for paper appendix

Generated variance maps, raw result JSON, and plot binaries are intentionally
excluded from the release branch. Run the pipeline to reproduce them locally.
