#!/usr/bin/env bash
# iOS upgrade check on one device (M5, docs/milestones.md): install an app
# built with the last release, add documents, then install a build of the
# package under test over it (same bundle id, same data container) and check
# that it opens the release's database.
#
# Usage: tool/upgrade_e2e/ios_device/run.sh <work dir> <device id> <step>
#   step: prepare (create the app, no install), a (install phase A),
#         b (install phase B over it), both (prepare + a + b)
# Environment:
#   M5_PATH          repository root of the package under test (phase B)
#   M5_BASE_VERSION  release for phase A (default 0.23.0)
#   M5_TEAM          Apple development team for device signing
#   M5_MODE          profile (default; devices) or debug (simulator rehearsal)
#   M5_WIRELESS      1 to pass --device-connection wireless
#   M5_PODS_DEPLOYMENT_TARGET  raise every pod's iOS deployment target (local
#                    Xcode 27 builds reject the 9.0-13.0 targets some pods set)
#
# `flutter drive` uninstalls the app when it finishes unless
# --keep-app-running is passed, so phase A keeps it.
set -euo pipefail

work=$(mkdir -p "$1" && cd "$1" && pwd)
device=$2
phases=$3
here=$(cd "$(dirname "$0")" && pwd)
base_version=${M5_BASE_VERSION:-0.23.0}
mode=${M5_MODE:-profile}
app="$work/app"
logs="$work/logs"
connection=()
[ "${M5_WIRELESS:-0}" = 1 ] && connection=(--device-connection wireless)

drive() {
  local test=$1 log=$2; shift 2
  (cd "$app" && flutter drive "--$mode" ${connection[@]+"${connection[@]}"} "$@" \
    --driver=test_driver/integration_test.dart \
    --target="integration_test/$test" -d "$device") > "$log" 2>&1
}

if [ "$phases" = prepare ] || [ "$phases" = both ]; then
  rm -rf "$app" "$logs"
  mkdir -p "$logs"
  echo "== Create the app with mobile_rag_engine $base_version"
  (cd "$work" && flutter create --platforms=ios --org com.example \
    --project-name m5_upgrade_app app > "$logs/create.log")
  cd "$app"
  flutter pub add "mobile_rag_engine:$base_version" path_provider \
    'dev:integration_test:{"sdk":"flutter"}' 'dev:flutter_driver:{"sdk":"flutter"}' > "$logs/pub_a.log"
  dart run mobile_rag_engine:setup --preset stable-minilm-l6-v2-arm64-en >> "$logs/pub_a.log"
  perl -0pi -e 's/^flutter:\n/flutter:\n  assets:\n    - assets\/mobile_rag\/\n/m' pubspec.yaml
  grep -q "^    - assets/mobile_rag/" pubspec.yaml
  if [ -n "${M5_TEAM:-}" ]; then
    perl -pi -e "s/(\s*)(PRODUCT_BUNDLE_IDENTIFIER = com\.example\.m5UpgradeApp;)/\$1DEVELOPMENT_TEAM = $M5_TEAM;\$1\$2/" \
      ios/Runner.xcodeproj/project.pbxproj
  fi
  if [ -n "${M5_PODS_DEPLOYMENT_TARGET:-}" ]; then
    perl -pi -e "s/^(\s*)flutter_additional_ios_build_settings\(target\)\n/\$1flutter_additional_ios_build_settings(target)\n\$1target.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '$M5_PODS_DEPLOYMENT_TARGET' }\n/" ios/Podfile
    grep -q "IPHONEOS_DEPLOYMENT_TARGET" ios/Podfile
  fi
  mkdir -p integration_test test_driver
  cp "$here/upgrade_common.dart" "$here/phase_a_test.dart" integration_test/
  printf "import 'package:integration_test/integration_test_driver.dart';\n\nFuture<void> main() => integrationDriver();\n" > test_driver/integration_test.dart
fi

if [ "$phases" = a ] || [ "$phases" = both ]; then
  cd "$app"
  echo "== Phase A ($base_version)"
  drive phase_a_test.dart "$logs/phase_a.log" --keep-app-running || { tail -n 60 "$logs/phase_a.log"; exit 1; }
  grep -h "M5_UPGRADE" "$logs/phase_a.log" | sed 's/^flutter: //'
fi

if [ "$phases" = b ] || [ "$phases" = both ]; then
  cd "$app"
  echo "== Switch to the package under test ($M5_PATH)"
  rm -f integration_test/phase_a_test.dart
  flutter pub remove mobile_rag_engine > "$logs/pub_b.log"
  flutter pub add "mobile_rag_engine:{\"path\":\"$M5_PATH\"}" >> "$logs/pub_b.log"
  flutter pub add "override:rag_engine_flutter:{\"path\":\"$M5_PATH/rust_builder\"}" >> "$logs/pub_b.log"
  grep -A5 -E "^  (mobile_rag_engine|rag_engine_flutter):" pubspec.lock | grep -E "^  [a-z_]+:|path:|source:" | tee -a "$logs/pub_b.log"
  cp "$here/upgrade_common.dart" "$here/phase_b_test.dart" integration_test/
  echo "== Phase B (installed over phase A)"
  status=0
  drive phase_b_test.dart "$logs/phase_b.log" --keep-app-running || status=$?
  grep -h "M5_UPGRADE" "$logs/phase_b.log" | sed 's/^flutter: //' || true
  [ $status = 0 ] || tail -n 60 "$logs/phase_b.log"
  exit $status
fi
