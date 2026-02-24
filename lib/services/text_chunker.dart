/// Utility for splitting text into semantic chunks.
library;

import '../src/rust/api/semantic_chunker.dart' as chunker;
import '../src/internal/defaults.dart';
import '../src/internal/validation.dart';

/// Utility class for splitting text into smaller chunks for RAG.
///
/// Wraps the low-level Rust semantic chunker functions.
class TextChunker {
  TextChunker._();

  /// Chunk text using Markdown structure-aware splitter.
  ///
  /// Preserves headers, code blocks, and tables.
  ///
  /// [text] - The markdown text to split.
  /// [maxChars] - Maximum characters per chunk (default: [kDefaultMaxChunkChars]).
  static Future<List<chunker.StructuredChunk>> markdown(
    String text, {
    int maxChars = kDefaultMaxChunkChars,
  }) async {
    final normalizedMaxChars = normalizeMaxChunkChars(
      maxChars,
      context: 'TextChunker.markdown',
    );
    return chunker.markdownChunk(text: text, maxChars: normalizedMaxChars);
  }

  /// Chunk text using standard recursive character splitter.
  ///
  /// Splits by paragraphs, then sentences, then words to fit within [maxChars].
  ///
  /// [text] - The text to split.
  /// [maxChars] - Maximum characters per chunk (default: [kDefaultMaxChunkChars]).
  /// [overlapChars] - Overlap between chunks for context continuity
  /// (default: [kDefaultOverlapChars]).
  static Future<List<chunker.SemanticChunk>> recursive(
    String text, {
    int maxChars = kDefaultMaxChunkChars,
    int overlapChars = kDefaultOverlapChars,
  }) async {
    final normalizedMaxChars = normalizeMaxChunkChars(
      maxChars,
      context: 'TextChunker.recursive',
    );
    final normalizedOverlapChars = normalizeOverlapChars(
      overlapChars,
      context: 'TextChunker.recursive',
    );
    return chunker.semanticChunkWithOverlap(
      text: text,
      maxChars: normalizedMaxChars,
      overlapChars: normalizedOverlapChars,
    );
  }

  /// Classify a text chunk by type (e.g., definition, list, code).
  ///
  /// Uses rule-based pattern matching to determine the likely content type.
  static Future<chunker.ChunkType> classify(String text) async =>
      chunker.classifyChunk(text: text);
}
