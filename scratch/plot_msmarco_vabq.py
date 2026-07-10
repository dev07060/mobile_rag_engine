import numpy as np
import matplotlib.pyplot as plt
import os
import sys

out_dir = "/Users/dev_bh/.gemini/antigravity/brain/7377f9b4-d0da-4217-9f2f-2f80f5b1d62f"
os.makedirs(out_dir, exist_ok=True)
np.random.seed(42)

def simulate_q8(v):
    q_v = np.zeros_like(v)
    max_abs = np.max(np.abs(v), axis=1, keepdims=True)
    max_abs[max_abs == 0] = 1e-9
    scale = 127.0 / max_abs
    q_v = np.round(v * scale) / scale
    return q_v

def simulate_vabq(v, block_size=32):
    q_v = np.zeros_like(v)
    for i in range(0, v.shape[1], block_size):
        block = v[:, i:i+block_size]
        max_abs = np.max(np.abs(block), axis=1, keepdims=True)
        max_abs[max_abs == 0] = 1e-9
        scale = 127.0 / max_abs
        q_v[:, i:i+block_size] = np.round(block * scale) / scale
    return q_v

print("Loading MS MARCO and encoding...")
try:
    from datasets import load_dataset
    from sentence_transformers import SentenceTransformer
except ImportError:
    print("Failed to import datasets or sentence_transformers")
    sys.exit(1)

# Only get a small slice to save time
ds = load_dataset("microsoft/ms_marco", "v2.1", split="train", streaming=True, trust_remote_code=True)
passages = []
for item in ds:
    for p in item.get("passages", {}).get("passage_text", []):
        if p and p not in passages:
            passages.append(p)
    if len(passages) >= 2000:
        break

passages = passages[:2000]
print(f"Collected {len(passages)} passages. Encoding...")

# Use 768d model for testing
model = SentenceTransformer("BAAI/bge-base-en-v1.5")
embs = model.encode(passages, convert_to_numpy=True, normalize_embeddings=True, show_progress_bar=False).astype(np.float32)

dim = embs.shape[1]
print(f"Generated {embs.shape} embeddings.")

sample_A = embs[:1000]
sample_B = embs[1000:2000]

print("Calculating similarities...")
cos_base = np.dot(sample_A, sample_B.T).flatten()

q8_B = simulate_q8(sample_B)
cos_q8 = np.dot(sample_A, q8_B.T).flatten()
diff_q8 = cos_base - cos_q8

vabq_B = simulate_vabq(sample_B, block_size=32)
cos_vabq = np.dot(sample_A, vabq_B.T).flatten()
diff_vabq = cos_base - cos_vabq

# Plot the distribution of the base similarities first
plt.figure(figsize=(10, 6))
plt.hist(cos_base, bins=100, color='#4A90E2', alpha=0.8, edgecolor='none')
plt.title(f"MS MARCO Real Data: Cosine Similarity Distribution\n({dim}d, BAAI/bge-base-en-v1.5)", fontsize=14, fontweight='bold')
plt.xlabel("Cosine Similarity", fontsize=12)
plt.ylabel("Frequency", fontsize=12)
plt.grid(axis='y', linestyle='--', alpha=0.7)
plt.axvline(0, color='red', linestyle='dashed', linewidth=1)
plt.tight_layout()
plt.savefig(f"{out_dir}/msmarco_base_similarity.png", dpi=150)
plt.close()

# Plot the Quantization Error comparison
plt.figure(figsize=(10, 6))
bins = np.linspace(-0.02, 0.02, 100)
plt.hist(diff_q8, bins=bins, color='#6C7A89', alpha=0.6, label='Standard Q8 Error', edgecolor='none')
plt.hist(diff_vabq, bins=bins, color='#FF7F0E', alpha=0.8, label='VABQ Error', edgecolor='none')

plt.title(f"MS MARCO Real Data: Q8 vs VABQ Quantization Error\n({dim}d Embeddings)", fontsize=14, fontweight='bold')
plt.xlabel("Error (f32 similarity - Quantized similarity)", fontsize=12)
plt.ylabel("Frequency", fontsize=12)
plt.axvline(0, color='black', linestyle='--', linewidth=1)
plt.grid(axis='y', linestyle=':', alpha=0.7)
plt.legend(fontsize=11)

std_q8 = np.std(diff_q8)
std_vabq = np.std(diff_vabq)
var_reduction = (1.0 - (std_vabq**2) / (std_q8**2)) * 100

textstr = f"Q8 Std Dev:   {std_q8:.6f}\nVABQ Std Dev: {std_vabq:.6f}\n\nVariance Reduction: {var_reduction:.1f}%"
plt.text(0.05, 0.95, textstr, transform=plt.gca().transAxes, fontsize=11,
        verticalalignment='top', bbox=dict(boxstyle='round,pad=0.5', facecolor='#F9F9F9', alpha=0.9, edgecolor='#CCCCCC'))

plt.tight_layout()
plt.savefig(f"{out_dir}/msmarco_q8_vs_vabq.png", dpi=150)
plt.close()

print("Plot saved successfully.")
