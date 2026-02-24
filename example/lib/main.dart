// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'screens/benchmark_screen.dart';
import 'screens/quality_test_screen.dart';
import 'screens/chunking_test_screen.dart';
import 'widgets/status_card.dart';
import 'widgets/collection_section.dart';
import 'widgets/document_section.dart';
import 'widgets/search_section.dart';
import 'widgets/source_list_section.dart';

enum _FeatureMenuAction { chunkingTest, benchmark, qualityTest }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Mobile RAG Engine (Singleton)
  // This automatically handles Rust initialization, threads, and model loading.
  await MobileRag.initialize(
    tokenizerAsset: 'assets/tokenizer.json',
    modelAsset: 'assets/model.onnx',
    databaseName: 'rag_db.sqlite',
    deferIndexWarmup: true,
    threadLevel: ThreadUseLevel.medium, // Default: ~40% of cores
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ── State ──────────────────────────────────────────────────────────────
  String _status = "Ready";
  bool _isReady = true; // MobileRag is already initialized in main()
  bool _isLoading = false;

  final TextEditingController _docController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  List<HybridSearchResult> _searchResults = [];
  List<SourceEntry> _sources = [];
  int? _selectedSourceId;
  int _topK = 5;
  final TextEditingController _collectionController = TextEditingController(
    text: SourceRagService.defaultCollectionId,
  );
  String _activeCollectionId = SourceRagService.defaultCollectionId;
  final Set<String> _knownCollectionIds = {
    SourceRagService.defaultCollectionId,
    'business',
    'travel',
    'personal',
  };

  bool get _isDefaultCollection =>
      _activeCollectionId == SourceRagService.defaultCollectionId;
  CollectionRag get _activeCollection =>
      MobileRag.instance.inCollection(_activeCollectionId);

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (MobileRag.isInitialized) {
      final vocab = MobileRag.instance.vocabSize;
      _status = "✅ Ready!\nVocab: $vocab | Embedding: 384 dims";
      _loadSources();
    } else {
      _status = "❌ MobileRag not initialzed in main()";
      _isReady = false;
    }
  }

  @override
  void dispose() {
    _docController.dispose();
    _queryController.dispose();
    _collectionController.dispose();
    super.dispose();
  }

  // ── Collection Logic ──────────────────────────────────────────────────

  String _normalizeCollectionId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return SourceRagService.defaultCollectionId;
    return trimmed;
  }

  Future<void> _switchCollection(String rawCollectionId) async {
    final normalized = _normalizeCollectionId(rawCollectionId);
    setState(() {
      _isLoading = true;
      _activeCollectionId = normalized;
      _knownCollectionIds.add(normalized);
      _collectionController.text = normalized;
      _selectedSourceId = null;
      _searchResults.clear();
      _status = 'Switching to collection "$normalized"...';
    });
    await _loadSources();
    setState(() {
      _status =
          '✅ Active collection: "$_activeCollectionId" (${_sources.length} sources)';
      _isLoading = false;
    });
  }

  Future<void> _waitWarmup() async {
    setState(() {
      _isLoading = true;
      _status = 'Waiting warmup for "$_activeCollectionId"...';
    });
    try {
      await _activeCollection.warmupFuture;
      setState(() {
        _status = '✅ Warmup done for "$_activeCollectionId".';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = '❌ Warmup error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _rebuildActive() async {
    setState(() {
      _isLoading = true;
      _status = 'Rebuilding "$_activeCollectionId"...';
    });
    try {
      await _activeCollection.rebuildIndex(force: true);
      await _loadSources();
      setState(() {
        _status = '✅ Rebuild complete for "$_activeCollectionId".';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = '❌ Rebuild error: $e';
        _isLoading = false;
      });
    }
  }

  // ── Source CRUD ────────────────────────────────────────────────────────

  Future<void> _loadSources() async {
    try {
      final sources = _isDefaultCollection
          ? await MobileRag.instance.listSources()
          : await _activeCollection.listSources();
      setState(() => _sources = sources);
    } catch (e) {
      debugPrint('Failed to load sources: $e');
    }
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

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      if (_isDefaultCollection) {
        await MobileRag.instance.removeSource(sourceId);
        await MobileRag.instance.rebuildIndex();
      } else {
        await _activeCollection.removeSource(sourceId);
        await _activeCollection.rebuildIndex();
      }
      await _loadSources();
      setState(() {
        _status = "✅ Deleted source $sourceId";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = "❌ Delete error: $e";
        _isLoading = false;
      });
    }
  }

  // ── Document Add ──────────────────────────────────────────────────────

  /// Save document: text -> chunking -> embedding -> DB storage
  Future<void> _saveDocument() async {
    final text = _docController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _status =
          'Processing document in "$_activeCollectionId" (chunking + embedding)...';
    });

    try {
      final result = _isDefaultCollection
          ? await MobileRag.instance.addDocument(
              text,
              name: "Manual Entry ${DateTime.now().toIso8601String()}",
              onProgress: (done, total) {
                if (done % 10 == 0 || done == total) {
                  debugPrint('Embedding progress: $done/$total');
                }
                setState(() => _status = "Embedding chunks: $done/$total");
              },
            )
          : await _activeCollection.addDocument(
              text,
              name:
                  "[$_activeCollectionId] Manual Entry ${DateTime.now().toIso8601String()}",
              onProgress: (done, total) {
                if (done % 10 == 0 || done == total) {
                  debugPrint('Embedding progress: $done/$total');
                }
                setState(() => _status = "Embedding chunks: $done/$total");
              },
            );

      if (result.isDuplicate) {
        setState(() {
          _status =
              "⚠️ Duplicate detected!\nDocument already exists in database.";
          _isLoading = false;
        });
      } else {
        if (_isDefaultCollection) {
          await MobileRag.instance.rebuildIndex();
        } else {
          await _activeCollection.rebuildIndex();
        }
        await _loadSources();

        setState(() {
          _status =
              "✅ Saved!\n"
              "📄 Source ID: ${result.sourceId}\n"
              "📦 Chunks created: ${result.chunkCount}\n"
              "(Each chunk ~500 chars with 50 char overlap)";
          _isLoading = false;
        });
        _docController.clear();
      }
    } catch (e) {
      setState(() {
        _status = "❌ Save error: $e";
        _isLoading = false;
      });
    }
  }

  /// Import PDF/DOCX/Markdown file and embed
  Future<void> _importAndEmbedDocument() async {
    setState(() {
      _isLoading = true;
      _status = "Selecting file...";
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'md', 'markdown'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _status = "⚠️ No file selected";
          _isLoading = false;
        });
        return;
      }

      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) {
        setState(() {
          _status = "❌ Could not get file path";
          _isLoading = false;
        });
        return;
      }

      setState(() => _status = "Reading file: ${file.name}");

      String extractedText;
      final ext = filePath.split('.').last.toLowerCase();

      if (ext == 'md' || ext == 'markdown') {
        extractedText = await File(filePath).readAsString();
        setState(
          () => _status = "Markdown loaded! (${extractedText.length} chars)",
        );
      } else {
        final bytes = await File(filePath).readAsBytes();
        setState(() => _status = "Extracting text from ${file.name}...");
        extractedText = await DocumentParser.parse(bytes.toList());
      }

      if (extractedText.isEmpty) {
        setState(() {
          _status = "⚠️ No text extracted from file";
          _isLoading = false;
        });
        return;
      }

      setState(
        () => _status =
            "Text extracted! (${extractedText.length} chars)\nProcessing chunks...",
      );

      final addResult = _isDefaultCollection
          ? await MobileRag.instance.addDocument(
              extractedText,
              metadata: '{"filename": "${file.name}"}',
              name: file.name,
              filePath: filePath,
              onProgress: (done, total) {
                if (done % 10 == 0 || done == total) {
                  debugPrint('Embedding progress: $done/$total');
                }
                setState(() => _status = "Embedding chunks: $done/$total");
              },
            )
          : await _activeCollection.addDocument(
              extractedText,
              metadata: '{"filename": "${file.name}"}',
              name: "[$_activeCollectionId] ${file.name}",
              filePath: filePath,
              onProgress: (done, total) {
                if (done % 10 == 0 || done == total) {
                  debugPrint('Embedding progress: $done/$total');
                }
                setState(() => _status = "Embedding chunks: $done/$total");
              },
            );

      if (addResult.isDuplicate) {
        if (addResult.chunkCount > 0) {
          if (_isDefaultCollection) {
            await MobileRag.instance.rebuildIndex();
          } else {
            await _activeCollection.rebuildIndex();
          }
          await _loadSources();
          setState(() {
            _status =
                "✅ Resumed & Completed!\n"
                "📄 File: ${file.name}\n"
                "📦 ${addResult.message}";
            _isLoading = false;
          });
        } else {
          setState(() {
            _status = "ℹ️ Already processed.\n${file.name} is up to date.";
            _isLoading = false;
          });
        }
      } else {
        if (_isDefaultCollection) {
          await MobileRag.instance.rebuildIndex();
        } else {
          await _activeCollection.rebuildIndex();
        }
        await _loadSources();

        setState(() {
          _status =
              "✅ Document imported!\n"
              "📄 File: ${file.name}\n"
              "📝 Text: ${extractedText.length} chars\n"
              "📦 ${addResult.message}";
          _isLoading = false;
        });
      }
    } catch (e, st) {
      setState(() {
        _status = "❌ Import error: $e\n$st";
        _isLoading = false;
      });
    }
  }

  // ── Search ────────────────────────────────────────────────────────────

  Future<void> _searchDocuments() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _status = 'Searching "$_activeCollectionId" chunks (Hybrid)...';
    });

    try {
      final results = _isDefaultCollection
          ? await MobileRag.instance.searchHybrid(
              query,
              topK: _topK,
              sourceIds: _selectedSourceId != null
                  ? [_selectedSourceId!]
                  : null,
            )
          : await _activeCollection.searchHybrid(
              query,
              topK: _topK,
              sourceIds: _selectedSourceId != null
                  ? [_selectedSourceId!]
                  : null,
            );

      setState(() {
        _searchResults = results;
        _status =
            "✅ Search complete!\n"
            "Found ${results.length} relevant chunks (Hybrid Search)";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = "❌ Search error: $e";
        debugPrint(e.toString());
        _isLoading = false;
      });
    }
  }

  // ── Sample Data ───────────────────────────────────────────────────────

  Future<void> _loadSampleDocuments() async {
    setState(() => _isLoading = true);
    try {
      final samples = [
        "Apple 사과는 비타민이 풍부한 과일로, 하루에 하나씩 먹으면 건강에 좋다고 알려져 있습니다.",
        "Apple Inc.는 아이폰, 맥북, 아이패드 등을 만드는 미국의 IT 기업입니다. 스티브 잡스가 설립했습니다.",
        "스마트폰 배터리 수명을 연장하려면 완전 방전을 피하고, 20-80% 사이를 유지하는 것이 좋습니다.",
        "휴대폰 충전 시 고속 충전보다 일반 충전이 배터리 건강에 더 좋다는 연구 결과가 있습니다.",
        "HNSW 알고리즘은 그래프 기반 ANN 검색 방식으로, 계층적 구조를 통해 효율적인 벡터 검색을 제공합니다.",
        "BM25는 TF-IDF를 개선한 키워드 검색 알고리즘으로, 문서 길이 정규화가 특징입니다.",
        "오늘 서울 날씨는 맑고 기온은 영하 5도입니다. 외출 시 따뜻하게 입으세요.",
        "제주도는 한국에서 가장 인기 있는 여행지로, 한라산과 해변이 유명합니다.",
      ];
      int totalChunks = 0;
      for (var i = 0; i < samples.length; i++) {
        setState(
          () => _status =
              'Adding sample ${i + 1}/${samples.length} to "$_activeCollectionId"...',
        );
        final result = _isDefaultCollection
            ? await MobileRag.instance.addDocument(
                samples[i],
                name: "Sample ${i + 1}",
              )
            : await _activeCollection.addDocument(
                samples[i],
                name: "[$_activeCollectionId] Sample ${i + 1}",
              );
        totalChunks += result.chunkCount;
      }
      if (_isDefaultCollection) {
        await MobileRag.instance.rebuildIndex();
      } else {
        await _activeCollection.rebuildIndex();
      }
      await _loadSources();

      setState(() {
        _status =
            '✅ Saved ${samples.length} sample documents in "$_activeCollectionId"!\n'
            "📦 Total chunks: $totalChunks";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = "❌ Sample save error: $e";
        _isLoading = false;
      });
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

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _status = 'Deleting all documents in "$_activeCollectionId"...';
    });

    try {
      late final SourceStats stats;
      if (_isDefaultCollection) {
        stats = await MobileRag.instance.engine.getStats();
        await MobileRag.instance.clearAllData();
      } else {
        stats = await _activeCollection.getStats();
        final sourceIds = _sources
            .map((s) => s.id.toInt())
            .toList(growable: false);
        for (final sourceId in sourceIds) {
          await _activeCollection.removeSource(sourceId);
        }
        await _activeCollection.rebuildIndex(force: true);
      }
      await _loadSources();

      setState(() {
        _searchResults.clear();
        _status =
            '✅ Deleted all documents in "$_activeCollectionId"!\n'
            "Previously had ${stats.sourceCount} sources.";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = "❌ Delete error: $e";
        _isLoading = false;
      });
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void _openFeatureMenuAction(BuildContext context, _FeatureMenuAction action) {
    if (!_isReady) return;
    switch (action) {
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatusCard(
                  status: _status,
                  isLoading: _isLoading,
                  isReady: _isReady,
                ),

                const SizedBox(height: 24),

                CollectionSection(
                  collectionController: _collectionController,
                  activeCollectionId: _activeCollectionId,
                  knownCollectionIds: _knownCollectionIds,
                  isReady: _isReady,
                  isLoading: _isLoading,
                  onApply: () => _switchCollection(_collectionController.text),
                  onChipSelected: _switchCollection,
                  onWaitWarmup: _waitWarmup,
                  onRebuild: _rebuildActive,
                ),

                const SizedBox(height: 12),

                DocumentSection(
                  docController: _docController,
                  isReady: _isReady,
                  isLoading: _isLoading,
                  onSave: _saveDocument,
                  onImport: _importAndEmbedDocument,
                ),

                const Divider(height: 40),

                SearchSection(
                  queryController: _queryController,
                  activeCollectionId: _activeCollectionId,
                  topK: _topK,
                  selectedSourceId: _selectedSourceId,
                  sources: _sources,
                  searchResults: _searchResults,
                  isReady: _isReady,
                  isLoading: _isLoading,
                  onTopKChanged: (v) => setState(() => _topK = v),
                  onSourceFilterChanged: (v) =>
                      setState(() => _selectedSourceId = v),
                  onSearch: _searchDocuments,
                ),

                const Divider(height: 40),

                SourceListSection(
                  activeCollectionId: _activeCollectionId,
                  sources: _sources,
                  isReady: _isReady,
                  isLoading: _isLoading,
                  onRefresh: _loadSources,
                  onDelete: _deleteSource,
                  onLoadSamples: _loadSampleDocuments,
                  onDeleteAll: () => _deleteAllDocuments(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
