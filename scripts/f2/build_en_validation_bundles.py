#!/usr/bin/env python3
"""English validation bundles from BEIR NFCorpus and SciFact (F2).

F2 found that the default hybrid weights (RRF vector 0.2 / BM25 0.8, 20
candidates per list in `ask`) let almost no vector-only result into the top 5
when the BM25 list is full. This builds English bundles to check whether the
same loss shows up in English and which weight suits each model there.

Data (BEIR copies, https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/):
  NFCorpus (Boteva et al. 2016): nutrition/medical questions from NutritionFacts.org
    with PubMed documents, graded relevance (1, 2). Free for academic use
    (Heidelberg StatNLP page). Test split: 323 queries, 3,633 documents.
  SciFact (Wadden et al. 2020): scientific claims against paper abstracts. CC BY-NC 2.0
    (original repository). Test split: 300 claims, 5,183 abstracts.
Neither is in the published fine-tuning lists of all-MiniLM-L6-v2,
multilingual-e5 or BGE-m3. SciFact claims were written from citation sentences
and MiniLM was trained on S2ORC citation pairs, so MiniLM may have seen related
pairs (see docs/perf/f2-fusion/validation_en.md).

Corpus: the whole corpus (title + text), no distractors.
Queries: every test query with at least one qrel score > 0, split in two halves
(tune / check) with a fixed seed. Positives = every qrel with score > 0.
Gold passage (for the harness's own chunk metric) = the first sentence of the
first positive; F2 scores by positive source. `class:` = share of query tokens
(engine BM25 tokenizer) found in the positive with the largest share.

Writes (git-ignored, text is not committed):
  example/assets/corpus/en_validation/<set>/<key>.md
  example/assets/evalsets/en_validation/enval_<set>_{sources_manifest.json,evalset.jsonl,gold.jsonl}
Writes (tracked): scripts/f2/en_validation_ids_v1.json

Usage: python3 -I scripts/f2/build_en_validation_bundles.py --beir-dir DIR [--sets nfcorpus,scifact]
  DIR holds the unzipped nfcorpus/ and scifact/ folders.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "miracl"))
from build_miracl_ko_bundle import tokens  # noqa: E402  (engine BM25 tokens via eval_dump)

EXAMPLE = ROOT / "example"
CORPUS_ROOT = EXAMPLE / "assets" / "corpus" / "en_validation"
OUT_DIR = EXAMPLE / "assets" / "evalsets" / "en_validation"
IDS_FILE = ROOT / "scripts" / "f2" / "en_validation_ids_v1.json"
SEED = 20261114
INFO = {
    "nfcorpus": {"domain": "medical", "author": "nfcorpus", "origin": "beir_nfcorpus_test"},
    "scifact": {"domain": "science", "author": "scifact", "origin": "beir_scifact_test"},
}


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def first_sentence(text: str) -> str:
    m = re.search(r"[.?!](\s|$)", text)
    s = text[: m.end()] if m else text
    return s.strip()[:400] or text[:200]


def classify(qt: set, pts: list) -> tuple[float, str]:
    r = max((len(qt & pt) / len(qt) for pt in pts), default=0.0) if qt else 0.0
    return r, ("none" if r == 0 else ("partial" if r < 0.5 else "high"))


def key_for(name: str, doc_id: str) -> str:
    return f"{name}_" + re.sub(r"[^A-Za-z0-9]+", "_", doc_id)


def build(name: str, d: Path, ids: dict) -> None:
    files = {"corpus.jsonl": d / "corpus.jsonl", "queries.jsonl": d / "queries.jsonl", "qrels/test.tsv": d / "qrels" / "test.tsv"}
    corpus = [json.loads(l) for l in files["corpus.jsonl"].read_text(encoding="utf-8").splitlines() if l.strip()]
    queries = {o["_id"]: o["text"].strip() for o in map(json.loads, files["queries.jsonl"].read_text(encoding="utf-8").splitlines()) if o}
    qrels = collections.defaultdict(dict)
    for line in files["qrels/test.tsv"].read_text(encoding="utf-8").splitlines()[1:]:
        if line.strip():
            qid, did, score = line.split("\t")
            qrels[qid][did] = int(score)

    key_of, text_of = {}, {}
    for o in corpus:
        k = key_for(name, o["_id"])
        assert k not in text_of, f"duplicate key {k}"
        title = (o.get("title") or "").strip()
        body = (o.get("text") or "").strip()
        key_of[o["_id"]] = k
        text_of[k] = f"{title}\n\n{body}" if title else body

    items = []
    for qid in sorted(qrels):
        pos = sorted((did for did, s in qrels[qid].items() if s > 0 and did in key_of), key=lambda x: (-qrels[qid][x], x))
        if not pos or qid not in queries:
            continue
        items.append({"id": qid, "question": queries[qid], "keys": [key_of[p] for p in pos]})
    order = [q["id"] for q in items]
    random.Random(SEED).shuffle(order)
    tune = set(order[: len(order) // 2])

    pos_keys = {k for q in items for k in q["keys"]}
    tok = tokens({**{f"q:{q['id']}": q["question"] for q in items}, **{f"p:{k}": text_of[k] for k in pos_keys}})

    corpus_dir = CORPUS_ROOT / name
    corpus_dir.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for k, t in text_of.items():
        (corpus_dir / f"{k}.md").write_text(t, encoding="utf-8")
    bundle = f"enval_{name}"
    info = INFO[name]
    manifest = {"dataset_id": bundle, "schema_version": 1, "sources": [
        {"source_key": k, "file_path": f"assets/corpus/en_validation/{name}/{k}.md", "language": "en", "domain": info["domain"],
         "format": "md", "char_length": len(t), "origin": info["origin"]} for k, t in sorted(text_of.items())]}
    (OUT_DIR / f"{bundle}_sources_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    ev, gold, classes = [], [], collections.Counter()
    for q in items:
        r, cls = classify(set(tok[f"q:{q['id']}"]), [set(tok[f"p:{k}"]) for k in q["keys"]])
        classes[cls] += 1
        tags = ["enval", name, f"split:{'tune' if q['id'] in tune else 'check'}", f"class:{cls}", "en"]
        base = {"dataset_id": bundle, "schema_version": 1, "item_id": f"{name}-{q['id']}", "query": q["question"],
                "language": "en", "query_type": cls, "author": info["author"], "tags": tags}
        g = first_sentence(text_of[q["keys"][0]].split("\n\n", 1)[-1])
        ev.append(base | {"expected_source_key": q["keys"][0], "hard_negative_source_keys": [], "positive_source_keys": q["keys"],
                          "overlap": round(r, 3)})
        gold.append(base | {"gold_source_key": q["keys"][0], "gold_chunk_id": f"{q['keys'][0]}#enval", "gold_passage": g,
                            "gold_span_start": 0, "gold_span_end": len(g), "hard_negative_passages": []})
    (OUT_DIR / f"{bundle}_evalset.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in ev), encoding="utf-8")
    (OUT_DIR / f"{bundle}_gold.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in gold), encoding="utf-8")

    npos = [len(q["keys"]) for q in items]
    ids[name] = {
        "seed": SEED,
        "input_sha256": {f: sha256(p) for f, p in files.items()},
        "documents": len(text_of),
        "positive_rule": "qrels/test.tsv score > 0",
        "positives_per_query": {"min": min(npos), "median": sorted(npos)[len(npos) // 2], "max": max(npos),
                                "mean": round(sum(npos) / len(npos), 2)},
        "queries": {"tune": sorted(tune), "check": sorted(set(order) - tune)},
        "overlap_classes": dict(classes),
    }
    print(f"{name}: documents {len(text_of)}, queries {len(items)} (tune {len(tune)}), positives/query {ids[name]['positives_per_query']}, classes {dict(classes)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--beir-dir", required=True)
    ap.add_argument("--sets", default="nfcorpus,scifact")
    a = ap.parse_args()
    ids = json.loads(IDS_FILE.read_text(encoding="utf-8")) if IDS_FILE.is_file() else {"schema": "en_validation_ids_v1"}
    ids["archives"] = {"source": "https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/",
                       "nfcorpus.zip": {"bytes": 2448432, "md5": "a89dba18a62ef92f7d323ec890a0d38d"},
                       "scifact.zip": {"bytes": 2816079, "md5": "5f7d1de60b170fc8027bb7898e2efca1"}}
    for name in a.sets.split(","):
        build(name, Path(a.beir_dir) / name, ids)
    IDS_FILE.write_text(json.dumps(ids, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
