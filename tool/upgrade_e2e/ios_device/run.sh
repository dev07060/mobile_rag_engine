#!/usr/bin/env bash
# iOS upgrade check on one device (M5, docs/milestones.md): install an app
# built with the last release, add documents, then install a build of the
# package under test over it (same bundle id, same data container) and check
# that it opens the release's database.
#
# Usage: tool/upgrade_e2e/ios_device/run.sh <work dir> <device id> <step>
#   step: prepare (create the app, no install), a (build + install phase A),
#         b (build + install phase B over it)
# Environment:
#   M5_PATH          repository root of the package under test (phase B)
#   M5_BASE_VERSION  release for phase A (default 0.23.0)
#   M5_TEAM          Apple development team for device signing
#   M5_PODS_DEPLOYMENT_TARGET  raise every pod's iOS deployment target (local
#                    Xcode 27 builds reject the 9.0-13.0 targets some pods set)
#   M5_UISCENE       1 to add a UIScene manifest with FlutterSceneDelegate
#                    (iOS 27 ends apps without one at launch)
#
# Each phase is a profile build installed with `devicectl` and started without
# a debugger; the test writes its result to Documents, which is copied back.
# `devicectl device install app` keeps the data container of an installed app.
set -euo pipefail

work=$(mkdir -p "$1" && cd "$1" && pwd)
device=$2
step=$3
here=$(cd "$(dirname "$0")" && pwd)
base_version=${M5_BASE_VERSION:-0.23.0}
app="$work/app"
logs="$work/logs"
bundle_id=com.example.m5UpgradeApp

install_and_run() {
  local phase=$1 result=$2
  (cd "$app" && flutter build ios --profile -t "integration_test/phase_${phase}_test.dart") \
    > "$logs/build_$phase.log" 2>&1 || { tail -n 40 "$logs/build_$phase.log"; exit 1; }
  xcrun devicectl device install app --device "$device" \
    "$app/build/ios/iphoneos/Runner.app" > "$logs/install_$phase.log" 2>&1
  xcrun devicectl device process launch --terminate-existing --device "$device" \
    "$bundle_id" > "$logs/launch_$phase.log" 2>&1
  for _ in $(seq 1 30); do
    local files
    files=$(xcrun devicectl device info files --device "$device" --domain-type appDataContainer \
      --domain-identifier "$bundle_id" 2>/dev/null || true)
    if grep -q "Documents/$result" <<< "$files"; then
      xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle_id" --source "Documents/$result" \
        --destination "$logs/$result" > /dev/null
      echo "== Phase $phase result"
      cat "$logs/$result"; echo
      return 0
    fi
    sleep 2
  done
  echo "Phase $phase wrote no result within 60 s" >&2
  return 1
}

case "$step" in
  prepare)
    rm -rf "$app" "$logs"
    mkdir -p "$logs"
    echo "== Create the app with mobile_rag_engine $base_version"
    (cd "$work" && flutter create --platforms=ios --org com.example \
      --project-name m5_upgrade_app app > "$logs/create.log")
    cd "$app"
    flutter pub add "mobile_rag_engine:$base_version" path_provider \
      'dev:integration_test:{"sdk":"flutter"}' > "$logs/pub_a.log"
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
    if [ "${M5_UISCENE:-0}" = 1 ] && ! grep -q UIApplicationSceneManifest ios/Runner/Info.plist; then
      plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false,"UISceneConfigurations":{"UIWindowSceneSessionRoleApplication":[{"UISceneClassName":"UIWindowScene","UISceneConfigurationName":"flutter","UISceneDelegateClassName":"FlutterSceneDelegate","UISceneStoryboardFile":"Main"}]}}' ios/Runner/Info.plist
    fi
    mkdir -p integration_test
    cp "$here/upgrade_common.dart" "$here/phase_a_test.dart" integration_test/
    ;;
  a)
    echo "== Phase A ($base_version)"
    install_and_run a m5_upgrade_phase_a.json
    ;;
  b)
    cd "$app"
    echo "== Switch to the package under test ($M5_PATH)"
    rm -f integration_test/phase_a_test.dart
    flutter pub remove mobile_rag_engine > "$logs/pub_b.log"
    flutter pub add "mobile_rag_engine:{\"path\":\"$M5_PATH\"}" >> "$logs/pub_b.log"
    flutter pub add "override:rag_engine_flutter:{\"path\":\"$M5_PATH/rust_builder\"}" >> "$logs/pub_b.log"
    grep -A5 -E "^  (mobile_rag_engine|rag_engine_flutter):" pubspec.lock | grep -E "^  [a-z_]+:|path:|source:"
    cp "$here/upgrade_common.dart" "$here/phase_b_test.dart" integration_test/
    echo "== Phase B (installed over phase A)"
    install_and_run b m5_upgrade_phase_b.json
    ;;
  *) echo "unknown step $step" >&2; exit 2 ;;
esac
