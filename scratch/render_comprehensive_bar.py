import matplotlib.pyplot as plt

methods = ['Python Numpy (F32)\nMacBook', 'Rust Native (F32)\nM3 Pro', 'VABQ (i8)\nM3 Pro', 'VABQ (i8)\niPad 10th Gen']
# Latencies in ms for scanning 2000 vectors of 768 dimensions
lats = [40.0, 10.0, 2.0, 15.9]
colors = ['#555555', '#888888', '#e63946', '#007acc']

plt.figure(figsize=(10, 6), dpi=150)
bars = plt.bar(methods, lats, color=colors, width=0.5)

plt.ylabel('Scan Latency for 2000 vectors (ms)', fontsize=12)
plt.title('Vector Search Scan Latency (768 Dimensions)', fontsize=14, fontweight='bold', pad=20)
plt.grid(axis='y', linestyle='--', alpha=0.7)

for bar in bars:
    yval = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2, yval + 0.5, f"{yval:.1f} ms", ha='center', va='bottom', fontweight='bold', fontsize=11)

plt.gca().spines['top'].set_visible(False)
plt.gca().spines['right'].set_visible(False)

plt.tight_layout()
save_path = '/Users/dev_bh/Desktop/toys/pub_package/mobile_rag_engine/vabq_latency_bar_updated.png'
plt.savefig(save_path, transparent=False, facecolor='white')
print(f"Saved {save_path}")
