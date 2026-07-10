import numpy as np
import matplotlib.pyplot as plt
import os

out_dir = "/Users/dev_bh/.gemini/antigravity/brain/7377f9b4-d0da-4217-9f2f-2f80f5b1d62f"
os.makedirs(out_dir, exist_ok=True)
np.random.seed(42)

def simulate_q8(v):
    # Vector-wise symmetric quantization (Standard Q8)
    q_v = np.zeros_like(v)
    max_abs = np.max(np.abs(v), axis=1, keepdims=True)
    max_abs[max_abs == 0] = 1e-9
    scale = 127.0 / max_abs
    q_v = np.round(v * scale) / scale
    return q_v

def simulate_vabq(v, block_size=32):
    # Block-wise quantization (VABQ)
    q_v = np.zeros_like(v)
    for i in range(0, v.shape[1], block_size):
        block = v[:, i:i+block_size]
        max_abs = np.max(np.abs(block), axis=1, keepdims=True)
        max_abs[max_abs == 0] = 1e-9
        scale = 127.0 / max_abs
        q_v[:, i:i+block_size] = np.round(block * scale) / scale
    return q_v

def generate_comparison(dim):
    N = 4000
    vecs = np.random.randn(N, dim)
    vecs = vecs / np.linalg.norm(vecs, axis=1, keepdims=True)

    sample_A = vecs[:2000]
    sample_B = vecs[2000:4000]

    cos_base = np.dot(sample_A, sample_B.T).flatten()

    q8_B = simulate_q8(sample_B)
    cos_q8 = np.dot(sample_A, q8_B.T).flatten()
    diff_q8 = cos_base - cos_q8

    vabq_B = simulate_vabq(sample_B, block_size=32)
    cos_vabq = np.dot(sample_A, vabq_B.T).flatten()
    diff_vabq = cos_base - cos_vabq

    return diff_q8, diff_vabq

print("Calculating for 768d...")
diff_q8_768, diff_vabq_768 = generate_comparison(768)
print("Calculating for 1024d...")
diff_q8_1024, diff_vabq_1024 = generate_comparison(1024)

fig, axes = plt.subplots(1, 2, figsize=(16, 6))

def plot_hist(ax, diff_q8, diff_vabq, dim):
    # Use identical bins for a fair visual comparison
    bins = np.linspace(-0.015, 0.015, 100)
    ax.hist(diff_q8, bins=bins, color='#6C7A89', alpha=0.6, label='Standard Q8 Error', edgecolor='none')
    ax.hist(diff_vabq, bins=bins, color='#FF7F0E', alpha=0.8, label='VABQ Error', edgecolor='none')

    ax.set_title(f"{dim} Dimensions\nQ8 vs VABQ Quantization Error", fontsize=14, fontweight='bold')
    ax.set_xlabel("Error (f32 similarity - Quantized similarity)", fontsize=12)
    ax.set_ylabel("Frequency", fontsize=12)
    ax.axvline(0, color='black', linestyle='--', linewidth=1)
    ax.grid(axis='y', linestyle=':', alpha=0.7)
    ax.legend(fontsize=11)

    std_q8 = np.std(diff_q8)
    std_vabq = np.std(diff_vabq)
    var_reduction = (1.0 - (std_vabq**2) / (std_q8**2)) * 100

    textstr = f"Q8 Std Dev:   {std_q8:.6f}\nVABQ Std Dev: {std_vabq:.6f}\n\nVariance Reduction: {var_reduction:.1f}%"
    ax.text(0.05, 0.95, textstr, transform=ax.transAxes, fontsize=11,
            verticalalignment='top', bbox=dict(boxstyle='round,pad=0.5', facecolor='#F9F9F9', alpha=0.9, edgecolor='#CCCCCC'))

plot_hist(axes[0], diff_q8_768, diff_vabq_768, 768)
plot_hist(axes[1], diff_q8_1024, diff_vabq_1024, 1024)

plt.tight_layout()
plt.savefig(f"{out_dir}/q8_vs_vabq_comparison.png", dpi=150)
print("Plot saved.")
