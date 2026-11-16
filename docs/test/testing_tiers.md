# Testing Tiers

Tests are split into three tiers.

## 1) Unit (`test/unit`)

- Purpose: pure Dart logic, no native library
- Fast and reproducible
- Run:

```bash
./scripts/test_ci.sh unit
```

## 2) Native (`test/native`)

- Purpose: checks the Rust/FFI path; needs the native library (macOS and Windows runners)
- Run:

```bash
./scripts/test_ci.sh native
```

## 3) Integration (`integration_test`)

- Purpose: runs the app end to end; skipped when the root `integration_test/`
  has no tests (it has none now; the app tests live in `example/integration_test/`)
- Run:

```bash
./scripts/test_ci.sh integration
```

## CI Gate Mapping

- Ubuntu: `analyze + unit`
- macOS: `native`
- Windows: `native` and Rust `cargo test --lib -- --test-threads=1`
- macOS: `integration` (skipped while there are no tests)
- Platform build smoke: `android`, `ios`, `macos`, `windows`