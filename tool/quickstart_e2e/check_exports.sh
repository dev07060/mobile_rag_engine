#!/usr/bin/env bash
# Fails unless a release binary exports every symbol in a list (one per line),
# such as the output of frb_symbols.py.
#
# Usage: tool/quickstart_e2e/check_exports.sh <Mach-O binary> <symbol list>
set -euo pipefail

exports=$(xcrun dyld_info -exports "$1")
total=0
missing=0
while IFS= read -r symbol; do
  [ -n "$symbol" ] || continue
  total=$((total + 1))
  # A here-string, not a pipe: with pipefail, grep -q exiting early breaks the
  # pipe and reads as "not found".
  if ! grep -q "_${symbol}\$" <<< "$exports"; then
    echo "::error::$(basename "$1") does not export $symbol"
    missing=$((missing + 1))
  fi
done < "$2"
if [ "$total" -eq 0 ]; then
  echo "::error::the symbol list $2 is empty"
  exit 1
fi
echo "exported: $((total - missing)) of $total symbols Dart looks up"
[ "$missing" -eq 0 ]
