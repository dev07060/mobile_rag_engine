#!/usr/bin/env python3
"""Generate seed evalset/chunk-gold JSONL from a source manifest.

The output is a draft dataset for offline evaluation bootstrap.
Manual review is still required before gate runs.
"""

from __future__ import annotations

import argparse
import json
import random
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any


ALLOWED_LANG = {"ko", "en", "other"}


@dataclass
class SourceDoc:
    source_key: str
    file_path: str
    language: str
    domain: str
    title: str
    snippets: list[str]


def _load_manifest(path: Path) -> tuple[str, int, list[dict[str, Any]]]:
    obj = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(obj, dict):
        raise ValueError("Manifest root must be object")
    dataset_id = str(obj.get("dataset_id", "")).strip()
    schema_version = obj.get("schema_version")
    sources = obj.get("sources", [])
    if not dataset_id:
        raise ValueError("manifest.dataset_id is required")
    if not isinstance(schema_version, int) or schema_version < 1:
        raise ValueError("manifest.schema_version must be integer >= 1")
    if not isinstance(sources, list) or not sources:
        raise ValueError("manifest.sources must be a non-empty list")
    return dataset_id, schema_version, sources


def _resolve_source_file(root: Path, file_path: str) -> Path:
    raw = Path(file_path)
    if raw.is_absolute():
        return raw
    if file_path.startswith("assets/"):
        return root / "example" / file_path
    return root / raw


def _clean_line(line: str) -> str:
    # Remove markdown links and emphasis markers.
    line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
    line = line.replace("**", "").replace("*", "").replace("`", "")
    line = re.sub(r"\s+", " ", line).strip()
    return line


def _split_sentences(text: str) -> list[str]:
    chunks = re.split(r"(?<=[\.\!\?])\s+|\n+", text)
    out = []
    for c in chunks:
        c = _clean_line(c)
        if 35 <= len(c) <= 220:
            out.append(c)
    return out


def _extract_title_and_body(md_text: str) -> tuple[str, str]:
    lines = md_text.splitlines()
    title = ""
    for line in lines:
        line = line.strip()
        if line.startswith("# "):
            title = _clean_line(line[2:])
            break

    if "\n---\n" in md_text:
        body = md_text.split("\n---\n", 1)[1]
    else:
        body = md_text
    return title or "Untitled", body


def _build_source_docs(root: Path, manifest_sources: list[dict[str, Any]]) -> list[SourceDoc]:
    docs: list[SourceDoc] = []
    for src in manifest_sources:
        source_key = str(src.get("source_key", "")).strip()
        file_path = str(src.get("file_path", "")).strip()
        language = str(src.get("language", "other")).strip()
        domain = str(src.get("domain", "unknown")).strip()
        if not source_key or not file_path:
            continue
        if language not in ALLOWED_LANG:
            language = "other"

        full_path = _resolve_source_file(root, file_path)
        if not full_path.exists():
            continue

        text = full_path.read_text(encoding="utf-8", errors="ignore")
        title, body = _extract_title_and_body(text)
        snippets = _split_sentences(body)
        if not snippets:
            snippets = [_clean_line(body[:180] or title)]

        docs.append(
            SourceDoc(
                source_key=source_key,
                file_path=file_path,
                language=language,
                domain=domain,
                title=title,
                snippets=snippets[:8],
            )
        )
    return docs


def _pick_distractor(doc: SourceDoc, docs: list[SourceDoc], rng: random.Random) -> SourceDoc:
    same_lang = [d for d in docs if d.language == doc.language and d.source_key != doc.source_key]
    if not same_lang:
        same_lang = [d for d in docs if d.source_key != doc.source_key]
    if not same_lang:
        return doc

    diff_domain = [d for d in same_lang if d.domain != doc.domain]
    pool = diff_domain or same_lang
    return rng.choice(pool)


def _make_positive_query(doc: SourceDoc, snippet: str, idx: int) -> str:
    if doc.language == "ko":
        if idx % 2 == 0:
            return f"{doc.title}의 핵심 개념과 주요 특징을 설명해줘"
        return snippet[:120]
    if doc.language == "en":
        if idx % 2 == 0:
            return f"What are the key concepts and features of {doc.title}?"
        return snippet[:120]
    return snippet[:120]


