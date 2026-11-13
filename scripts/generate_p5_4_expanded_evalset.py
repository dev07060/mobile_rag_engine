#!/usr/bin/env python3
"""Generate the P5-4 balanced 80-item passage relevance evalset.

The source material already exists in the repo's local wiki corpus fixtures.
This script creates a deterministic, smaller benchmark that is broad enough to
stress generalization while still practical for profile-mode macOS runs.
"""

from __future__ import annotations

import collections
import json
import re
from pathlib import Path
from typing import Any


RAW_MANIFEST = Path("example/assets/evalsets/templates/sources_manifest.json")
RAW_EVALSET = Path("example/assets/evalsets/templates/wiki_article_evalset_seed_v1.jsonl")
RAW_CHUNK_GOLD = Path(
    "example/assets/evalsets/templates/wiki_article_chunk_gold_seed_v1.jsonl"
)

OUT_MANIFEST = Path(
    "example/assets/evalsets/wiki_article_sources_manifest_80_balanced_v1.json"
)
OUT_EVALSET = Path("example/assets/evalsets/hybrid_relevance_seed_80_balanced_v1.jsonl")
OUT_CHUNK_GOLD = Path(
    "example/assets/evalsets/hybrid_passage_gold_80_balanced_v1.jsonl"
)

DATASET_ID = "wiki_article_corpus_80_balanced_v1"
COLLECTED_AT = "2026-06-13"
CLASSES = [
    "lexical",
    "semantic",
    "mixed",
    "hard_negative",
    "multilingual",
    "lexical",
    "semantic",
    "mixed",
    "hard_negative",
    "multilingual",
]
LANGUAGES = ["ko", "en"]
DOMAINS = ["tech", "finance", "policy", "support"]


def main() -> int:
    manifest = json.loads(RAW_MANIFEST.read_text(encoding="utf-8"))
    eval_items = _read_jsonl(RAW_EVALSET)
    gold_items = _read_jsonl(RAW_CHUNK_GOLD)
    source_by_key = {source["source_key"]: source for source in manifest["sources"]}

    pairs = _matched_pairs(eval_items, gold_items, source_by_key)
    selected = _select_balanced_sources(pairs)
    selected_source_keys = {pair["source"]["source_key"] for pair in selected}
    selected_sources = [
        source
        for source in manifest["sources"]
        if source["source_key"] in selected_source_keys
    ]
    source_order = {source["source_key"]: i for i, source in enumerate(selected_sources)}
    selected.sort(key=lambda pair: source_order[pair["source"]["source_key"]])

    by_lang_domain: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for pair in selected:
        by_lang_domain[(pair["source"]["language"], pair["source"]["domain"])].append(pair)

    eval_out: list[dict[str, Any]] = []
    gold_out: list[dict[str, Any]] = []
    serial = 1
    for lang in LANGUAGES:
        for domain in DOMAINS:
            bucket = by_lang_domain[(lang, domain)]
            if len(bucket) != 10:
                raise SystemExit(f"expected 10 selected pairs for {(lang, domain)}, got {len(bucket)}")
            for index, pair in enumerate(bucket):
                item_class = CLASSES[index]
                hard_pair = bucket[(index + 1) % len(bucket)]
                item_id = f"p5-expanded-{serial:04d}"
                query, query_language, query_type = _build_query(
                    item_class=item_class,
                    source=pair["source"],
                    hard_source=hard_pair["source"],
                    gold_passage=pair["gold"]["gold_passage"],
                )
                tags = [
                    "p5-4",
                    "expanded",
                    f"class:{item_class}",
                    query_language,
                    domain,
                    f"source-lang:{lang}",
                ]
                eval_out.append(
                    {
                        "dataset_id": DATASET_ID,
                        "schema_version": 1,
                        "item_id": item_id,
                        "query": query,
                        "language": query_language,
                        "query_type": query_type,
                        "expected_source_key": pair["source"]["source_key"],
                        "hard_negative_source_keys": [hard_pair["source"]["source_key"]],
                        "tags": tags,
                        "collected_at": COLLECTED_AT,
                    }
                )
                gold_out.append(
                    {
                        "dataset_id": DATASET_ID,
                        "schema_version": 1,
                        "item_id": item_id,
                        "query": query,
                        "language": query_language,
                        "query_type": query_type,
                        "gold_source_key": pair["source"]["source_key"],
                        "gold_chunk_id": f"{pair['source']['source_key']}#p5-4-gold",
                        "gold_passage": pair["gold"]["gold_passage"],
                        "gold_span_start": pair["gold"].get("gold_span_start", 0),
                        "gold_span_end": pair["gold"].get(
                            "gold_span_end", len(pair["gold"]["gold_passage"])
                        ),
                        "hard_negative_passages": [
                            {
                                "source_key": hard_pair["source"]["source_key"],
                                "passage": _first_paragraph(hard_pair["source"]),
                                "reason": "same language/domain distractor selected for P5-4 balanced subset",
                            }
                        ],
                        "tags": tags + ["chunk-gold"],
                        "collected_at": COLLECTED_AT,
                    }
                )
                serial += 1

    output_manifest = {
        "dataset_id": DATASET_ID,
        "schema_version": 1,
        "selection": {
            "source": str(RAW_MANIFEST),
            "evalset": str(RAW_EVALSET),
            "chunk_gold": str(RAW_CHUNK_GOLD),
            "rule": "10 unique sources for each language/domain bucket; 80 sources total",
            "classes_per_bucket": CLASSES,
        },
        "sources": selected_sources,
    }
    OUT_MANIFEST.write_text(
        json.dumps(output_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    _write_jsonl(OUT_EVALSET, eval_out)
    _write_jsonl(OUT_CHUNK_GOLD, gold_out)

    print("P5_4_EXPANDED_EVALSET_OK")
    print(f"manifest={OUT_MANIFEST} sources={len(selected_sources)}")
    print(f"evalset={OUT_EVALSET} items={len(eval_out)}")
    print(f"chunk_gold={OUT_CHUNK_GOLD} items={len(gold_out)}")
    print("query_language", dict(collections.Counter(item["language"] for item in eval_out)))
    print(
        "source_language",
        dict(collections.Counter(source["language"] for source in selected_sources)),
    )
    print("domain", dict(collections.Counter(source["domain"] for source in selected_sources)))
    print(
        "query_class",
        dict(collections.Counter(_query_class(item) for item in eval_out)),
    )
    return 0


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in rows),
        encoding="utf-8",
    )


