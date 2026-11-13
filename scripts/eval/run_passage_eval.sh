#!/usr/bin/env bash
# One-command search evaluation on macOS (docs/milestones.md F1, F-4/F-5).
#
#   scripts/eval/run_passage_eval.sh --model DIR [--bundle 80|f1] [--name NAME] [--out DIR]
#   scripts/eval/run_passage_eval.sh --model-pack PRESET [--bundle 80|f1] ...
#
# --model DIR         a directory with model.onnx and tokenizer.json (models are
#                     never committed; pass a path)
# --model-pack PRESET download a Model Pack with `dart run mobile_rag_engine:setup`
#                     (e.g. stable-minilm-l6-v2-arm64-en)
# --bundle            80 = 80-query regression bundle (default), f1 = F1 bundle
# --name              label used in file names (default: model directory name)
# --out               result directory (default: build/eval_results/<time>_<name>_<bundle>)
# --dump-candidates   also dump the engine's vector and BM25 candidate lists and a
#                     copy of the index DB for scripts/eval/f7_fusion_compare.py
#
# The script never edits tracked files. It copies example/ to build/eval_app/,
# declares the evaluation assets there, applies the Xcode 27 workarounds
# (linker wrapper, arm64 only, Pod deployment target 14.0), runs the harness
# example/integration_test/hybrid_passage_relevance_measure_test.dart in
# profile mode, and writes the results plus run_meta.json (commit, toolchain,
# device, model fingerprint, chunk count) to the result directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL_DIR="" ; MODEL_PACK="" ; BUNDLE="80" ; NAME="" ; OUT="" ; DUMP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_DIR="$2"; shift 2;;
    --model-pack) MODEL_PACK="$2"; shift 2;;
    --bundle) BUNDLE="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --dump-candidates) DUMP=true; shift;;
    -h|--help) sed -n '2,22p' "$0"; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
if [[ -z "$MODEL_DIR" && -z "$MODEL_PACK" ]] || [[ -n "$MODEL_DIR" && -n "$MODEL_PACK" ]]; then
  echo "pass exactly one of --model DIR or --model-pack PRESET" >&2; exit 2
fi
[[ "$(uname)" == "Darwin" ]] || { echo "macOS only" >&2; exit 2; }

case "$BUNDLE" in
  80)
    MANIFEST=assets/evalsets/wiki_article_sources_manifest_80_balanced_v1.json
    EVALSET=assets/evalsets/hybrid_relevance_seed_80_balanced_v1.jsonl
    GOLD=assets/evalsets/hybrid_passage_gold_80_balanced_v1.jsonl
    NO_ANSWER="";;
  f1)
    MANIFEST=assets/evalsets/f1/f1_sources_manifest_v1.json
    EVALSET=assets/evalsets/f1/f1_evalset_v1.jsonl
    GOLD=assets/evalsets/f1/f1_passage_gold_v1.jsonl
    NO_ANSWER=assets/evalsets/f1/f1_no_answer_v1.jsonl;;
  *) echo "unknown bundle: $BUNDLE (80 or f1)" >&2; exit 2;;
esac

WORK="$ROOT/build/eval_app"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WORK"

echo "[eval] copying example/ to $WORK"
rsync -a --delete \
  --exclude build/ --exclude .dart_tool/ --exclude macos/Pods/ \
  --exclude macos/Flutter/ephemeral/ --exclude assets/eval_model/ \
  --exclude assets/mobile_rag/ --exclude assets/koen/ --exclude assets/bgem3/ \
  "$ROOT/example/" "$WORK/"

# Model files go to assets/eval_model/ inside the copy only.
mkdir -p "$WORK/assets/eval_model"
if [[ -n "$MODEL_PACK" ]]; then
  echo "[eval] downloading Model Pack $MODEL_PACK"
  (cd "$WORK" && flutter pub get >/dev/null && \
    dart run mobile_rag_engine:setup --preset "$MODEL_PACK" --output assets/eval_model --skip-host-config)
  NAME="${NAME:-$MODEL_PACK}"
