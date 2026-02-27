import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';

void main() {
  group('decideDuplicateSourceIngestion', () {
    test('returns skipCompleted for completed with chunks', () {
      final decision = decideDuplicateSourceIngestion(
        status: 'completed',
        chunkCount: 3,
      );

      expect(decision, DuplicateSourceIngestionDecision.skipCompleted);
    });

    test('returns alreadyInProgress for pending', () {
      final decision = decideDuplicateSourceIngestion(
        status: 'pending',
        chunkCount: 0,
      );

      expect(decision, DuplicateSourceIngestionDecision.alreadyInProgress);
    });

    test('returns alreadyInProgress for processing', () {
      final decision = decideDuplicateSourceIngestion(
        status: 'processing',
        chunkCount: 10,
      );

      expect(decision, DuplicateSourceIngestionDecision.alreadyInProgress);
    });

    test('returns resetAndResume for failed', () {
      final decision = decideDuplicateSourceIngestion(
        status: 'failed',
        chunkCount: 2,
      );

      expect(decision, DuplicateSourceIngestionDecision.resetAndResume);
    });

    test('returns resetAndResume for completed with zero chunks', () {
      final decision = decideDuplicateSourceIngestion(
        status: 'completed',
        chunkCount: 0,
      );

      expect(decision, DuplicateSourceIngestionDecision.resetAndResume);
    });
  });
}
