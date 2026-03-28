/// Context assembly for LLM prompts.
///
/// ContextBuilder takes search results and assembles them into
/// an optimized context string within a token budget.
library;

import 'package:flutter/foundation.dart';

import '../src/rust/api/source_rag.dart';
import '../src/rust/api/compression_utils.dart' as compression;
import '../src/rust/api/tokenizer.dart';

typedef TokenCounter = int Function(String text);
typedef CompressionRunner = Future<String> Function(
  String renderedText,
  int maxChars,
  int level,
  String language,
);

class PromptBudgetOptions {
  final int safetyMarginTokens;
  final int? fixedPromptOverheadTokens;
  final TokenCounter? targetPromptTokenCounter;

  const PromptBudgetOptions({
    this.safetyMarginTokens = 0,
    this.fixedPromptOverheadTokens,
    this.targetPromptTokenCounter,
  });
}

@visibleForTesting
({String rawType, String? headerPath}) decodeStructuredChunkType(
  String chunkType,
) {
  // TODO(metadata-breaking): stop multiplexing chunk type and contextual path
  // inside a single string field once the public/runtime schema can change.
  final separator = chunkType.indexOf('|');
  if (separator < 0) {
    return (rawType: chunkType, headerPath: null);
  }

  final rawType = chunkType.substring(0, separator);
  final headerPath = chunkType.substring(separator + 1).trim();
  return (rawType: rawType, headerPath: headerPath.isEmpty ? null : headerPath);
}

String encodeStructuredChunkType({
  required String rawType,
  String? headerPath,
}) {
  final normalizedHeaderPath = headerPath?.trim();
  if (normalizedHeaderPath == null || normalizedHeaderPath.isEmpty) {
    return rawType;
  }
  return '$rawType|$normalizedHeaderPath';
}

String renderContextText({required String content, required String chunkType}) {
  final decoded = decodeStructuredChunkType(chunkType);
  final headerPath = decoded.headerPath;
  if (headerPath == null) {
    return content;
  }

  return 'Header Path: $headerPath\n$content';
}

/// Assembled context ready for LLM consumption.
class AssembledContext {
  /// The combined text of all selected chunks.
  final String text;

  /// Chunks that were included in the context.
  final List<ChunkSearchResult> includedChunks;

  /// Exact engine-tokenizer count for `text`.
  /// The legacy field name is kept for backward compatibility.
  // TODO(token-naming-breaking): rename to exactTokens in the next breaking API.
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

String _chunkCacheKey(ChunkSearchResult chunk) =>
    '${chunk.sourceId}:${chunk.chunkId}:${chunk.chunkIndex}';

class _RenderedSelectionState {
  _RenderedSelectionState({
    required this.separator,
    required this.skipHeaders,
    required this.tokenCounter,
  });

  final String separator;
  final bool skipHeaders;
  final TokenCounter tokenCounter;

  final Map<String, String> _chunkTextCache = {};
  final Map<String, int> _tokenCountCache = {};
  final List<ChunkSearchResult> _selectedInOrder = [];

  final List<int> _sourceOrder = [];
  final Map<int, List<ChunkSearchResult>> _selectedBySource = {};
  final Map<int, String> _renderedSourceBlocks = {};

  String _renderedText = '';
  int _measuredTokens = 0;

  List<ChunkSearchResult> get selectedChunks =>
      List<ChunkSearchResult>.unmodifiable(_selectedInOrder);

  String get renderedText => _renderedText;

  int get measuredTokens => _measuredTokens;

  bool tryAddChunk(ChunkSearchResult chunk, int tokenBudget) {
    final candidateText = skipHeaders
        ? _renderCandidateWithoutHeaders(chunk)
        : _renderCandidateWithHeaders(chunk);
    final candidateTokens = _countTokens(candidateText);

    if (candidateTokens > tokenBudget) {
      return false;
    }

    _acceptChunk(
      chunk: chunk,
      renderedText: candidateText,
      measuredTokens: candidateTokens,
    );
    return true;
  }

  String _renderCandidateWithoutHeaders(ChunkSearchResult chunk) {
    final renderedChunk = _renderChunk(chunk);
    if (_renderedText.isEmpty) {
      return renderedChunk;
    }
    return '$_renderedText$separator$renderedChunk';
  }

