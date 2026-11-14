#!/usr/bin/env python3
"""Compare the example app's E1 results with the harness dump (docs/milestones.md E1).

    python3 -I scripts/e1/compare_app_parity.py <e1_app_parity_<model>.json> <harness result dir>

The JSON comes from example/integration_test/e1_app_docs_parity_test.dart; the
directory from `scripts/eval/run_passage_eval.sh --bundle e1 --dump-candidates`
with the same model. For every question and weight preset it compares the
app's top-5 source keys and gold hit with the harness candidates re-fused the
same way as scripts/e1/e1_report.py. Differences in tied BM25 scores can
reorder chunks; those are listed, not hidden.
"""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "e1"))
sys.path.insert(0, str(ROOT / "scripts" / "eval"))
import f7_fusion_compare as f7  # noqa: E402
from e1_report import METHODS  # noqa: E402

PRESET_TO_METHOD = {
    "0.2 / 0.8": "rrf 0.2",
    "0.5 / 0.5": "rrf 0.5",
    "0.6 / 0.4": "rrf 0.6",
    "Vector only": "vector only",
    "BM25 only": "bm25 only",
}


def main() -> int:
    app = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    d = Path(sys.argv[2])
    cand = {r["item_id"]: r for r in json.loads((d / "candidates.json").read_text(encoding="utf-8"))["rows"]}
    meta = json.loads((d / "run_meta.json").read_text(encoding="utf-8"))
    gold = {}
    for line in (ROOT / "example" / meta["dataset"]["gold"]).read_text(encoding="utf-8").splitlines():
        if line.strip():
            r = json.loads(line)
            gold[r["item_id"]] = f7.norm(r["gold_passage"])
    db = sqlite3.connect(str(d / "index.sqlite"))
    src, content = {}, {}
    for cid, text, name in db.execute("SELECT c.id, c.content, s.name FROM chunks c JOIN sources s ON s.id = c.source_id"):
        src[cid], content[cid] = name, f7.norm(text)

    rw = app["recipe_weights"]
    presets = dict(PRESET_TO_METHOD)
    presets["App default"] = f"rrf {rw[0]:.1f}"
    total = same_sources = same_hit = 0
    diffs = []
    hits_app, hits_harness = {}, {}
    for row in app["rows"]:
        q = row["item_id"]
        for preset, method in presets.items():
            top = METHODS[method](cand[q])
            h_sources = [src[c] for c in top]
            h_hit = q in gold and any(gold[q] in content[c] for c in top)
            a = row[preset]
            a_hit = a["gold_rank"] > 0
            total += 1
            same_sources += a["sources"] == h_sources
            same_hit += a_hit == h_hit
            if q in gold:
                hits_app[preset] = hits_app.get(preset, 0) + a_hit
                hits_harness[preset] = hits_harness.get(preset, 0) + h_hit
            if a["sources"] != h_sources or a_hit != h_hit:
                diffs.append({"item_id": q, "preset": preset, "app": a["sources"], "harness": h_sources,
                              "app_hit": a_hit, "harness_hit": h_hit})
    print(f"model={app['model']} harness={d.name} comparisons={total} same_top5_sources={same_sources} same_gold_hit={same_hit}")
    for p in presets:
        print(f"  {p:<12} app={hits_app.get(p)} harness={hits_harness.get(p)} of {sum(1 for q in gold)}")
    print(f"  default_vs_recipe_mismatch={app['default_vs_recipe_mismatch']} differed_on_first_try={app.get('differed_on_first_try')}")
    for x in diffs[:20]:
        print("  diff", json.dumps(x, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
