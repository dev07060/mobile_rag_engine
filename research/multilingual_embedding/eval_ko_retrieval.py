"""Korean retrieval quality for candidate embedding presets.

Mirrors the on-device embedding path of mobile_rag_engine as closely as a
desktop harness can:

- tokenizer.json through HF `tokenizers` (same crate family the Rust side
  uses), special tokens on, truncation tiers 256/384/512 picked by character
  count exactly like `resolve_truncation_max_length` in
  rust_builder/rust/src/api/tokenizer.rs;
- ONNX Runtime CPU, inputs input_ids / attention_mask / token_type_ids(0);
- attention-masked mean pooling over `last_hidden_state`
  (lib/services/embedding_service.dart);
- exact cosine top-k (no HNSW / no Q8_0 vector storage — those are measured
  separately in docs/perf/vector-math-refactor).

Metrics follow MTEB retrieval: nDCG@10 and Recall@10 over graded qrels,
documents rendered as "{title} {text}".strip().

Usage:
  python -I eval_ko_retrieval.py --data DIR --models DIR --out results.json
"""

import argparse
import json
import math
import os
import time

import numpy as np
import onnxruntime as ort
import pyarrow.parquet as pq
from tokenizers import Tokenizer

DATASETS = {
    "Ko-StrategyQA": "dev",
    "AutoRAGRetrieval": "test",
}

# (label, model dir, onnx file, query prefix, document prefix)
CONFIGS = [
    ("minilm-l6 int8(shipped)", "minilm", "model_qint8_arm64.onnx", "", ""),
    ("koen-e5-tiny fp32", "koen-tiny", "model.onnx", "query: ", "passage: "),
    ("koen-e5-tiny int8(shipped)", "koen-tiny", "model_qint8_arm64.onnx", "query: ", "passage: "),
    ("koen-e5-tiny int8(ours)", "koen-tiny", "model_ours_qint8_arm64.onnx", "query: ", "passage: "),
    ("koen-e5-tiny int8(shipped) no-prefix", "koen-tiny", "model_qint8_arm64.onnx", "", ""),
    ("e5-small fp32", "e5-small", "model.onnx", "query: ", "passage: "),
    ("e5-small int8(ours)", "e5-small", "model_ours_qint8_arm64.onnx", "query: ", "passage: "),
    ("e5-small int8(ours) no-prefix", "e5-small", "model_ours_qint8_arm64.onnx", "", ""),
    ("e5-small-ko-v2 fp32", "e5-ko-v2", "model.onnx", "query: ", "passage: "),
    ("e5-small-ko-v2 int8(ours)", "e5-ko-v2", "model_ours_qint8_arm64.onnx", "query: ", "passage: "),
    ("e5-small-ko-v2 int8(ours) no-prefix", "e5-ko-v2", "model_ours_qint8_arm64.onnx", "", ""),
]


FIXED_MAX_LENGTH = None


def truncation_max_length(text):
    if FIXED_MAX_LENGTH:
        return FIXED_MAX_LENGTH
    n = len(text)
    if n >= 2400:
        return 512
    if n >= 1200:
        return 384
    return 256


