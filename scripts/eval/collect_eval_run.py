#!/usr/bin/env python3
"""Collect one evaluation run into its result directory (docs/milestones.md F1, F-5).

Called by scripts/eval/run_passage_eval.sh. Copies the harness output out of the
app container and records, without manual steps, everything rule 9 of
docs/milestones.md asks for: embedding model name and fingerprint, engine
commit, build mode and Rust features, device, OS and toolchain versions,
dataset, chunk count, time, and the machine load at the end of the run.

Writes <out>/run_meta.json, <out>/passage_result.json (harness JSON with
"run_meta" added), <out>/passage_result.csv, <out>/ask_condition.json, and
<out>/summary.txt. With --dump-candidates also <out>/candidates.json and
<out>/index.sqlite (a copy of the index DB).
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


def sh(*cmd: str, cwd: str | None = None) -> str:
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False).stdout.strip()
    except FileNotFoundError:
        return ""


def sha256(path: Path) -> str | None:
    if not path.is_file():
        return None
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def rust_features(root: Path) -> dict[str, str]:
    # rust_builder/rust/cargokit.yaml: cargo.<profile>.extra_flags = [--features, a,b]
    text = (root / "rust_builder/rust/cargokit.yaml").read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for profile in ("profile", "release"):
        m = re.search(rf"^  {profile}:\n    extra_flags:\n      - --features\n      - (\S+)", text, re.M)
        if m:
            out[profile] = m.group(1)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    for name in ("root", "log", "docs", "out", "model-dir", "model-name", "bundle",
                 "manifest", "evalset", "gold", "no-answer", "exit-code", "elapsed"):
        ap.add_argument(f"--{name}", default="")
    a = ap.parse_args()
    root, out, docs = Path(a.root), Path(a.out), Path(a.docs)
    log = Path(a.log).read_text(encoding="utf-8", errors="replace").replace("\r", "\n")

    files = {}
    m = re.search(r"HYBRID_PASSAGE_RELEVANCE_EXPORT_FILE (\S+\.json) (\S+\.csv)", log)
    if m:
        files["passage_result.json"], files["passage_result.csv"] = Path(m.group(1)), Path(m.group(2))
    m = re.search(r"F3_ASK_FILE (\S+\.json)", log)
    if m:
        files["ask_condition.json"] = Path(m.group(1))
    m = re.search(r"F7_CANDIDATES_FILE (\S+\.json)", log)
    if m:
        files["candidates.json"] = Path(m.group(1))
    m = re.search(r"PASSAGE_SUMMARY chunks=(\d+) fp=(\S+)", log)
    chunks, fingerprint = (int(m.group(1)), m.group(2)) if m else (None, None)

    flutter = sh("flutter", "--version", "--machine")
    try:
        flutter_info = json.loads(flutter[flutter.index("{"):]) if "{" in flutter else {}
    except ValueError:
        flutter_info = {}
    model_dir = Path(a.model_dir)
    pack = model_dir / "model-pack.json"
    example = root / "example"
    # `flutter drive` can exit 0 after the test itself failed (for example on
    # its time limit); count the run as failed then.
    test_failed = "Some tests failed" in log or "PASSAGE_SUMMARY chunks=" not in log
    meta = {
        "schema": "f1_eval_run_meta_v1",
        "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "exit_code": int(a.exit_code or 0) or (1 if test_failed else 0),
        "test_failed": test_failed,
        "elapsed_seconds": int(a.elapsed or 0),
        "model": {
            "name": a.model_name,
            "embedding_fingerprint": fingerprint,
            "model_onnx_sha256": sha256(model_dir / "model.onnx"),
            "tokenizer_json_sha256": sha256(model_dir / "tokenizer.json"),
            "model_pack": json.loads(pack.read_text()) if pack.is_file() else None,
        },
        "engine": {
            "commit": sh("git", "rev-parse", "HEAD", cwd=str(root)),
            "branch": sh("git", "rev-parse", "--abbrev-ref", "HEAD", cwd=str(root)),
            # sh() strips the output, which would eat the first line's leading
            # status column; split on whitespace instead of slicing.
            "dirty_tracked_files": [l.split(None, 1)[1] for l in sh("git", "status", "--porcelain", "--untracked-files=no", cwd=str(root)).splitlines() if l.strip()],
            "build_mode": "profile",
            "rust_features": rust_features(root),
        },
        "device": {
            "cpu": sh("sysctl", "-n", "machdep.cpu.brand_string"),
            "macos": sh("sw_vers", "-productVersion"),
            "load_average_at_end": sh("sysctl", "-n", "vm.loadavg"),
        },
        "toolchain": {
            "xcode": sh("xcodebuild", "-version").replace("\n", " "),
            "flutter": flutter_info.get("frameworkVersion"),
            "dart": flutter_info.get("dartSdkVersion"),
            "rustc": sh("rustc", "--version"),
            "xcode27_workarounds": ["linker -Wl,-no_fixup_chains", "ARCHS = arm64", "Pod MACOSX_DEPLOYMENT_TARGET 14.0"],
        },
        "dataset": {
            "bundle": a.bundle,
            "manifest": a.manifest,
            "evalset": a.evalset,
            "gold": a.gold,
            "no_answer": a.no_answer or None,
            "sha256": {
                k: sha256(example / v) for k, v in
                (("manifest", a.manifest), ("evalset", a.evalset), ("gold", a.gold), ("no_answer", a.no_answer)) if v
            },
            "chunk_count": chunks,
        },
    }

    out.mkdir(parents=True, exist_ok=True)
    for name, src in files.items():
        dst = out / name
        if src.is_file():
            shutil.copyfile(src, dst)
            if name.endswith(".json"):
                obj = json.loads(dst.read_text(encoding="utf-8"))
                obj["run_meta"] = meta
                dst.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if (out / "candidates.json").is_file():
        # A consistent single-file copy of the index DB (chunk text and
        # embeddings) for the offline fusion comparison.
        import sqlite3
        cand = json.loads((out / "candidates.json").read_text(encoding="utf-8"))
        src = sqlite3.connect(f"file:{cand['db_path']}?mode=ro", uri=True)
        dst = sqlite3.connect(str(out / "index.sqlite"))
        src.backup(dst)
        dst.close()
        src.close()
    meta["result_files"] = sorted(p.name for p in out.iterdir() if p.name != "run.log")
    (out / "run_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [l.split("flutter: ", 1)[-1] for l in log.splitlines() if "PASSAGE_SUMMARY" in l or "F3_ASK profile" in l or "F2_INIT_WEIGHTS" in l]
    seen, summary = set(), []
    for l in lines:
        if l not in seen:
            seen.add(l)
            summary.append(l)
    head = (f"model={a.model_name} fp={fingerprint} chunks={chunks} bundle={a.bundle} "
            f"commit={meta['engine']['commit'][:7]} exit={meta['exit_code']} secs={meta['elapsed_seconds']}")
    (out / "summary.txt").write_text(head + "\n" + "\n".join(summary) + "\n", encoding="utf-8")
    print(head)
    print("\n".join(summary))
    print(f"[eval] results in {out}")
    return meta["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
