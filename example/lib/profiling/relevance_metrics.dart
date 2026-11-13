import 'dart:math' as math;

double log2(num value) => math.log(value) / math.log(2);

SourceRankingScore scoreSourceRanking({
  required String expectedSourceKey,
  required List<String> rankedSourceKeys,
  required List<String> hardNegativeSourceKeys,
}) {
  final uniqueRankedSourceKeys = _dedupePreservingOrder(rankedSourceKeys);
  final expectedIndex = uniqueRankedSourceKeys.indexOf(expectedSourceKey);
  final expectedRank = expectedIndex < 0 ? null : expectedIndex + 1;
  final hardNegativeSet =
      hardNegativeSourceKeys.where((key) => key != expectedSourceKey).toSet();
  final hardNegativeRanks = <String, int>{};

  for (var i = 0; i < uniqueRankedSourceKeys.length; i++) {
    final key = uniqueRankedSourceKeys[i];
    if (hardNegativeSet.contains(key)) {
      hardNegativeRanks[key] = i + 1;
    }
  }

  return SourceRankingScore(
    expectedSourceKey: expectedSourceKey,
    uniqueRankedSourceKeys: uniqueRankedSourceKeys,
    expectedRank: expectedRank,
    hardNegativeRanks: hardNegativeRanks,
  );
}

List<String> _dedupePreservingOrder(List<String> sourceKeys) {
  final seen = <String>{};
  final result = <String>[];
  for (final sourceKey in sourceKeys) {
    if (seen.add(sourceKey)) {
      result.add(sourceKey);
    }
  }
  return result;
}

class SourceRankingScore {
  final String expectedSourceKey;
  final List<String> uniqueRankedSourceKeys;
  final int? expectedRank;
  final Map<String, int> hardNegativeRanks;

  const SourceRankingScore({
    required this.expectedSourceKey,
    required this.uniqueRankedSourceKeys,
    required this.expectedRank,
    required this.hardNegativeRanks,
  });

  double recallAt(int k) => expectedRank != null && expectedRank! <= k ? 1 : 0;

  double mrrAt(int k) =>
      expectedRank != null && expectedRank! <= k ? 1 / expectedRank! : 0;

  double ndcgAt(int k) => expectedRank != null && expectedRank! <= k
      ? 1 / log2(expectedRank! + 1)
      : 0;

  double get top1Accuracy => expectedRank == 1 ? 1 : 0;

  double missingExpectedAt(int k) => recallAt(k) == 1 ? 0 : 1;

  double hardNegativeIntrusionAt(int k) =>
      hardNegativeRanks.values.any((rank) => rank <= k) ? 1 : 0;

  int get hardNegativeAboveExpectedCount {
    if (expectedRank == null) {
      return hardNegativeRanks.length;
    }
    return hardNegativeRanks.values
        .where((rank) => rank < expectedRank!)
        .length;
  }

  int get hardNegativeBelowExpectedCount {
    if (expectedRank == null) {
      return 0;
    }
    return hardNegativeRanks.values
        .where((rank) => rank > expectedRank!)
        .length;
  }

  Map<String, Object?> toJson() => {
        'expected_source_key': expectedSourceKey,
        'expected_rank': expectedRank ?? -1,
        'ranked_source_keys': uniqueRankedSourceKeys,
        'hard_negative_ranks': hardNegativeRanks,
        'recall@5': recallAt(5),
        'recall@10': recallAt(10),
        'mrr@10': mrrAt(10),
        'ndcg@10': ndcgAt(10),
        'top1_accuracy': top1Accuracy,
        'hard_negative_intrusion@5': hardNegativeIntrusionAt(5),
        'hard_negative_intrusion@10': hardNegativeIntrusionAt(10),
        'hard_negative_above_expected_count': hardNegativeAboveExpectedCount,
        'hard_negative_below_expected_count': hardNegativeBelowExpectedCount,
        'missing_expected@5': missingExpectedAt(5),
        'missing_expected@10': missingExpectedAt(10),
      };
}

