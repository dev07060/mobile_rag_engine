import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/native_runtime_expectations.dart';

void main() {
  test('passes when expected allocator and features match actual values', () {
    expect(
      () => verifyNativeRuntimeExpectations(
        actualAllocator: 'system',
        actualRustFeatures: 'vector_faer,vector_quant_i8',
        expectedAllocator: 'system',
        expectedRustFeatures: 'vector_faer,vector_quant_i8',
      ),
      returnsNormally,
    );
  });

  test('ignores an empty expectation', () {
    expect(
      () => verifyNativeRuntimeExpectations(
        actualAllocator: 'system',
        actualRustFeatures: 'default',
        expectedAllocator: '',
        expectedRustFeatures: '',
      ),
      returnsNormally,
    );
  });

  test('fails when allocator expectation does not match', () {
    expect(
      () => verifyNativeRuntimeExpectations(
        actualAllocator: 'system',
        actualRustFeatures: 'vector_faer,vector_quant_i8',
        expectedAllocator: 'mimalloc',
        expectedRustFeatures: 'vector_faer,vector_quant_i8',
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('EXPECTED_NATIVE_ALLOCATOR=mimalloc'),
      )),
    );
  });

  test('fails when feature expectation does not match', () {
    expect(
      () => verifyNativeRuntimeExpectations(
        actualAllocator: 'mimalloc',
        actualRustFeatures: 'vector_faer,vector_quant_i8,allocator_mimalloc',
        expectedAllocator: 'mimalloc',
        expectedRustFeatures: 'vector_faer,vector_quant_i8',
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('EXPECTED_RUST_FEATURES=vector_faer,vector_quant_i8'),
      )),
    );
  });
}
