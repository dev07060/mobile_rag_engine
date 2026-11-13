#!/usr/bin/env python3
"""Korean validation bundles from data the measured models were not fine-tuned on (F2).

KoEn-E5-Tiny's base (multilingual-e5-small) and BGE-m3 were fine-tuned on
MIRACL, so F2 re-checks the per-model weight recommendation on Korean data that is in
none of the published fine-tuning lists (multilingual-e5 report Table 2,
M3-Embedding paper section 3.1, the AI Hub reading-comprehension sets named by
dragonkue/snowflake-arctic-embed-l-v2.0-ko). Korean Wikipedia text may still
have been seen in pre-training.

KorQuAD 1.0 dev (https://korquad.github.io, CC BY-ND; questions written by
crowd workers looking at Korean Wikipedia paragraphs). Input: the original
KorQuAD_v1.0_dev.json. Distractors: random passages from the MIRACL Korean
corpus files already used in F1 (Korean Wikipedia, CC BY-SA), skipping every
article whose title is a KorQuAD dev title, so a distractor cannot be an
unjudged answer from the same article.

Corpus: every dev paragraph (identical texts once) + distractors up to --size.
Queries: --queries questions sampled with a fixed seed from all 5,774, split
in two halves (tune / check). Positive = the paragraph the question was written
on. Gold passage (for the harness's own chunk metric) = the sentence that holds
the answer span. Scoring for F2 is by positive source.

AutoRAG retrieval (mteb/AutoRAGRetrieval revision 43b81793..., MIT): 720 chunks
of public Korean PDF reports (finance, public sector, medical, law,
commerce) and 114 questions, one relevant chunk each. Inputs: the three
parquet files (corpus, queries, qrels), read with scripts/f2/mini_parquet.py.
The whole set is used as it is (no distractors); split in two halves.

Writes (git-ignored, text is not committed):
  example/assets/corpus/ko_validation/<key>.md
  example/assets/evalsets/ko_validation/koval_{korquad,autorag}_{sources_manifest.json,evalset.jsonl,gold.jsonl}
Writes (tracked): scripts/f2/ko_validation_ids_v1.json

Usage: python3 -I scripts/f2/build_ko_validation_bundles.py [--korquad FILE --miracl-dir DIR] [--autorag-dir DIR]
"""

from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "miracl"))
from build_miracl_ko_bundle import tokens  # noqa: E402  (engine BM25 tokens via eval_dump)

sys.path.insert(0, str(ROOT / "scripts" / "f2"))
import mini_parquet  # noqa: E402

AUTORAG_REVISION = "43b817937708cb10ba519f86edb4f6885a1631a4"

EXAMPLE = ROOT / "example"
CORPUS_DIR = EXAMPLE / "assets" / "corpus" / "ko_validation"
OUT_DIR = EXAMPLE / "assets" / "evalsets" / "ko_validation"
IDS_FILE = ROOT / "scripts" / "f2" / "ko_validation_ids_v1.json"
SEED = 20261114


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def answer_sentence(context: str, start: int, text: str) -> str:
    """The sentence around the answer span: from the previous sentence end to the next."""
    end = start + len(text)
    left = max((m.end() for m in re.finditer(r"[.?!]\s", context[:start])), default=0)
    m = re.search(r"[.?!](\s|$)", context[end:])
    right = end + m.end() if m else len(context)
    return context[left:right].strip()


def classify(qt: set, pt: set) -> tuple[float, str]:
    r = len(qt & pt) / len(qt) if qt else 0.0
    return r, ("none" if r == 0 else ("partial" if r < 0.5 else "high"))


