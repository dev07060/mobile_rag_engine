import matplotlib.pyplot as plt
import numpy as np

dimensions = [384, 768, 1024]
# Measured on iPad 10
vabq_latency = [3939, 7952, 10667]
vabq_us = [l / 1000.0 for l in vabq_latency]

fig, ax = plt.subplots(figsize=(8, 6), dpi=150)
ax.plot(dimensions, vabq_us, marker='o', linestyle='-', color='#007acc', linewidth=2, markersize=8, label='VABQ (i8)')

for i, txt in enumerate(vabq_us):
    ax.annotate(f"{txt:.1f} µs", (dimensions[i], vabq_us[i]), textcoords="offset points", xytext=(0,10), ha='center', fontsize=11, fontweight='bold', color='#007acc')

ax.set_title('On-Device Vector Search Latency\n(Apple A14 Bionic - iPad 10th Gen)', fontsize=14, fontweight='bold', pad=20)
ax.set_xlabel('Embedding Dimension', fontsize=12)
ax.set_ylabel('Latency per Query (Microseconds)', fontsize=12)
ax.set_xticks(dimensions)
ax.set_ylim(0, max(vabq_us) * 1.5)
ax.grid(axis='y', linestyle='--', alpha=0.7)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.legend(loc='upper left', frameon=False)

plt.tight_layout()
plt.savefig('/Users/dev_bh/Desktop/toys/pub_package/mobile_rag_engine/latency_benchmark_a14.png', transparent=False, facecolor='white')
print("Saved latency_benchmark_a14.png")
