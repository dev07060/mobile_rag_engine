#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: ./scripts/test_ci.sh <unit|native|integration>"
  exit 2
fi

case "$TARGET" in
  unit)
    echo "[ci] Running unit tests from test/unit"
    flutter test test/unit
    ;;
  native)
    echo "[ci] Running native-dependent tests from test/native"
    echo "[ci] Running Rust tracked PDF parser smoke"
    # Fail closed: `cargo test <filter>` exits 0 even when the filter matches
    # ZERO tests, so a rename/cfg-exclusion would silently drop the only Rust
    # test in CI while staying green. Capture the run and require a passing
    # "test result: ok. N passed" line with N >= 1.
    if ! smoke_out="$(cargo test --manifest-path rust_builder/rust/Cargo.toml --lib test_tracked_pdf_smoke_fixtures_extract 2>&1)"; then
      echo "$smoke_out"
      echo "[ci] ERROR: tracked PDF smoke test failed" >&2
      exit 1
    fi
    echo "$smoke_out"
    if ! grep -Eq 'test result: ok\. [1-9][0-9]* passed' <<<"$smoke_out"; then
      echo "[ci] ERROR: tracked PDF smoke matched 0 tests (renamed/excluded?); failing closed" >&2
      exit 1
    fi
    cargo build --manifest-path rust_builder/rust/Cargo.toml --release
    flutter test test/native
    ;;
  integration)
    INTEGRATION_TESTS="$(rg --files integration_test -g '*_test.dart' 2>/dev/null || true)"
    if [[ -z "$INTEGRATION_TESTS" ]]; then
      echo "[ci] No integration tests found in integration_test/"
      exit 0
    fi
    echo "[ci] Running integration tests from integration_test"
    flutter test integration_test
    ;;
  *)
    echo "Unknown target: $TARGET"
    exit 2
    ;;
esac
