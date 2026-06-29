void verifyNativeRuntimeExpectations({
  required String actualAllocator,
  required String actualRustFeatures,
  required String expectedAllocator,
  required String expectedRustFeatures,
}) {
  if (expectedAllocator.isNotEmpty && actualAllocator != expectedAllocator) {
    throw StateError(
      'Native allocator mismatch: '
      'EXPECTED_NATIVE_ALLOCATOR=$expectedAllocator, '
      'actual=$actualAllocator',
    );
  }

  if (expectedRustFeatures.isNotEmpty &&
      actualRustFeatures != expectedRustFeatures) {
    throw StateError(
      'Rust feature mismatch: '
      'EXPECTED_RUST_FEATURES=$expectedRustFeatures, '
      'actual=$actualRustFeatures',
    );
  }
}
