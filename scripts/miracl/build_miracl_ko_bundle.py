#!/usr/bin/env python3
"""Build reduced MIRACL Korean bundles for the search evaluation harness.

MIRACL (https://github.com/project-miracl/miracl, Apache-2.0; passage text is
Korean Wikipedia, CC BY-SA). Queries were written by native speakers and
judged by humans. This script only reads the original files; it never runs a
remote loader.

Inputs (download into an empty directory outside the repo):
  topics.miracl-v1.0-ko-dev.tsv, qrels.miracl-v1.0-ko-dev.tsv
    from huggingface.co/datasets/miracl/miracl  (miracl-v1.0-ko/{topics,qrels}/)
  docs-0.jsonl.gz docs-1.jsonl.gz docs-2.jsonl.gz
    from huggingface.co/datasets/miracl/miracl-corpus  (miracl-corpus-v1.0-ko/)

Corpus for each size, nested (the small corpus is a subset of the large one):
  a + b  every judged passage of the 213 dev queries (positives and the
         passages humans judged non-relevant; they act as hard negatives that
         were not mined with any model evaluated here or with the engine BM25)
  c      other passages of articles that hold a positive (seeded shuffle)
  d      random passages from the rest of the corpus (seeded shuffle)
  c and d fill the remainder half and half.
Each passage becomes one source file "<title>\\n\\n<text>" (title included,
no metadata header). Identical texts are kept once (the engine dedupes by
content hash); judged passages win.

Queries: all 213 dev queries, none dropped (rule fixed before any run: drop a
query only if none of its positive passages is in the corpus; that removed 0).
The 213 are split in two with a fixed seed: "tune" (for choosing values in F2)
and "check" (held out).

Writes (git-ignored: the text is CC BY-SA and is not committed):
  example/assets/corpus/miracl_ko/<id>.md
  example/assets/evalsets/miracl_ko/miracl_ko_<size>_{sources_manifest.json,evalset.jsonl,gold.jsonl}
  example/assets/evalsets/miracl_ko/miracl_ko_qrels.json, miracl_ko_overlap.json
Writes (tracked): scripts/miracl/miracl_ko_ids_v1.json (query split, passage
ids per size, seed, input sha256, dataset revisions).

Usage: python3 -I scripts/miracl/build_miracl_ko_bundle.py --data DIR [--sizes 5000,15000]
"""

from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import json
import os
import random
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "example"
CORPUS_DIR = EXAMPLE / "assets" / "corpus" / "miracl_ko"
OUT_DIR = EXAMPLE / "assets" / "evalsets" / "miracl_ko"
IDS_FILE = ROOT / "scripts" / "miracl" / "miracl_ko_ids_v1.json"
SEED = 20261114
REVISIONS = {
    "miracl/miracl": "5be20db9509754dadad47689368639fcec739c00",
    "miracl/miracl-corpus": "d921ec7e349ce0d28daf30b2da9da5ee698bef0d",
}


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def key(docid: str) -> str:
    return "miracl_ko_" + docid.replace("#", "_")


def content(p: dict) -> str:
    return f"{p['title']}\n\n{p['text']}"


