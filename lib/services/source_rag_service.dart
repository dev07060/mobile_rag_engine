/// High-level RAG service for managing sources and chunks.
///
/// This service provides a convenient API that combines:
/// - Rust semantic chunking for document splitting (Unicode sentence/word boundaries)
/// - EmbeddingService for vector generation
/// - Rust source_rag APIs for storage and search
/// - ContextBuilder for LLM context assembly
/// - Hybrid search combining vector and BM25 keyword search

import 'dart:typed_data';
import '../src/rust/api/source_rag.dart';
import '../src/rust/api/semantic_chunker.dart';
import '../src/rust/api/hybrid_search.dart' as hybrid;
import 'context_builder.dart';
import 'embedding_service.dart';

/// Result of adding a source document with automatic chunking.
class SourceAddResult {
  final int sourceId;
  final bool isDuplicate;
  final int chunkCount;
  final String message;

  SourceAddResult({
    required this.sourceId,
    required this.isDuplicate,
    required this.chunkCount,
    required this.message,
  });
}

/// Search result with assembled context.
class RagSearchResult {
  /// Individual chunk results.
  final List<ChunkSearchResult> chunks;
  
  /// Assembled context for LLM.
  final AssembledContext context;

  RagSearchResult({
    required this.chunks,
    required this.context,
  });
}

/// High-level service for source-based RAG operations.
class SourceRagService {
  final String dbPath;
  
  /// Maximum characters per chunk (default: 500)
  final int maxChunkChars;
  
  /// Overlap characters between chunks for context continuity
  final int overlapChars;

  SourceRagService({
    required this.dbPath,
    this.maxChunkChars = 500,
    this.overlapChars = 50,
  });

  /// Initialize the source database.
  Future<void> init() async {
    await initSourceDb(dbPath: dbPath);
  }

  /// Add a source document with automatic chunking and embedding.
  ///
  /// The document is:
  /// 1. Split into chunks based on [chunkConfig]
  /// 2. Each chunk is embedded
  /// 3. Source and chunks are stored in DB
  Future<SourceAddResult> addSourceWithChunking(
    String content, {
    String? metadata,
    void Function(int done, int total)? onProgress,
  }) async {
    // 1. Add source document
    final sourceResult = await addSource(
      dbPath: dbPath,
      content: content,
      metadata: metadata,
    );

    if (sourceResult.isDuplicate) {
      return SourceAddResult(
        sourceId: sourceResult.sourceId.toInt(),
        isDuplicate: true,
        chunkCount: 0,
        message: sourceResult.message,
      );
    }

    // 2. Split into semantic chunks using Rust (Unicode sentence/word boundaries)
    final chunks = semanticChunkWithOverlap(
      text: content,
      maxChars: maxChunkChars,
      overlapChars: overlapChars,
    );
    
    if (chunks.isEmpty) {
      return SourceAddResult(
        sourceId: sourceResult.sourceId.toInt(),
        isDuplicate: false,
        chunkCount: 0,
        message: 'No chunks created',
      );
    }

    // 3. Generate embeddings for each chunk
    final chunkDataList = <ChunkData>[];
    
    for (var i = 0; i < chunks.length; i++) {
      onProgress?.call(i, chunks.length);
      
      final chunk = chunks[i];
      final embedding = await EmbeddingService.embed(chunk.content);
      
      chunkDataList.add(ChunkData(
        content: chunk.content,
        chunkIndex: chunk.index,
        startPos: chunk.startPos,
        endPos: chunk.endPos,
        embedding: Float32List.fromList(embedding),
      ));
    }
    
    onProgress?.call(chunks.length, chunks.length);

    // 4. Store chunks
    await addChunks(
      dbPath: dbPath,
      sourceId: sourceResult.sourceId,
      chunks: chunkDataList,
    );

    return SourceAddResult(
      sourceId: sourceResult.sourceId.toInt(),
      isDuplicate: false,
      chunkCount: chunks.length,
      message: 'Added ${chunks.length} chunks',
    );
  }