  String _renderCandidateWithHeaders(ChunkSearchResult chunk) {
    final sourceId = chunk.sourceId.toInt();
    final selectedForSource =
        List<ChunkSearchResult>.from(_selectedBySource[sourceId] ?? const [])
          ..add(chunk)
          ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    final candidateBlock = _renderSourceBlock(sourceId, selectedForSource);

    final buffer = StringBuffer();
    var isFirst = true;
    final sourceOrder = _sourceOrder.contains(sourceId)
        ? _sourceOrder
        : [..._sourceOrder, sourceId];

    for (final currentSourceId in sourceOrder) {
      if (!isFirst) {
        buffer.write('\n');
      }
      buffer.write(
        currentSourceId == sourceId
            ? candidateBlock
            : _renderedSourceBlocks[currentSourceId],
      );
      isFirst = false;
    }

    return buffer.toString();
  }

  void _acceptChunk({
    required ChunkSearchResult chunk,
    required String renderedText,
    required int measuredTokens,
  }) {
    _selectedInOrder.add(chunk);
    _renderedText = renderedText;
    _measuredTokens = measuredTokens;

    if (skipHeaders) {
      return;
    }

    final sourceId = chunk.sourceId.toInt();
    final selectedForSource =
        _selectedBySource.putIfAbsent(sourceId, () => <ChunkSearchResult>[]);
    selectedForSource.add(chunk);
    selectedForSource.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    if (!_sourceOrder.contains(sourceId)) {
      _sourceOrder.add(sourceId);
    }

    _renderedSourceBlocks[sourceId] = _renderSourceBlock(
      sourceId,
      selectedForSource,
    );
  }

  int _countTokens(String text) {
    return _tokenCountCache.putIfAbsent(text, () => tokenCounter(text));
  }

  String _renderChunk(ChunkSearchResult chunk) {
    return _chunkTextCache.putIfAbsent(
      _chunkCacheKey(chunk),
      () => ContextBuilder._renderChunkText(chunk),
    );
  }

  String _renderSourceBlock(int sourceId, List<ChunkSearchResult> chunks) {
    final buffer = StringBuffer();
    buffer.write('<document id="$sourceId">\n');

    final firstChunk = chunks.first;
    if (firstChunk.metadata != null) {
      buffer.write('  <metadata>${firstChunk.metadata}</metadata>\n');
    }

    buffer.write('  <content>\n');
    buffer.write(chunks.map(_renderChunk).join('\n\n'));
    buffer.write('\n  </content>\n');
    buffer.write('</document>\n');
    return buffer.toString();
  }
}

/// Builds optimized context for LLM prompts.
class ContextBuilder {
  ContextBuilder._();

  @visibleForTesting
  static TokenCounter? debugTokenCounterOverride;

  @visibleForTesting
  static CompressionRunner? debugCompressionRunnerOverride;

  static String _renderChunkText(ChunkSearchResult chunk) {
    return renderContextText(
      content: chunk.content,
      chunkType: chunk.chunkType,
    );
  }