else
  MODEL_DIR="$(cd "$MODEL_DIR" && pwd)"
  for f in model.onnx tokenizer.json; do
    [[ -f "$MODEL_DIR/$f" ]] || { echo "missing $MODEL_DIR/$f" >&2; exit 2; }
    cp -c "$MODEL_DIR/$f" "$WORK/assets/eval_model/$f" 2>/dev/null || cp "$MODEL_DIR/$f" "$WORK/assets/eval_model/$f"
  done
  rm -f "$WORK/assets/eval_model/model-pack.json"
  [[ -f "$MODEL_DIR/model-pack.json" ]] && cp "$MODEL_DIR/model-pack.json" "$WORK/assets/eval_model/"
  NAME="${NAME:-$(basename "$MODEL_DIR")}"
fi
OUT="${OUT:-$ROOT/build/eval_results/${STAMP}_${NAME}_${BUNDLE}}"
mkdir -p "$OUT"

echo "[eval] patching the copy (asset declarations, Xcode 27 workarounds)"
python3 - "$WORK" "$ROOT" <<'PY'
import pathlib, re, sys
work, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
p = work / "pubspec.yaml"
s = p.read_text()
s = s.replace("path: ../rust_builder", f"path: {root}/rust_builder").replace("path: ../\n", f"path: {root}/\n")
dirs = sorted({str(q.parent.relative_to(work)) + "/" for q in (work / "assets" / "corpus").rglob("*.md")})
dirs += ["assets/evalsets/", "assets/evalsets/f1/", "assets/eval_model/"]
block = "".join(f"    - {d}\n" for d in dirs)
s = s.replace("    - assets/\n", "    - assets/\n" + block, 1)
p.write_text(s)
x = work / "macos/Runner/Configs/Release.xcconfig"
if "ARCHS = arm64" not in x.read_text():
    x.write_text(x.read_text() + "ARCHS = arm64\n")
pod = work / "macos/Podfile"
t = pod.read_text()
if "MACOSX_DEPLOYMENT_TARGET" not in t:
    t = t.replace("    flutter_additional_macos_build_settings(target)\n",
                  "    flutter_additional_macos_build_settings(target)\n"
                  "    target.build_configurations.each do |config|\n"
                  "      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'\n"
                  "    end\n", 1)
    pod.write_text(t)
PY

# Rust proc-macro dylibs built with chained fixups cannot be loaded by rustc
# under Xcode 27's linker; build them without.
LINKER="$WORK/nofixup-linker.sh"
printf '#!/bin/sh\nexec cc -Wl,-no_fixup_chains "$@"\n' > "$LINKER"; chmod +x "$LINKER"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="$LINKER"

DOCS="$HOME/Library/Containers/com.example.mobileRagEngineExample/Data/Documents"
DB="f1eval_${NAME//[^A-Za-z0-9_]/_}_${BUNDLE}.sqlite"
LOG="$OUT/run.log"
START="$(date +%s)"
echo "[eval] flutter drive --profile (log: $LOG)"
set +e
(cd "$WORK" && flutter pub get >/dev/null && flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/hybrid_passage_relevance_measure_test.dart \
  --profile -d macos \
  --dart-define=HYBRID_PASSAGE_MANIFEST_ASSET="$MANIFEST" \
  --dart-define=HYBRID_PASSAGE_SOURCE_EVALSET_ASSET="$EVALSET" \
  --dart-define=HYBRID_PASSAGE_CHUNK_GOLD_ASSET="$GOLD" \
  --dart-define=HYBRID_PASSAGE_DB_NAME="$DB" \
  --dart-define=F1_NO_ANSWER_ASSET="$NO_ANSWER" \
  --dart-define=F7_DUMP_CANDIDATES="$DUMP" \
  --dart-define=EVAL_MODEL_ASSET=assets/eval_model/model.onnx \
  --dart-define=EVAL_TOKENIZER_ASSET=assets/eval_model/tokenizer.json) > "$LOG" 2>&1
RC=$?
set -e
ELAPSED=$(( $(date +%s) - START ))
python3 "$ROOT/scripts/eval/collect_eval_run.py" \
  --root "$ROOT" --log "$LOG" --docs "$DOCS" --out "$OUT" \
  --model-dir "$WORK/assets/eval_model" --model-name "$NAME" --bundle "$BUNDLE" \
  --manifest "$MANIFEST" --evalset "$EVALSET" --gold "$GOLD" --no-answer "$NO_ANSWER" \
  --exit-code "$RC" --elapsed "$ELAPSED"
exit "$RC"
