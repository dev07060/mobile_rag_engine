import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/src/internal/embedding_dimension_state.dart';

void main() {
  group('EmbeddingDimensionState', () {
    test(
      'sets baseline on first validation and keeps it for same dimension',
      () {
        final state = EmbeddingDimensionState();

        state.validateAndRemember(384);
        state.validateAndRemember(384);

        expect(state.baselineDimension, 384);
      },
    );

    test('throws for non-positive dimensions', () {
      final state = EmbeddingDimensionState();

      expect(
        () => state.validateAndRemember(0),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Invalid embedding dimension'),
          ),
        ),
      );
    });

    test('throws clear mismatch error with expected and got dimensions', () {
      final state = EmbeddingDimensionState();
      state.validateAndRemember(384);

      expect(
        () => state.validateAndRemember(1024),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('expected 384, got 1024'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('regenerateAllEmbeddings()'),
              ),
        ),
      );
    });

    test('reset clears baseline and allows a new baseline', () {
      final state = EmbeddingDimensionState();
      state.validateAndRemember(384);
      state.reset();

      state.validateAndRemember(1024);

      expect(state.baselineDimension, 1024);
    });
  });
}