class SourceRelevanceAccumulator {
  final List<SourceRankingScore> _scores = [];

  void add(SourceRankingScore score) {
    _scores.add(score);
  }

  SourceRelevanceAggregate toAggregate() =>
      SourceRelevanceAggregate.fromScores(_scores);
}

class SourceRelevanceAggregate {
  final int total;
  final double recallAt5;
  final double recallAt10;
  final double mrrAt10;
  final double ndcgAt10;
  final double top1Accuracy;
  final double hardNegativeIntrusionRateAt5;
  final double hardNegativeIntrusionRateAt10;
  final double hardNegativeAboveExpectedRate;
  final double missingExpectedRateAt5;
  final double missingExpectedRateAt10;

  const SourceRelevanceAggregate({
    required this.total,
    required this.recallAt5,
    required this.recallAt10,
    required this.mrrAt10,
    required this.ndcgAt10,
    required this.top1Accuracy,
    required this.hardNegativeIntrusionRateAt5,
    required this.hardNegativeIntrusionRateAt10,
    required this.hardNegativeAboveExpectedRate,
    required this.missingExpectedRateAt5,
    required this.missingExpectedRateAt10,
  });

  factory SourceRelevanceAggregate.fromScores(List<SourceRankingScore> scores) {
    final total = scores.length;
    if (total == 0) {
      return const SourceRelevanceAggregate(
        total: 0,
        recallAt5: 0,
        recallAt10: 0,
        mrrAt10: 0,
        ndcgAt10: 0,
        top1Accuracy: 0,
        hardNegativeIntrusionRateAt5: 0,
        hardNegativeIntrusionRateAt10: 0,
        hardNegativeAboveExpectedRate: 0,
        missingExpectedRateAt5: 0,
        missingExpectedRateAt10: 0,
      );
    }

    return SourceRelevanceAggregate(
      total: total,
      recallAt5: _mean(scores, (score) => score.recallAt(5)),
      recallAt10: _mean(scores, (score) => score.recallAt(10)),
      mrrAt10: _mean(scores, (score) => score.mrrAt(10)),
      ndcgAt10: _mean(scores, (score) => score.ndcgAt(10)),
      top1Accuracy: _mean(scores, (score) => score.top1Accuracy),
      hardNegativeIntrusionRateAt5: _mean(
        scores,
        (score) => score.hardNegativeIntrusionAt(5),
      ),
      hardNegativeIntrusionRateAt10: _mean(
        scores,
        (score) => score.hardNegativeIntrusionAt(10),
      ),
      hardNegativeAboveExpectedRate: _mean(
        scores,
        (score) => score.hardNegativeAboveExpectedCount > 0 ? 1 : 0,
      ),
      missingExpectedRateAt5: _mean(
        scores,
        (score) => score.missingExpectedAt(5),
      ),
      missingExpectedRateAt10: _mean(
        scores,
        (score) => score.missingExpectedAt(10),
      ),
    );
  }

  Map<String, Object?> toJson() => {
        'total': total,
        'recall@5': recallAt5,
        'recall@10': recallAt10,
        'mrr@10': mrrAt10,
        'ndcg@10': ndcgAt10,
        'top1_accuracy': top1Accuracy,
        'hard_negative_intrusion_rate@5': hardNegativeIntrusionRateAt5,
        'hard_negative_intrusion_rate@10': hardNegativeIntrusionRateAt10,
        'hard_negative_above_expected_rate': hardNegativeAboveExpectedRate,
        'missing_expected_rate@5': missingExpectedRateAt5,
        'missing_expected_rate@10': missingExpectedRateAt10,
      };
}

class PassageCandidate {
  final int chunkId;
  final String sourceKey;
  final int chunkIndex;
  final String content;