  static int _countTokens(String text) {
    final override = debugTokenCounterOverride;
    if (override != null) {
      return override(text);
    }
    return countTokens(text: text);
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

    final skipHeaders = singleSourceMode;
    final state = _RenderedSelectionState(
      separator: separator,
      skipHeaders: skipHeaders,
      tokenCounter: _countTokens,
    );

    for (final chunk in orderedResults) {
      state.tryAddChunk(chunk, tokenBudget);
    }

    final text = state.renderedText;
    final measuredTokens = text.isEmpty ? 0 : state.measuredTokens;

    return AssembledContext(
      text: text,
      includedChunks: state.selectedChunks,
      estimatedTokens: measuredTokens,
      remainingBudget: tokenBudget - measuredTokens,
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

  static String _resolveSystemInstruction({
    String? systemInstruction,
    required bool useStrictMode,
  }) {
    return systemInstruction ??
        (useStrictMode
            ? 'Answer the question based ONLY on the documents below. If the information is not in the documents, say "I could not find the information in the provided documents".'
            : 'Answer based on the following documents:');
  }

  static String _buildPromptText({
    required String instruction,
    required String contextText,
    required String query,
  }) {
    return '''$instruction

--- Reference Documents ---
$contextText
--- End of Documents ---

Question: $query

Answer:''';
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

    final instruction = _resolveSystemInstruction(
      systemInstruction: systemInstruction,
      useStrictMode: useStrictMode,
    );

    return _buildPromptText(
      instruction: instruction,
      contextText: context.text,
      query: query,
    );
  }

  /// Derive how many tokens can be safely assigned to `context.text`
  /// when the downstream consumer budgets the full prompt instead.
  static int deriveContextBudgetForPrompt({
    required int fullPromptBudget,
    required String query,
    String? systemInstruction,
    bool useStrictMode = true,
    PromptBudgetOptions options = const PromptBudgetOptions(),
  }) {
    final promptOverheadTokens = switch (options.targetPromptTokenCounter) {
      final targetCounter? => targetCounter(
          _buildPromptText(
            instruction: _resolveSystemInstruction(
              systemInstruction: systemInstruction,
              useStrictMode: useStrictMode,
            ),
            contextText: '',
            query: query,
          ),
        ),
      null => options.fixedPromptOverheadTokens ?? 0,
    };

    final budget =
        fullPromptBudget - promptOverheadTokens - options.safetyMarginTokens;
    return budget < 0 ? 0 : budget;
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

    final renderText = _buildGroupedText(
      orderedResults,
      '\n\n',
      skipHeaders: singleSourceMode,
    );
    final compressedText = await _compressRenderedTextToBudget(
      renderText,
      tokenBudget,
      compressionLevel,
      language,
    );
    final exactTokens =
        compressedText.isEmpty ? 0 : _countTokens(compressedText);

    return AssembledContext(
      text: compressedText,
      includedChunks: orderedResults,
      estimatedTokens: exactTokens,
      remainingBudget: tokenBudget - exactTokens,
    );
  }

  static Future<String> _compressRenderedTextToBudget(
    String renderedText,
    int tokenBudget,
    int level,
    String language,
  ) async {
    if (renderedText.isEmpty) {
      return '';
    }

    var maxChars = renderedText.length;
    String compressedText = renderedText;
    final options = compression.CompressionOptions(
      removeStopwords: false, // Disabled - damages context
      removeDuplicates: true,
      language: language,
      level: level,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      final override = debugCompressionRunnerOverride;
      if (override != null) {
        compressedText = (await override(
          renderedText,
          maxChars,
          level,
          language,
        ))
            .trimRight();
      } else {
        final result = await compression.compressText(
          text: renderedText,
          maxChars: maxChars,
          options: options,
        );
        compressedText = result.text.trimRight();
      }

      if (compressedText.isEmpty) {
        return compressedText;
      }

      final tokenCount = _countTokens(compressedText);
      if (tokenCount <= tokenBudget) {
        return compressedText;
      }

      final nextMaxChars = ((maxChars * tokenBudget) / tokenCount)
          .floor()
          .clamp(32, maxChars - 1);
      if (nextMaxChars >= maxChars) {
        break;
      }
      maxChars = nextMaxChars;
    }

    return _trimRenderedTextToBudget(compressedText, tokenBudget);
  }

  static String _trimRenderedTextToBudget(String text, int tokenBudget) {
    var current = text.trimRight();

    while (current.isNotEmpty && _countTokens(current) > tokenBudget) {
      final boundary = _previousTrimBoundary(current);
      if (boundary <= 0) {
        return '';
      }
      current = current.substring(0, boundary).trimRight();
    }

    return current;
  }

  static int _previousTrimBoundary(String text) {
    final newlineBoundary = text.lastIndexOf('\n');
    if (newlineBoundary > 0) {
      return newlineBoundary;
    }

    RegExpMatch? sentenceBoundary;
    for (final match in RegExp(
      "[.!?。！？…](?:[\"')\\]\\u2019\\u201d]+)?\\s+",
    ).allMatches(text)) {
      sentenceBoundary = match;
    }
    if (sentenceBoundary != null && sentenceBoundary.end < text.length) {
      return sentenceBoundary.end;
    }

    final paragraphBoundary = text.lastIndexOf(' ');
    if (paragraphBoundary > 0) {
      return paragraphBoundary;
    }

    return 0;
  }
}
