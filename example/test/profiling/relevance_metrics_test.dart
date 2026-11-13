import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine_example/profiling/relevance_metrics.dart';

void main() {
  group('scoreSourceRanking', () {
    test('computes recall, MRR, nDCG, and top1 for a hit', () {
      final score = scoreSourceRanking(
        expectedSourceKey: 'src_b',
        rankedSourceKeys: ['src_a', 'src_b', 'src_c'],
        hardNegativeSourceKeys: const [],
      );

      expect(score.expectedRank, 2);
      expect(score.recallAt(1), 0);
      expect(score.recallAt(2), 1);
      expect(score.mrrAt(10), closeTo(0.5, 1e-12));
      expect(score.ndcgAt(10), closeTo(1 / log2(3), 1e-12));
      expect(score.top1Accuracy, 0);
    });

    test('empty results score deterministic misses', () {
      final score = scoreSourceRanking(
        expectedSourceKey: 'src_expected',
        rankedSourceKeys: const [],
        hardNegativeSourceKeys: const ['src_hard'],
      );

      expect(score.expectedRank, isNull);
      expect(score.recallAt(10), 0);
      expect(score.mrrAt(10), 0);
      expect(score.ndcgAt(10), 0);
      expect(score.top1Accuracy, 0);
      expect(score.missingExpectedAt(10), 1);
      expect(score.hardNegativeIntrusionAt(10), 0);
    });

    test('duplicate source ids do not change source-level rank', () {
      final score = scoreSourceRanking(
        expectedSourceKey: 'src_expected',
        rankedSourceKeys: [
          'src_noise',
          'src_noise',
          'src_expected',
          'src_expected',
        ],
        hardNegativeSourceKeys: const [],
      );

      expect(score.uniqueRankedSourceKeys, ['src_noise', 'src_expected']);
      expect(score.expectedRank, 2);
      expect(score.recallAt(1), 0);
      expect(score.recallAt(2), 1);
    });

    test('hard negatives above expected are counted separately from below', () {
      final score = scoreSourceRanking(
        expectedSourceKey: 'src_expected',
        rankedSourceKeys: ['src_hard_above', 'src_expected', 'src_hard_below'],
        hardNegativeSourceKeys: const ['src_hard_above', 'src_hard_below'],
      );

      expect(score.hardNegativeRanks, {
        'src_hard_above': 1,
        'src_hard_below': 3,
      });
      expect(score.hardNegativeAboveExpectedCount, 1);
      expect(score.hardNegativeBelowExpectedCount, 1);
      expect(score.hardNegativeIntrusionAt(2), 1);
    });
  });

  group('SourceRelevanceAccumulator', () {
    test('aggregates query scores into headline metrics', () {
      final accumulator = SourceRelevanceAccumulator();
      accumulator.add(
        scoreSourceRanking(
          expectedSourceKey: 'src_a',
          rankedSourceKeys: const ['src_a', 'src_b'],
          hardNegativeSourceKeys: const ['src_b'],
        ),
      );
      accumulator.add(
        scoreSourceRanking(
          expectedSourceKey: 'src_c',
          rankedSourceKeys: const ['src_b', 'src_d'],
          hardNegativeSourceKeys: const ['src_b'],
        ),
      );

      final aggregate = accumulator.toAggregate();
      expect(aggregate.total, 2);
      expect(aggregate.recallAt5, 0.5);
      expect(aggregate.recallAt10, 0.5);
      expect(aggregate.mrrAt10, 0.5);
      expect(aggregate.ndcgAt10, 0.5);
      expect(aggregate.top1Accuracy, 0.5);
      expect(aggregate.hardNegativeIntrusionRateAt10, 1.0);
      expect(aggregate.hardNegativeAboveExpectedRate, 0.5);
      expect(aggregate.missingExpectedRateAt10, 0.5);
    });
  });

  group('scorePassageRanking', () {
    test('scores strict passage match rank and aggregate metrics', () {
      final score = scorePassageRanking(
        goldSourceKey: 'src_a',
        goldPassage: 'Install the package.',
        rankedChunks: const [
          PassageCandidate(
            chunkId: 10,
            sourceKey: 'src_b',
            chunkIndex: 0,
            content: 'Run the smoke test.',
          ),
          PassageCandidate(
            chunkId: 11,
            sourceKey: 'src_a',
            chunkIndex: 0,
            content: 'Install the package. Verify the checksum.',
          ),
        ],
        hardNegativeSourceKeys: const ['src_b'],
        answerableContextByK: const {5: true, 10: true},
      );

      expect(score.goldSourceRank, 2);
      expect(score.goldPassageRank, 2);
      expect(score.passageRecallAt(1), 0);
      expect(score.passageRecallAt(2), 1);
      expect(score.passageMrrAt(10), closeTo(0.5, 1e-12));
      expect(score.passageNdcgAt(10), closeTo(1 / log2(3), 1e-12));
      expect(score.sourceButPassageMissAt(10), 0);
      expect(score.answerableContextAt(5), 1);
      expect(score.hardNegativePassageIntrusionAt(10), 1);
      expect(score.hardNegativePassageAboveGoldCount, 1);
    });

    test('distinguishes correct source from wrong passage', () {
      final score = scorePassageRanking(
        goldSourceKey: 'src_a',
        goldPassage: 'Install the package.',
        rankedChunks: const [
          PassageCandidate(
            chunkId: 10,
            sourceKey: 'src_a',
            chunkIndex: 0,
            content: 'Verify the checksum.',
          ),
        ],
        hardNegativeSourceKeys: const [],
        answerableContextByK: const {5: false, 10: false},
      );

      expect(score.goldSourceRank, 1);
      expect(score.goldPassageRank, isNull);
      expect(score.sourceRecallAt(10), 1);
      expect(score.passageRecallAt(10), 0);
      expect(score.sourceButPassageMissAt(10), 1);
    });

    test('normalizes whitespace and case for deterministic matching', () {
      final score = scorePassageRanking(
        goldSourceKey: 'src_a',
        goldPassage: 'Install   The Package.',
        rankedChunks: const [
          PassageCandidate(
            chunkId: 10,
            sourceKey: 'src_a',
            chunkIndex: 0,
            content: 'Before. install the package. After.',
          ),
        ],
        hardNegativeSourceKeys: const [],
        answerableContextByK: const {5: true, 10: true},
      );

      expect(score.goldPassageRank, 1);
    });
  });
}
