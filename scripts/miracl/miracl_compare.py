#!/usr/bin/env python3
"""Score MIRACL Korean runs from engine candidate dumps (docs/milestones.md F1).

Input: result directories of
  scripts/eval/run_passage_eval.sh --bundle miracl_ko_<size> --dump-candidates
1. Validation as in scripts/eval/f7_fusion_compare.py: re-fusing the dumps must
   give the engine's own gold rank for every query and weight profile.
2. Scoring by source id, because MIRACL has several positives per query and a
   passage can be split into several chunks: a query is a hit when one of the
   top 5 results (ask condition: 20 candidates per list) comes from a positive
   passage. This is `ask@5` with "any positive" in place of the single gold
   passage of the 80-query and F1 bundles.
Reports per method: hits, new and lost queries against the default (RRF 0.2),
by split (tune / check) and overlap class; queries the vector list finds in its
top 5 but the default hybrid drops; the share of unjudged passages in the
default top 5; how many passages were split into several chunks.

Usage: python3 -I scripts/miracl/miracl_compare.py DIR [DIR ...] [--json out.json]
"""

from __future__ import annotations

import argparse
import collections
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "eval"))
import f7_fusion_compare as f7  # noqa: E402

EVAL = ROOT / "example" / "assets" / "evalsets" / "miracl_ko"
DEFAULT = "rrf 0.2"
REPORT = ["rrf 0.2", "rrf 0.3", "rrf 0.4", "rrf 0.5", "rrf 0.6", "rrf 0.7",
          "linear 0.3", "linear 0.5", "linear 0.7",
          "rrf 0.2+top1", "rrf 0.2+top1>0.02", "rrf 0.2+top1>0.05", "rrf 0.2+top1>0.1"]


def analyse(d: Path) -> dict:
    run = f7.load_run(d)
    val = f7.validate(run)
    meta = json.loads((d / "run_meta.json").read_text(encoding="utf-8"))
    db = sqlite3.connect(str(d / "index.sqlite"))
    src_of = {cid: name for cid, name in db.execute("SELECT c.id, s.name FROM chunks c JOIN sources s ON s.id = c.source_id")}
    chunks_per_src = collections.Counter(src_of.values())
    n_sources = db.execute("SELECT count(*) FROM sources").fetchone()[0]
    ev = {r["item_id"]: r for r in map(json.loads, (ROOT / "example" / meta["dataset"]["evalset"]).read_text(encoding="utf-8").splitlines()) if r}
    qrels = json.loads((EVAL / "miracl_ko_qrels.json").read_text(encoding="utf-8"))
    overlap = json.loads((EVAL / "miracl_ko_overlap.json").read_text(encoding="utf-8"))
    positives = {q: set(r["positive_source_keys"]) for q, r in ev.items()}
    indexed = set(src_of.values())
    missing_pos = sorted(k for s in positives.values() for k in s if k not in indexed)
    split = {q: next(t[6:] for t in r["tags"] if t.startswith("split:")) for q, r in ev.items()}

    def hit(ranked, q):
        return any(src_of.get(c) in positives[q] for c in ranked[:5])

    rows = {r["item_id"]: r for r in run["rows"]}
    methods = f7.methods()
    per = {m: {q: hit(methods[m](rows[q]["vector_20"], rows[q]["bm25_20"], 5), q) for q in rows} for m in REPORT}
    vec5 = {q: hit([c for c, _ in rows[q]["vector_20"]], q) for q in rows}
    bm5 = {q: hit([c for c, _ in rows[q]["bm25_20"]], q) for q in rows}

    def summary(qs):
        out = {}
        for m in REPORT:
            new = [q for q in qs if per[m][q] and not per[DEFAULT][q]]
            lost = [q for q in qs if per[DEFAULT][q] and not per[m][q]]
            out[m] = {"hits": sum(per[m][q] for q in qs), "of": len(qs), "new": len(new), "lost": len(lost), "lost_ids": lost}
        out["vector_top5"] = {"hits": sum(vec5[q] for q in qs), "of": len(qs)}
        out["bm25_top5"] = {"hits": sum(bm5[q] for q in qs), "of": len(qs)}
        dropped = [q for q in qs if vec5[q] and not per[DEFAULT][q]]
        out["vector_found_default_dropped"] = {"count": len(dropped), "of_vector_hits": sum(vec5[q] for q in qs), "ids": dropped}
        return out

    groups = {"all": list(rows)}
    for g in ("tune", "check"):
        groups[g] = [q for q in rows if split[q] == g]
    for c in ("none", "partial", "high"):
        groups[f"class:{c}"] = [q for q in rows if overlap[q]["class"] == c]
    # Default top 5: share of results from passages nobody judged for that query.
    unjudged = total = 0
    for q in rows:
        top = [src_of.get(c) for c in methods[DEFAULT](rows[q]["vector_20"], rows[q]["bm25_20"], 5)[:5]]
        total += len(top)
        unjudged += sum(1 for s in top if s not in qrels[q])
    return {
        "name": meta["model"]["name"], "bundle": meta["dataset"]["bundle"], "commit": meta["engine"]["commit"],
        "fingerprint": meta["model"]["embedding_fingerprint"], "chunks": meta["dataset"]["chunk_count"],
        "sources_indexed": n_sources, "sources_in_manifest": None,
        "positive_sources_not_indexed": missing_pos,
        "sources_split_into_chunks": sum(1 for v in chunks_per_src.values() if v > 1),
        "positive_sources_split": sum(1 for s in {k for v in positives.values() for k in v} if chunks_per_src.get(s, 0) > 1),
        "validation": {k: {kk: vv for kk, vv in v.items() if kk != "mismatches"} | {"mismatches": v["mismatches"][:10]} for k, v in val.items()},
        "default_top5_unjudged_share": round(unjudged / total, 3) if total else None,
        "groups": {g: summary(qs) for g, qs in groups.items()},
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--json")
    a = ap.parse_args()
    out = []
    for d in a.dirs:
        r = analyse(Path(d))
        man = json.loads((ROOT / "example" / json.loads((Path(d) / "run_meta.json").read_text())["dataset"]["manifest"]).read_text())
        r["sources_in_manifest"] = len(man["sources"])
        out.append(r)
        print(f"## {r['name']} {r['bundle']} chunks={r['chunks']} sources={r['sources_indexed']}/{r['sources_in_manifest']} commit={r['commit'][:7]}")
        for c, v in r["validation"].items():
            print(f"  validate {c}: same {v['same']}, different {v['different']}")
        print(f"  positives not indexed {len(r['positive_sources_not_indexed'])}, sources split {r['sources_split_into_chunks']}, positives split {r['positive_sources_split']}, default top5 unjudged {r['default_top5_unjudged_share']}")
        for g, s in r["groups"].items():
            if not s[DEFAULT]["of"]:
                continue
            vd = s["vector_found_default_dropped"]
            print(f"  [{g}] n={s[DEFAULT]['of']} vector@5 {s['vector_top5']['hits']} bm25@5 {s['bm25_top5']['hits']} | vector-found-default-dropped {vd['count']}/{vd['of_vector_hits']}")
            for m in REPORT:
                x = s[m]
                print(f"    {m:<18} {x['hits']:>4}  +{x['new']:<3} -{x['lost']}")
    if a.json:
        Path(a.json).write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
