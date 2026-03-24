/// Context assembly for LLM prompts.
///
/// ContextBuilder takes search results and assembles them into
/// an optimized context string within a token budget.
library;

import '../src/rust/api/source_rag.dart';
import '../src/rust/api/compression_utils.dart' as compression;

/// Assembled context ready for LLM consumption.
class AssembledContext {
  /// The combined text of all selected chunks.
  final String text;

  /// Chunks that were included in the context.
  final List<ChunkSearchResult> includedChunks;

  /// Approximate token count used.
  final int estimatedTokens;

  /// Tokens remaining from budget.
  final int remainingBudget;

  const AssembledContext({
    required this.text,
    required this.includedChunks,
    required this.estimatedTokens,
    required this.remainingBudget,
  });

  @override
  String toString() =>
      'AssembledContext(${includedChunks.length} chunks, ~$estimatedTokens tokens)';
}

/// Strategy for selecting and ordering chunks.
enum ContextStrategy {
  /// Include highest similarity chunks first until budget exhausted.
  relevanceFirst,

  /// Ensure diversity by not including chunks from same source consecutively.
  diverseSources,

  /// Order by chunk index within each source (maintains document order).
  chronological,
}

/// Builds optimized context for LLM prompts.
class ContextBuilder {
  ContextBuilder._();

  static ({String rawType, String? headerPath}) _decodeChunkType(
    String chunkType,
  ) {
    final separator = chunkType.indexOf('|');
    if (separator < 0) {
      return (rawType: chunkType, headerPath: null);
    }

    final rawType = chunkType.substring(0, separator);
    final headerPath = chunkType.substring(separator + 1).trim();
    return (
      rawType: rawType,
      headerPath: headerPath.isEmpty ? null : headerPath,
    );
  }

  static String _renderChunkText(ChunkSearchResult chunk) {
    final decoded = _decodeChunkType(chunk.chunkType);
    final headerPath = decoded.headerPath;
    if (headerPath == null) {
      return chunk.content;
    }

    return 'Header Path: $headerPath\n${chunk.content}';
  }

  /// Assemble context from search results within a token budget.
  ///
  /// [searchResults] - Chunks ranked by relevance (highest first).
  /// [tokenBudget] - Maximum tokens to use.
  /// [strategy] - How to select and order chunks.
  /// [separator] - Text between chunks.
  /// [singleSourceMode] - If true, only include chunks from the most relevant source.
  static AssembledContext build({
    required List<ChunkSearchResult> searchResults,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    String separator = '\n\n---\n\n',
    bool singleSourceMode = false,
  }) {
    if (searchResults.isEmpty) {
      return const AssembledContext(
        text: '',
        includedChunks: [],
        estimatedTokens: 0,
        remainingBudget: 0,
      );
    }

    // Filter to single source if requested
    var filteredResults = searchResults;
    if (singleSourceMode) {
      filteredResults = _filterToMostRelevantSource(searchResults);
    }

    // Apply strategy
    final orderedResults = switch (strategy) {
      ContextStrategy.relevanceFirst => filteredResults,
      ContextStrategy.diverseSources => _diversifySources(filteredResults),
      ContextStrategy.chronological => _orderChronologically(filteredResults),
    };

    // Select chunks within budget using rendered output estimation
    // (includes XML tags/metadata overhead).
    final selected = <ChunkSearchResult>[];
    var usedTokens = 0;
    final skipHeaders = singleSourceMode;

    for (final chunk in orderedResults) {
      final candidateSelection = List<ChunkSearchResult>.from(selected)
        ..add(chunk);
      final totalIfAdded = _estimateGroupedTokens(
        candidateSelection,
        separator,
        skipHeaders: skipHeaders,
      );

      if (totalIfAdded <= tokenBudget) {
        selected.add(chunk);
        usedTokens = totalIfAdded;
      } else {
        break; // Budget exhausted
      }
    }

    // Build final text - group by source with clear headers (skip headers in singleSourceMode)
    final text = _buildGroupedText(
      selected,
      separator,
      skipHeaders: skipHeaders,
    );

    return AssembledContext(
      text: text,
      includedChunks: selected,
      estimatedTokens: usedTokens,
      remainingBudget: tokenBudget - usedTokens,
    );
  }