  const PassageCandidate({
    required this.chunkId,
    required this.sourceKey,
    required this.chunkIndex,
    required this.content,
  });
}

PassageRankingScore scorePassageRanking({
  required String goldSourceKey,
  required String goldPassage,
  required List<PassageCandidate> rankedChunks,
  required List<String> hardNegativeSourceKeys,
  required Map<int, bool> answerableContextByK,
}) {
  return PassageRankingScore.fromCandidates(
    goldSourceKey: goldSourceKey,
    goldPassage: goldPassage,
    rankedChunks: rankedChunks,
    hardNegativeSourceKeys: hardNegativeSourceKeys,
    answerableContextByK: answerableContextByK,
  );
}

String normalizePassageText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

double ngramJaccard(String left, String right, {int n = 5}) {
  final leftGrams = _charNgrams(normalizePassageText(left), n);
  final rightGrams = _charNgrams(normalizePassageText(right), n);
  if (leftGrams.isEmpty && rightGrams.isEmpty) {
    return 1;
  }
  if (leftGrams.isEmpty || rightGrams.isEmpty) {
    return 0;
  }
  final intersection = leftGrams.intersection(rightGrams).length;
  final union = leftGrams.union(rightGrams).length;
  return union == 0 ? 0 : intersection / union;
}

Set<String> _charNgrams(String value, int n) {
  if (value.isEmpty) {
    return const {};
  }
  if (value.length <= n) {
    return {value};
  }
  return {
    for (var i = 0; i <= value.length - n; i++) value.substring(i, i + n),
  };
}

List<PassageCandidate> _dedupeChunksPreservingOrder(
  List<PassageCandidate> chunks,
) {
  final seen = <int>{};
  final result = <PassageCandidate>[];
  for (final chunk in chunks) {
    if (seen.add(chunk.chunkId)) {
      result.add(chunk);
    }
  }
  return result;
}

class PassageRankingScore {
  final String goldSourceKey;
  final String goldPassage;
  final List<PassageCandidate> uniqueRankedChunks;
  final int? goldSourceRank;
  final int? goldPassageRank;
  final Map<String, int> hardNegativeSourceRanks;
  final Map<int, bool> answerableContextByK;
  final List<double> ngramJaccardByRank;

  const PassageRankingScore({
    required this.goldSourceKey,
    required this.goldPassage,
    required this.uniqueRankedChunks,
    required this.goldSourceRank,
    required this.goldPassageRank,
    required this.hardNegativeSourceRanks,
    required this.answerableContextByK,
    required this.ngramJaccardByRank,
  });

  factory PassageRankingScore.fromCandidates({
    required String goldSourceKey,
    required String goldPassage,
    required List<PassageCandidate> rankedChunks,
    required List<String> hardNegativeSourceKeys,
    required Map<int, bool> answerableContextByK,
  }) {
    final uniqueRankedChunks = _dedupeChunksPreservingOrder(rankedChunks);
    final normalizedGold = normalizePassageText(goldPassage);
    int? goldSourceRank;
    int? goldPassageRank;
    final hardNegativeSet =
        hardNegativeSourceKeys.where((key) => key != goldSourceKey).toSet();
    final hardNegativeSourceRanks = <String, int>{};
    final ngramJaccards = <double>[];

    for (var i = 0; i < uniqueRankedChunks.length; i++) {
      final rank = i + 1;
      final chunk = uniqueRankedChunks[i];
      if (goldSourceRank == null && chunk.sourceKey == goldSourceKey) {
        goldSourceRank = rank;
      }
      if (!hardNegativeSourceRanks.containsKey(chunk.sourceKey) &&
          hardNegativeSet.contains(chunk.sourceKey)) {
        hardNegativeSourceRanks[chunk.sourceKey] = rank;
      }
      final normalizedContent = normalizePassageText(chunk.content);
      if (goldPassageRank == null &&
          normalizedGold.isNotEmpty &&
          normalizedContent.contains(normalizedGold)) {
        goldPassageRank = rank;
      }
      ngramJaccards.add(ngramJaccard(chunk.content, goldPassage));
    }

    return PassageRankingScore(
      goldSourceKey: goldSourceKey,
      goldPassage: goldPassage,
      uniqueRankedChunks: uniqueRankedChunks,
      goldSourceRank: goldSourceRank,
      goldPassageRank: goldPassageRank,
      hardNegativeSourceRanks: hardNegativeSourceRanks,
      answerableContextByK: Map<int, bool>.from(answerableContextByK),
      ngramJaccardByRank: List<double>.unmodifiable(ngramJaccards),
    );
  }

