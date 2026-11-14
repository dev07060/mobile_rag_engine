#!/usr/bin/env python3
"""E1 report tables from dumped engine candidates (docs/perf/e1-app-docs/).

    python3 -I scripts/e1/e1_report.py build/eval_results/e1_minilm build/eval_results/e1_koen ... \
        [--json docs/perf/e1-app-docs/results_e1.json]

Each directory is a `scripts/eval/run_passage_eval.sh --bundle e1 --dump-candidates`
result. Everything is recomputed from the dumped vector / BM25 candidate lists
in the `ask` condition (top 5, 20 candidates per list), the same way as
scripts/f2/f2_0_compare.py; the engine match is checked separately with
scripts/eval/f7_fusion_compare.py.

Prints, per model:
  1. answer in top 5 per method (vector only, BM25 only, RRF 0.2 / 0.5 / 0.6),
     by language x intent, language x measured class, document kind, tune / check,
     with new / lost against 0.2 and a two-sided sign test for 0.5 and 0.6
  2. the "wall": BM25 20-list full, share of the 0.2 top 5 that came from the
     BM25 list, vector-only hits lost by 0.2 and how many 0.5 / 0.6 recover
  3. what the misses are made of: the answer in any 20-list, in any 400-list
  4. no-answer questions: where the top 1 comes from, BM25 list size, and the
     vector top-1 similarity next to that of answered questions
"""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "eval"))
import f7_fusion_compare as f7  # noqa: E402

METHODS = {
    "vector only": lambda r: [c for c, _ in r["vector_20"][:5]],
    "bm25 only": lambda r: [c for c, _ in r["bm25_20"][:5]],
    "rrf 0.2": lambda r: f7.rrf(r["vector_20"], r["bm25_20"], 0.2, 5),
    "rrf 0.5": lambda r: f7.rrf(r["vector_20"], r["bm25_20"], 0.5, 5),
    "rrf 0.6": lambda r: f7.rrf(r["vector_20"], r["bm25_20"], 0.6, 5),
}
DEFAULT = "rrf 0.2"


def sign_test(new: int, lost: int) -> float:
    n = new + lost
    if n == 0:
        return 1.0
    k = min(new, lost)
    p = sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, 2 * p)


