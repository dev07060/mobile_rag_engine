// lib/models/quality_test_models.dart

/// Test case data class
class TestCase {
  final String query;
  final List<String> relevantDocs;
  final String category;

  TestCase({
    required this.query,
    required this.relevantDocs,
    required this.category,
  });
}

/// Quality test result
class QualityResult {
  final String query;
  final List<String> expected;
  final List<String> actual;
  final double recallAt3;
  final double precision;
  final bool passed;

  QualityResult({
    required this.query,
    required this.expected,
    required this.actual,
    required this.recallAt3,
    required this.precision,
    required this.passed,
  });
}

/// Overall test summary
class QualityTestSummary {
  final List<QualityResult> results;
  final double avgRecallAt3;
  final double avgPrecision;
  final int passed;
  final int total;

  QualityTestSummary({
    required this.results,
    required this.avgRecallAt3,
    required this.avgPrecision,
    required this.passed,
    required this.total,
  });

  double get passRate => passed / total;
}
