import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/rust/frb_generated.dart';
import 'package:mobile_rag_engine/src/rust/api/simple.dart';

Future<void> _ensureRustLoaded() async {
  if (!RustLib.instance.initialized) {
    await RustLib.init();
  }
}

void main() {
  setUpAll(() async {
    await _ensureRustLoaded();
  });

  test('vabq benchmark 384/768/1024', () async {
    final dims = [384, 768, 1024];
    final iterations = 50000;

    print("=== VABQ Benchmark on Device ===");
    for (final dim in dims) {
      final ns = benchmarkVabqDevice(
        dim: BigInt.from(dim),
        iterations: iterations,
      );
      print("Dimension: $dim -> $ns ns / query");
    }
    print("================================");
  });
}
