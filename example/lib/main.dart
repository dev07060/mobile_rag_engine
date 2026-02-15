// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'screens/benchmark_screen.dart';
import 'screens/quality_test_screen.dart';
import 'screens/chunking_test_screen.dart';

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
  String _status = "Ready";
  bool _isReady = true; // MobileRag is already initialized in main()
  bool _isLoading = false;

  final TextEditingController _docController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  // Store full hybrid results
  List<HybridSearchResult> _searchResults = [];
  // Store source list
  List<SourceEntry> _sources = [];
  int? _selectedSourceId; // Selected source for filtering
  int _topK = 5; // Adjustable topK for search

  @override
  void initState() {
    super.initState();
    // Verify initialization
    if (MobileRag.isInitialized) {
      final vocab = MobileRag.instance.vocabSize;
      _status = "✅ Ready!\nVocab: $vocab | Embedding: 384 dims";
      _loadSources();
    } else {
      _status = "❌ MobileRag not initialzed in main()";
      _isReady = false;
    }
  }

  Future<void> _loadSources() async {
    try {
      final sources = await MobileRag.instance.listSources();
      setState(() {
        _sources = sources;
      });
    } catch (e) {
      debugPrint('Failed to load sources: $e');
    }
  }

  /// Save document: text -> chunking -> embedding -> DB storage
  Future<void> _saveDocument() async {
    final text = _docController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _status = "Processing document (chunking + embedding)...";
    });

    try {
      // Add document with automatic chunking and embedding
      final result = await MobileRag.instance.addDocument(
        text,
        name: "Manual Entry ${DateTime.now().toIso8601String()}",
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
        // Rebuild HNSW index after adding
        await MobileRag.instance.rebuildIndex();
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

  /// Search: query -> embedding -> chunk similarity search
  Future<void> _searchDocuments() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _status = "Searching chunks (Hybrid)...";
    });

    try {
      // Use Hybrid Search for enriched results (Vector + BM25 + Metadata)
      final results = await MobileRag.instance.searchHybrid(
        query,
        topK: _topK,
        sourceIds: _selectedSourceId != null ? [_selectedSourceId!] : null,
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

  /// Import PDF/DOCX/Markdown file and embed: file -> text extraction -> chunking -> embedding
  Future<void> _importAndEmbedDocument() async {
    setState(() {
      _isLoading = true;
      _status = "Selecting file...";
    });

    try {
      // Pick a PDF, DOCX, or Markdown file
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
        // Markdown: read as text directly
        extractedText = await File(filePath).readAsString();
        setState(
          () => _status = "Markdown loaded! (${extractedText.length} chars)",
        );
      } else {
        // PDF/DOCX: use Rust DTT extractor
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

      // Add to RAG with chunking and embedding (auto-detect strategy from filePath)
      final addResult = await MobileRag.instance.addDocument(
        extractedText,
        metadata: '{"filename": "${file.name}"}',
        name: file.name,
        filePath: filePath, // <-- Auto-detect chunking strategy
        onProgress: (done, total) {
          if (done % 10 == 0 || done == total) {
            debugPrint('Embedding progress: $done/$total');
          }
          setState(() => _status = "Embedding chunks: $done/$total");
        },
      );

      if (addResult.isDuplicate) {
        // Since we now support resuming, "duplicate" might mean "fully processed" or "resumed and finished".
        // The message from addDocument will clarify (e.g. "Already processed" or "Added X chunks (resumed)")

        // However, if chunkCount > 0, it means we did some work (resumed).
        // If chunkCount == 0, it means it was already fully complete.

        if (addResult.chunkCount > 0) {
          await MobileRag.instance.rebuildIndex();
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
        // Rebuild HNSW index
        await MobileRag.instance.rebuildIndex();
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

  Widget _buildStatusIcon(String? status) {
    switch (status) {
      case 'processing':
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'pending':
        return const Icon(Icons.timer, color: Colors.orange, size: 20);
      case 'failed':
        return const Icon(Icons.error, color: Colors.red, size: 20);
      case 'completed':
      default:
        // Default to checkmark for legacy data or explicit success
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
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
      await MobileRag.instance.removeSource(sourceId);
      // HNSW index update is recommended but not strictly required for deletion
      // But for consistency we can rebuild or just accept it's gone from DB
      // Rebuild is expensive, so maybe skip or do it
      // Let's rebuild to be safe
      await MobileRag.instance.rebuildIndex();
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
              IconButton(
                icon: const Icon(Icons.science),
                tooltip: 'Chunking Test',
                onPressed: _isReady
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChunkingTestScreen(),
                          ),
                        );
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.speed),
                tooltip: 'Benchmark',
                onPressed: _isReady
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BenchmarkScreen(),
                          ),
                        );
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: 'Quality Test',
                onPressed: _isReady
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const QualityTestScreen(),
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status display
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        if (_isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _isReady ? Icons.check_circle : Icons.error,
                            color: _isReady ? Colors.green : Colors.red,
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _status,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Document save section
                const Text(
                  '📄 Save Document',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _docController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter document content to save',
                  ),
                  maxLines: 3,
                  enabled: _isReady,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isReady && !_isLoading ? _saveDocument : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Document (Auto Embed)'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isReady && !_isLoading
                      ? _importAndEmbedDocument
                      : null,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import PDF/DOCX'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),

                const Divider(height: 40),

                // Search section
                const Text(
                  '🔎 Semantic Search',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                // TopK slider
                Row(
                  children: [
                    const Text('Top K: '),
                    Expanded(
                      child: Slider(
                        value: _topK.toDouble(),
                        min: 1,
                        max: 20,
                        divisions: 19,
                        label: _topK.toString(),
                        onChanged: _isReady
                            ? (value) {
                                setState(() => _topK = value.round());
                              }
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$_topK',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter search query',
                  ),
                  enabled: _isReady,
                ),
                const SizedBox(height: 8),
                // Source Filter Dropdown
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Filter by Source',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedSourceId,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All Sources'),
                        ),
                        ..._sources.map(
                          (s) => DropdownMenuItem<int?>(
                            value: s.id.toInt(),
                            child: Text(
                              '#${s.id} ${s.name ?? "Untitled"}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _isReady
                          ? (value) {
                              setState(() => _selectedSourceId = value);
                            }
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isReady && !_isLoading ? _searchDocuments : null,
                  icon: const Icon(Icons.search),
                  label: const Text('Search Similar Documents'),
                ),

                const SizedBox(height: 16),

                // Search results
                if (_searchResults.isNotEmpty) ...[
                  const Text(
                    'Search Results (Hybrid):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_searchResults.length, (i) {
                    final r = _searchResults[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(
                          r.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              "Score: ${r.score.toStringAsFixed(4)} (Vec: ${r.vectorRank}, BM25: ${r.bm25Rank})",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Source ID: ${r.sourceId} | Meta: ${r.metadata ?? 'None'}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),
                ],

                const Divider(height: 40),

                // Source List Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '📚 Sources (${_sources.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadSources,
                      tooltip: 'Refresh Sources',
                    ),
                  ],
                ),

                if (_sources.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("No sources found. Add a document!"),
                  )
                else
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      itemCount: _sources.length,
                      separatorBuilder: (c, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final source = _sources[index];
                        return ListTile(
                          dense: true,
                          leading: _buildStatusIcon(source.status),
                          title: Text(
                            source.name ?? "Untitled Source ${source.id}",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            "${DateTime.fromMillisecondsSinceEpoch((source.createdAt * 1000).toInt()).toString().split('.')[0]} • ${source.status ?? 'completed'}",
                            style: TextStyle(fontSize: 10),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed: _isReady && !_isLoading
                                ? () =>
                                      _deleteSource(context, source.id.toInt())
                                : null,
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                // Sample data load button
                OutlinedButton.icon(
                  onPressed: _isReady && !_isLoading
                      ? () async {
                          setState(() => _isLoading = true);
                          try {
                            // Demo samples for Hybrid Search presentation
                            // These samples showcase Vector vs BM25 strengths
                            final samples = [
                              // Group 1: "Apple" - same keyword, different meanings (tests semantic understanding)
                              "Apple 사과는 비타민이 풍부한 과일로, 하루에 하나씩 먹으면 건강에 좋다고 알려져 있습니다.",
                              "Apple Inc.는 아이폰, 맥북, 아이패드 등을 만드는 미국의 IT 기업입니다. 스티브 잡스가 설립했습니다.",
                              // Group 2: Similar meaning, different keywords (tests semantic similarity)
                              "스마트폰 배터리 수명을 연장하려면 완전 방전을 피하고, 20-80% 사이를 유지하는 것이 좋습니다.",
                              "휴대폰 충전 시 고속 충전보다 일반 충전이 배터리 건강에 더 좋다는 연구 결과가 있습니다.",
                              // Group 3: Technical documents (tests BM25 with specific terms)
                              "HNSW 알고리즘은 그래프 기반 ANN 검색 방식으로, 계층적 구조를 통해 효율적인 벡터 검색을 제공합니다.",
                              "BM25는 TF-IDF를 개선한 키워드 검색 알고리즘으로, 문서 길이 정규화가 특징입니다.",
                              // Group 4: Miscellaneous for diversity
                              "오늘 서울 날씨는 맑고 기온은 영하 5도입니다. 외출 시 따뜻하게 입으세요.",
                              "제주도는 한국에서 가장 인기 있는 여행지로, 한라산과 해변이 유명합니다.",
                            ];
                            int totalChunks = 0;
                            for (var i = 0; i < samples.length; i++) {
                              setState(
                                () => _status =
                                    "Adding sample ${i + 1}/${samples.length}...",
                              );
                              final result = await MobileRag.instance
                                  .addDocument(
                                    samples[i],
                                    name: "Sample ${i + 1}",
                                  );
                              totalChunks += result.chunkCount;
                            }
                            // Rebuild index after all samples added
                            await MobileRag.instance.rebuildIndex();
                            await _loadSources();

                            setState(() {
                              _status =
                                  "✅ Saved ${samples.length} sample documents!\n"
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
                      : null,
                  icon: const Icon(Icons.dataset),
                  label: const Text('Load 5 Sample Documents'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isReady && !_isLoading
                      ? () async {
                          // Confirm dialog
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
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;

                          setState(() {
                            _isLoading = true;
                            _status = "Deleting all documents...";
                          });

                          try {
                            // Get stats before deletion
                            final stats = await MobileRag.instance.engine
                                .getStats();

                            // Use the new clearAllData API
                            await MobileRag.instance.clearAllData();
                            await _loadSources();

                            setState(() {
                              _searchResults.clear();
                              _status =
                                  "✅ Deleted all documents!\n"
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
                      : null,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text(
                    'Delete All Documents',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // MobileRag is global, don't dispose it here
    super.dispose();
  }
}
