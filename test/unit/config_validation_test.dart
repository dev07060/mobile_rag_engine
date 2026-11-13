import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
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

    test('RagConfig default hybrid weights are 0.2 / 0.8 unless given', () {
      final config = RagConfig.fromAssets(
        tokenizerAsset: 'assets/tokenizer.json',
        modelAsset: 'assets/model.onnx',
      );
      expect(config.defaultVectorWeight, kDefaultVectorWeight);
      expect(config.defaultBm25Weight, kDefaultBm25Weight);
      expect(kDefaultVectorWeight, 0.2);
      expect(kDefaultBm25Weight, 0.8);

      final prepared = RagConfig.fromPreparedFiles(
        tokenizerPath: '/t.json',
        modelPath: '/m.onnx',
        expectedEmbeddingDimension: 384,
        defaultVectorWeight: 0.6,
        defaultBm25Weight: 0.4,
      );
      expect(prepared.defaultVectorWeight, 0.6);
      expect(prepared.defaultBm25Weight, 0.4);
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

    test('clamps overlapChars below half of maxChunkChars (matches Rust)', () {
      expect(normalizeOverlapChars(600, maxChunkChars: 500), 249);
      expect(normalizeOverlapChars(50, maxChunkChars: 100), 49);
      expect(normalizeOverlapChars(30, maxChunkChars: 500), 30);
      expect(normalizeOverlapChars(-1, maxChunkChars: 500), 0);

      final service = SourceRagService(
        dbPath: 'test.sqlite',
        maxChunkChars: 10,
        overlapChars: 80,
      );
      expect(service.overlapChars, 49);
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

    test('default hybrid weights accept 0.0~1.0 and reject the rest', () {
      for (final (v, b) in [(0.6, 0.4), (1.0, 0.0), (0.0, 1.0), (0.2, 0.8)]) {
        expect(
          () => validateDefaultHybridWeights(vectorWeight: v, bm25Weight: b),
          returnsNormally,
        );
      }
      for (final (v, b) in [
        (-0.1, 0.5),
        (0.5, 1.1),
        (double.nan, 0.5),
        (0.5, double.infinity),
        (0.0, 0.0),
      ]) {
        expect(
          () => validateDefaultHybridWeights(vectorWeight: v, bm25Weight: b),
          throwsArgumentError,
          reason: '($v, $b)',
        );
      }
    });

    test('a weight the call does not pass comes from the defaults', () {
      const defaults = NormalizedHybridWeights(
        vectorWeight: 0.6,
        bm25Weight: 0.4,
      );
      final none = resolveHybridWeights(
        vectorWeight: null,
        bm25Weight: null,
        defaults: defaults,
      );
      expect((none.vectorWeight, none.bm25Weight), (0.6, 0.4));
      final given = resolveHybridWeights(
        vectorWeight: 0.2,
        bm25Weight: 0.8,
        defaults: defaults,
      );
      expect((given.vectorWeight, given.bm25Weight), (0.2, 0.8));
      final one = resolveHybridWeights(
        vectorWeight: 0.5,
        bm25Weight: null,
        defaults: defaults,
      );
      expect((one.vectorWeight, one.bm25Weight), (0.5, 0.4));
    });

    test('initialize rejects bad default weights before loading anything', () {
      expect(
        () => MobileRag.initialize(
          tokenizerAsset: 'missing/tokenizer.json',
          modelAsset: 'missing/model.onnx',
          defaultVectorWeight: 1.5,
        ),
        throwsArgumentError,
      );
      expect(
        () => RagEngine.initialize(
          config: RagConfig.fromAssets(
            tokenizerAsset: 'missing/tokenizer.json',
            modelAsset: 'missing/model.onnx',
            defaultVectorWeight: 0.0,
            defaultBm25Weight: 0.0,
          ),
        ),
        throwsArgumentError,
      );
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
