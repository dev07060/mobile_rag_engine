#!/usr/bin/env bash
# Exits 0 when the GitHub release `precompiled_<crate hash>` has a signed
# binary for every given Rust target, so Cargokit can link the crate on a
# machine without Rust. Binaries are uploaded by precompile_binaries.yml after
# a Rust change reaches main, so a pull request that changes the crate has
# none yet.
#
# Usage: tool/quickstart_e2e/precompiled_available.sh <crate dir> <target>...
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
crate=$1
shift
# On Windows runners `python3` can be a Store stub that does not run.
python=""
for candidate in python3 python; do
  if "$candidate" -c "" >/dev/null 2>&1; then python=$candidate; break; fi
done
[ -n "$python" ] || { echo "::error::python not found"; exit 1; }
hash=$("$python" -I "$here/crate_hash.py" "$crate" | tr -d '\r')
prefix=$(sed -n 's/^ *url_prefix: *//p' "$crate/cargokit.yaml" | tr -d '\r')
echo "crate hash: $hash"
missing=0
for target in "$@"; do
  case "$target" in
    *-windows-*) file="${target}_rag_engine_flutter.dll" ;;
    *-apple-*) file="${target}_librag_engine_flutter.a" ;;
    *) file="${target}_librag_engine_flutter.so" ;;
  esac
  for asset in "$file" "$file.sig"; do
    if curl -sfIL -o /dev/null "$prefix$hash/$asset"; then
      echo "precompiled: $asset"
    else
      echo "not precompiled: $asset"
      missing=1
    fi
  done
done
exit $missing
