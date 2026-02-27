// lib/services/quality_test_service.dart
import 'package:mobile_rag_engine/services/embedding_service.dart';
import 'package:mobile_rag_engine/src/rust/api/simple_rag.dart';
import 'package:mobile_rag_engine/src/rust/api/db_pool.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:mobile_rag_engine/models/quality_test_models.dart';

/// Search quality testing service
class QualityTestService {
  /// Test document dataset with explicit category keywords
  static final List<String> testDocuments = [
    // Fruits - explicitly contains "fruit"
    "Apple is a delicious red fruit",
    "Banana is a yellow tropical fruit",
    "Orange is a citrus fruit with vitamin C",
    "Grape is a small purple fruit for wine",
    "Watermelon is a large refreshing fruit",
    "Strawberry is a sweet red berry fruit",

    // Animals - explicitly contains "animal" or "pet"
    "Dog is a loyal pet animal",
    "Cat is a cute pet animal",
    "Rabbit is a fluffy pet with long ears",
    "Monkey is an intelligent wild animal",
    "Elephant is the largest land animal",
    "Penguin is an animal that lives in cold regions",

    // Tech Companies - explicitly contains "company" or "tech"
    "Tesla is a tech company making electric cars",
    "Apple is a tech company making iPhones",
    "Google is a technology company with search engine",
    "Samsung is a tech company making phones",
    "Microsoft is a software company making Windows",
    "Amazon is an e-commerce technology company",

    // Food - explicitly contains "food" or food type
    "Kimchi is traditional Korean food",
    "Pizza is popular Italian food",
    "Sushi is famous Japanese food with rice",
    "Hamburger is American fast food",
    "Pasta is Italian noodle food",
    "Ramen is Asian noodle soup",
  ];

  /// Test cases with direct queries
  static final List<TestCase> testCases = [
    TestCase(
      query: "fruit",
      relevantDocs: [
        "Apple",
        "Banana",
        "Orange",
        "Grape",
        "Watermelon",
        "Strawberry",
      ],
      category: "Fruits",
    ),
    TestCase(
      query: "red fruit",
      relevantDocs: ["Apple", "Strawberry"],
      category: "Color",
    ),
    TestCase(
      query: "pet animal",
      relevantDocs: ["Dog", "Cat", "Rabbit"],
      category: "Animals",
    ),
    TestCase(
      query: "wild animal",
      relevantDocs: ["Monkey", "Elephant", "Penguin"],
      category: "Animals",
    ),
    TestCase(
      query: "tech company",
      relevantDocs: [
        "Tesla",
        "Apple",
        "Google",
        "Samsung",
        "Microsoft",
        "Amazon",
      ],
      category: "Tech",
    ),
    TestCase(
      query: "phone company",
      relevantDocs: ["Apple", "Samsung"],
      category: "Tech",
    ),
    TestCase(
      query: "Italian food",
      relevantDocs: ["Pizza", "Pasta"],
      category: "Food",
    ),
    TestCase(
      query: "Asian food",
      relevantDocs: ["Kimchi", "Sushi", "Ramen"],
      category: "Food",
    ),
    TestCase(
      query: "noodle",
      relevantDocs: ["Pasta", "Ramen"],
      category: "Food",
    ),
    TestCase(
      query: "tropical fruit",
      relevantDocs: ["Banana", "Watermelon"],
      category: "Fruits",
    ),
  ];

  /// Check if document is in relevant docs list
  static bool _isRelevant(String doc, List<String> relevantDocs) {
    final docLower = doc.toLowerCase();
    for (final relevant in relevantDocs) {
      if (docLower.contains(relevant.toLowerCase())) return true;
    }
    return false;
  }

  /// Calculate Recall@K
  static double _calculateRecall(
    List<String> actual,
    List<String> expected,
    int k,
  ) {
    int hits = 0;
    final topK = actual.take(k).toList();

    for (final doc in topK) {
      if (_isRelevant(doc, expected)) {
        hits++;
      }
    }

    return hits / expected.length.clamp(1, k);
  }

