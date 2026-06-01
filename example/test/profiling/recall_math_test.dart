import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/recall_math.dart';

void main() {
  group('decodeF32Blob', () {
    test('round-trips a known Float32List (native endian)', () {
      final original = Float32List.fromList([1.0, -2.5, 3.25, 0.0]);
      final bytes = original.buffer.asUint8List();
      final decoded = decodeF32Blob(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.length, 4);
      expect(decoded[0], closeTo(1.0, 1e-7));
      expect(decoded[1], closeTo(-2.5, 1e-7));
      expect(decoded[2], closeTo(3.25, 1e-7));
      expect(decoded[3], closeTo(0.0, 1e-7));
    });

    test('returns null when length is not a multiple of 4', () {
      expect(decodeF32Blob(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('cosineSimilarity', () {
    test('identical vectors returns 1.0', () {
      final v = <double>[1, 2, 3];
      expect(cosineSimilarity(v, v), closeTo(1.0, 1e-9));
    });

    test('orthogonal vectors returns 0.0', () {
      expect(
        cosineSimilarity(<double>[1, 0], <double>[0, 1]),
        closeTo(0.0, 1e-9),
      );
    });

    test('opposite vectors returns -1.0', () {
      expect(
        cosineSimilarity(<double>[1, 0], <double>[-1, 0]),
        closeTo(-1.0, 1e-9),
      );
    });

    test('zero vector returns 0.0 without NaN', () {
      expect(cosineSimilarity(<double>[0, 0], <double>[1, 1]), 0.0);
    });
  });
}