  /// Filter to only chunks from the most relevant source.
  /// Most relevant = source with highest total similarity score from top chunks.
  static List<ChunkSearchResult> _filterToMostRelevantSource(
    List<ChunkSearchResult> results,
  ) {
    if (results.isEmpty) return results;

    // Count chunks and sum scores by source
    final sourceScores = <int, double>{};
    final sourceChunkCounts = <int, int>{};

    for (final chunk in results) {
      final sourceId = chunk.sourceId.toInt();
      sourceScores[sourceId] = (sourceScores[sourceId] ?? 0) + chunk.similarity;
      sourceChunkCounts[sourceId] = (sourceChunkCounts[sourceId] ?? 0) + 1;
    }

    // Find source with highest total score
    int? bestSourceId;
    double bestScore = -1;
    for (final entry in sourceScores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestSourceId = entry.key;
      }
    }

    if (bestSourceId == null) return results;

    // Filter to only that source
    return results.where((c) => c.sourceId.toInt() == bestSourceId).toList();
  }

  /// Build text grouped by source with clear document headers.
  static int _estimateGroupedTokens(
    List<ChunkSearchResult> chunks,
    String separator, {
    bool skipHeaders = false,
  }) {
    if (chunks.isEmpty) return 0;
    final rendered = _buildGroupedText(
      chunks,
      separator,
      skipHeaders: skipHeaders,
    );
    return (rendered.length / 4).ceil();
  }

  /// Build text grouped by source with clear document headers.
  static String _buildGroupedText(
    List<ChunkSearchResult> chunks,
    String separator, {
    bool skipHeaders = false,
  }) {
    if (chunks.isEmpty) return '';

    if (skipHeaders) {
      // Keep lean output for single-source mode and preserve selection order.
      return chunks.map(_renderChunkText).join(separator);
    }

    // Group chunks by source
    final bySource = <int, List<ChunkSearchResult>>{};
    for (final chunk in chunks) {
      final sourceId = chunk.sourceId.toInt();
      bySource.putIfAbsent(sourceId, () => []).add(chunk);
    }

    // Sort chunks within each source by chunk index
    for (final list in bySource.values) {
      list.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    }

    // Build text with document headers.
    final buffer = StringBuffer();
    var isFirst = true;

    for (final entry in bySource.entries) {
      if (!isFirst) {
        buffer.write('\n');
      }

      final sourceId = entry.key;
      final chunks = entry.value;

      // Open document tag
      buffer.write('<document id="$sourceId">\n');

      // Add metadata if available
      final firstChunk = chunks.first;
      if (firstChunk.metadata != null) {
        buffer.write('  <metadata>${firstChunk.metadata}</metadata>\n');
      }

      // Add content
      buffer.write('  <content>\n');
      buffer.write(chunks.map(_renderChunkText).join('\n\n'));
      buffer.write('\n  </content>\n');

      // Close document tag
      buffer.write('</document>\n');

      isFirst = false;
    }

    return buffer.toString();
  }

  /// Diversify by avoiding consecutive chunks from same source.
  static List<ChunkSearchResult> _diversifySources(
    List<ChunkSearchResult> results,
  ) {
    final diverse = <ChunkSearchResult>[];
    final remaining = List<ChunkSearchResult>.from(results);
    int? lastSourceId;

    while (remaining.isNotEmpty) {
      // Find next chunk not from last source
      final idx = remaining.indexWhere(
        (r) => r.sourceId.toInt() != lastSourceId,
      );

      if (idx >= 0) {
        diverse.add(remaining.removeAt(idx));
        lastSourceId = diverse.last.sourceId.toInt();
      } else {
        // All remaining are from same source
        diverse.addAll(remaining);
        break;
      }
    }

    return diverse;
  }

  /// Order by source ID then chunk index (maintains document order).
  static List<ChunkSearchResult> _orderChronologically(
    List<ChunkSearchResult> results,
  ) {
    final sorted = List<ChunkSearchResult>.from(results);
    sorted.sort((a, b) {
      final sourceCompare = a.sourceId.compareTo(b.sourceId);
      if (sourceCompare != 0) return sourceCompare;
      return a.chunkIndex.compareTo(b.chunkIndex);
    });
    return sorted;
  }

  /// Format context for LLM prompt.
  ///
  /// Creates a prompt that instructs the LLM to answer based ONLY on
  /// the provided documents. Uses bilingual instructions for better
  /// compliance with smaller models.
  static String formatForPrompt({
    required String query,
    required AssembledContext context,
    String? systemInstruction,
    bool useStrictMode =
        true, // Strict mode instructs LLM to ONLY use documents
  }) {
    if (context.text.isEmpty) {
      return query;
    }

    // Default instruction: bilingual for better model understanding
    final instruction = systemInstruction ??
        (useStrictMode
            ? 'Answer the question based ONLY on the documents below. If the information is not in the documents, say "I could not find the information in the provided documents".'
            : 'Answer based on the following documents:');

    return '''$instruction

--- Reference Documents ---
${context.text}
--- End of Documents ---

Question: $query

Answer:''';
  }

  /// Build context with REFRAG-style compression.
  ///
  /// Uses PromptCompressor to reduce token count while preserving key information.
  /// This is an async method unlike [build].
  ///
  /// [searchResults] - Chunks ranked by relevance.
  /// [tokenBudget] - Maximum tokens to use.
  /// [compressionLevel] - How aggressively to compress (0=minimal, 1=balanced, 2=aggressive).
  /// [language] - Language for stopword filtering ("ko" or "en").
  static Future<AssembledContext> buildWithCompression({
    required List<ChunkSearchResult> searchResults,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int compressionLevel = 1, // 0=minimal, 1=balanced, 2=aggressive
    String language = 'ko',
    bool singleSourceMode = false,
  }) async {
    if (searchResults.isEmpty) {
      return const AssembledContext(
        text: '',
        includedChunks: [],
        estimatedTokens: 0,
        remainingBudget: 0,
      );
    }

    // First, apply standard filtering and ordering
    var filteredResults = searchResults;
    if (singleSourceMode) {
      filteredResults = _filterToMostRelevantSource(searchResults);
    }

    final orderedResults = switch (strategy) {
      ContextStrategy.relevanceFirst => filteredResults,
      ContextStrategy.diverseSources => _diversifySources(filteredResults),
      ContextStrategy.chronological => _orderChronologically(filteredResults),
    };

    // Import compression utilities dynamically
    final compressText = await _compressChunksText(
      orderedResults,
      tokenBudget,
      compressionLevel,
      language,
    );

    final estimatedTokens = (compressText.length / 4).ceil();

    return AssembledContext(
      text: compressText,
      includedChunks: orderedResults,
      estimatedTokens: estimatedTokens,
      remainingBudget: tokenBudget - estimatedTokens,
    );
  }

  /// Internal: Compress chunks text using Rust compression.
  static Future<String> _compressChunksText(
    List<ChunkSearchResult> chunks,
    int tokenBudget,
    int level,
    String language,
  ) async {
    // Combine text from chunks
    final combinedText = chunks.map(_renderChunkText).join('\n\n');

    // Apply compression
    final maxChars = tokenBudget * 4; // Rough token to char conversion
    final options = compression.CompressionOptions(
      removeStopwords: false, // Disabled - damages context
      removeDuplicates: true,
      language: language,
      level: level,
    );

    final result = await compression.compressText(
      text: combinedText,
      maxChars: maxChars,
      options: options,
    );

    return result.text;
  }
}