def _make_paraphrase_query(doc: SourceDoc) -> str:
    if doc.language == "ko":
        return f"{doc.title} 문서의 핵심 내용을 한 문단으로 요약해줘"
    if doc.language == "en":
        return f"Summarize the core idea of {doc.title} in one short paragraph."
    return f"Summarize {doc.title}."


def _make_noise_query(base_query: str) -> str:
    q = base_query.lower()
    q = re.sub(r"[aeiou]", "", q)
    q = re.sub(r"\s+", "", q)
    return (q[:24] + " ???") if len(q) > 24 else (q + " ???")


def _build_eval_rows(
    docs: list[SourceDoc],
    *,
    dataset_id: str,
    schema_version: int,
    total: int,
    rng: random.Random,
) -> list[dict[str, Any]]:
    if not docs:
        return []

    n_pos = round(total * 0.55)
    n_hard = round(total * 0.25)
    n_para = round(total * 0.10)
    n_noise = max(total - n_pos - n_hard - n_para, 0)

    rows: list[dict[str, Any]] = []
    today = date.today().isoformat()
    seq = 1

    def next_id(prefix: str) -> str:
        nonlocal seq
        item = f"seed-{prefix}-{seq:05d}"
        seq += 1
        return item

    # Positive pool: rotate across docs and snippets.
    pos_candidates: list[tuple[SourceDoc, str]] = []
    for d in docs:
        for i, s in enumerate(d.snippets[:3], start=1):
            pos_candidates.append((d, _make_positive_query(d, s, i)))
    rng.shuffle(pos_candidates)
    if not pos_candidates:
        return rows

    for i in range(n_pos):
        d, q = pos_candidates[i % len(pos_candidates)]
        rows.append(
            {
                "dataset_id": dataset_id,
                "schema_version": schema_version,
                "item_id": next_id("pos"),
                "query": q,
                "language": d.language,
                "query_type": "positive",
                "expected_source_key": d.source_key,
                "hard_negative_source_keys": [],
                "tags": ["seed", d.language, d.domain, "positive"],
                "collected_at": today,
            }
        )

    # Hard negative: target + distractor mixed terms.
    for i in range(n_hard):
        d, q = pos_candidates[i % len(pos_candidates)]
        dis = _pick_distractor(d, docs, rng)
        if d.language == "ko":
            query = f"{q[:90]} {dis.title[:28]}"
        elif d.language == "en":
            query = f"{q[:90]} with reference to {dis.title[:28]}"
        else:
            query = f"{q[:100]} {dis.title[:20]}"
        rows.append(
            {
                "dataset_id": dataset_id,
                "schema_version": schema_version,
                "item_id": next_id("hard"),
                "query": query.strip(),
                "language": d.language,
                "query_type": "hard_negative",
                "expected_source_key": d.source_key,
                "hard_negative_source_keys": [dis.source_key],
                "tags": ["seed", d.language, d.domain, "hard-negative"],
                "collected_at": today,
            }
        )

    # Paraphrase.
    for i in range(n_para):
        d = docs[i % len(docs)]
        rows.append(
            {
                "dataset_id": dataset_id,
                "schema_version": schema_version,
                "item_id": next_id("para"),
                "query": _make_paraphrase_query(d),
                "language": d.language,
                "query_type": "paraphrase",
                "expected_source_key": d.source_key,
                "hard_negative_source_keys": [],
                "tags": ["seed", d.language, d.domain, "paraphrase"],
                "collected_at": today,
            }
        )

    # Noise.
    for i in range(n_noise):
        d, q = pos_candidates[i % len(pos_candidates)]
        rows.append(
            {
                "dataset_id": dataset_id,
                "schema_version": schema_version,
                "item_id": next_id("noise"),
                "query": _make_noise_query(q),
                "language": d.language,
                "query_type": "noise",
                "expected_source_key": d.source_key,
                "hard_negative_source_keys": [],
                "tags": ["seed", d.language, d.domain, "noise"],
                "collected_at": today,
            }
        )

    return rows


