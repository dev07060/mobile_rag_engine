#!/usr/bin/env python3
"""Offline fusion comparison from dumped engine candidates (docs/milestones.md F1, F-7).

Input: result directories written by
  scripts/eval/run_passage_eval.sh --dump-candidates ...
each holding candidates.json (the engine's own `search_hnsw_slice(k)` and
`bm25_search(k)` lists for k = 20 and 400), index.sqlite (chunk text), and the
harness outputs passage_result.json / ask_condition.json.

1. Validation: re-fuse the dumped lists with the engine's RRF (weights w/(60+rank),
   ties broken by chunk id ascending, as in compute_hybrid_rrf_scores) and check
   that every query's gold rank equals what the engine returned, for all five
   weight profiles, in both conditions:
     ask      candidates 20 per list, top 5   (MobileRag.ask)
     harness  candidates 400 per list, top 10 (README numbers, topK 100)
2. Comparison of fusion candidates (2026-11-13 research), in the ask condition:
     rrf w        weights only (vector weight w, BM25 1-w)
     linear w     min-max normalise each list, then w*vector + (1-w)*bm25
     rrf+top1     default RRF, the vector top-1 always keeps a slot in the top k
     rrf+top1>d   same, only when the vector top-1 leads the 2nd by >= d (1 - distance)

This only compares; it changes no engine default (rule 10.3).

Usage: python3 scripts/eval/f7_fusion_compare.py DIR [DIR ...] [--json out.json]
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RRF_K = 60
PROFILES = {
    "vector_only": 1.0,
    "bm25_only": 0.0,
    "default_hybrid": 0.2,
    "sweep_0_4_0_6": 0.4,
    "sweep_0_6_0_4": 0.6,
}
CONDITIONS = {"ask": (20, 5), "harness": (400, 10)}


def norm(text: str) -> str:
    # normalizePassageText in example/lib/profiling/relevance_metrics.dart
    return re.sub(r"\s+", " ", text.strip().lower())


def rrf(vec, bm25, wv, top_k):
    """Engine RRF. vec/bm25 are [id, score] lists in engine order."""
    wb = 1.0 - wv
    vr = {}
    for i, (cid, _) in enumerate(vec):
        vr.setdefault(cid, i + 1)
    br = {}
    for i, (cid, _) in enumerate(bm25):
        br.setdefault(cid, i + 1)
    ids = sorted(set(vr) | set(br))
    scored = []
    for cid in ids:
        s = 0.0
        if cid in vr:
            s += wv * (1.0 / (RRF_K + vr[cid]))
        if cid in br:
            s += wb * (1.0 / (RRF_K + br[cid]))
        scored.append((cid, s))
    scored.sort(key=lambda t: -t[1])  # stable: ties stay in id order
    return [cid for cid, _ in scored[:top_k]]


def linear(vec, bm25, wv, top_k):
    def minmax(pairs):
        if not pairs:
            return {}
        vals = [v for _, v in pairs]
        lo, hi = min(vals), max(vals)
        return {cid: (v - lo) / (hi - lo) if hi > lo else 1.0 for cid, v in pairs}

    v = minmax([(cid, 1.0 - d) for cid, d in vec])
    b = minmax(bm25)
    ids = sorted(set(v) | set(b))
    scored = sorted(((cid, wv * v.get(cid, 0.0) + (1 - wv) * b.get(cid, 0.0)) for cid in ids), key=lambda t: -t[1])
    return [cid for cid, _ in scored[:top_k]]


def with_top1(vec, bm25, wv, top_k, margin=None):
    ranked = rrf(vec, bm25, wv, top_k)
    if not vec:
        return ranked
    top1 = vec[0][0]
    if margin is not None:
        if len(vec) < 2 or (1.0 - vec[0][1]) - (1.0 - vec[1][1]) < margin:
            return ranked
    if top1 in ranked:
        return ranked
    return ranked[: top_k - 1] + [top1]


def gold_rank(ranked, gold_ids):
    for i, cid in enumerate(ranked):
        if cid in gold_ids:
            return i + 1
    return -1


def bm25_tie_near(bm25, gold_ids, k):
    """True when equal BM25 scores sit within the first k entries (tie order is
    not deterministic in the engine: scores come out of a HashMap)."""
    scores = [s for _, s in bm25[:k]]
    return len(scores) != len(set(scores))


def load_run(d: Path):
    cand = json.loads((d / "candidates.json").read_text(encoding="utf-8"))
    meta = json.loads((d / "run_meta.json").read_text(encoding="utf-8"))
    gold_path = ROOT / "example" / meta["dataset"]["gold"]
    gold = {}
    for line in gold_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            r = json.loads(line)
            gold[r["item_id"]] = r
    db = sqlite3.connect(str(d / "index.sqlite"))
    content = {cid: norm(text) for cid, text in db.execute("SELECT id, content FROM chunks")}
    gold_ids = {}
    for item_id, r in gold.items():
        g = norm(r["gold_passage"])
        gold_ids[item_id] = {cid for cid, text in content.items() if g in text}
    engine = {"ask": {}, "harness": {}}
    ask = json.loads((d / "ask_condition.json").read_text(encoding="utf-8"))
    for r in ask["rows"]:
        engine["ask"][(r["item_id"], r["profile"])] = r["ask_gold_rank"]
    passage = json.loads((d / "passage_result.json").read_text(encoding="utf-8"))
    for r in passage["query_outcomes"]:
        engine["harness"][(r["item_id"], r["profile"])] = r["gold_passage_rank"]
    classes = {}
    for r in ask["rows"]:
        tags = r.get("tags") or []
        c = next((t[6:] for t in tags if t.startswith("class:")), r.get("query_class"))
        classes[r["item_id"]] = c
    rows = [r for r in cand["rows"] if r["item_id"] in gold]
    return {
        "name": meta["model"]["name"],
        "bundle": meta["dataset"]["bundle"],
        "fingerprint": meta["model"]["embedding_fingerprint"],
        "chunks": meta["dataset"]["chunk_count"],
        "commit": meta["engine"]["commit"],
        "rows": rows,
        "gold_ids": gold_ids,
        "engine": engine,
        "classes": classes,
    }


def validate(run):
    out = {}
    for cond, (cand_k, top_k) in CONDITIONS.items():
        same = diff = tie = 0
        mismatches = []
        for r in run["rows"]:
            vec, bm = r[f"vector_{cand_k}"], r[f"bm25_{cand_k}"]
            for prof, wv in PROFILES.items():
                sim = gold_rank(rrf(vec, bm, wv, top_k), run["gold_ids"][r["item_id"]])
                eng = run["engine"][cond].get((r["item_id"], prof))
                if eng is None:
                    continue
                if sim == eng:
                    same += 1
                else:
                    diff += 1
                    t = bm25_tie_near(bm, run["gold_ids"][r["item_id"]], cand_k)
                    tie += t
                    mismatches.append((r["item_id"], prof, eng, sim, "bm25_tie" if t else "other"))
        out[cond] = {"same": same, "different": diff, "different_with_bm25_ties": tie, "mismatches": mismatches}
    return out


def methods():
    m = {}
    for w in (0.2, 0.3, 0.4, 0.5, 0.6, 0.7):
        m[f"rrf {w:.1f}"] = lambda v, b, k, w=w: rrf(v, b, w, k)
    for w in (0.3, 0.5, 0.7):
        m[f"linear {w:.1f}"] = lambda v, b, k, w=w: linear(v, b, w, k)
    m["rrf 0.2+top1"] = lambda v, b, k: with_top1(v, b, 0.2, k)
    for d in (0.02, 0.05, 0.1):
        m[f"rrf 0.2+top1>{d}"] = lambda v, b, k, d=d: with_top1(v, b, 0.2, k, margin=d)
    return m


def compare(run, cond="ask"):
    cand_k, top_k = CONDITIONS[cond]
    res = {}
    for name, fn in methods().items():
        hits = collections.Counter()
        total = collections.Counter()
        for r in run["rows"]:
            ranked = fn(r[f"vector_{cand_k}"], r[f"bm25_{cand_k}"], top_k)
            ok = gold_rank(ranked[:5], run["gold_ids"][r["item_id"]]) > 0
            c = run["classes"].get(r["item_id"], "?")
            for g in ("all", c):
                total[g] += 1
                hits[g] += ok
        res[name] = {g: (hits[g], total[g]) for g in total}
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--json")
    a = ap.parse_args()
    report = []
    for d in a.dirs:
        run = load_run(Path(d))
        val = validate(run)
        cmp_ = compare(run)
        report.append({k: run[k] for k in ("name", "bundle", "fingerprint", "chunks", "commit")} | {"validation": val, "ask_recall_at_5": cmp_})
        print(f"## {run['name']} bundle={run['bundle']} chunks={run['chunks']} fp=…{run['fingerprint'][-12:]} commit={run['commit'][:7]}")
        unreach = [i for i, s in run["gold_ids"].items() if not s]
        if unreach:
            print(f"  gold passage in no chunk: {unreach}")
        for cond, v in val.items():
            print(f"  validate {cond}: same {v['same']}, different {v['different']} (with BM25 ties {v['different_with_bm25_ties']})")
            for m in v["mismatches"][:8]:
                print(f"    {m}")
        groups = sorted({g for r in cmp_.values() for g in r}, key=lambda g: (g != "all", g))
        print("  ask@5 (candidates 20, top 5) by method: " + " | ".join(groups))
        for name, r in cmp_.items():
            cells = [f"{r[g][0]}/{r[g][1]}" if g in r else "-" for g in groups]
            print(f"    {name:<18} " + "  ".join(c.ljust(7) for c in cells))
    if a.json:
        Path(a.json).write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