  /// Calculate Precision
  static double _calculatePrecision(
    List<String> actual,
    List<String> expected,
    int k,
  ) {
    int hits = 0;
    final topK = actual.take(k).toList();

    for (final doc in topK) {
      if (_isRelevant(doc, expected)) {
        hits++;
      }
    }

    return hits / k;
  }

  /// Run full quality test
  ///
  /// [appDbPath] - Path to the app's main database. After the test completes,
  /// the global DB pool is restored to this path so the app continues working.
  static Future<QualityTestSummary> runQualityTest({
    Function(String, int, int)? onProgress,
    String? appDbPath,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final testDbPath = "${dir.path}/quality_test_db.sqlite";

    // Delete existing DB
    final dbFile = File(testDbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    // Initialize test DB (overwrites global pool)
    await initDbPool(dbPath: testDbPath, maxSize: 5);
    await initDb();

    onProgress?.call("Embedding documents...", 0, testDocuments.length);

    // Embed and store documents
    for (var i = 0; i < testDocuments.length; i++) {
      final doc = testDocuments[i];
      final emb = await EmbeddingService.embed(doc);
      await addDocument(content: doc, embedding: emb);
      onProgress?.call("Embedding documents...", i + 1, testDocuments.length);
    }

    // Rebuild HNSW index (explicit call after adding documents)
    debugPrint(
      '[DEBUG] Rebuilding HNSW index with ${testDocuments.length} documents...',
    );
    await rebuildHnswIndex();
    debugPrint('[DEBUG] HNSW index rebuilt');

    // Run tests
    final results = <QualityResult>[];

    for (var i = 0; i < testCases.length; i++) {
      final tc = testCases[i];
      onProgress?.call("Testing: ${tc.query}", i + 1, testCases.length);

      // Query embedding
      // Enable debug mode for first query
      if (i == 0) {
        EmbeddingService.debugMode = true;
        debugPrint('[DEBUG] === Testing query: "${tc.query}" ===');
      }
      final queryEmb = await EmbeddingService.embed(tc.query);
      if (i == 0) {
        EmbeddingService.debugMode = false;
        debugPrint(
          '[DEBUG] Query embedding (first 5): ${queryEmb.take(5).toList()}',
        );
      }

      // Search
      final searchResults = await searchSimilar(
        queryEmbedding: queryEmb,
        topK: 3,
      );

      // Debug first query results
      if (i == 0) {
        debugPrint(
          '[DEBUG] Search results for "${tc.query}": ${searchResults.length} items',
        );
        for (final r in searchResults) {
          debugPrint('[DEBUG]   - ${r.substring(0, r.length.clamp(0, 50))}...');
        }
      }

      // Calculate metrics
      final recall = _calculateRecall(searchResults, tc.relevantDocs, 3);
      final precision = _calculatePrecision(searchResults, tc.relevantDocs, 3);

      // Pass if at least 1 match
      final passed = searchResults.any(
        (doc) => _isRelevant(doc, tc.relevantDocs),
      );

      results.add(
        QualityResult(
          query: tc.query,
          expected: tc.relevantDocs,
          actual: searchResults,
          recallAt3: recall,
          precision: precision,
          passed: passed,
        ),
      );
    }

    // Cleanup test DB
    await closeDbPool();
    await dbFile.delete();

    // Restore original app DB pool
    if (appDbPath != null) {
      await initDbPool(dbPath: appDbPath, maxSize: 4);
      debugPrint('[QualityTest] Restored app DB pool: $appDbPath');
    }

    // Aggregate
    final avgRecall =
        results.map((r) => r.recallAt3).reduce((a, b) => a + b) /
        results.length;
    final avgPrecision =
        results.map((r) => r.precision).reduce((a, b) => a + b) /
        results.length;
    final passedCount = results.where((r) => r.passed).length;

    return QualityTestSummary(
      results: results,
      avgRecallAt3: avgRecall,
      avgPrecision: avgPrecision,
      passed: passedCount,
      total: results.length,
    );
  }
}
