#!/usr/bin/env bash
# Run the example app's E1 parity test on macOS (docs/milestones.md E1).
#
#   scripts/e1/run_app_parity.sh minilm|koen [OUT_DIR]
#
# Needs the Model Pack in example/assets/models/<model>/ (see its README.md).
# Like scripts/eval/run_passage_eval.sh, it never edits tracked files: it
# copies example/ to build/e1_app_check/, applies the same Xcode 27
# workarounds (linker wrapper, arm64 only, Pod deployment target 14.0), runs
# integration_test/e1_app_docs_parity_test.dart in profile mode with
# --dart-define=EXAMPLE_MODEL=<model>, and copies the result JSON to OUT_DIR
# (default build/eval_results/e1_app_<model>). Compare it with the harness:
#   python3 -I scripts/e1/compare_app_parity.py OUT_DIR/e1_app_parity_<model>.json build/eval_results/e1_<model>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL="${1:?usage: run_app_parity.sh minilm|koen [OUT_DIR]}"
OUT="${2:-$ROOT/build/eval_results/e1_app_$MODEL}"
[[ -f "$ROOT/example/assets/models/$MODEL/model-pack.json" ]] || {
  echo "missing example/assets/models/$MODEL/model-pack.json (see its README.md)" >&2; exit 2; }
WORK="$ROOT/build/e1_app_check"
mkdir -p "$WORK" "$OUT"
rsync -a --delete \
  --exclude build/ --exclude .dart_tool/ --exclude macos/Pods/ \
  --exclude macos/Flutter/ephemeral/ --exclude assets/eval_model/ \
  --exclude assets/mobile_rag/ --exclude assets/koen/ --exclude assets/bgem3/ \
  "$ROOT/example/" "$WORK/"
python3 - "$WORK" "$ROOT" <<'PY'
import pathlib, sys
work, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
p = work / "pubspec.yaml"
s = p.read_text()
s = s.replace("path: ../rust_builder", f"path: {root}/rust_builder").replace("path: ../\n", f"path: {root}/\n")
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
LINKER="$WORK/nofixup-linker.sh"
printf '#!/bin/sh\nexec cc -Wl,-no_fixup_chains "$@"\n' > "$LINKER"; chmod +x "$LINKER"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="$LINKER"
DOCS="$HOME/Library/Containers/com.example.mobileRagEngineExample/Data/Documents"
rm -f "$DOCS/e1_app_parity_$MODEL.json"
START="$(date +%s)"
set +e
(cd "$WORK" && flutter pub get >/dev/null && flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/e1_app_docs_parity_test.dart \
  --profile -d macos --dart-define=EXAMPLE_MODEL="$MODEL") > "$OUT/run.log" 2>&1
RC=$?
set -e
echo "elapsed_seconds=$(( $(date +%s) - START )) exit_code=$RC commit=$(git -C "$ROOT" rev-parse HEAD)" >> "$OUT/run.log"
[[ -f "$DOCS/e1_app_parity_$MODEL.json" ]] && cp "$DOCS/e1_app_parity_$MODEL.json" "$OUT/"
grep -E "E1_APP_PARITY|All tests passed|Some tests failed" "$OUT/run.log" || true
exit "$RC"
