#!/usr/bin/env python3
"""Validate a source manifest + evalset + optional chunk-gold bundle.

The validator intentionally avoids third-party JSON-schema dependencies so it
can run in a fresh checkout. It checks the invariants the offline/profile
eval runners rely on: required fields, duplicate ids, and source-key
referential integrity.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


VALID_LANGUAGES = {"ko", "en", "other"}
VALID_QUERY_TYPES = {"positive", "hard_negative", "paraphrase", "noise"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--evalset", required=True)
    parser.add_argument("--chunk-gold", default="")
    parser.add_argument(
        "--require-evalset-chunk-gold-join",
        action="store_true",
        help="Require evalset item ids and chunk-gold item ids to match exactly.",
    )
    args = parser.parse_args()

    errors: list[str] = []
    manifest = _load_json(Path(args.manifest), errors, "manifest")
    eval_items = _load_jsonl(Path(args.evalset), errors, "evalset")
    chunk_gold_items = (
        _load_jsonl(Path(args.chunk_gold), errors, "chunk-gold")
        if args.chunk_gold
        else []
    )

    if manifest is None:
        _print_result(errors)
        return 1

    source_keys = _validate_manifest(manifest, errors)
    _validate_evalset(eval_items, source_keys, errors)
    if args.chunk_gold:
        _validate_chunk_gold(chunk_gold_items, source_keys, errors)
    if args.require_evalset_chunk_gold_join:
        _validate_evalset_chunk_gold_join(eval_items, chunk_gold_items, errors)

    _print_result(errors)
    if errors:
        return 1

    print(
        "VALID_EVALSET_BUNDLE "
        f"sources={len(source_keys)} "
        f"eval_items={len(eval_items)} "
        f"chunk_gold_items={len(chunk_gold_items)}"
    )
    return 0


def _load_json(path: Path, errors: list[str], label: str) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - CLI should report any parse/read issue.
        errors.append(f"{label}: failed to read JSON {path}: {exc}")
        return None
    if not isinstance(data, dict):
        errors.append(f"{label}: root must be a JSON object")
        return None
    return data


def _load_jsonl(path: Path, errors: list[str], label: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{label}: failed to read JSONL {path}: {exc}")
        return items

    for line_no, line in enumerate(raw.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            item = json.loads(stripped)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{label}:{line_no}: invalid JSON: {exc}")
            continue
        if not isinstance(item, dict):
            errors.append(f"{label}:{line_no}: line must be a JSON object")
            continue
        items.append(item)
    return items


def _validate_manifest(manifest: dict[str, Any], errors: list[str]) -> set[str]:
    _require_string(manifest, "dataset_id", errors, "manifest")
    _require_int(manifest, "schema_version", errors, "manifest")
    sources = manifest.get("sources")
    if not isinstance(sources, list) or not sources:
        errors.append("manifest: sources must be a non-empty list")
        return set()

    source_keys: set[str] = set()
    for index, source in enumerate(sources):
        ctx = f"manifest.sources[{index}]"
        if not isinstance(source, dict):
            errors.append(f"{ctx}: source must be an object")
            continue
        source_key = _require_string(source, "source_key", errors, ctx)
        _require_string(source, "file_path", errors, ctx)
        language = _require_string(source, "language", errors, ctx)
        if language and language not in VALID_LANGUAGES:
            errors.append(f"{ctx}: unsupported language {language!r}")
        if source_key:
            if source_key in source_keys:
                errors.append(f"{ctx}: duplicate source_key {source_key!r}")
            source_keys.add(source_key)
    return source_keys


def _validate_evalset(
    items: list[dict[str, Any]],
    source_keys: set[str],
    errors: list[str],
) -> None:
    item_ids: set[str] = set()
    for index, item in enumerate(items):
        ctx = f"evalset[{index}]"
        item_id = _require_string(item, "item_id", errors, ctx)
        _require_string(item, "dataset_id", errors, ctx)
        _require_int(item, "schema_version", errors, ctx)
        _require_string(item, "query", errors, ctx)
        language = _require_string(item, "language", errors, ctx)
        query_type = _require_string(item, "query_type", errors, ctx)
        expected = _require_string(item, "expected_source_key", errors, ctx)
        if item_id:
            if item_id in item_ids:
                errors.append(f"{ctx}: duplicate item_id {item_id!r}")
            item_ids.add(item_id)
        if language and language not in VALID_LANGUAGES:
            errors.append(f"{ctx}: unsupported language {language!r}")
        if query_type and query_type not in VALID_QUERY_TYPES:
            errors.append(f"{ctx}: unsupported query_type {query_type!r}")
        if expected and expected not in source_keys:
            errors.append(f"{ctx}: unknown expected_source_key {expected!r}")

        hard_keys = item.get("hard_negative_source_keys")
        if not isinstance(hard_keys, list):
            errors.append(f"{ctx}: hard_negative_source_keys must be a list")
            continue
        for key in hard_keys:
            if not isinstance(key, str) or not key:
                errors.append(f"{ctx}: hard_negative_source_keys entries must be strings")
            elif key not in source_keys:
                errors.append(f"{ctx}: unknown hard_negative_source_key {key!r}")


def _validate_chunk_gold(
    items: list[dict[str, Any]],
    source_keys: set[str],
    errors: list[str],
) -> None:
    item_ids: set[str] = set()
    for index, item in enumerate(items):
        ctx = f"chunk_gold[{index}]"
        item_id = _require_string(item, "item_id", errors, ctx)
        _require_string(item, "dataset_id", errors, ctx)
        _require_int(item, "schema_version", errors, ctx)
        _require_string(item, "query", errors, ctx)
        _require_string(item, "gold_passage", errors, ctx)
        language = _require_string(item, "language", errors, ctx)
        query_type = _require_string(item, "query_type", errors, ctx)
        gold_source = _require_string(item, "gold_source_key", errors, ctx)
        if item_id:
            if item_id in item_ids:
                errors.append(f"{ctx}: duplicate item_id {item_id!r}")
            item_ids.add(item_id)
        if language and language not in VALID_LANGUAGES:
            errors.append(f"{ctx}: unsupported language {language!r}")
        if query_type and query_type not in VALID_QUERY_TYPES:
            errors.append(f"{ctx}: unsupported query_type {query_type!r}")
        if gold_source and gold_source not in source_keys:
            errors.append(f"{ctx}: unknown gold_source_key {gold_source!r}")

        for hn_index, hard in enumerate(item.get("hard_negative_passages") or []):
            hn_ctx = f"{ctx}.hard_negative_passages[{hn_index}]"
            if not isinstance(hard, dict):
                errors.append(f"{hn_ctx}: entry must be an object")
                continue
            source_key = _require_string(hard, "source_key", errors, hn_ctx)
            _require_string(hard, "passage", errors, hn_ctx)
            if source_key and source_key not in source_keys:
                errors.append(f"{hn_ctx}: unknown source_key {source_key!r}")


def _validate_evalset_chunk_gold_join(
    eval_items: list[dict[str, Any]],
    chunk_gold_items: list[dict[str, Any]],
    errors: list[str],
) -> None:
    eval_by_id = {item.get("item_id"): item for item in eval_items}
    gold_by_id = {item.get("item_id"): item for item in chunk_gold_items}

    if len(eval_by_id) != len(eval_items):
        errors.append("chunk-gold join: evalset has duplicate item ids")
    if len(gold_by_id) != len(chunk_gold_items):
        errors.append("chunk-gold join: chunk-gold has duplicate item ids")

    if set(eval_by_id) != set(gold_by_id):
        missing_gold = sorted(set(eval_by_id) - set(gold_by_id))
        extra_gold = sorted(set(gold_by_id) - set(eval_by_id))
        if missing_gold:
            errors.append(f"chunk-gold join: missing item ids {missing_gold!r}")
        if extra_gold:
            errors.append(f"chunk-gold join: extra item ids {extra_gold!r}")

    for item_id in sorted(set(eval_by_id) & set(gold_by_id)):
        expected = eval_by_id[item_id].get("expected_source_key")
        gold_source = gold_by_id[item_id].get("gold_source_key")
        if expected != gold_source:
            errors.append(
                "chunk-gold join: item "
                f"{item_id!r} expected_source_key {expected!r} "
                f"does not match gold_source_key {gold_source!r}"
            )


def _require_string(
    obj: dict[str, Any],
    key: str,
    errors: list[str],
    ctx: str,
) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or not value:
        errors.append(f"{ctx}: {key} must be a non-empty string")
        return ""
    return value


def _require_int(obj: dict[str, Any], key: str, errors: list[str], ctx: str) -> int:
    value = obj.get(key)
    if not isinstance(value, int):
        errors.append(f"{ctx}: {key} must be an integer")
        return 0
    return value


def _print_result(errors: list[str]) -> None:
    for error in errors:
        print(f"ERROR {error}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
