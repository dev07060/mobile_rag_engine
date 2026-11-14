// lib/main.dart

import 'package:flutter/material.dart';

import 'example_model.dart';
import 'screens/app_docs_screen.dart';
import 'screens/benchmark_screen.dart';
import 'screens/quality_test_screen.dart';
import 'screens/chunking_test_screen.dart';
import 'widgets/status_card.dart';
import 'widgets/collection_section.dart';
import 'widgets/document_section.dart';
import 'widgets/search_section.dart';
import 'widgets/source_list_section.dart';
import 'services/rag_controller.dart';

enum _FeatureMenuAction { appDocs, chunkingTest, benchmark, qualityTest }

/// Chosen at build time with `--dart-define=EXAMPLE_MODEL=minilm|koen`.
final ExampleModel exampleModel = resolveExampleModel();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Mobile RAG Engine (Singleton) from the model's Model Pack.
  // KoEn-E5-Tiny also sets the recipe's hybrid weights (0.5 / 0.5); MiniLM
  // keeps the engine default (0.2 / 0.8). See lib/example_model.dart.
  await exampleModel.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final RagController _controller = RagController(model: exampleModel);

  @override
  void initState() {
    super.initState();
    _controller.initializeStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _deleteSource(BuildContext context, int sourceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Source'),
        content: Text('Delete source #$sourceId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _controller.deleteSource(sourceId);
    }
  }

  Future<void> _deleteAllDocuments(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Documents'),
        content: const Text(
          'Are you sure you want to delete all documents? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _controller.deleteAllDocuments();
    }
  }

  void _openFeatureMenuAction(BuildContext context, _FeatureMenuAction action) {
    if (!_controller.isReady) return;
    switch (action) {
      case _FeatureMenuAction.appDocs:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AppDocsScreen(model: exampleModel)),
        );
        break;
      case _FeatureMenuAction.chunkingTest:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ChunkingTestScreen()));
        break;
      case _FeatureMenuAction.benchmark:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const BenchmarkScreen()));
        break;
      case _FeatureMenuAction.qualityTest:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const QualityTestScreen()));
        break;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('🔍 Local RAG Engine'),
            centerTitle: true,
            actions: [
              PopupMenuButton<_FeatureMenuAction>(
                tooltip: 'Feature Menu',
                icon: const Icon(Icons.apps),
                onSelected: (action) => _openFeatureMenuAction(context, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _FeatureMenuAction.appDocs,
                    child: Text('App docs (E1 questions)'),
                  ),
                  PopupMenuItem(
                    value: _FeatureMenuAction.chunkingTest,
                    child: Text('Chunking Test'),
                  ),
                  PopupMenuItem(
                    value: _FeatureMenuAction.benchmark,
                    child: Text('Benchmark'),
                  ),
                  PopupMenuItem(
                    value: _FeatureMenuAction.qualityTest,
                    child: Text('Quality Test'),
                  ),
                ],
              ),
            ],
          ),
          body: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatusCard(
                      status: _controller.status,
                      isLoading: _controller.isLoading,
                      isReady: _controller.isReady,
                    ),
                    const SizedBox(height: 24),
                    CollectionSection(
                      collectionController: _controller.collectionController,
                      activeCollectionId: _controller.activeCollectionId,
                      knownCollectionIds: _controller.knownCollectionIds,
                      isReady: _controller.isReady,
                      isLoading: _controller.isLoading,
                      onApply: () => _controller.switchCollection(
                        _controller.collectionController.text,
                      ),
                      onChipSelected: _controller.switchCollection,
                      onWaitWarmup: _controller.waitWarmup,
                      onRebuild: _controller.rebuildActive,
                    ),
                    const SizedBox(height: 12),
                    DocumentSection(
                      docController: _controller.docController,
                      isReady: _controller.isReady,
                      isLoading: _controller.isLoading,
                      onSave: _controller.saveDocument,
                      onImport: _controller.importAndEmbedDocument,
                    ),
                    const Divider(height: 40),
                    SearchSection(
                      queryController: _controller.queryController,
                      activeCollectionId: _controller.activeCollectionId,
                      topK: _controller.topK,
                      selectedSourceId: _controller.selectedSourceId,
                      sources: _controller.sources,
                      searchResults: _controller.searchResults,
                      isReady: _controller.isReady,
                      isLoading: _controller.isLoading,
                      onTopKChanged: _controller.setTopK,
                      onSourceFilterChanged: _controller.setSelectedSourceId,
                      onSearch: _controller.searchDocuments,
                    ),
                    const Divider(height: 40),
                    SourceListSection(
                      activeCollectionId: _controller.activeCollectionId,
                      sources: _controller.sources,
                      isReady: _controller.isReady,
                      isLoading: _controller.isLoading,
                      onRefresh: _controller.loadSources,
                      onDelete: (ctx, id) => _deleteSource(ctx, id),
                      onLoadSamples: _controller.loadSampleDocuments,
                      onDeleteAll: () => _deleteAllDocuments(context),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
