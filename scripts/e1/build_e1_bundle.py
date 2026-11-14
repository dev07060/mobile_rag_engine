#!/usr/bin/env python3
"""Build the E1 app-document bundle (docs/milestones.md E1) from the hand-edited spec.

Writes into example/assets/evalsets/e1/:
  e1_sources_manifest_v1.json   GNOME Help pages (en 15, ko 15), own short docs
                                (en 12, ko 12), sample_eng.pdf, sample_kor.pdf
  e1_evalset_v1.jsonl           answerable queries (harness source evalset)
  e1_passage_gold_v1.jsonl      gold passages, same item_ids
  e1_no_answer_v1.jsonl         queries with no answer in the corpus
  e1_overlap_v1.json            BM25-token overlap per query and totals

Gold passages must appear verbatim (after the harness normalization) in the
indexed text. For the PDFs that is the engine's own extraction, dumped by the
test-only `eval_dump::dump_file_text`; token overlap uses the engine's
`tokenize_for_bm25` through `eval_dump::dump_bm25_tokens`. Both run with cargo
unless --pdf-text / --tokens point at existing dumps.

Tags per query: e1, class:<none|partial|high> (measured), intent:<lexical|
paraphrase>, doc:<gnome|own|pdf>, <en|ko>, split:<tune|check>, author:<...>.
The split is seeded (20261114) and stratified by language x intent.

Usage: python3 scripts/e1/build_e1_bundle.py [--pdf-text DIR] [--tokens FILE]
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "example"
OUT = EXAMPLE / "assets" / "evalsets" / "e1"
CORPUS = EXAMPLE / "assets" / "corpus" / "e1"
PDFS = {"e1_pdf_eng": ("assets/sample_data/sample_eng.pdf", "en", "IFRS 17 Insurance Contracts (IFRS Foundation)"),
        "e1_pdf_kor": ("assets/sample_data/sample_kor.pdf", "ko", "군 장병 피싱·스캠 예방 서비스 시장 조사 보고서")}
DATASET_ID = "e1_app_docs_v1"
AUTHOR = "session_draft+human_review"  # session drafts, reviewed and confirmed by the maintainer (2026-11-14)
SEED = 20261114

sys.path.insert(0, str(Path(__file__).resolve().parent))
from e1_queries_v1_spec import ROWS  # noqa: E402


def norm(text: str) -> str:
    # Same as normalizePassageText in example/lib/profiling/relevance_metrics.dart.
    return re.sub(r"\s+", " ", text.strip().lower())


def cargo(test: str, env: dict) -> None:
    subprocess.run(["cargo", "test", "--offline", "--lib", test, "--", "--ignored", "--test-threads=1"],
                   cwd=ROOT / "rust_builder" / "rust", env=dict(os.environ, **env), check=True,
                   stdout=subprocess.DEVNULL)


def md_sources() -> list[dict]:
    out = []
    for path in sorted(CORPUS.glob("gnome/*/*.md")) + sorted(CORPUS.glob("own/*/*.md")):
        text = path.read_text(encoding="utf-8")
        if path.parts[-3] == "gnome":
            head = dict(l.split(": ", 1) for l in text.split("\n---\n", 1)[0].splitlines())
            key, lang, origin, title = head["source_key"], head["language"], "gnome_help_cc_by_sa_3", head["title"]
            domain = "app_manual"
        else:
            m = re.match(r"e1_(en|ko)_(\d\d)_", path.name)
            lang, num = m.groups()
            key, origin, domain = f"e1_own_{lang}_{num}", "session_written", "app_docs"
            title = text.splitlines()[0].lstrip("# ").strip()
        out.append({"source_key": key, "file_path": str(path.relative_to(EXAMPLE)), "language": lang,
                    "domain": domain, "format": "md", "length_bucket": "tiny", "char_length": len(text),
                    "origin": origin, "description": title})
    return out


def pdf_texts(existing: str | None) -> dict[str, str]:
    out = {}
    for key, (rel, _, _) in PDFS.items():
        name = Path(rel).stem + ".txt"
        if existing:
            out[key] = (Path(existing) / name).read_text(encoding="utf-8")
            continue
        with tempfile.TemporaryDirectory() as tmp:
            dst = Path(tmp) / name
            cargo("eval_dump::dump_file_text", {"E1_DUMP_FILE": str(EXAMPLE / rel), "E1_DUMP_OUT": str(dst)})
            out[key] = dst.read_text(encoding="utf-8")
    return out


def dump_tokens(texts: dict[str, str], existing: str | None) -> dict[str, list[str]]:
    if existing:
        rows = [json.loads(l) for l in Path(existing).read_text(encoding="utf-8").splitlines() if l.strip()]
        return {r["id"]: r["tokens"] for r in rows}
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp) / "in.jsonl", Path(tmp) / "out.jsonl"
        src.write_text("".join(json.dumps({"id": k, "text": v}, ensure_ascii=False) + "\n" for k, v in texts.items()),
                       encoding="utf-8")
        cargo("eval_dump::dump_bm25_tokens", {"F1_DUMP_IN": str(src), "F1_DUMP_OUT": str(dst)})
        rows = [json.loads(l) for l in dst.read_text(encoding="utf-8").splitlines() if l.strip()]
    return {r["id"]: r["tokens"] for r in rows}


def measured_class(ratio_gold: float) -> str:
    if ratio_gold == 0:
        return "none"
    return "partial" if ratio_gold < 0.5 else "high"


def doc_kind(key: str) -> str:
    return "gnome" if key.startswith("gnome_") else ("pdf" if key.startswith("e1_pdf_") else "own")


def splits() -> dict[str, str]:
    rng = random.Random(SEED)
    strata = collections.defaultdict(list)
    for item_id, lang, intent, *_ in ROWS:
        strata[(lang, intent)].append(item_id)
    out = {}
    for key in sorted(strata):
        ids = sorted(strata[key])
        rng.shuffle(ids)
        for i, q in enumerate(ids):
            out[q] = "tune" if i < len(ids) // 2 else "check"
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf-text", help="directory with sample_eng.txt / sample_kor.txt from dump_file_text")
    ap.add_argument("--tokens", help="reuse a token dump instead of running cargo")
    args = ap.parse_args()

    sources = md_sources()
    texts = pdf_texts(args.pdf_text)
    for key, (rel, lang, title) in PDFS.items():
        sources.append({"source_key": key, "file_path": rel, "language": lang, "domain": "large_pdf", "format": "pdf",
                        "length_bucket": "long", "char_length": len(texts[key]), "origin": "repository_sample_pdf",
                        "description": title})
    by_key = {s["source_key"]: s for s in sources}
    doc_text = {k: texts.get(k) or (EXAMPLE / s["file_path"]).read_text(encoding="utf-8") for k, s in by_key.items()}

    errors = []
    ids = [r[0] for r in ROWS]
    if len(ids) != len(set(ids)):
        errors.append("duplicate item_id")
    for item_id, lang, intent, key, gold, query in ROWS:
        if intent == "no_answer":
            continue
        if key not in by_key:
            errors.append(f"{item_id}: unknown source {key}")
        elif norm(gold) not in norm(doc_text[key]):
            errors.append(f"{item_id}: gold passage not found verbatim in {key}")
        elif norm(doc_text[key]).count(norm(gold)) > 1:
            errors.append(f"{item_id}: gold passage occurs more than once in {key}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    tok_in = {}
    for item_id, lang, intent, key, gold, query in ROWS:
        tok_in[f"q:{item_id}"] = query
        if gold:
            tok_in[f"g:{item_id}"] = gold
    for key in {r[3] for r in ROWS if r[3]}:
        tok_in[f"d:{key}"] = doc_text[key]
    toks = dump_tokens(tok_in, args.tokens)
    split = splits()

    OUT.mkdir(parents=True, exist_ok=True)
    evalset, gold_rows, no_answer, overlap = [], [], [], []
    for item_id, lang, intent, key, gold, query in ROWS:
        q = set(toks[f"q:{item_id}"])
        row = {"item_id": item_id, "language": lang, "intent": intent, "split": split[item_id], "query_tokens": len(q)}
        base_tags = ["e1", lang, f"split:{split[item_id]}", f"author:{AUTHOR}"]
        if intent == "no_answer":
            row.update(measured="no_answer")
            overlap.append(row)
            no_answer.append({"dataset_id": DATASET_ID, "schema_version": 1, "item_id": item_id, "query": query,
                              "language": lang, "query_type": "no_answer", "author": AUTHOR,
                              "tags": base_tags + ["class:no_answer", "intent:no_answer"]})
            continue
        g, d = set(toks[f"g:{item_id}"]), set(toks[f"d:{key}"])
        rg = len(q & g) / len(q) if q else 0.0
        rd = len(q & d) / len(q) if q else 0.0
        measured = measured_class(rg)
        kind = doc_kind(key)
        row.update(source_key=key, doc_kind=kind, overlap_gold=round(rg, 3), overlap_doc=round(rd, 3),
                   shared_with_gold=sorted(q & g), measured=measured)
        overlap.append(row)
        common = {"dataset_id": DATASET_ID, "schema_version": 1, "item_id": item_id, "query": query, "language": lang,
                  "query_type": measured, "author": AUTHOR,
                  "tags": base_tags + [f"class:{measured}", f"intent:{intent}", f"doc:{kind}"]}
        evalset.append(dict(common, expected_source_key=key, hard_negative_source_keys=[],
                            overlap_gold=round(rg, 3), overlap_doc=round(rd, 3)))
        gold_rows.append(dict(common, gold_source_key=key, gold_chunk_id=f"{key}#e1-gold", gold_passage=gold,
                              gold_span_start=0, gold_span_end=len(gold), hard_negative_passages=[]))

    manifest = {"dataset_id": DATASET_ID, "schema_version": 1,
                "note": "E1 app-style documents: GNOME Help (CC BY-SA 3.0), session-written short docs (MIT), "
                        "the two repository sample PDFs.",
                "sources": sources}
    (OUT / "e1_sources_manifest_v1.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                                     encoding="utf-8")

    def jsonl(path: Path, rows: list[dict]) -> None:
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")

    jsonl(OUT / "e1_evalset_v1.jsonl", evalset)
    jsonl(OUT / "e1_passage_gold_v1.jsonl", gold_rows)
    jsonl(OUT / "e1_no_answer_v1.jsonl", no_answer)

    C = collections.Counter
    totals = {
        "queries": len(ROWS), "sources": len(sources), "seed": SEED, "author": AUTHOR,
        "by_language": dict(C(r["language"] for r in overlap)),
        "by_intent_and_language": {f"{k[0]}/{k[1]}": v for k, v in sorted(C((r["intent"], r["language"]) for r in overlap).items())},
        "by_measured_class_and_language": {f"{k[0]}/{k[1]}": v for k, v in sorted(C((r["measured"], r["language"]) for r in overlap).items())},
        "by_intent_and_measured": {f"{k[0]}/{k[1]}": v for k, v in sorted(C((r["intent"], r["measured"]) for r in overlap).items())},
        "by_doc_kind": {f"{k[0]}/{k[1]}": v for k, v in sorted(C((r.get("doc_kind", "-"), r["language"]) for r in overlap).items())},
        "by_split": {f"{k[0]}/{k[1]}": v for k, v in sorted(C((r["split"], r["language"]) for r in overlap).items())},
        "zero_overlap_with_whole_doc": [r["item_id"] for r in overlap if r.get("overlap_doc") == 0],
    }
    (OUT / "e1_overlap_v1.json").write_text(json.dumps({"totals": totals, "rows": overlap}, ensure_ascii=False, indent=2) + "\n",
                                            encoding="utf-8")
    print(json.dumps(totals, ensure_ascii=False, indent=1))
    for r in overlap:
        if r["measured"] != "no_answer":
            print(f"{r['item_id']} {r['language']} {r['intent']:>10}->{r['measured']:<7} gold={r['overlap_gold']:.2f} "
                  f"doc={r['overlap_doc']:.2f} shared={r['shared_with_gold']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