def _build_chunk_gold_rows(
    eval_rows: list[dict[str, Any]],
    source_by_key: dict[str, SourceDoc],
    *,
    max_rows: int,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    today = date.today().isoformat()

    for i, ev in enumerate(eval_rows[:max_rows], start=1):
        key = str(ev["expected_source_key"])
        src = source_by_key[key]
        passage = src.snippets[0] if src.snippets else src.title
        hard_entries: list[dict[str, str]] = []

        for neg_key in ev.get("hard_negative_source_keys", []):
            neg_src = source_by_key.get(neg_key)
            if not neg_src:
                continue
            neg_passage = neg_src.snippets[0] if neg_src.snippets else neg_src.title
            hard_entries.append(
                {
                    "source_key": neg_key,
                    "passage": neg_passage[:200],
                    "reason": "seed auto-generated hard negative",
                }
            )

        rows.append(
            {
                "dataset_id": ev["dataset_id"],
                "schema_version": ev["schema_version"],
                "item_id": f"seed-cg-{i:05d}",
                "query": ev["query"],
                "language": ev["language"],
                "query_type": ev["query_type"],
                "gold_source_key": key,
                "gold_chunk_id": f"{key}#seed-001",
                "gold_passage": passage[:220],
                "gold_span_start": 0,
                "gold_span_end": min(len(passage), 220),
                "hard_negative_passages": hard_entries,
                "tags": ["seed", "chunk-gold", ev["query_type"]],
                "collected_at": today,
            }
        )
    return rows


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate seed evalset/chunk-gold from manifest")
    p.add_argument("--manifest", required=True, help="Path to sources_manifest.json")
    p.add_argument("--out-evalset", required=True, help="Output evalset JSONL path")
    p.add_argument("--out-chunk-gold", default="", help="Output chunk gold JSONL path (optional)")
    p.add_argument("--total", type=int, default=800, help="Total eval rows to generate")
    p.add_argument("--chunk-gold-max", type=int, default=400, help="Chunk gold max rows")
    p.add_argument("--seed", type=int, default=42, help="Random seed")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    rng = random.Random(args.seed)

    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = (root / manifest_path).resolve()

    dataset_id, schema_version, manifest_sources = _load_manifest(manifest_path)
    docs = _build_source_docs(root, manifest_sources)
    if not docs:
        raise SystemExit("No valid sources found from manifest")

    eval_rows = _build_eval_rows(
        docs,
        dataset_id=dataset_id,
        schema_version=schema_version,
        total=max(args.total, 1),
        rng=rng,
    )
    out_evalset = Path(args.out_evalset)
    if not out_evalset.is_absolute():
        out_evalset = (root / out_evalset).resolve()
    _write_jsonl(out_evalset, eval_rows)

    source_by_key = {d.source_key: d for d in docs}
    chunk_rows = []
    if args.out_chunk_gold:
        chunk_rows = _build_chunk_gold_rows(
            eval_rows, source_by_key, max_rows=max(args.chunk_gold_max, 1)
        )
        out_chunk = Path(args.out_chunk_gold)
        if not out_chunk.is_absolute():
            out_chunk = (root / out_chunk).resolve()
        _write_jsonl(out_chunk, chunk_rows)
    else:
        out_chunk = None

    lang_dist: dict[str, int] = {}
    type_dist: dict[str, int] = {}
    for row in eval_rows:
        lang = row["language"]
        typ = row["query_type"]
        lang_dist[lang] = lang_dist.get(lang, 0) + 1
        type_dist[typ] = type_dist.get(typ, 0) + 1

    print(f"dataset_id={dataset_id}")
    print(f"sources={len(docs)}")
    print(f"eval_rows={len(eval_rows)} type_dist={type_dist} lang_dist={lang_dist}")
    print(f"out_evalset={out_evalset}")
    if out_chunk is not None:
        print(f"chunk_gold_rows={len(chunk_rows)} out_chunk_gold={out_chunk}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
