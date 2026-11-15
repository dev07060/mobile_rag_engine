#!/usr/bin/env bash
# Builds the archives `flutter pub publish` would upload for mobile_rag_engine
# and rag_engine_flutter, and extracts them, so the Quick Start app can depend
# on exactly what a pub.dev user downloads (.pubignore applied) through path
# dependencies.
#
# Usage: tool/quickstart_e2e/pack.sh <repo dir> <out dir>
# Writes <out>/<package>/ (extracted), <out>/<package>.tar.gz and
# <out>/<package>.dry-run.txt. Fails when `pub publish --dry-run` reports an
# error. Warnings are allowed: the exact version pins between the two packages
# are intentional (they ship in lockstep) and pub reports them as warnings.
set -euo pipefail

repo=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)

native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

pack() {
  local name=$1 dir=$2
  local log="$out/$name.dry-run.txt"
  local status=0
  (cd "$dir" && flutter pub publish --dry-run) > "$log" 2>&1 || status=$?
  local summary
  summary=$(grep -E '^Package has ' "$log" | tail -n 1 || true)
  echo "$name: pub publish --dry-run exit $status (${summary:-no warnings})"
  if [ "$status" -ne 0 ] && ! grep -qE '^Package has [0-9]+ warnings?\.$' <<< "$summary"; then
    tail -n 40 "$log"
    echo "::error::pub publish --dry-run failed for $name"
    exit 1
  fi
  rm -f "$out/$name.tar.gz"
  (cd "$dir" && flutter pub publish --to-archive="$(native_path "$out/$name.tar.gz")") >> "$log" 2>&1 \
    || { tail -n 40 "$log"; echo "::error::could not write the $name archive"; exit 1; }
  rm -rf "${out:?}/$name"
  mkdir -p "$out/$name"
  (cd "$out/$name" && tar -xzf "../$name.tar.gz")
  echo "$name: archive has $(tar -tzf "$out/$name.tar.gz" | grep -vc '/$') files"
}

pack mobile_rag_engine "$repo"
pack rag_engine_flutter "$repo/rust_builder"