def jsonl(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


def analyze(d: Path) -> dict:
    meta = json.loads((d / "run_meta.json").read_text(encoding="utf-8"))
    cand = json.loads((d / "candidates.json").read_text(encoding="utf-8"))
    ds = meta["dataset"]
    ev = {r["item_id"]: r for r in jsonl(ROOT / "example" / ds["evalset"])}
    na = {r["item_id"]: r for r in jsonl(ROOT / "example" / ds["no_answer"])}
    gold = {r["item_id"]: r for r in jsonl(ROOT / "example" / ds["gold"])}
    db = sqlite3.connect(str(d / "index.sqlite"))
    content, src = {}, {}
    for cid, text, name in db.execute("SELECT c.id, c.content, s.name FROM chunks c JOIN sources s ON s.id = c.source_id"):
        content[cid] = f7.norm(text)
        src[cid] = name
    gold_ids = {q: {c for c, t in content.items() if f7.norm(g["gold_passage"]) in t} for q, g in gold.items()}
    rows = {r["item_id"]: r for r in cand["rows"]}

    def tags(q):
        r = ev.get(q) or na[q]
        return {t.split(":", 1)[0]: t.split(":", 1)[1] for t in r["tags"] if ":" in t} | {"lang": r["language"]}

    answerable = sorted(q for q in ev if gold_ids.get(q))
    missing_gold = sorted(q for q in ev if not gold_ids.get(q))
    hit = {m: {q: f7.gold_rank(fn(rows[q]), gold_ids[q]) > 0 for q in answerable} for m, fn in METHODS.items()}

    groups = {"all": answerable}
    for q in answerable:
        t = tags(q)
        for g in (t["lang"], f"{t['lang']}|{t['intent']}", f"{t['lang']}|class:{t['class']}",
                  f"{t['lang']}|doc:{t['doc']}", f"split:{t['split']}", f"{t['lang']}|split:{t['split']}"):
            groups.setdefault(g, []).append(q)

    table = {}
    for g, qs in groups.items():
        table[g] = {}
        for m in METHODS:
            new = sum(1 for q in qs if hit[m][q] and not hit[DEFAULT][q])
            lost = sum(1 for q in qs if hit[DEFAULT][q] and not hit[m][q])
            table[g][m] = {"hits": sum(hit[m][q] for q in qs), "of": len(qs), "new": new, "lost": lost,
                           "sign_p": round(sign_test(new, lost), 4)}

    # The wall.
    wall = {}
    for lang in ("en", "ko"):
        qs = [q for q in rows if tags(q)["lang"] == lang]
        full = [q for q in qs if len(rows[q]["bm25_20"]) >= 20]
        slots = from_bm25 = 0
        for q in full:
            bm = {c for c, _ in rows[q]["bm25_20"]}
            top = METHODS[DEFAULT](rows[q])
            slots += len(top)
            from_bm25 += sum(1 for c in top if c in bm)
        aq = [q for q in answerable if tags(q)["lang"] == lang]
        vec_lost = [q for q in aq if hit["vector only"][q] and not hit[DEFAULT][q]]
        wall[lang] = {
            "queries": len(qs), "bm25_20_full": len(full), "top5_slots_in_full": slots,
            "top5_slots_from_bm25_list": from_bm25,
            "vector_hit_default_miss": len(vec_lost),
            "of_which_bm25_full": sum(1 for q in vec_lost if len(rows[q]["bm25_20"]) >= 20),
            "recovered_by_0.5": sum(1 for q in vec_lost if hit["rrf 0.5"][q]),
            "recovered_by_0.6": sum(1 for q in vec_lost if hit["rrf 0.6"][q]),
        }

    # What the misses are made of.
    misses = {}
    for m in (DEFAULT, "rrf 0.5"):
        for lang in ("en", "ko"):
            qs = [q for q in answerable if tags(q)["lang"] == lang and not hit[m][q]]
            r = rows
            in20 = [q for q in qs if gold_ids[q] & ({c for c, _ in r[q]["vector_20"]} | {c for c, _ in r[q]["bm25_20"]})]
            in400 = [q for q in qs if gold_ids[q] & ({c for c, _ in r[q]["vector_400"]} | {c for c, _ in r[q]["bm25_400"]})]
            by_class = {}
            for q in qs:
                by_class[tags(q)["class"]] = by_class.get(tags(q)["class"], 0) + 1
            pdf_top = sum(1 for q in qs if METHODS[m](r[q]) and src[METHODS[m](r[q])[0]].startswith("e1_pdf_"))
            misses[f"{m}|{lang}"] = {"missed": len(qs), "by_class": by_class, "answer_in_a_20_list": len(in20),
                                     "answer_in_a_400_list": len(in400), "top1_from_a_pdf": pdf_top,
                                     "ids": qs}

    # No-answer questions.
    def kind(name):
        return "pdf" if name.startswith("e1_pdf_") else ("gnome" if name.startswith("gnome_") else "own")

    def lang_of(name):
        return "en" if ("_en_" in name or name in ("e1_pdf_eng",) or name.startswith("gnome_en")) else "ko"

    noans = {}
    for lang in ("en", "ko"):
        qs = sorted(q for q in na if na[q]["language"] == lang)
        out = {"queries": len(qs), "top1_kind": {}, "top1_same_language": 0, "bm25_20_sizes": [],
               "vector_top1_similarity": [], "rows": []}
        for q in qs:
            for m in ("rrf 0.2", "rrf 0.5"):
                top = METHODS[m](rows[q])
                k = kind(src[top[0]]) if top else "none"
                out["top1_kind"].setdefault(m, {}).setdefault(k, 0)
                out["top1_kind"][m][k] += 1
            top = METHODS[DEFAULT](rows[q])
            if top and lang_of(src[top[0]]) == lang:
                out["top1_same_language"] += 1
            out["bm25_20_sizes"].append(len(rows[q]["bm25_20"]))
            sim = 1 - rows[q]["vector_20"][0][1] if rows[q]["vector_20"] else None
            out["vector_top1_similarity"].append(sim)
            out["rows"].append({"item_id": q, "query": na[q]["query"], "top1_0.2": src[top[0]] if top else None,
                                "top1_0.5": src[METHODS["rrf 0.5"](rows[q])[0]] if top else None,
                                "bm25_20": len(rows[q]["bm25_20"]), "vector_top1_similarity": sim})
        ans_sims = [1 - rows[q]["vector_20"][0][1] for q in answerable if tags(q)["lang"] == lang and hit["vector only"][q]]
        sims = [s for s in out["vector_top1_similarity"] if s is not None]
        out["similarity_summary"] = {
            "no_answer_median": round(statistics.median(sims), 3), "no_answer_max": round(max(sims), 3),
            "answered_vector_hit_median": round(statistics.median(ans_sims), 3) if ans_sims else None,
            "answered_vector_hit_min": round(min(ans_sims), 3) if ans_sims else None,
            "no_answer_above_answered_min": sum(1 for s in sims if ans_sims and s >= min(ans_sims)),
        }
        noans[lang] = out

    return {"dir": d.name, "model": meta["model"]["name"], "fingerprint": meta["model"]["embedding_fingerprint"],
            "commit": meta["engine"]["commit"], "dirty": meta["engine"].get("dirty_tracked_files"),
            "chunks": cand["chunk_count"], "elapsed_seconds": meta.get("elapsed_seconds"),
            "finished_at_utc": meta.get("finished_at_utc"), "dataset_sha256": ds.get("sha256"),
            "answerable": len(answerable), "gold_not_in_any_chunk": missing_gold,
            "table": table, "wall": wall, "misses": misses, "no_answer": noans}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--json")
    a = ap.parse_args()
    report = [analyze(Path(d)) for d in a.dirs]
    for r in report:
        print(f"## {r['model']} chunks={r['chunks']} commit={r['commit'][:7]} answerable={r['answerable']} gold_missing={r['gold_not_in_any_chunk']}")
        for g in ("all", "en", "ko", "en|lexical", "en|paraphrase", "ko|lexical", "ko|paraphrase",
                  "en|class:high", "en|class:partial", "en|class:none", "ko|class:high", "ko|class:partial", "ko|class:none",
                  "en|doc:gnome", "en|doc:own", "en|doc:pdf", "ko|doc:gnome", "ko|doc:own", "ko|doc:pdf",
                  "split:tune", "split:check", "en|split:tune", "en|split:check", "ko|split:tune", "ko|split:check"):
            if g not in r["table"]:
                continue
            cells = []
            for m, x in r["table"][g].items():
                extra = "" if m == DEFAULT else f" +{x['new']}/-{x['lost']}"
                cells.append(f"{m}={x['hits']}{extra}")
            n = r["table"][g][DEFAULT]["of"]
            p5, p6 = r["table"][g]["rrf 0.5"]["sign_p"], r["table"][g]["rrf 0.6"]["sign_p"]
            print(f"  {g:<16} n={n:<3} " + "  ".join(cells) + f"  p0.5={p5} p0.6={p6}")
        print("  wall", json.dumps(r["wall"]))
        for k, v in r["misses"].items():
            print("  miss", k, json.dumps({x: y for x, y in v.items() if x != "ids"}, ensure_ascii=False))
        for lang, v in r["no_answer"].items():
            print("  no_answer", lang, json.dumps({x: y for x, y in v.items() if x not in ("rows", "bm25_20_sizes", "vector_top1_similarity")}, ensure_ascii=False),
                  "bm25_sizes", v["bm25_20_sizes"])
    if a.json:
        Path(a.json).write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