class Embedder:
    def __init__(self, model_dir, onnx_file, threads):
        self.tok = Tokenizer.from_file(os.path.join(model_dir, "tokenizer.json"))
        self.tok.no_padding()
        self.tok.no_truncation()
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        self.sess = ort.InferenceSession(
            os.path.join(model_dir, "onnx", onnx_file),
            opts,
            providers=["CPUExecutionProvider"],
        )
        self.input_names = {i.name for i in self.sess.get_inputs()}

    def token_ids(self, text):
        self.tok.enable_truncation(truncation_max_length(text))
        return self.tok.encode(text, add_special_tokens=True).ids

    def embed_ids(self, batch):
        width = max(len(ids) for ids in batch)
        input_ids = np.zeros((len(batch), width), np.int64)
        mask = np.zeros((len(batch), width), np.int64)
        for row, ids in enumerate(batch):
            input_ids[row, : len(ids)] = ids
            mask[row, : len(ids)] = 1
        feeds = {"input_ids": input_ids, "attention_mask": mask}
        if "token_type_ids" in self.input_names:
            feeds["token_type_ids"] = np.zeros_like(input_ids)
        hidden = self.sess.run(None, feeds)[0]
        summed = (hidden * mask[:, :, None]).sum(1)
        return summed / mask.sum(1, keepdims=True)

    def embed(self, texts, batch_size=32):
        ids = [self.token_ids(t) for t in texts]
        order = np.argsort([len(i) for i in ids])
        out = np.zeros((len(texts), 0), np.float32)
        chunks = []
        for start in range(0, len(order), batch_size):
            idx = order[start : start + batch_size]
            chunks.append((idx, self.embed_ids([ids[i] for i in idx])))
        out = np.zeros((len(texts), chunks[0][1].shape[1]), np.float32)
        for idx, vecs in chunks:
            out[idx] = vecs
        out /= np.linalg.norm(out, axis=1, keepdims=True) + 1e-12
        return out


def load_dataset(data_dir, name, split):
    def rows(part):
        return pq.read_table(
            os.path.join(data_dir, name, part, f"{split}-00000-of-00001.parquet")
        ).to_pylist()

    corpus = rows("corpus")
    doc_ids = [d["_id"] for d in corpus]
    docs = [f"{d.get('title') or ''} {d['text']}".strip() for d in corpus]
    queries = {q["_id"]: q["text"] for q in rows("queries")}
    qrels = {}
    for r in rows("qrels"):
        if r["score"] > 0:
            qrels.setdefault(r["query-id"], {})[r["corpus-id"]] = r["score"]
    query_ids = [q for q in queries if q in qrels]
    return doc_ids, docs, query_ids, [queries[q] for q in query_ids], qrels


def ndcg_recall_at_k(ranked, rels, k=10):
    dcg = sum(
        (2 ** rels.get(d, 0) - 1) / math.log2(i + 2) for i, d in enumerate(ranked[:k])
    )
    ideal = sorted(rels.values(), reverse=True)[:k]
    idcg = sum((2**g - 1) / math.log2(i + 2) for i, g in enumerate(ideal))
    hits = sum(1 for d in ranked[:k] if d in rels)
    return (dcg / idcg if idcg else 0.0), hits / len(rels)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--only", default="", help="comma-separated substring filters on config label")
    ap.add_argument("--datasets", default=",".join(DATASETS))
    ap.add_argument(
        "--fixed-max-length",
        type=int,
        default=0,
        help="override the engine's char-count truncation tiers (MTEB uses 512)",
    )
    args = ap.parse_args()
    global FIXED_MAX_LENGTH
    FIXED_MAX_LENGTH = args.fixed_max_length or None
    wanted = set(args.datasets.split(","))

    results = []
    for label, mdir, onnx_file, qp, dp in CONFIGS:
        if args.only and not any(o in label for o in args.only.split(",")):
            continue
        emb = Embedder(os.path.join(args.models, mdir), onnx_file, args.threads)
        for ds, split in DATASETS.items():
            if ds not in wanted:
                continue
            doc_ids, docs, query_ids, queries, qrels = load_dataset(args.data, ds, split)
            t0 = time.time()
            dvec = emb.embed([dp + d for d in docs])
            qvec = emb.embed([qp + q for q in queries])
            scores = qvec @ dvec.T
            nd, rc = [], []
            for row, qid in enumerate(query_ids):
                top = np.argsort(-scores[row])[:10]
                n, r = ndcg_recall_at_k([doc_ids[i] for i in top], qrels[qid])
                nd.append(n)
                rc.append(r)
            res = {
                "config": label,
                "max_length": FIXED_MAX_LENGTH or "engine-tiers",
                "dataset": ds,
                "ndcg@10": round(float(np.mean(nd)), 5),
                "recall@10": round(float(np.mean(rc)), 5),
                "queries": len(query_ids),
                "docs": len(docs),
                "seconds": round(time.time() - t0, 1),
            }
            print(json.dumps(res, ensure_ascii=False), flush=True)
            results.append(res)
    with open(args.out, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
