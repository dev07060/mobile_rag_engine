import matplotlib.pyplot as plt

def render_chart(dimensions, latencies_ns, title, filename, color):
    # Convert ns to microseconds
    latencies_us = [l / 1000.0 for l in latencies_ns]

    fig, ax = plt.subplots(figsize=(8, 6), dpi=150)
    ax.plot(dimensions, latencies_us, marker='o', linestyle='-', color=color, linewidth=2, markersize=8, label='VABQ (i8)')

    for i, txt in enumerate(latencies_us):
        ax.annotate(f"{txt:.1f} µs", (dimensions[i], latencies_us[i]), textcoords="offset points", xytext=(0,10), ha='center', fontsize=11, fontweight='bold', color=color)

    ax.set_title(title, fontsize=14, fontweight='bold', pad=20)
    ax.set_xlabel('Embedding Dimension', fontsize=12)
    ax.set_ylabel('Latency per Query (Microseconds)', fontsize=12)
    ax.set_xticks(dimensions)
    ax.set_ylim(0, max(latencies_us) * 1.5)
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.legend(loc='upper left', frameon=False)

    plt.tight_layout()
    plt.savefig(f'/Users/dev_bh/Desktop/toys/pub_package/mobile_rag_engine/{filename}', transparent=False, facecolor='white')
    print(f"Saved {filename}")

if __name__ == '__main__':
    dimensions = [384, 768, 1024]

    # 1. iPad 10 (A14 Bionic)
    ipad_ns = [3939, 7952, 10667]
    render_chart(dimensions, ipad_ns,
                 'On-Device Vector Search Latency\n(Apple A14 Bionic - iPad 10th Gen)',
                 'latency_benchmark_ipad10.png',
                 '#007acc')

    # 2. M3 Pro (macOS)
    m3pro_ns = [500, 1000, 1500]
    render_chart(dimensions, m3pro_ns,
                 'Native Vector Search Latency\n(Apple M3 Pro - macOS)',
                 'latency_benchmark_m3_pro.png',
                 '#e63946')
