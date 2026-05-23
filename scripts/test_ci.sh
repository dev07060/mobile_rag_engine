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
    cargo test --manifest-path rust_builder/rust/Cargo.toml test_tracked_pdf_smoke_fixtures_extract --lib
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
