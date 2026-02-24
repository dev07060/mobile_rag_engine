import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/services/rag_config.dart';
import 'package:mobile_rag_engine/services/source_rag_service.dart';
import 'package:mobile_rag_engine/src/internal/defaults.dart';
import 'package:mobile_rag_engine/src/internal/validation.dart';

void main() {
  group('Default alignment', () {
    test('RagConfig defaults are aligned with internal constants', () {
      final config = RagConfig.fromAssets(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
      );

      expect(config.maxChunkChars, kDefaultMaxChunkChars);
      expect(config.overlapChars, kDefaultOverlapChars);
    });

    test('SourceRagService defaults are aligned with internal constants', () {
      final service = SourceRagService(dbPath: 'test.sqlite');

      expect(service.maxChunkChars, kDefaultMaxChunkChars);
      expect(service.overlapChars, kDefaultOverlapChars);
    });
  });

  group('Runtime soft validation', () {
    test('normalizes maxChunkChars below minimum', () {
      expect(normalizeMaxChunkChars(1), kMinChunkChars);
      expect(normalizeMaxChunkChars(kMinChunkChars), kMinChunkChars);
    });

    test('normalizes negative overlapChars to zero', () {
      expect(normalizeOverlapChars(-3), 0);
      expect(normalizeOverlapChars(7), 7);
    });

    test('applies chunking normalization in SourceRagService constructor', () {
      final service = SourceRagService(
        dbPath: 'test.sqlite',
        maxChunkChars: 10,
        overlapChars: -9,
      );

      expect(service.maxChunkChars, kMinChunkChars);
      expect(service.overlapChars, 0);
    });

    test('clamps hybrid weights into 0.0~1.0 range', () {
      final weights = normalizeHybridWeights(
        vectorWeight: -0.5,
        bm25Weight: 1.5,
      );

      expect(weights.vectorWeight, 0.0);
      expect(weights.bm25Weight, 1.0);
    });

    test('restores defaults when both hybrid weights become zero', () {
      final weights = normalizeHybridWeights(
        vectorWeight: 0.0,
        bm25Weight: 0.0,
      );

      expect(weights.vectorWeight, kDefaultVectorWeight);
      expect(weights.bm25Weight, kDefaultBm25Weight);
    });

    test('handles NaN and Infinity in hybrid weights', () {
      final weights = normalizeHybridWeights(
        vectorWeight: double.nan,
        bm25Weight: double.infinity,
      );

      expect(weights.vectorWeight, kDefaultVectorWeight);
      expect(weights.bm25Weight, kDefaultBm25Weight);
    });

    test('thread conflict warning path does not throw', () {
      expect(
        () => warnThreadConfigConflict(
          threadLevel: ThreadUseLevel.medium,
          embeddingIntraOpNumThreads: 2,
        ),
        returnsNormally,
      );
    });
  });
}