def write_bundle(name, sources, items, tok, tune):
    """sources: [(key, text, origin)]; items: [{id, item_id, question, key, gold, author, tag}]."""
    CORPUS_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for k, t, _ in sources:
        (CORPUS_DIR / f"{k}.md").write_text(t, encoding="utf-8")
    manifest = {"dataset_id": name, "schema_version": 1, "sources": [
        {"source_key": k, "file_path": f"assets/corpus/ko_validation/{k}.md", "language": "ko", "domain": o,
         "format": "md", "char_length": len(t), "origin": o} for k, t, o in sources]}
    (OUT_DIR / f"{name}_sources_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    ev, gold, classes = [], [], collections.Counter()
    for q in items:
        r, cls = classify(set(tok[f"q:{q['id']}"]), set(tok[f"p:{q['key']}"]))
        classes[cls] += 1
        tags = ["koval", q["tag"], f"split:{'tune' if q['id'] in tune else 'check'}", f"class:{cls}", "ko"]
        base = {"dataset_id": name, "schema_version": 1, "item_id": q["item_id"], "query": q["question"],
                "language": "ko", "query_type": cls, "author": q["author"], "tags": tags}
        ev.append(base | {"expected_source_key": q["key"], "hard_negative_source_keys": [], "positive_source_keys": [q["key"]],
                          "overlap": round(r, 3)})
        gold.append(base | {"gold_source_key": q["key"], "gold_chunk_id": f"{q['key']}#koval", "gold_passage": q["gold"],
                            "gold_span_start": 0, "gold_span_end": len(q["gold"]), "hard_negative_passages": []})
    (OUT_DIR / f"{name}_evalset.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in ev), encoding="utf-8")
    (OUT_DIR / f"{name}_gold.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in gold), encoding="utf-8")
    return dict(classes)


def build_autorag(d: Path, ids: dict) -> None:
    corpus = mini_parquet.read_table(d / "autorag_corpus.parquet")
    queries = mini_parquet.read_table(d / "autorag_queries.parquet")
    qrels = mini_parquet.read_table(d / "autorag_qrels.parquet")
    key_of = {r["_id"]: f"autorag_{i:03d}" for i, r in enumerate(sorted(corpus, key=lambda r: r["_id"]))}
    text_of = {key_of[r["_id"]]: r["text"].strip() for r in corpus}
    rel = {r["query-id"]: r["corpus-id"] for r in qrels}
    items = []
    for q in sorted(queries, key=lambda r: r["_id"]):
        k = key_of[rel[q["_id"]]]
        first = next((l.strip() for l in text_of[k].splitlines() if len(l.strip()) >= 20), text_of[k][:80])
        items.append({"id": q["_id"], "item_id": f"autorag-{q['_id']}", "question": q["text"].strip(), "key": k,
                      "gold": first, "author": "autorag", "tag": "autorag"})
    rng = random.Random(SEED)
    order = [q["id"] for q in items]
    rng.shuffle(order)
    tune = set(order[: len(order) // 2])
    tok = tokens({**{f"q:{q['id']}": q["question"] for q in items}, **{f"p:{k}": t for k, t in text_of.items()}})
    sources = [(k, text_of[k], "autorag") for k in sorted(text_of)]
    classes = write_bundle("koval_autorag", sources, items, tok, tune)
    ids["autorag"] = {
        "dataset_revision": {"mteb/AutoRAGRetrieval": AUTORAG_REVISION},
        "seed": SEED,
        "input_sha256": {f"autorag_{c}.parquet": sha256(d / f"autorag_{c}.parquet") for c in ("corpus", "queries", "qrels")},
        "source_keys": {key_of[r["_id"]]: r["_id"] for r in corpus},
        "queries": {"tune": sorted(tune), "check": sorted(set(order) - tune)},
        "overlap_classes": classes,
    }
    print(f"autorag: sources {len(sources)}, queries {len(items)} (tune {len(tune)}), classes {classes}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--korquad")
    ap.add_argument("--miracl-dir")
    ap.add_argument("--autorag-dir")
    ap.add_argument("--size", type=int, default=5000)
    ap.add_argument("--queries", type=int, default=500)
    a = ap.parse_args()
    ids = json.loads(IDS_FILE.read_text(encoding="utf-8")) if IDS_FILE.is_file() else {"schema": "ko_validation_ids_v1"}
    if a.autorag_dir:
        build_autorag(Path(a.autorag_dir), ids)
    if a.korquad:
        build_korquad(a, ids)
    IDS_FILE.write_text(json.dumps(ids, indent=1) + "\n", encoding="utf-8")
    return 0


def build_korquad(a, ids: dict) -> None:
    kq_path = Path(a.korquad)
    data = json.loads(kq_path.read_text(encoding="utf-8"))["data"]

    paras, key_of_text, titles = [], {}, set()
    questions = []
    for ai, art in enumerate(data):
        titles.add(art["title"].strip())
        for pi, p in enumerate(art["paragraphs"]):
            text = f"{art['title']}\n\n{p['context']}"
            if text not in key_of_text:
                k = f"korquad_{ai:03d}_{pi:02d}"
                key_of_text[text] = k
                paras.append((k, text))
            k = key_of_text[text]
            for q in p["qas"]:
                ans = q["answers"][0]
                questions.append({"id": q["id"], "question": q["question"].strip(), "key": k,
                                  "gold": answer_sentence(p["context"], ans["answer_start"], ans["text"])})
    n_dup_paras = sum(len(art["paragraphs"]) for art in data) - len(paras)

    # Distractors from the MIRACL Korean corpus, skipping KorQuAD dev articles.
    rng = random.Random(SEED)
    pool = []
    for i in range(3):
        with gzip.open(Path(a.miracl_dir) / f"docs-{i}.jsonl.gz", "rt", encoding="utf-8") as f:
            for line in f:
                o = json.loads(line)
                if o["title"].strip() not in titles:
                    pool.append(o["docid"])
    pool.sort()
    rng.shuffle(pool)
    need = a.size - len(paras)
    want = set(pool[: need + 200])
    distract = {}
    for i in range(3):
        with gzip.open(Path(a.miracl_dir) / f"docs-{i}.jsonl.gz", "rt", encoding="utf-8") as f:
            for line in f:
                o = json.loads(line)
                if o["docid"] in want:
                    distract[o["docid"]] = f"{o['title']}\n\n{o['text']}"
    seen = set(key_of_text)
    dlist = []
    for did in pool[: need + 200]:
        t = distract[did]
        if t in seen:
            continue
        seen.add(t)
        dlist.append((f"koval_miracl_{did.replace('#', '_')}", t, did))
        if len(dlist) == need:
            break

    qrng = random.Random(SEED)
    sample = qrng.sample(questions, a.queries)
    qrng.shuffle(sample)
    tune = {q["id"] for q in sample[: len(sample) // 2]}
    text_of = dict(paras)
    tok = tokens({**{f"q:{q['id']}": q["question"] for q in sample}, **{f"p:{k}": text_of[k] for k in {q['key'] for q in sample}}})

    CORPUS_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sources = [(k, t, "korquad_v1.0_dev") for k, t in paras] + [(k, t, "miracl_ko_corpus_v1.0") for k, t, _ in dlist]
    for k, t, _ in sources:
        (CORPUS_DIR / f"{k}.md").write_text(t, encoding="utf-8")
    name = "koval_korquad"
    manifest = {"dataset_id": name, "schema_version": 1, "sources": [
        {"source_key": k, "file_path": f"assets/corpus/ko_validation/{k}.md", "language": "ko", "domain": "wikipedia",
         "format": "md", "char_length": len(t), "origin": o} for k, t, o in sources]}
    (OUT_DIR / f"{name}_sources_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    ev, gold, classes = [], [], collections.Counter()
    for q in sample:
        r, cls = classify(set(tok[f"q:{q['id']}"]), set(tok[f"p:{q['key']}"]))
        classes[cls] += 1
        tags = ["koval", "korquad", f"split:{'tune' if q['id'] in tune else 'check'}", f"class:{cls}", "ko"]
        base = {"dataset_id": name, "schema_version": 1, "item_id": f"korquad-{q['id']}", "query": q["question"],
                "language": "ko", "query_type": cls, "author": "korquad_crowd", "tags": tags}
        ev.append(base | {"expected_source_key": q["key"], "hard_negative_source_keys": [], "positive_source_keys": [q["key"]],
                          "overlap": round(r, 3)})
        gold.append(base | {"gold_source_key": q["key"], "gold_chunk_id": f"{q['key']}#korquad", "gold_passage": q["gold"],
                            "gold_span_start": 0, "gold_span_end": len(q["gold"]), "hard_negative_passages": []})
    (OUT_DIR / f"{name}_evalset.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in ev), encoding="utf-8")
    (OUT_DIR / f"{name}_gold.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in gold), encoding="utf-8")

    ids["korquad"] = {
        "seed": SEED,
        "input_sha256": {kq_path.name: sha256(kq_path)},
        "miracl_corpus_sha256": {f"docs-{i}.jsonl.gz": sha256(Path(a.miracl_dir) / f"docs-{i}.jsonl.gz") for i in range(3)},
        "korquad_paragraphs": len(paras), "korquad_duplicate_paragraphs_skipped": n_dup_paras,
        "distractor_rule": "random MIRACL Korean passages whose title is not a KorQuAD dev title; identical texts once",
        "distractor_docids": [d for _, _, d in dlist],
        "queries": {"tune": sorted(q["id"] for q in sample if q["id"] in tune),
                    "check": sorted(q["id"] for q in sample if q["id"] not in tune)},
        "overlap_classes": dict(classes),
    }
    print(f"korquad: paragraphs {len(paras)} (+{n_dup_paras} duplicates skipped), distractors {len(dlist)}, "
          f"sources {len(sources)}, queries {len(sample)} (tune {len(tune)}), classes {dict(classes)}")


if __name__ == "__main__":
    raise SystemExit(main())
