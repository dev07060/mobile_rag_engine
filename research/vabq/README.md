# VABQ Research

This directory contains all code for the **Variance-aware Adaptive Block Quantization (VABQ)** research simulation, supporting the academic paper:

> **"VABQ: Variance-aware Adaptive Block Quantization for Memory-Efficient On-Device RAG"**

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
├── variance_maps/          ← Output: pre-computed variance maps (JSON + .npy)
└── results/                ← Output: eval_results.json + plots/
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

### Option B: Real MSMARCO Data (Recommended for paper)
```bash
# Small scale (20k vectors, all-MiniLM)
.venv/bin/python research/vabq/run_pipeline.py \
    --mode msmarco \
    --model sentence-transformers/all-MiniLM-L6-v2 \
    --n_db 20000

# Large scale (100k vectors, BGE-M3, for paper submission)
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

This dual-precision strategy achieves significantly better **recall vs. storage tradeoff** compared to uniform Q8_0 and Product Quantization.

| Method           | Bytes/Vec (384-dim) | Expected Recall@10 |
|:---               |:---:                |:---:               |
| F32 (Exact)       | 1536 B              | 1.000              |
| Uniform Q8        | 384 B               | ~0.85              |
| Q8_0 (block=32)   | 432 B               | ~0.92              |
| PQ (M=16)         | 16 B                | ~0.80              |
| **VABQ (ours)**   | **280–340 B**       | **~0.96–0.98**     |

---

## ✅ Running Unit Tests

```bash
.venv/bin/python research/vabq/test_quantizers.py
```

---

## 📊 Paper Figures Generated

- `fig1_pareto_curve.pdf` — Memory vs. Recall@10 Pareto curve
- `fig2_latency_vs_recall.pdf` — Latency vs. Recall scatterplot
- `fig3_compression_ratio.pdf` — Bytes/vector bar chart
- `fig4_recall_distribution.pdf` — Recall distribution per method
- `fig0_combined.pdf` — Combined 2×2 figure for paper appendix
