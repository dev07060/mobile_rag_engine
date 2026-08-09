/// Mobile RAG Engine
///
/// A high-performance, on-device RAG (Retrieval-Augmented Generation) engine
/// for Flutter. Run semantic search completely offline on iOS, Android, and
/// macOS.
///
/// ## Quick Start (Recommended)
///
/// ```dart
/// import 'package:mobile_rag_engine/mobile_rag_engine.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // Initialize (just 1 line!)
///   await MobileRag.initialize(
///     tokenizerAsset: 'assets/tokenizer.json',
///     modelAsset: 'assets/model.onnx',
///   );
///
///   runApp(const MyApp());
/// }
///
/// // Add documents
/// await MobileRag.instance.addDocument('Your long document text here');
/// await MobileRag.instance.rebuildIndex();
///
/// // Search with LLM context assembly
/// final result = await MobileRag.instance.search('query', tokenBudget: 2000);
/// final prompt = MobileRag.instance.formatPrompt('query', result);
/// // Send prompt to LLM
/// ```
///
/// ## Advanced Usage
///
/// Most apps should use the [MobileRag] facade. For fine-grained workflows,
/// use the public APIs exported by this package:
///
/// ```dart
/// await MobileRag.initialize(...) // Preferred
/// ```
library;

// Primary API (Singleton Pattern)
export 'mobile_rag.dart';
export 'model_pack.dart';

// High-level services (for advanced usage)
export 'services/rag_config.dart';
export 'services/rag_engine.dart';
export 'services/context_builder.dart';
export 'services/source_rag_service.dart';
export 'services/embedding_service.dart';
export 'services/mobile_rag_vector_store.dart';
export 'services/benchmark_service.dart';
export 'services/quality_test_service.dart';
export 'services/prompt_compressor.dart';
export 'services/text_chunker.dart';

// Document parsing
export 'services/document_parser.dart';
// Re-export document parser functions for backward compatibility.
export 'src/rust/api/document_parser.dart';

// Intent parsing
export 'services/intent_parser.dart';

// Search Result Types (Essential for using search APIs)
export 'src/rust/api/source_rag.dart'
    show
        ChunkSearchResult,
        SourceStats,
        AddSourceResult,
        ChunkData,
        SourceEntry,
        ChunkForReembedding,
        SearchHandle,
        SearchHitMeta,
        ChunkExcerptResult,
        AssembledContextV2;

// Hybrid Search Types
export 'src/rust/api/hybrid_search.dart' show HybridSearchResult;

// User Intent Types (Direct export for parseIntent)
export 'src/rust/api/user_intent.dart';

// Semantic Chunking Types
export 'src/rust/api/semantic_chunker.dart'
    show SemanticChunk, StructuredChunk, ChunkType;

// Error Types
export 'src/rust/api/error.dart' show RagError;

// Note: other low-level Rust exports are hidden by default for better DX.
// If you need them, import 'package:mobile_rag_engine/src/rust/api/...' directly.