  double sourceRecallAt(int k) =>
      goldSourceRank != null && goldSourceRank! <= k ? 1 : 0;

  double passageRecallAt(int k) =>
      goldPassageRank != null && goldPassageRank! <= k ? 1 : 0;

  double passageMrrAt(int k) => goldPassageRank != null && goldPassageRank! <= k
      ? 1 / goldPassageRank!
      : 0;

  double passageNdcgAt(int k) =>
      goldPassageRank != null && goldPassageRank! <= k
          ? 1 / log2(goldPassageRank! + 1)
          : 0;

  double answerableContextAt(int k) => answerableContextByK[k] == true ? 1 : 0;

  double sourceButPassageMissAt(int k) =>
      sourceRecallAt(k) == 1 && passageRecallAt(k) == 0 ? 1 : 0;

  double hardNegativePassageIntrusionAt(int k) =>
      hardNegativeSourceRanks.values.any((rank) => rank <= k) ? 1 : 0;

  int get hardNegativePassageAboveGoldCount {
    if (goldPassageRank == null) {
      return hardNegativeSourceRanks.length;
    }
    return hardNegativeSourceRanks.values
        .where((rank) => rank < goldPassageRank!)
        .length;
  }

  double bestNgramJaccardAt(int k) {
    if (ngramJaccardByRank.isEmpty || k <= 0) {
      return 0;
    }
    return ngramJaccardByRank
        .take(k)
        .fold<double>(0, (best, value) => math.max(best, value));
  }

  Map<String, Object?> toJson() => {
        'gold_source_key': goldSourceKey,
        'gold_source_rank': goldSourceRank ?? -1,
        'gold_passage_rank': goldPassageRank ?? -1,
        'passage_recall@5': passageRecallAt(5),
        'passage_recall@10': passageRecallAt(10),
        'passage_mrr@10': passageMrrAt(10),
        'passage_ndcg@10': passageNdcgAt(10),
        'answerable_context@5': answerableContextAt(5),
        'answerable_context@10': answerableContextAt(10),
        'source_recall@10': sourceRecallAt(10),
        'source_but_passage_miss@10': sourceButPassageMissAt(10),
        'hard_negative_passage_intrusion@10':
            hardNegativePassageIntrusionAt(10),
        'hard_negative_passage_above_gold_count':
            hardNegativePassageAboveGoldCount,
        'best_ngram_jaccard@10': bestNgramJaccardAt(10),
      };
}

class PassageRelevanceAccumulator {
  final List<PassageRankingScore> _scores = [];

  void add(PassageRankingScore score) {
    _scores.add(score);
  }

  PassageRelevanceAggregate toAggregate() =>
      PassageRelevanceAggregate.fromScores(_scores);
}

class PassageRelevanceAggregate {
  final int total;
  final double passageRecallAt5;
  final double passageRecallAt10;
  final double passageMrrAt10;
  final double passageNdcgAt10;
  final double answerableContextAt5;
  final double answerableContextAt10;
  final double sourceRecallAt10;
  final double sourceButPassageMissAt10;
  final double hardNegativePassageIntrusionRateAt10;
  final double hardNegativePassageAboveGoldRate;
  final double bestNgramJaccardAt10;

