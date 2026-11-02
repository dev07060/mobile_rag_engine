"""Chunk-level variant of eval_ko_retrieval.py.

The engine never embeds a whole document: the semantic chunker splits text so
every chunk fits `resolve_truncation_max_length` (a token budget), and the
markdown chunker splits by characters only (no token budget), so its chunks
can still be truncated at embed time. This harness approximates both:

- `budget`: sentence-packed chunks of at most --max-chars characters that are
  further split until they fit the token budget (semantic chunker);
- `chars-only`: the same packing without the token check, embedded with the
  engine's truncation (markdown chunker).

A document's score is the max over its chunks (MaxP), then nDCG@10 as before.

Usage:
  python -I eval_chunked.py --data DIR --models DIR --model koen-tiny \
      --onnx model_qint8_arm64.onnx --out results.json
"""

import argparse
import json
import re

import numpy as np

from eval_ko_retrieval import DATASETS, Embedder, load_dataset, ndcg_recall_at_k
import eval_ko_retrieval

SENTENCE_END = re.compile(r"(?<=[.!?。])\s+|(?<=다\.)\s*|\n+")


def engine_tiers(text):
    n = len(text)
    return 512 if n >= 2400 else 384 if n >= 1200 else 256


def chunk(text, max_chars, budget_fn, tok_len):
    sentences = [s for s in SENTENCE_END.split(text) if s and s.strip()]
    chunks, buf = [], ""
    for sentence in sentences:
        candidate = f"{buf} {sentence}".strip() if buf else sentence
        if len(candidate) <= max_chars:
            buf = candidate
            continue
        if buf:
            chunks.append(buf)
        buf = sentence
    if buf:
        chunks.append(buf)
    if budget_fn is None:
        return chunks
    out = []
    for c in chunks:
        stack = [c]
        while stack:
            piece = stack.pop(0)
            if tok_len(piece) <= budget_fn(piece) or len(piece) < 20:
                out.append(piece)
            else:
                mid = len(piece) // 2
                stack[:0] = [piece[:mid], piece[mid:]]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--onnx", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-chars", type=int, nargs="+", default=[500, 1000])
    args = ap.parse_args()

    emb = Embedder(f"{args.models}/{args.model}", args.onnx, 8)

    def tok_len(text):
        emb.tok.no_truncation()
        return len(emb.tok.encode("passage: " + text).ids)

    variants = {
        "budget=engine-tiers (current)": (lambda t: engine_tiers(t), None),
        "budget=512": (lambda t: 512, 512),
        "chars-only, embed=engine-tiers (markdown, current)": (None, None),
        "chars-only, embed=512 (markdown)": (None, 512),
    }
    results = []
    for ds, split in DATASETS.items():
        doc_ids, docs, query_ids, queries, qrels = load_dataset(args.data, ds, split)
        eval_ko_retrieval.FIXED_MAX_LENGTH = None
        qvec = emb.embed(["query: " + q for q in queries])
        for max_chars in args.max_chars:
            for name, (budget_fn, embed_max) in variants.items():
                owners, texts = [], []
                for i, d in enumerate(docs):
                    for c in chunk(d, max_chars, budget_fn, tok_len):
                        owners.append(i)
                        texts.append("passage: " + c)
                eval_ko_retrieval.FIXED_MAX_LENGTH = embed_max
                cvec = emb.embed(texts)
                sims = qvec @ cvec.T
                doc_scores = np.full((len(queries), len(docs)), -1.0, np.float32)
                owners = np.array(owners)
                for i in range(len(docs)):
                    cols = np.where(owners == i)[0]
                    if len(cols):
                        doc_scores[:, i] = sims[:, cols].max(1)
                nd, rc = [], []
                for row, qid in enumerate(query_ids):
                    top = np.argsort(-doc_scores[row])[:10]
                    n, r = ndcg_recall_at_k([doc_ids[j] for j in top], qrels[qid])
                    nd.append(n)
                    rc.append(r)
                truncated = sum(
                    1 for t in texts if tok_len(t[len("passage: "):]) > (embed_max or engine_tiers(t))
                )
                res = {
                    "dataset": ds,
                    "max_chars": max_chars,
                    "variant": name,
                    "chunks": len(texts),
                    "truncated_chunks_pct": round(100 * truncated / len(texts), 1),
                    "ndcg@10": round(float(np.mean(nd)), 5),
                    "recall@10": round(float(np.mean(rc)), 5),
                }
                print(json.dumps(res, ensure_ascii=False), flush=True)
                results.append(res)
    with open(args.out, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
