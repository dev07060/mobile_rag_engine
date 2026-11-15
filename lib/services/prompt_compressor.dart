/// REFRAG-style prompt compression service.
///
/// Reduces token count while preserving key information for LLM context.
/// Uses Rust-based text processing for performance.
library;

import '../src/rust/api/compression_utils.dart' as rust;
import '../src/rust/api/source_rag.dart';

/// Compression level options.
enum CompressionLevel {
  /// Minimal compression: remove duplicates only.
  minimal,

  /// Balanced compression: remove duplicates + light stopword filtering.
  balanced,

  /// Aggressive compression: full stopword removal + sentence pruning.
  aggressive,
}

/// Result of prompt compression.
class CompressedContext {
  /// The compressed text for LLM input.
  final String text;

  /// Original character count before compression.
  final int originalChars;

  /// Character count after compression.
  final int compressedChars;

  /// Compression ratio (0.0 - 1.0, lower = more compressed).
  final double ratio;

  /// Estimated token savings.
  final int estimatedTokensSaved;

  /// Chunks included in the context.
  final List<ChunkSearchResult> includedChunks;

  const CompressedContext({
    required this.text,
    required this.originalChars,
    required this.compressedChars,
    required this.ratio,
    required this.estimatedTokensSaved,
    required this.includedChunks,
  });

  @override
  String toString() =>
      'CompressedContext('
      'ratio: ${(ratio * 100).toStringAsFixed(1)}%, '
      'saved: ~$estimatedTokensSaved tokens)';
}

/// Prompt compression service using REFRAG principles.
///
/// Phase 1: Rule-based compression (stopwords, duplicates)
/// Phase 2: Similarity-based sentence selection (future)
class PromptCompressor {
  PromptCompressor._();

  /// Compress chunks for LLM context within a token budget.
  ///
  /// [chunks] - Search result chunks to compress.
  /// [level] - Compression aggressiveness.
  /// [maxTokens] - Target maximum tokens. Without [tokenCounter] this is an
  ///   estimate of 4 characters per token, which can be several times off
  ///   for Korean, Japanese, Chinese, Thai or emoji.
  /// [language] - Language for stopword filtering ("ko" or "en").
  /// [tokenCounter] - Counts tokens as your LLM does. When given, the text is
  ///   cut at sentence boundaries until it has at most [maxTokens] tokens by
  ///   this count, and [CompressedContext.estimatedTokensSaved] uses it too.
  static Future<CompressedContext> compress({
    required List<ChunkSearchResult> chunks,
    CompressionLevel level = CompressionLevel.balanced,
    int maxTokens = 2000,
    String language = 'ko',
    int Function(String text)? tokenCounter,
  }) async {
    if (chunks.isEmpty) {
      return const CompressedContext(
        text: '',
        originalChars: 0,
        compressedChars: 0,
        ratio: 1.0,
        estimatedTokensSaved: 0,
        includedChunks: [],
      );
    }

    // Combine all chunk content
    final originalText = chunks.map((c) => c.content).join('\n\n');
    final originalChars = originalText.length;

    // Convert level to int for Rust
    final levelInt = level.index;

    // Create compression options
    final options = rust.CompressionOptions(
      removeStopwords: false, // Disabled - damages context
      removeDuplicates: true,
      language: language,
      level: levelInt,
    );

    final rust.CompressedText result;
    final int tokensSaved;
    if (tokenCounter == null) {
      // Calculate max chars from token budget (~4 chars per token)
      result = await rust.compressText(
        text: originalText,
        maxChars: maxTokens * 4,
        options: options,
      );
      // Calculate token savings (rough estimate)
      tokensSaved =
          (originalChars / 4).ceil() - (result.compressedChars / 4).ceil();
    } else {
      result = await _compressToTokens(
        originalText,
        maxTokens,
        tokenCounter,
        options,
      );
      tokensSaved = tokenCounter(originalText) - tokenCounter(result.text);
    }

    return CompressedContext(
      text: result.text,
      originalChars: result.originalChars,
      compressedChars: result.compressedChars,
      ratio: result.ratio,
      estimatedTokensSaved: tokensSaved,
      includedChunks: chunks,
    );
  }

