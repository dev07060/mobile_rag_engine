import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/internal/embedding_fingerprint.dart';

void main() {
  group('embeddingCosine', () {
    test('is 1 for parallel vectors and 0 for orthogonal ones', () {
      expect(embeddingCosine([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-9));
      expect(embeddingCosine([1, 0], [0, 1]), 0);
      expect(embeddingCosine([0, 0], [1, 1]), 0);
    });

    test('refuses vectors of different lengths', () {
      expect(() => embeddingCosine([1], [1, 2]), throwsArgumentError);
    });
  });

  group('reproducesStoredEmbedding', () {
    test('accepts small numeric drift from the same model', () {
      expect(
        reproducesStoredEmbedding([0.5, -0.2, 0.1], [0.501, -0.199, 0.1]),
        isTrue,
      );
    });

    test('rejects a vector from another model', () {
      expect(
        reproducesStoredEmbedding([0.5, -0.2, 0.1], [0.1, 0.4, -0.3]),
        isFalse,
      );
    });

    test('rejects a different dimension instead of throwing', () {
      expect(reproducesStoredEmbedding([0.5, -0.2], [0.5, -0.2, 0]), isFalse);
    });
  });
}
