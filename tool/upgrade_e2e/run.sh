#!/usr/bin/env bash
# Upgrade harness (milestone H1, docs/milestones.md), macOS only.
#
# Creates a fresh Flutter app, indexes a corpus with mobile_rag_engine
# $H1_BASE_VERSION from pub.dev (phase A), then switches the same app, and so
# the same data container, to the package under test and runs it again
# (phase B). Each phase B process prints H1_CHECK lines; this script compares
# them with $H1_KNOWN_FAILING:
#   PASS                      ok
#   FAIL, listed as known     ok, reported as reproduced
#   FAIL, not listed          job fails
#   PASS, listed as known     job fails: the fix landed, remove it from the list
#   missing                   job fails (the process crashed before reporting)
#
# Usage: tool/upgrade_e2e/run.sh <work dir>
# Environment:
#   H1_PACKAGE        git (default) or path
#   H1_GIT_URL, H1_GIT_REF   package under test for git mode
#   H1_PATH           repository root for path mode
#   H1_BASE_VERSION   last published release (default 0.22.3)
#   H1_KNOWN_FAILING  space-separated check ids expected to fail
#   H1_SUMMARY        file to append the Markdown summary to (optional)
set -euo pipefail

work=$(mkdir -p "$1" && cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
package=${H1_PACKAGE:-git}
base_version=${H1_BASE_VERSION:-0.22.3}
known=" ${H1_KNOWN_FAILING:-} "
summary=${H1_SUMMARY:-/dev/null}
app="$work/app"
logs="$work/logs"
bundle_id=com.example.h1UpgradeApp

koen_revision=5cf599a8cd6577f2f12a026130ad50132e472cfd
koen_base=https://huggingface.co/exp-models/dragonkue-KoEn-E5-Tiny-ONNX/resolve/$koen_revision
koen_model_sha=d463c9b1c29f3202d510e2836265d60f9e6e6dd518c5930ba865700646489bd4
koen_tokenizer_sha=a6dd38d692ac1caa6d5dbc195d92f1f978b5c74ec60e02ed15fdf04404742fe3

phase_a_scenarios="s1 s2 s3 s4"
phase_b_scenarios="p0 s1 s2 s3 s4 contract"
expected_checks="p0 s1 s2 s3 s4 b1 b2 b3 b4"

rm -rf "$app" "$logs"
mkdir -p "$logs"

echo "== Create the app with mobile_rag_engine $base_version"
(cd "$work" && flutter create --platforms=macos --project-name h1_upgrade_app app > "$logs/create.log")
cd "$app"
flutter pub add "mobile_rag_engine:$base_version" path_provider 'dev:integration_test:{"sdk":"flutter"}' > "$logs/pub_a.log"
dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en >> "$logs/pub_a.log"

echo "== Add KoEn-E5-Tiny as a second 384-dim model.onnx"
koen="$app/assets/h1/koen"
mkdir -p "$koen"
curl -sSfL -o "$koen/model.onnx" "$koen_base/onnx/model_qint8_arm64.onnx"
curl -sSfL -o "$koen/tokenizer.json" "$koen_base/tokenizer.json"
echo "$koen_model_sha  $koen/model.onnx" | shasum -a 256 -c -
echo "$koen_tokenizer_sha  $koen/tokenizer.json" | shasum -a 256 -c -
cat > "$koen/model-pack.json" <<EOF
{
  "schemaVersion": 1,
  "preset": "h1-koen-e5-tiny-arm64",
  "modelId": "exp-models/dragonkue-KoEn-E5-Tiny-ONNX",
  "revision": "$koen_revision",
  "modelAsset": "assets/h1/koen/model.onnx",
  "tokenizerAsset": "assets/h1/koen/tokenizer.json",
  "modelSha256": "$koen_model_sha",
  "tokenizerSha256": "$koen_tokenizer_sha",
  "modelBytes": $(wc -c < "$koen/model.onnx" | tr -d ' '),
  "tokenizerBytes": $(wc -c < "$koen/tokenizer.json" | tr -d ' '),
  "architecture": "arm64",
  "embeddingDimension": 384,
  "license": "apache-2.0",
  "language": "Korean, English"
}
EOF
perl -0pi -e 's/^flutter:\n/flutter:\n  assets:\n    - assets\/mobile_rag\/\n    - assets\/h1\/koen\/\n/m' pubspec.yaml
grep -q "^    - assets/h1/koen/" pubspec.yaml

# Local runs only: newer Xcode releases reject the pods' 10.15 deployment
# target. CI leaves this unset so the generated host project stays as is.
if [ -n "${H1_PODS_DEPLOYMENT_TARGET:-}" ]; then
  perl -pi -e "s/^(\s*)flutter_additional_macos_build_settings\(target\)\n/\$1flutter_additional_macos_build_settings(target)\n\$1target.build_configurations.each { |c| c.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '$H1_PODS_DEPLOYMENT_TARGET' }\n/" macos/Podfile
  grep -q "MACOSX_DEPLOYMENT_TARGET" macos/Podfile
fi

# The sandboxed app keeps its documents here; start from an empty container.
rm -rf "$HOME/Library/Containers/$bundle_id"

run_phase() {
  local phase=$1 test=$2 id=$3
  local log="$logs/${phase}_$id.log"
  echo "== Phase $phase: $id"
  set +e
  flutter test "integration_test/$test" -d macos -r expanded \
    --dart-define=H1_SCENARIO="$id" > "$log" 2>&1
  local status=$?
  set -e
  grep -hE "^(flutter: )?H1_(CHECK|PHASE_A)" "$log" | sed 's/^flutter: //' || true
  return $status
}

mkdir -p integration_test
cp "$here/h1_common.dart" "$here/phase_a_test.dart" integration_test/
for id in $phase_a_scenarios; do
  # Phase A is the baseline, not a check: a failure here is a harness error.
  run_phase a phase_a_test.dart "$id" || { tail -n 80 "$logs/a_$id.log"; exit 1; }
done

echo "== Switch the same app to the package under test ($package)"
rm integration_test/phase_a_test.dart
flutter pub remove mobile_rag_engine > "$logs/pub_b.log"
if [ "$package" = path ]; then
  flutter pub add "mobile_rag_engine:{\"path\":\"$H1_PATH\"}" >> "$logs/pub_b.log"
  flutter pub add "override:rag_engine_flutter:{\"path\":\"$H1_PATH/rust_builder\"}" >> "$logs/pub_b.log"
else
  flutter pub add "mobile_rag_engine:{\"git\":{\"url\":\"$H1_GIT_URL\",\"ref\":\"$H1_GIT_REF\"}}" >> "$logs/pub_b.log"
  flutter pub add "override:rag_engine_flutter:{\"git\":{\"url\":\"$H1_GIT_URL\",\"ref\":\"$H1_GIT_REF\",\"path\":\"rust_builder\"}}" >> "$logs/pub_b.log"
fi
flutter pub deps --style=compact | grep -E "^- (mobile_rag_engine|rag_engine_flutter) " | tee -a "$logs/pub_b.log"
cp "$here/phase_b_test.dart" integration_test/
for id in $phase_b_scenarios; do
  run_phase b phase_b_test.dart "$id" || true
done

echo "== Compare with the known-failing list:$known"
checks=$(cat "$logs"/b_*.log | sed 's/^flutter: //' | grep -E "^H1_CHECK " || true)
unexpected=0
{
  echo "### Upgrade harness (H1)"
  echo ""
  echo "- From \`mobile_rag_engine $base_version\` (pub.dev) to the package under test ($package)"
  echo "- Known failing: \`${H1_KNOWN_FAILING:-none}\`"
  echo ""
  echo "| Check | Result | Verdict | Detail |"
  echo "|---|---|---|---|"
} >> "$summary"
for id in $expected_checks; do
  line=$(grep -E "^H1_CHECK $id " <<< "$checks" | head -n 1 || true)
  result=$(awk '{print $3}' <<< "$line")
  detail=$(cut -d' ' -f4- <<< "$line" | sed 's/|/\\|/g')
  case "$result:$known" in
    PASS:*" $id "*) verdict="FIXED: remove $id from H1_KNOWN_FAILING"; unexpected=1 ;;
    PASS:*) verdict="ok" ;;
    FAIL:*" $id "*) verdict="reproduced (known)" ;;
    FAIL:*) verdict="UNEXPECTED FAILURE"; unexpected=1 ;;
    *) result="MISSING"; verdict="no result (crashed?)"; unexpected=1 ;;
  esac
  echo "$id $result $verdict"
  echo "| $id | $result | $verdict | $detail |" >> "$summary"
done
exit $unexpected
