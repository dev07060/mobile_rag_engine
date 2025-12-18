/// Mobile RAG Engine
///
/// A high-performance, on-device RAG (Retrieval-Augmented Generation) engine
/// for Flutter. Run semantic search completely offline on iOS and Android.
///
/// ## Quick Start (Simple API)
///
/// ```dart
/// import 'package:mobile_rag_engine/mobile_rag_engine.dart';
///
/// // Initialize
/// await RustLib.init();
/// await initTokenizer(tokenizerPath: 'path/to/tokenizer.json');
/// await EmbeddingService.init(modelBytes);
/// await initDb(dbPath: 'path/to/rag.db');
///
/// // Add documents
/// final embedding = await EmbeddingService.embed("Your text");
/// await addDocument(dbPath: dbPath, content: "Your text", embedding: embedding);
///
/// // Search
/// final queryEmb = await EmbeddingService.embed("query");
/// final results = await searchSimilar(dbPath: dbPath, queryEmbedding: queryEmb, topK: 5);
/// ```
///
/// ## LLM-Optimized API (with Chunking)
///
/// ```dart
/// // Initialize
/// final rag = SourceRagService(dbPath: 'path/to/rag.db');
/// await rag.init();
///
/// // Add long document (auto-chunked)
/// await rag.addSourceWithChunking(longDocument);
/// await rag.rebuildIndex();
///
/// // Search with LLM context assembly
/// final result = await rag.search("query", tokenBudget: 2000);
/// final prompt = rag.formatPrompt("query", result);
/// // Send prompt to LLM
/// ```
library mobile_rag_engine;

// Core RAG functions (simple API)
export 'src/rust/api/simple_rag.dart';

// Source-based RAG functions (chunked API)
export 'src/rust/api/source_rag.dart';

// Tokenizer functions
export 'src/rust/api/tokenizer.dart';

// Services
export 'services/embedding_service.dart';
export 'src/rust/api/semantic_chunker.dart'; // Rust-based semantic chunking
export 'src/rust/api/hybrid_search.dart'; // Hybrid search (Vector + BM25)
export 'src/rust/api/bm25_search.dart'; // BM25 keyword search
export 'services/context_builder.dart';
export 'services/source_rag_service.dart';

// Rust library initialization
export 'src/rust/frb_generated.dart' show RustLib;
