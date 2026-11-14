#!/usr/bin/env python3
"""F2-0: compare fix shapes for the hybrid fusion loss offline (docs/milestones.md F2).

Re-fuses dumped engine candidates (`scripts/eval/run_passage_eval.sh
--dump-candidates`) and scores every candidate method in the `ask` condition
(top 5). No engine code runs; validation against the engine is done by
f7_fusion_compare.py / miracl_compare.py on the same dumps.

Inputs (result directories):
  --miracl DIR...   bundles with positive_source_keys and split:/class: tags (MIRACL
                    Korean, the F2 Korean validation bundles), scored by positive source
  --b80 DIR...      80-query bundle runs (regression check), groups all / en / ko
  --f1 DIR...       reviewed F1 bundle runs (32 answerable), groups all / class

Method families (F2 draft):
  (A) fusion added as an option: linear w (min-max per list), rrf w + vector top-1 slot
  (B) per-model weight: rrf w for w = 0.2..0.7, picked per model on MIRACL tune
  (C) one new default for every model: any single method, judged on all inputs
  (D) more candidates: default rrf 0.2 over the first K entries of the 400-lists
  ref: vector only / BM25 only top 5 of the 20-lists, for reference

(D) uses prefixes of the dumped 400-candidate lists. The engine would search
HNSW with a different ef for another K, so these are close to, not equal to,
what the engine returns; the script reports how often the 20-prefix of the
400-list equals the engine's own 20-list.

Usage: python3 -I scripts/f2/f2_0_compare.py --miracl D... --b80 D... --f1 D... [--json out.json]
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "eval"))
import f7_fusion_compare as f7  # noqa: E402

DEFAULT = "rrf 0.2"


def method_table():
    m = {}
    for w in (0.2, 0.3, 0.4, 0.5, 0.6, 0.7):
        m[f"rrf {w:.1f}"] = ("B", lambda r, w=w: f7.rrf(r["vector_20"], r["bm25_20"], w, 5))
    for w in (0.3, 0.5, 0.7):
        m[f"linear {w:.1f}"] = ("A", lambda r, w=w: f7.linear(r["vector_20"], r["bm25_20"], w, 5))
    m["rrf 0.2+top1"] = ("A", lambda r: f7.with_top1(r["vector_20"], r["bm25_20"], 0.2, 5))
    for d in (0.02, 0.05):
        m[f"rrf 0.2+top1>{d}"] = ("A", lambda r, d=d: f7.with_top1(r["vector_20"], r["bm25_20"], 0.2, 5, margin=d))
    m["rrf 0.5+top1"] = ("A", lambda r: f7.with_top1(r["vector_20"], r["bm25_20"], 0.5, 5))
    for k in (50, 100, 200, 400):
        m[f"rrf 0.2 K{k}"] = ("D", lambda r, k=k: f7.rrf(r["vector_400"][:k], r["bm25_400"][:k], 0.2, 5))
    m["rrf 0.5 K50"] = ("D", lambda r: f7.rrf(r["vector_400"][:50], r["bm25_400"][:50], 0.5, 5))
    m["vector only"] = ("ref", lambda r: [c for c, _ in r["vector_20"][:5]])
    m["bm25 only"] = ("ref", lambda r: [c for c, _ in r["bm25_20"][:5]])
    return m


METHODS = method_table()


def prefix_agreement(rows):
    same = sum(1 for r in rows if [c for c, _ in r["vector_400"][:20]] == [c for c, _ in r["vector_20"]])
    return same, len(rows)


def score_miracl(d: Path):
    run = f7.load_run(d)
    meta = json.loads((d / "run_meta.json").read_text(encoding="utf-8"))
    db = sqlite3.connect(str(d / "index.sqlite"))
    src_of = dict(db.execute("SELECT c.id, s.name FROM chunks c JOIN sources s ON s.id = c.source_id"))
    ev = [json.loads(l) for l in (ROOT / "example" / meta["dataset"]["evalset"]).read_text(encoding="utf-8").splitlines() if l.strip()]
    pos = {r["item_id"]: set(r["positive_source_keys"]) for r in ev}
    split = {r["item_id"]: next(t[6:] for t in r["tags"] if t.startswith("split:")) for r in ev}
    cls = {r["item_id"]: next(t[6:] for t in r["tags"] if t.startswith("class:")) for r in ev}
    hits = {m: {r["item_id"]: any(src_of.get(c) in pos[r["item_id"]] for c in fn(r)) for r in run["rows"]} for m, (_, fn) in METHODS.items()}
    groups = {"tune": [q for q in split if split[q] == "tune"], "check": [q for q in split if split[q] == "check"]}
    for c in ("none", "partial", "high"):
        if any(cls[q] == c for q in split):
            groups[c] = [q for q in split if cls[q] == c]
    return run, hits, groups


def score_gold(d: Path, group_key):
    run = f7.load_run(d)
    meta = json.loads((d / "run_meta.json").read_text(encoding="utf-8"))
    ev = {r["item_id"]: r for r in (json.loads(l) for l in (ROOT / "example" / meta["dataset"]["evalset"]).read_text(encoding="utf-8").splitlines() if l.strip())}
    rows = [r for r in run["rows"] if run["gold_ids"].get(r["item_id"])]
    hits = {m: {r["item_id"]: f7.gold_rank(fn(r), run["gold_ids"][r["item_id"]]) > 0 for r in rows} for m, (_, fn) in METHODS.items()}
    qs = [r["item_id"] for r in rows]
    groups = {"all": qs}
    for q in qs:
        groups.setdefault(group_key(ev[q], run["classes"].get(q)), []).append(q)
    run["rows"] = rows
    return run, hits, groups


def summarize(hits, groups):
    out = {}
    for g, qs in groups.items():
        out[g] = {}
        for m in METHODS:
            new = sum(1 for q in qs if hits[m][q] and not hits[DEFAULT][q])
            lost = sum(1 for q in qs if hits[DEFAULT][q] and not hits[m][q])
            out[g][m] = {"hits": sum(hits[m][q] for q in qs), "of": len(qs), "new": new, "lost": lost}
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--miracl", nargs="*", default=[])
    ap.add_argument("--b80", nargs="*", default=[])
    ap.add_argument("--f1", nargs="*", default=[])
    ap.add_argument("--json")
    a = ap.parse_args()
    report = []
    for kind, dirs in (("miracl", a.miracl), ("b80", a.b80), ("f1", a.f1)):
        for d in dirs:
            if kind == "miracl":
                run, hits, groups = score_miracl(Path(d))
            elif kind == "b80":
                run, hits, groups = score_gold(Path(d), lambda e, c: "lang:" + (e.get("language") if e.get("language") in ("en", "ko") else "other"))
            else:
                run, hits, groups = score_gold(Path(d), lambda e, c: f"class:{c}")
            same, n = prefix_agreement(run["rows"])
            entry = {"kind": kind, "dir": Path(d).name, "model": run["name"], "bundle": run["bundle"],
                     "fingerprint": run["fingerprint"], "chunks": run["chunks"], "commit": run["commit"],
                     "vector_prefix20_equals_engine20": [same, n],
                     "bm25_20_full": [sum(1 for r in run["rows"] if len(r["bm25_20"]) >= 20), len(run["rows"])],
                     "groups": summarize(hits, groups)}
            report.append(entry)
            print(f"## {kind} {run['name']} {run['bundle']} chunks={run['chunks']} commit={run['commit'][:7]} prefix20==engine20 {same}/{n} bm25_20_full {entry['bm25_20_full'][0]}/{n}")
            gs = list(entry["groups"])
            print(f"    {'method':<18}" + "".join(f"{g:>18}" for g in gs))
            for m, (fam, _) in METHODS.items():
                cells = [f"{x['hits']}/{x['of']} +{x['new']}-{x['lost']}" for x in (entry["groups"][g][m] for g in gs)]
                print(f"  {fam} {m:<18}" + "".join(f"{c:>18}" for c in cells))
    if a.json:
        Path(a.json).write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