  /// Rebuild the HNSW index after adding sources.
  Future<void> rebuildIndex() async {
    await rebuildChunkHnswIndex(dbPath: dbPath);
  }

  /// Search for relevant chunks and assemble context for LLM.
  Future<RagSearchResult> search(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
  }) async {
    // 1. Generate query embedding
    final queryEmbedding = await EmbeddingService.embed(query);

    // 2. Search chunks
    final chunks = await searchChunks(
      dbPath: dbPath,
      queryEmbedding: queryEmbedding,
      topK: topK,
    );

    // 3. Assemble context
    final context = ContextBuilder.build(
      searchResults: chunks,
      tokenBudget: tokenBudget,
      strategy: strategy,
    );

    return RagSearchResult(
      chunks: chunks,
      context: context,
    );
  }

  /// Get the original source document for a chunk.
  Future<String?> getSourceForChunk(ChunkSearchResult chunk) async {
    return await getSource(dbPath: dbPath, sourceId: chunk.sourceId);
  }

  /// Get statistics about stored sources and chunks.
  Future<SourceStats> getStats() async {
    return await getSourceStats(dbPath: dbPath);
  }

  /// Format search results as an LLM prompt.
  String formatPrompt(String query, RagSearchResult result) {
    return ContextBuilder.formatForPrompt(
      query: query,
      context: result.context,
    );
  }

  /// Hybrid search combining vector and keyword (BM25) search.
  ///
  /// This method uses Reciprocal Rank Fusion (RRF) to combine:
  /// - Vector search: semantic similarity using embeddings
  /// - BM25 search: keyword matching for exact terms
  ///
  /// Use this for better results when searching for:
  /// - Proper nouns (names, product models)
  /// - Technical terms or code snippets
  /// - Exact keyword matches
  ///
  /// Parameters:
  /// - [query]: The search query text
  /// - [topK]: Number of results to return (default: 10)
  /// - [vectorWeight]: Weight for vector search (0.0-1.0, default: 0.5)
  /// - [bm25Weight]: Weight for BM25 search (0.0-1.0, default: 0.5)
  Future<List<hybrid.HybridSearchResult>> searchHybrid(
    String query, {
    int topK = 10,
    double vectorWeight = 0.5,
    double bm25Weight = 0.5,
  }) async {
    // 1. Generate query embedding
    final queryEmbedding = await EmbeddingService.embed(query);

    // 2. Perform hybrid search with RRF fusion
    final results = await hybrid.searchHybridWeighted(
      dbPath: dbPath,
      queryText: query,
      queryEmbedding: queryEmbedding,
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
    );

    return results;
  }

  /// Hybrid search with context assembly for LLM.
  ///
  /// Similar to [search] but uses hybrid (vector + BM25) search.
  Future<RagSearchResult> searchHybridWithContext(
    String query, {
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    double vectorWeight = 0.5,
    double bm25Weight = 0.5,
  }) async {
    // 1. Get hybrid search results
    final hybridResults = await searchHybrid(
      query,
      topK: topK,
      vectorWeight: vectorWeight,
      bm25Weight: bm25Weight,
    );

    // 2. Convert to ChunkSearchResult format for context building
    // Note: Hybrid search returns content directly, so we create minimal chunks
    final chunks = hybridResults.map((r) => ChunkSearchResult(
      chunkId: r.docId,
      sourceId: r.docId,  // Same as chunk ID for simple docs
      content: r.content,
      chunkIndex: 0,
      similarity: r.score,  // RRF score as similarity
    )).toList();

    // 3. Assemble context
    final context = ContextBuilder.build(
      searchResults: chunks,
      tokenBudget: tokenBudget,
      strategy: strategy,
    );

    return RagSearchResult(
      chunks: chunks,
      context: context,
    );
  }
}

