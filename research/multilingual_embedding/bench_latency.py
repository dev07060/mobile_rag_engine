"""Load time, single-text embed latency and peak RSS per candidate model.

Desktop proxy only (Apple Silicon CPU, ONNX Runtime CPU EP). Each model runs
in its own subprocess so peak RSS is attributable to that model alone.
Batch size is 1 and there is no padding, matching the on-device path.

Usage:
  python -I bench_latency.py --models DIR --out latency.json [--threads 1]
"""

import argparse
import json
import os
import resource
import statistics
import subprocess
import sys
import time

MODELS = [
    ("minilm-l6 int8(shipped)", "minilm", "model_qint8_arm64.onnx"),
    ("koen-e5-tiny int8(shipped)", "koen-tiny", "model_qint8_arm64.onnx"),
    ("e5-small int8(ours)", "e5-small", "model_ours_qint8_arm64.onnx"),
    ("e5-small-ko-v2 int8(ours)", "e5-ko-v2", "model_ours_qint8_arm64.onnx"),
]

QUERY = "query: 개인정보 보호법에서 정한 민감정보의 처리 제한 조건은 무엇인가요?"
CHUNK = "passage: " + (
    "온디바이스 검색 엔진은 사용자의 문서를 기기 밖으로 보내지 않고 색인한다. "
    "문서는 의미 단위로 나뉘고 각 조각은 임베딩 벡터로 변환되어 저장된다. "
) * 12


def child(model_dir, onnx_file, threads):
    import numpy as np
    import onnxruntime as ort
    from tokenizers import Tokenizer

    def rss_mb():
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        return rss / 2**20 if sys.platform == "darwin" else rss / 1024

    rss_start = rss_mb()
    t0 = time.perf_counter()
    tok = Tokenizer.from_file(os.path.join(model_dir, "tokenizer.json"))
    # The engine disables padding (init_tokenizer); some tokenizer.json files
    # (all-MiniLM-L6-v2) ship a fixed 128-token padding that would skew timing.
    tok.no_padding()
    rss_tokenizer = rss_mb()
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = threads
    sess = ort.InferenceSession(
        os.path.join(model_dir, "onnx", onnx_file), opts, providers=["CPUExecutionProvider"]
    )
    load_ms = (time.perf_counter() - t0) * 1000

    def run(text, max_len):
        tok.enable_truncation(max_len)
        ids = np.array([tok.encode(text).ids], np.int64)
        feeds = {
            "input_ids": ids,
            "attention_mask": np.ones_like(ids),
            "token_type_ids": np.zeros_like(ids),
        }
        t = time.perf_counter()
        sess.run(None, feeds)
        return (time.perf_counter() - t) * 1000, ids.shape[1]

    rss_session = rss_mb()
    out = {
        "load_ms": round(load_ms, 1),
        "tokenizer_rss_mb": round(rss_tokenizer - rss_start, 1),
        "session_rss_mb": round(rss_session - rss_tokenizer, 1),
    }
    for name, text in [("query", QUERY), ("chunk", CHUNK)]:
        for _ in range(5):
            run(text, 256)
        samples = [run(text, 256) for _ in range(50)]
        out[f"{name}_tokens"] = samples[0][1]
        out[f"{name}_p50_ms"] = round(statistics.median(s[0] for s in samples), 2)
    out["inference_rss_mb"] = round(rss_mb() - rss_session, 1)
    out["onnx_mb"] = round(os.path.getsize(os.path.join(model_dir, "onnx", onnx_file)) / 2**20, 1)
    out["tokenizer_mb"] = round(os.path.getsize(os.path.join(model_dir, "tokenizer.json")) / 2**20, 1)
    print(json.dumps(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models")
    ap.add_argument("--out")
    ap.add_argument("--threads", type=int, default=1)
    ap.add_argument("--child", nargs=2)
    args = ap.parse_args()
    if args.child:
        child(args.child[0], args.child[1], args.threads)
        return
    results = []
    for label, mdir, onnx_file in MODELS:
        proc = subprocess.run(
            [sys.executable, "-I", __file__, "--threads", str(args.threads),
             "--child", os.path.join(args.models, mdir), onnx_file],
            capture_output=True, text=True, check=True,
        )
        res = {"model": label, "threads": args.threads, **json.loads(proc.stdout.strip().splitlines()[-1])}
        print(json.dumps(res, ensure_ascii=False), flush=True)
        results.append(res)
    with open(args.out, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
