#!/usr/bin/env python3
"""Build the F1 query bundle (docs/milestones.md F1, F-2) from the hand-edited spec.

Writes into example/assets/evalsets/f1/:
  f1_sources_manifest_v1.json   80 wiki sources (regression bundle) + session-written short docs
  f1_evalset_v1.jsonl           answerable queries (harness source evalset)
  f1_passage_gold_v1.jsonl      gold passages, same item_ids
  f1_no_answer_v1.jsonl         queries with no answer in the corpus
  f1_overlap_v1.json            BM25-token overlap per query and totals

Token overlap uses the engine's own `tokenize_for_bm25` through the test-only
dump in rust_builder/rust/src/api/eval_dump.rs (run by this script with cargo).

Usage: python3 scripts/f1/build_f1_bundle.py [--tokens existing_dump.jsonl]
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "example"
OUT = EXAMPLE / "assets" / "evalsets" / "f1"
WIKI_MANIFEST = EXAMPLE / "assets" / "evalsets" / "wiki_article_sources_manifest_80_balanced_v1.json"
SHORT_DIR = EXAMPLE / "assets" / "corpus" / "f1_short"
DATASET_ID = "f1_eval_v1"
AUTHOR = "session_draft"  # becomes "session_draft+human_review" after review

sys.path.insert(0, str(Path(__file__).resolve().parent))
from f1_queries_v1_spec import ROWS  # noqa: E402


def norm(text: str) -> str:
    # Same as normalizePassageText in example/lib/profiling/relevance_metrics.dart.
    return re.sub(r"\s+", " ", text.strip().lower())


def short_sources() -> list[dict]:
    out = []
    for path in sorted(SHORT_DIR.glob("*/*.md")):
        m = re.match(r"f1_(en|ko)_(\d\d)_", path.name)
        if not m:
            continue
        lang, num = m.groups()
        text = path.read_text(encoding="utf-8")
        out.append(
            {
                "source_key": f"f1_short_{lang}_{num}",
                "file_path": str(path.relative_to(EXAMPLE)),
                "language": lang,
                "domain": "app_docs",
                "format": "md",
                "length_bucket": "tiny",
                "char_length": len(text),
                "origin": "session_written",
                "description": text.splitlines()[0].lstrip("# ").strip(),
            }
        )
    return out


def dump_tokens(texts: dict[str, str], existing: str | None) -> dict[str, list[str]]:
    if existing:
        rows = [json.loads(l) for l in Path(existing).read_text(encoding="utf-8").splitlines() if l.strip()]
        return {r["id"]: r["tokens"] for r in rows}
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.jsonl"
        dst = Path(tmp) / "out.jsonl"
        src.write_text(
            "".join(json.dumps({"id": k, "text": v}, ensure_ascii=False) + "\n" for k, v in texts.items()),
            encoding="utf-8",
        )
        env = dict(os.environ, F1_DUMP_IN=str(src), F1_DUMP_OUT=str(dst))
        subprocess.run(
            ["cargo", "test", "--lib", "eval_dump::dump_bm25_tokens", "--", "--ignored", "--test-threads=1"],
            cwd=ROOT / "rust_builder" / "rust",
            env=env,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        rows = [json.loads(l) for l in dst.read_text(encoding="utf-8").splitlines() if l.strip()]
    return {r["id"]: r["tokens"] for r in rows}


def measured_class(ratio_gold: float) -> str:
    if ratio_gold == 0:
        return "none"
    return "partial" if ratio_gold < 0.5 else "high"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tokens", help="reuse a token dump instead of running cargo")
    args = ap.parse_args()

    wiki = json.loads(WIKI_MANIFEST.read_text(encoding="utf-8"))["sources"]
    shorts = short_sources()
    sources = [dict(s, origin="wikipedia_cc_by_sa") for s in wiki] + shorts
    by_key = {s["source_key"]: s for s in sources}
    doc_text = {k: (EXAMPLE / s["file_path"]).read_text(encoding="utf-8") for k, s in by_key.items()}

    errors = []
    for item_id, lang, intended, key, gold, query in ROWS:
        if intended == "no_answer":
            continue
        if key not in by_key:
            errors.append(f"{item_id}: unknown source {key}")
        elif norm(gold) not in norm(doc_text[key]):
            errors.append(f"{item_id}: gold passage not found verbatim in {key}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    texts = {}
    for item_id, lang, intended, key, gold, query in ROWS:
        texts[f"q:{item_id}"] = query
        if gold:
            texts[f"g:{item_id}"] = gold
    for key in {r[3] for r in ROWS if r[3]}:
        texts[f"d:{key}"] = doc_text[key]
    toks = dump_tokens(texts, args.tokens)

    OUT.mkdir(parents=True, exist_ok=True)
    evalset, gold_rows, no_answer, overlap = [], [], [], []
    for item_id, lang, intended, key, gold, query in ROWS:
        q = set(toks[f"q:{item_id}"])
        row = {"item_id": item_id, "language": lang, "intended": intended, "query_tokens": len(q)}
        if intended == "no_answer":
            row.update(measured="no_answer")
            no_answer.append(
                {
                    "dataset_id": DATASET_ID,
                    "schema_version": 1,
                    "item_id": item_id,
                    "query": query,
                    "language": lang,
                    "query_type": "no_answer",
                    "author": AUTHOR,
                    "tags": ["f1", "class:no_answer", f"author:{AUTHOR}"],
                }
            )
            overlap.append(row)
            continue
        g = set(toks[f"g:{item_id}"])
        d = set(toks[f"d:{key}"])
        rg = len(q & g) / len(q) if q else 0.0
        rd = len(q & d) / len(q) if q else 0.0
        measured = measured_class(rg)
        doc_kind = "short" if key.startswith("f1_short_") else "wiki"
        row.update(
            source_key=key,
            doc_kind=doc_kind,
            overlap_gold=round(rg, 3),
            overlap_doc=round(rd, 3),
            shared_with_gold=sorted(q & g),
            measured=measured,
        )
        overlap.append(row)
        tags = ["f1", f"class:{measured}", f"doc:{doc_kind}", lang, f"author:{AUTHOR}"]
        common = {
            "dataset_id": DATASET_ID,
            "schema_version": 1,
            "item_id": item_id,
            "query": query,
            "language": lang,
            "query_type": measured,
            "author": AUTHOR,
            "tags": tags,
        }
        evalset.append(dict(common, expected_source_key=key, hard_negative_source_keys=[],
                            overlap_gold=round(rg, 3), overlap_doc=round(rd, 3)))
        gold_rows.append(dict(common, gold_source_key=key, gold_chunk_id=f"{key}#f1-gold",
                              gold_passage=gold, gold_span_start=0, gold_span_end=len(gold),
                              hard_negative_passages=[]))

    manifest = {
        "dataset_id": DATASET_ID,
        "schema_version": 1,
        "note": "80 wiki sources of the 80-query regression bundle plus session-written short docs (F1 F-2 stage 1).",
        "sources": sources,
    }
    (OUT / "f1_sources_manifest_v1.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def jsonl(path: Path, rows: list[dict]) -> None:
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")

    jsonl(OUT / "f1_evalset_v1.jsonl", evalset)
    jsonl(OUT / "f1_passage_gold_v1.jsonl", gold_rows)
    jsonl(OUT / "f1_no_answer_v1.jsonl", no_answer)

    C = collections.Counter
    totals = {
        "queries": len(ROWS),
        "by_language": dict(C(r["language"] for r in overlap)),
        "by_measured_class": dict(C(r["measured"] for r in overlap)),
        "by_class_and_doc_kind": {f"{k[0]}/{k[1]}": v for k, v in C((r["measured"], r.get("doc_kind", "-")) for r in overlap).items()},
        "by_class_and_language": {f"{k[0]}/{k[1]}": v for k, v in C((r["measured"], r["language"]) for r in overlap).items()},
        "intended_vs_measured_mismatch": [r["item_id"] for r in overlap if r["intended"] != r["measured"]],
        "zero_overlap_with_whole_doc": [r["item_id"] for r in overlap if r.get("overlap_doc") == 0],
        "author": AUTHOR,
    }
    (OUT / "f1_overlap_v1.json").write_text(json.dumps({"totals": totals, "rows": overlap}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(totals, ensure_ascii=False, indent=1))
    for r in overlap:
        if r["measured"] != "no_answer":
            print(f"{r['item_id']} {r['language']} {r['intended']:>7}->{r['measured']:<7} gold={r['overlap_gold']:.2f} doc={r['overlap_doc']:.2f} shared={r['shared_with_gold']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
