#!/usr/bin/env bash
# Checks the native libraries in an Android release APK or app bundle:
# - every ABI named on the command line ships librag_engine_flutter.so, so an
#   ABI whose libraries are missing fails instead of being skipped;
# - every 64-bit library (arm64-v8a, x86_64) has 16 KB aligned LOAD segments,
#   as Google Play requires for apps targeting Android 15+;
# - an APK's uncompressed libraries are 16 KB aligned in the zip (zipalign -P 16,
#   from the Android SDK build-tools; ZIPALIGN=skip skips it for local runs).
#
# Usage: tool/quickstart_e2e/check_android_libs.sh <app.apk|app.aab> <abi>...
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# On Windows runners `python3` can be a Store stub that does not run.
python=""
for candidate in python3 python; do
  if "$candidate" -c "" >/dev/null 2>&1; then python=$candidate; break; fi
done
[ -n "$python" ] || { echo "::error::python not found"; exit 1; }
package=$1
shift
sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
case "$package" in
  *.aab) prefix=base/lib ;;
  *) prefix=lib ;;
esac
unzip -q "$package" "$prefix/*" -d "$work" 2>/dev/null || true
name=$(basename "$package")
status=0
for abi in "$@"; do
  if [ ! -f "$work/$prefix/$abi/librag_engine_flutter.so" ]; then
    echo "::error::$name has no $abi/librag_engine_flutter.so"
    status=1
  fi
done
for so in "$work/$prefix"/*/*.so; do
  [ -f "$so" ] || continue
  abi=$(basename "$(dirname "$so")")
  case "$abi" in arm64-v8a | x86_64) ;; *) continue ;; esac
  align=$("$python" -I "$here/elf_align.py" "$so" || true)
  echo "page alignment: $name $abi/$(basename "$so") $align"
  if [ -z "$align" ] || [ "$align" -lt 16384 ]; then
    echo "::error::$name $abi/$(basename "$so") is not 16 KB aligned ($align)"
    status=1
  fi
done
if [ "$prefix" = lib ]; then
  zipalign=""
  if [ -n "$sdk" ]; then
    zipalign=$(ls "$sdk"/build-tools/*/zipalign 2>/dev/null | tail -n 1 || true)
  fi
  if [ -n "$zipalign" ]; then
    if "$zipalign" -c -P 16 4 "$package" > "$work/zipalign.txt" 2>&1; then
      echo "zip alignment: $name 16 KB"
    else
      grep -i "lib/.*BAD" "$work/zipalign.txt" | head -n 10 || tail -n 10 "$work/zipalign.txt"
      echo "::error::$name native libraries are not 16 KB aligned in the zip"
      status=1
    fi
  elif [ "${ZIPALIGN:-}" = skip ]; then
    echo "zip alignment: skipped (ZIPALIGN=skip)"
  else
    echo "::error::no zipalign in \$ANDROID_SDK_ROOT/build-tools (set ZIPALIGN=skip to skip)"
    status=1
  fi
fi
exit $status
