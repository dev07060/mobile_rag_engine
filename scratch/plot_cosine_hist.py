import numpy as np
import matplotlib.pyplot as plt
import os

# Create an artifacts directory path (use conversation id)
out_dir = "/Users/dev_bh/.gemini/antigravity/brain/7377f9b4-d0da-4217-9f2f-2f80f5b1d62f"
os.makedirs(out_dir, exist_ok=True)

np.random.seed(42)
dim = 768

# 1. Random Vector Distribution (Baseline)
# 10,000 vectors
N = 10000
vecs = np.random.randn(N, dim)
vecs = vecs / np.linalg.norm(vecs, axis=1, keepdims=True)

# Calculate cosine similarities for a subset of pairs to avoid memory issues
# We calculate dot product of 2000 x 2000 = 4 million pairs
sample_A = vecs[:2000]
sample_B = vecs[2000:4000]
cos_sims_base = np.dot(sample_A, sample_B.T).flatten()

# 2. VABQ Quantization Error Distribution
def simulate_vabq(v, block_size=32):
    q_v = np.zeros_like(v)
    for i in range(0, v.shape[1], block_size):
        block = v[:, i:i+block_size]
        max_abs = np.max(np.abs(block), axis=1, keepdims=True)
        # Avoid div by zero
        max_abs[max_abs == 0] = 1e-9
        scale = 127.0 / max_abs
        q_block = np.round(block * scale)
        q_v[:, i:i+block_size] = q_block / scale
    return q_v

# Quantize Sample B
q_sample_B = simulate_vabq(sample_B, block_size=32)

# Calculate Asymmetric Distance: f32 (Sample A) x VABQ (Sample B)
cos_sims_vabq = np.dot(sample_A, q_sample_B.T).flatten()

# Calculate the difference (Quantization noise)
diff = cos_sims_base - cos_sims_vabq

# Plot 1: Overall Cosine Similarity Distribution
plt.figure(figsize=(10, 6))
plt.hist(cos_sims_base, bins=100, color='#4A90E2', alpha=0.8, edgecolor='white', linewidth=0.5)
plt.axvline(0, color='red', linestyle='dashed', linewidth=1)
plt.title(f"Cosine Similarity Distribution\n({dim}-dimensional random vectors)", fontsize=14, fontweight='bold')
plt.xlabel("Cosine Similarity", fontsize=12)
plt.ylabel("Frequency", fontsize=12)
plt.grid(axis='y', linestyle='--', alpha=0.7)
# Annotate
mean_val = np.mean(cos_sims_base)
std_val = np.std(cos_sims_base)
plt.text(0.05, 0.95, f"Mean: {mean_val:.4f}\nStd Dev: {std_val:.4f}\n(Notice how tightly clustered around 0 it is)",
         transform=plt.gca().transAxes, fontsize=11, verticalalignment='top', bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
plt.tight_layout()
plt.savefig(f"{out_dir}/cosine_distribution.png", dpi=150)
plt.close()

# Plot 2: VABQ vs Baseline Error
plt.figure(figsize=(10, 6))
plt.hist(diff, bins=100, color='#F5A623', alpha=0.8, edgecolor='white', linewidth=0.5)
plt.axvline(0, color='black', linestyle='dashed', linewidth=1)
plt.title("VABQ Quantization Error (f32 - VABQ)\nDistribution of Similarity Differences", fontsize=14, fontweight='bold')
plt.xlabel("Similarity Difference (Error)", fontsize=12)
plt.ylabel("Frequency", fontsize=12)
plt.grid(axis='y', linestyle='--', alpha=0.7)
mean_err = np.mean(diff)
std_err = np.std(diff)
plt.text(0.05, 0.95, f"Mean Error: {mean_err:.6f}\nStd Dev: {std_err:.6f}\n(Extremely small error margin)",
         transform=plt.gca().transAxes, fontsize=11, verticalalignment='top', bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
plt.tight_layout()
plt.savefig(f"{out_dir}/vabq_error_distribution.png", dpi=150)
plt.close()

print("Plots generated successfully.")
