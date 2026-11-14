"""E1 vector-weight grid per language (docs/perf/e1-app-docs/README.md).

    python3 -I scripts/e1/e1_weight_grid.py build/eval_results/e1_minilm build/eval_results/e1_koen ...
    python3 -I scripts/e1/e1_weight_grid.py --weights 0.42,0.47,0.485,0.49,0.495,0.5,0.51 <dirs>

Same data and condition as e1_report.py (`ask`: top 5, 20 candidates per list),
recomputed offline from the dumped candidate lists. For each model and
language, prints the answered questions with the gold passage in the top 5 at
vector weight 0.0 (BM25 only), 0.1 ... 0.9 (RRF, BM25 weight = 1 - w) and 1.0
(vector only), for all questions and for the tune / check halves.
"""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "eval"))
sys.path.insert(0, str(ROOT / "scripts" / "e1"))
import f7_fusion_compare as f7  # noqa: E402
import e1_queries_v1_spec as spec  # noqa: E402

WEIGHTS = [round(i / 10, 1) for i in range(11)]


def top5(row: dict, w: float) -> list:
    if w == 0.0:
        return [c for c, _ in row["bm25_20"][:5]]
    if w == 1.0:
        return [c for c, _ in row["vector_20"][:5]]
    return f7.rrf(row["vector_20"], row["bm25_20"], w, 5)


def main() -> int:
    global WEIGHTS
    args = sys.argv[1:]
    if args[:1] == ["--weights"]:
        WEIGHTS = [float(w) for w in args[1].split(",")]
        args = args[2:]
    overlap = json.loads((ROOT / "example/assets/evalsets/e1/e1_overlap_v1.json").read_text())
    split = {r["item_id"]: r["split"] for r in overlap["rows"]}
    answered = [(i, lang, gold) for i, lang, intent, _key, gold, _q in spec.ROWS if intent != "no_answer"]
    print("| model | language | questions | " + " | ".join(str(w) for w in WEIGHTS) + " |")
    print("|---|---|---|" + "---|" * len(WEIGHTS))
    for d in map(Path, args):
        cand = {r["item_id"]: r for r in json.loads((d / "candidates.json").read_text())["rows"]}
        db = sqlite3.connect(str(d / "index.sqlite"))
        content = {cid: f7.norm(t) for cid, t in db.execute("SELECT id, content FROM chunks")}
        for lang in ("en", "ko"):
            for half in (None, "tune", "check"):
                qs = [(i, g) for i, l, g in answered if l == lang and (half is None or split[i] == half)]
                cells = [sum(any(f7.norm(g) in content[c] for c in top5(cand[i], w)) for i, g in qs) for w in WEIGHTS]
                print(f"| {d.name} | {lang} {half or 'all'} | {len(qs)} | " + " | ".join(map(str, cells)) + " |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