def tokens(rows: dict[str, str]) -> dict[str, list[str]]:
    """Engine tokenizer via the test-only dump (rust_builder/rust/src/api/eval_dump.rs)."""
    with tempfile.TemporaryDirectory() as td:
        src, dst = Path(td) / "in.jsonl", Path(td) / "out.jsonl"
        src.write_text("".join(json.dumps({"id": k, "text": v}, ensure_ascii=False) + "\n" for k, v in rows.items()), encoding="utf-8")
        env = dict(os.environ, F1_DUMP_IN=str(src), F1_DUMP_OUT=str(dst))
        subprocess.run(["cargo", "test", "--lib", "eval_dump::dump_bm25_tokens", "--", "--ignored", "--test-threads=1"],
                       cwd=ROOT / "rust_builder" / "rust", env=env, check=True, capture_output=True)
        return {r["id"]: r["tokens"] for r in map(json.loads, dst.read_text(encoding="utf-8").splitlines()) if r}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--sizes", default="5000,15000")
    a = ap.parse_args()
    data = Path(a.data)
    sizes = sorted(int(s) for s in a.sizes.split(","))

    topics = {}
    for line in (data / "topics.miracl-v1.0-ko-dev.tsv").read_text(encoding="utf-8").splitlines():
        if line.strip():
            qid, q = line.split("\t", 1)
            topics[qid] = q.strip()
    qrels = collections.defaultdict(dict)
    for line in (data / "qrels.miracl-v1.0-ko-dev.tsv").read_text(encoding="utf-8").splitlines():
        if line.strip():
            qid, _, docid, rel = line.split()
            qrels[qid][docid] = int(rel)
    judged = {d for r in qrels.values() for d in r}
    pos_articles = {d.split("#")[0] for r in qrels.values() for d, v in r.items() if v > 0}

    passages, same_article, rest = {}, [], []
    for i in range(3):
        with gzip.open(data / f"docs-{i}.jsonl.gz", "rt", encoding="utf-8") as f:
            for line in f:
                o = json.loads(line)
                did = o["docid"]
                if did in judged:
                    passages[did] = o
                elif did.split("#")[0] in pos_articles:
                    same_article.append(o)
                else:
                    rest.append(did)
    missing = judged - set(passages)
    qids = sorted(topics, key=int)
    dropped = [q for q in qids if not any(d in passages for d, v in qrels[q].items() if v > 0)]
    qids = [q for q in qids if q not in dropped]

    rng = random.Random(SEED)
    rng.shuffle(same_article)
    rest.sort()
    rng.shuffle(rest)
    fill = sizes[-1] - len(judged)
    n_c = min(len(same_article), fill // 2)
    rand_ids = set(rest[: fill - n_c + 200])  # a little spare for dedupe
    rand = []
    for i in range(3):
        with gzip.open(data / f"docs-{i}.jsonl.gz", "rt", encoding="utf-8") as f:
            for line in f:
                o = json.loads(line)
                if o["docid"] in rand_ids:
                    rand.append(o)
    order = {d: i for i, d in enumerate(rest)}
    rand.sort(key=lambda o: order[o["docid"]])

    seen, dup = set(), []

    def take(items):
        out = []
        for o in items:
            h = content(o)
            if h in seen:
                dup.append(o["docid"])
                continue
            seen.add(h)
            out.append(o)
        return out

    judged_list = take(sorted(passages.values(), key=lambda o: (int(o["docid"].split("#")[0]), int(o["docid"].split("#")[1]))))
    c_list = take(same_article)
    d_list = take(rand)
    per_size = {}
    for n in sizes:
        room = n - len(judged_list)
        kc = min(len(c_list), room // 2)
        per_size[n] = judged_list + c_list[:kc] + d_list[: room - kc]

    CORPUS_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for o in per_size[sizes[-1]]:
        (CORPUS_DIR / f"{key(o['docid'])}.md").write_text(content(o), encoding="utf-8")

    split_rng = random.Random(SEED)
    shuffled = qids[:]
    split_rng.shuffle(shuffled)
    tune = set(shuffled[: len(shuffled) // 2])

    # Overlap: query tokens that also appear in the indexed text of the
    # positive passage; the highest over a query's positives.
    pos = {q: [d for d, v in qrels[q].items() if v > 0 and d in passages] for q in qids}
    tok = tokens({**{f"q:{q}": topics[q] for q in qids}, **{f"p:{d}": content(passages[d]) for q in qids for d in pos[q]}})
    overlap = {}
    for q in qids:
        qt = set(tok[f"q:{q}"])
        best = max(((len(qt & set(tok[f"p:{d}"])) / len(qt) if qt else 0.0, d) for d in pos[q]), key=lambda t: t[0])
        cls = "none" if best[0] == 0 else ("partial" if best[0] < 0.5 else "high")
        overlap[q] = {"overlap": round(best[0], 3), "best_positive": best[1], "class": cls,
                      "shared": sorted(qt & set(tok[f"p:{best[1]}"])), "query_tokens": len(qt)}

    for n, items in per_size.items():
        keys = {key(o["docid"]) for o in items}
        manifest = {"dataset_id": f"miracl_ko_{n}", "schema_version": 1, "sources": [
            {"source_key": key(o["docid"]), "file_path": f"assets/corpus/miracl_ko/{key(o['docid'])}.md",
             "language": "ko", "domain": "wikipedia", "format": "md", "char_length": len(content(o)),
             "origin": "miracl_ko_dev_v1.0", "docid": o["docid"]} for o in items]}
        (OUT_DIR / f"miracl_ko_{n}_sources_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        ev, gold = [], []
        for q in qids:
            first = pos[q][0]
            tags = ["miracl_ko", f"split:{'tune' if q in tune else 'check'}", f"class:{overlap[q]['class']}", "ko"]
            base = {"dataset_id": f"miracl_ko_{n}", "schema_version": 1, "item_id": f"miracl-ko-{q}", "query": topics[q],
                    "language": "ko", "query_type": overlap[q]["class"], "author": "miracl", "tags": tags}
            ev.append(base | {"expected_source_key": key(first), "hard_negative_source_keys": [],
                              "positive_source_keys": [key(d) for d in pos[q] if key(d) in keys]})
            text = passages[first]["text"]
            gold.append(base | {"gold_source_key": key(first), "gold_chunk_id": f"{key(first)}#miracl", "gold_passage": text,
                                "gold_span_start": 0, "gold_span_end": len(text), "hard_negative_passages": []})
        (OUT_DIR / f"miracl_ko_{n}_evalset.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in ev), encoding="utf-8")
        (OUT_DIR / f"miracl_ko_{n}_gold.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in gold), encoding="utf-8")
    (OUT_DIR / "miracl_ko_qrels.json").write_text(json.dumps(
        {f"miracl-ko-{q}": {key(d): v for d, v in qrels[q].items()} for q in qids}, indent=1) + "\n", encoding="utf-8")
    (OUT_DIR / "miracl_ko_overlap.json").write_text(json.dumps(
        {f"miracl-ko-{q}": v | {"best_positive": key(v["best_positive"])} for q, v in overlap.items()}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    ids = {
        "schema": "miracl_ko_ids_v1",
        "seed": SEED,
        "dataset_revisions": REVISIONS,
        "input_sha256": {p.name: sha256(p) for p in sorted(data.iterdir()) if p.is_file()},
        "title_in_content": True,
        "query_drop_rule": "drop a query only if none of its positive passages is in the corpus",
        "dropped_queries": dropped,
        "judged_passages_missing_from_corpus": sorted(missing),
        "duplicate_texts_skipped": dup,
        "queries": {"tune": sorted((q for q in qids if q in tune), key=int), "check": sorted((q for q in qids if q not in tune), key=int)},
        "corpus": {str(n): {"judged": len(judged_list),
                            "same_article": min(len(c_list), (n - len(judged_list)) // 2),
                            "random": len(items) - len(judged_list) - min(len(c_list), (n - len(judged_list)) // 2),
                            "docids": [o["docid"] for o in items]} for n, items in per_size.items()},
    }
    IDS_FILE.write_text(json.dumps(ids, indent=1) + "\n", encoding="utf-8")
    cls = collections.Counter(v["class"] for v in overlap.values())
    print(f"queries {len(qids)} (dropped {len(dropped)}), tune {len(ids['queries']['tune'])}, check {len(ids['queries']['check'])}")
    print(f"judged {len(judged_list)}, duplicates skipped {len(dup)}, missing {len(missing)}")
    for n, c in ids["corpus"].items():
        print(f"size {n}: judged {c['judged']} same_article {c['same_article']} random {c['random']}")
    print("overlap classes", dict(cls))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