def _matched_pairs(
    eval_items: list[dict[str, Any]],
    gold_items: list[dict[str, Any]],
    source_by_key: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    pairs: list[dict[str, Any]] = []
    for eval_item, gold_item in zip(eval_items, gold_items):
        expected = eval_item["expected_source_key"]
        if eval_item["query"] != gold_item["query"]:
            continue
        if expected != gold_item["gold_source_key"]:
            continue
        source = source_by_key[expected]
        file_path = Path("example") / source["file_path"]
        if not file_path.exists():
            continue
        pairs.append({"eval": eval_item, "gold": gold_item, "source": source})
    return pairs


def _select_balanced_sources(pairs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for lang in LANGUAGES:
        for domain in DOMAINS:
            bucket = [
                pair
                for pair in pairs
                if pair["source"]["language"] == lang and pair["source"]["domain"] == domain
            ]
            seen_sources: set[str] = set()
            bucket_selected: list[dict[str, Any]] = []
            for pair in bucket:
                source_key = pair["source"]["source_key"]
                if source_key in seen_sources:
                    continue
                seen_sources.add(source_key)
                bucket_selected.append(pair)
                if len(bucket_selected) == 10:
                    break
            if len(bucket_selected) != 10:
                raise SystemExit(
                    f"not enough unique sources for {(lang, domain)}: {len(bucket_selected)}"
                )
            selected.extend(bucket_selected)
    return selected


def _build_query(
    *,
    item_class: str,
    source: dict[str, Any],
    hard_source: dict[str, Any],
    gold_passage: str,
) -> tuple[str, str, str]:
    lang = source["language"]
    title = _title(source)
    hard_title = _title(hard_source)
    terms = _terms(gold_passage, lang=lang)
    term_text = " ".join(terms[:8])
    if item_class == "lexical":
        return term_text, lang, "positive"
    if item_class == "semantic":
        if lang == "ko":
            return f"{title}의 핵심 개념과 주요 특징을 설명해줘", lang, "paraphrase"
        return f"What are the key concepts and features of {title}?", lang, "paraphrase"
    if item_class == "mixed":
        if lang == "ko":
            return f"{title} 관련 passage를 찾아줘: {term_text}", lang, "positive"
        return f"Find the {title} passage with these terms: {term_text}", lang, "positive"
    if item_class == "hard_negative":
        if lang == "ko":
            return (
                f"{title} 내용을 찾되 {hard_title} 주제와 혼동하지 말고 "
                f"{term_text} 관련 근거를 찾아줘",
                lang,
                "hard_negative",
            )
        return (
            f"Find evidence about {title}, not {hard_title}, using terms {term_text}",
            lang,
            "hard_negative",
        )
    if item_class == "multilingual":
        if lang == "ko":
            return f"Explain in English the key evidence for {title}: {term_text}", "other", "paraphrase"
        return f"{title}의 핵심 근거를 한국어 질문으로 찾아줘: {term_text}", "other", "paraphrase"
    raise AssertionError(f"unknown item_class {item_class}")


def _terms(text: str, *, lang: str) -> list[str]:
    tokens = re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}|[가-힣]{2,}", text)
    stop = {
        "the",
        "and",
        "for",
        "with",
        "from",
        "that",
        "this",
        "are",
        "was",
        "were",
        "또는",
        "그리고",
        "대한",
        "있는",
        "한다",
    }
    result: list[str] = []
    seen: set[str] = set()
    for token in tokens:
        key = token.lower()
        if key in stop or key in seen:
            continue
        seen.add(key)
        result.append(token)
    if result:
        return result
    return [text[:80]]


def _title(source: dict[str, Any]) -> str:
    file_path = Path("example") / source["file_path"]
    for line in file_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        stripped = line.strip().lstrip("#").strip()
        if stripped:
            return stripped[:80]
    return Path(source["file_path"]).stem.replace("_", " ")[:80]


def _first_paragraph(source: dict[str, Any]) -> str:
    file_path = Path("example") / source["file_path"]
    paragraphs = []
    current: list[str] = []
    for line in file_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        stripped = line.strip()
        if not stripped:
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        if stripped.startswith("#"):
            continue
        current.append(stripped)
        if len(" ".join(current)) >= 120:
            break
    if current:
        paragraphs.append(" ".join(current))
    for paragraph in paragraphs:
        if len(paragraph) >= 40:
            return paragraph[:400]
    return _title(source)


def _query_class(item: dict[str, Any]) -> str:
    for tag in item["tags"]:
        if tag.startswith("class:"):
            return tag.split(":", 1)[1]
    return item["query_type"]


if __name__ == "__main__":
    raise SystemExit(main())