  /// Compresses [text] without a length limit, then shortens the limit (in
  /// characters, which `compressText` cuts at a sentence end) until [count]
  /// gives at most [maxTokens].
  static Future<rust.CompressedText> _compressToTokens(
    String text,
    int maxTokens,
    int Function(String text) count,
    rust.CompressionOptions options,
  ) async {
    var result = await rust.compressText(
      text: text,
      maxChars: 0,
      options: options,
    );
    var maxChars = result.text.runes.length;
    for (var i = 0; i < 16; i++) {
      final tokens = count(result.text);
      if (tokens <= maxTokens || maxChars <= 1) break;
      maxChars = ((maxChars * maxTokens) / tokens).floor().clamp(
        1,
        maxChars - 1,
      );
      result = await rust.compressText(
        text: text,
        maxChars: maxChars,
        options: options,
      );
      // The cut may land before the limit; continue from the actual length.
      maxChars = result.text.runes.length.clamp(1, maxChars);
    }
    return result;
  }

  /// Quick compress a single text string.
  ///
  /// Convenience method for simple use cases.
  static Future<String> compressSimple({
    required String text,
    CompressionLevel level = CompressionLevel.balanced,
  }) async {
    return rust.compressTextSimple(text: text, level: level.index);
  }

  /// Check if text needs compression based on token estimate.
  ///
  /// Returns true if estimated tokens exceed threshold.
  static Future<bool> needsCompression({
    required String text,
    int tokenThreshold = 2000,
  }) async {
    return rust.shouldCompress(text: text, tokenThreshold: tokenThreshold);
  }

  /// Split text into sentences.
  ///
  /// Useful for debugging or custom processing.
  static Future<List<String>> splitSentences(String text) async {
    return rust.splitSentences(text: text);
  }

  // NOTE: filterStopwords was removed - stopword filtering damages context quality.
  // See Rust code comment: modern LLM systems use perplexity-based methods instead.

  // ============================================================
  // Phase 2: Similarity-based sentence selection
  // ============================================================

  /// Select sentences most relevant to the query using embedding similarity.
  ///
  /// This implements the REFRAG "Sense" stage in a lightweight way:
  /// - Instead of RL policy network, uses cosine similarity scoring
  /// - Leverages existing EmbeddingService for embeddings
  ///
  /// [sentences] - List of sentences to score.
  /// [queryEmbedding] - Pre-computed query embedding.
  /// [topK] - Maximum number of sentences to select.
  /// [minSimilarity] - Minimum similarity threshold (0.0 - 1.0).
  static Future<List<ScoredSentence>> scoreSentences({
    required List<String> sentences,
    required List<double> queryEmbedding,
    int topK = 10,
    double minSimilarity = 0.2,
  }) async {
    if (sentences.isEmpty || queryEmbedding.isEmpty) {
      return [];
    }

    // Import EmbeddingService dynamically to avoid circular dependency
    final embedService = await _getEmbeddingService();
    if (embedService == null) {
      // Fallback: return all sentences if embedding service unavailable
      return sentences
          .asMap()
          .entries
          .map(
            (e) => ScoredSentence(
              sentence: e.value,
              similarity: 1.0,
              index: e.key,
            ),
          )
          .toList();
    }

    // Generate embeddings for each sentence
    final scored = <ScoredSentence>[];
    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      if (sentence.trim().isEmpty) continue;

      try {
        final sentenceEmbedding = await embedService(sentence);
        final similarity = _cosineSimilarity(queryEmbedding, sentenceEmbedding);

        if (similarity >= minSimilarity) {
          scored.add(
            ScoredSentence(
              sentence: sentence,
              similarity: similarity,
              index: i,
            ),
          );
        }
      } catch (e) {
        // Skip sentences that fail to embed
        continue;
      }
    }