  const PassageRelevanceAggregate({
    required this.total,
    required this.passageRecallAt5,
    required this.passageRecallAt10,
    required this.passageMrrAt10,
    required this.passageNdcgAt10,
    required this.answerableContextAt5,
    required this.answerableContextAt10,
    required this.sourceRecallAt10,
    required this.sourceButPassageMissAt10,
    required this.hardNegativePassageIntrusionRateAt10,
    required this.hardNegativePassageAboveGoldRate,
    required this.bestNgramJaccardAt10,
  });

  factory PassageRelevanceAggregate.fromScores(
    List<PassageRankingScore> scores,
  ) {
    final total = scores.length;
    if (total == 0) {
      return const PassageRelevanceAggregate(
        total: 0,
        passageRecallAt5: 0,
        passageRecallAt10: 0,
        passageMrrAt10: 0,
        passageNdcgAt10: 0,
        answerableContextAt5: 0,
        answerableContextAt10: 0,
        sourceRecallAt10: 0,
        sourceButPassageMissAt10: 0,
        hardNegativePassageIntrusionRateAt10: 0,
        hardNegativePassageAboveGoldRate: 0,
        bestNgramJaccardAt10: 0,
      );
    }

    return PassageRelevanceAggregate(
      total: total,
      passageRecallAt5: _meanPassage(
        scores,
        (score) => score.passageRecallAt(5),
      ),
      passageRecallAt10: _meanPassage(
        scores,
        (score) => score.passageRecallAt(10),
      ),
      passageMrrAt10: _meanPassage(scores, (score) => score.passageMrrAt(10)),
      passageNdcgAt10: _meanPassage(scores, (score) => score.passageNdcgAt(10)),
      answerableContextAt5: _meanPassage(
        scores,
        (score) => score.answerableContextAt(5),
      ),
      answerableContextAt10: _meanPassage(
        scores,
        (score) => score.answerableContextAt(10),
      ),
      sourceRecallAt10: _meanPassage(
        scores,
        (score) => score.sourceRecallAt(10),
      ),
      sourceButPassageMissAt10: _meanPassage(
        scores,
        (score) => score.sourceButPassageMissAt(10),
      ),
      hardNegativePassageIntrusionRateAt10: _meanPassage(
        scores,
        (score) => score.hardNegativePassageIntrusionAt(10),
      ),
      hardNegativePassageAboveGoldRate: _meanPassage(
        scores,
        (score) => score.hardNegativePassageAboveGoldCount > 0 ? 1 : 0,
      ),
      bestNgramJaccardAt10: _meanPassage(
        scores,
        (score) => score.bestNgramJaccardAt(10),
      ),
    );
  }

  Map<String, Object?> toJson() => {
        'total': total,
        'passage_recall@5': passageRecallAt5,
        'passage_recall@10': passageRecallAt10,
        'passage_mrr@10': passageMrrAt10,
        'passage_ndcg@10': passageNdcgAt10,
        'answerable_context@5': answerableContextAt5,
        'answerable_context@10': answerableContextAt10,
        'source_recall@10': sourceRecallAt10,
        'source_but_passage_miss@10': sourceButPassageMissAt10,
        'hard_negative_passage_intrusion_rate@10':
            hardNegativePassageIntrusionRateAt10,
        'hard_negative_passage_above_gold_rate':
            hardNegativePassageAboveGoldRate,
        'best_ngram_jaccard@10': bestNgramJaccardAt10,
      };
}

double _mean(
  List<SourceRankingScore> scores,
  double Function(SourceRankingScore score) valueOf,
) =>
    scores.map(valueOf).reduce((a, b) => a + b) / scores.length;

double _meanPassage(
  List<PassageRankingScore> scores,
  double Function(PassageRankingScore score) valueOf,
) =>
    scores.map(valueOf).reduce((a, b) => a + b) / scores.length;