    // Sort by similarity (descending) and take top K
    scored.sort((a, b) => b.similarity.compareTo(a.similarity));
    return scored.take(topK).toList();
  }

  /// Compress with Phase 2 similarity-based selection.
  ///
  /// Combines Phase 1 (rule-based) with Phase 2 (similarity-based):
  /// 1. Split text into sentences
  /// 2. Score each sentence by query similarity
  /// 3. Select top-K sentences
  /// 4. Apply Phase 1 compression (duplicates, stopwords)
  ///
  /// [chunks] - Search result chunks to compress.
  /// [queryEmbedding] - Pre-computed query embedding.
  /// [level] - Compression level for Phase 1 post-processing.
  /// [maxSentences] - Maximum sentences to keep after selection.
  /// [minSimilarity] - Minimum similarity threshold.
  static Future<CompressedContext> compressWithSimilarity({
    required List<ChunkSearchResult> chunks,
    required List<double> queryEmbedding,
    CompressionLevel level = CompressionLevel.balanced,
    int maxSentences = 15,
    double minSimilarity = 0.2,
    String language = 'ko',
  }) async {
    if (chunks.isEmpty || queryEmbedding.isEmpty) {
      return const CompressedContext(
        text: '',
        originalChars: 0,
        compressedChars: 0,
        ratio: 1.0,
        estimatedTokensSaved: 0,
        includedChunks: [],
      );
    }

    // Combine all chunk content
    final originalText = chunks.map((c) => c.content).join('\n\n');
    final originalChars = originalText.length;

    // Step 1: Split into sentences
    final sentences = await rust.splitSentences(text: originalText);

    // Step 2: Score and select relevant sentences
    final scored = await scoreSentences(
      sentences: sentences,
      queryEmbedding: queryEmbedding,
      topK: maxSentences,
      minSimilarity: minSimilarity,
    );

    // Step 3: Reconstruct text from selected sentences (preserve original order)
    final selectedSentences = scored.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final selectedText = selectedSentences.map((s) => s.sentence).join(' ');

    // Step 4: Apply Phase 1 compression on selected text
    final options = rust.CompressionOptions(
      removeStopwords: false, // Disabled - damages context
      removeDuplicates: true,
      language: language,
      level: level.index,
    );

    final result = await rust.compressText(
      text: selectedText,
      maxChars: 0, // No char limit after similarity selection
      options: options,
    );

    // Calculate token savings
    final originalTokens = (originalChars / 4).ceil();
    final compressedTokens = (result.compressedChars / 4).ceil();
    final tokensSaved = originalTokens - compressedTokens;

    return CompressedContext(
      text: result.text,
      originalChars: originalChars,
      compressedChars: result.compressedChars,
      ratio: result.ratio,
      estimatedTokensSaved: tokensSaved,
      includedChunks: chunks,
    );
  }

  /// Calculate cosine similarity between two embedding vectors.
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Get embedding function (lazy load to avoid circular imports)
  static Future<Function(String)?> _getEmbeddingService() async {
    try {
      // Use dynamic import pattern
      return (String text) async {
        // This will be resolved at runtime
        final embedService = _embeddingServiceInstance;
        if (embedService != null) {
          return await embedService(text);
        }
        return <double>[];
      };
    } catch (e) {
      return null;
    }
  }

  /// Set embedding service instance (call this during app initialization)
  static void setEmbeddingService(
    Future<List<double>> Function(String) service,
  ) {
    _embeddingServiceInstance = service;
  }

  static Future<List<double>> Function(String)? _embeddingServiceInstance;
}

/// Scored sentence with similarity value.
class ScoredSentence {
  /// The sentence text.
  final String sentence;

  /// Similarity score to query (0.0 - 1.0).
  final double similarity;

  /// Original index in the sentence list.
  final int index;

  const ScoredSentence({
    required this.sentence,
    required this.similarity,
    required this.index,
  });

  @override
  String toString() =>
      'ScoredSentence(sim: ${similarity.toStringAsFixed(3)}, "$sentence")';
}

/// Helper: sqrt function
double sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x / 2;
  for (var i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
