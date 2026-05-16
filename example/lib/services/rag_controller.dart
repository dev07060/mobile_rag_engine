import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

class _PickedImportResult {
  final SourceAddResult addResult;
  final int? textLength;

  const _PickedImportResult({required this.addResult, this.textLength});
}

class RagController extends ChangeNotifier {
  String status = "Ready";
  bool isReady = true;
  bool isLoading = false;

  final TextEditingController docController = TextEditingController();
  final TextEditingController queryController = TextEditingController();
  List<HybridSearchResult> searchResults = [];
  List<SourceEntry> sources = [];
  int? selectedSourceId;
  int topK = 5;
  final TextEditingController collectionController = TextEditingController(
    text: SourceRagService.defaultCollectionId,
  );
  String activeCollectionId = SourceRagService.defaultCollectionId;
  final Set<String> knownCollectionIds = {
    SourceRagService.defaultCollectionId,
    'business',
    'travel',
    'personal',
  };

  bool get _isDefaultCollection =>
      activeCollectionId == SourceRagService.defaultCollectionId;
  CollectionRag get _activeCollection =>
      MobileRag.instance.inCollection(activeCollectionId);

  void setTopK(int value) {
    topK = value;
    notifyListeners();
  }

  void setSelectedSourceId(int? value) {
    selectedSourceId = value;
    notifyListeners();
  }

  void initializeStatus() {
    if (MobileRag.isInitialized) {
      final vocab = MobileRag.instance.vocabSize;
      status = "✅ Ready!\nVocab: $vocab | Embedding: 384 dims";
      isReady = true;
      loadSources();
    } else {
      status = "❌ MobileRag not initialzed in main()";
      isReady = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    docController.dispose();
    queryController.dispose();
    collectionController.dispose();
    super.dispose();
  }

  void _updateState(String newStatus, {bool newIsLoading = false}) {
    status = newStatus;
    isLoading = newIsLoading;
    notifyListeners();
  }

  String _normalizeCollectionId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return SourceRagService.defaultCollectionId;
    return trimmed;
  }

  Future<void> switchCollection(String rawCollectionId) async {
    final normalized = _normalizeCollectionId(rawCollectionId);
    _updateState(
      'Switching to collection "$normalized"...',
      newIsLoading: true,
    );
    activeCollectionId = normalized;
    knownCollectionIds.add(normalized);
    collectionController.text = normalized;
    selectedSourceId = null;
    searchResults.clear();

    await loadSources();
    _updateState(
      '✅ Active collection: "$activeCollectionId" (${sources.length} sources)',
      newIsLoading: false,
    );
  }

  Future<void> waitWarmup() async {
    _updateState(
      'Waiting warmup for "$activeCollectionId"...',
      newIsLoading: true,
    );
    try {
      await _activeCollection.warmupFuture;
      _updateState(
        '✅ Warmup done for "$activeCollectionId".',
        newIsLoading: false,
      );
    } catch (e) {
      _updateState('❌ Warmup error: $e', newIsLoading: false);
    }
  }

  Future<void> rebuildActive() async {
    _updateState('Rebuilding "$activeCollectionId"...', newIsLoading: true);
    try {
      await _activeCollection.rebuildIndex(force: true);
      await loadSources();
      _updateState(
        '✅ Rebuild complete for "$activeCollectionId".',
        newIsLoading: false,
      );
    } catch (e) {
      _updateState('❌ Rebuild error: $e', newIsLoading: false);
    }
  }

  Future<void> loadSources() async {
    try {
      final newSources = _isDefaultCollection
          ? await MobileRag.instance.listSources()
          : await _activeCollection.listSources();
      sources = newSources;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load sources: $e');
    }
  }

  Future<void> deleteSource(int sourceId) async {
    _updateState('Deleting source $sourceId...', newIsLoading: true);
    try {
      if (_isDefaultCollection) {
        await MobileRag.instance.removeSource(sourceId);
        await MobileRag.instance.rebuildIndex();
      } else {
        await _activeCollection.removeSource(sourceId);
        await _activeCollection.rebuildIndex();
      }
      await loadSources();
      _updateState("✅ Deleted source $sourceId", newIsLoading: false);
    } catch (e) {
      _updateState("❌ Delete error: $e", newIsLoading: false);
    }
  }

  Future<void> saveDocument() async {
    final text = docController.text.trim();
    if (text.isEmpty) return;

    _updateState(
      'Processing document in "$activeCollectionId" (chunking + embedding)...',
      newIsLoading: true,
    );

    try {
      final result = _isDefaultCollection
          ? await MobileRag.instance.addDocument(
              text,
              name: "Manual Entry ${DateTime.now().toIso8601String()}",
              onProgress: (done, total) {
                if (done % 10 == 0 || done == total) {
                  debugPrint('Embedding progress: $done/$total');
                }
                status = "Embedding chunks: $done/$total";
                notifyListeners();
              },
            )
          : await _activeCollection.addDocument(
              text,
              name:
                  "[$activeCollectionId] Manual Entry ${DateTime.now().toIso8601String()}",
              onProgress: (done, total) {
                if (done % 10 == 0 || done == total) {
                  debugPrint('Embedding progress: $done/$total');
                }
                status = "Embedding chunks: $done/$total";
                notifyListeners();
              },
            );

      if (result.isDuplicate) {
        _updateState(
          "⚠️ Duplicate detected!\nDocument already exists in database.",
          newIsLoading: false,
        );
      } else {
        if (_isDefaultCollection) {
          await MobileRag.instance.rebuildIndex();
        } else {
          await _activeCollection.rebuildIndex();
        }
        await loadSources();

        _updateState(
          "✅ Saved!\n"
          "📄 Source ID: ${result.sourceId}\n"
          "📦 Chunks created: ${result.chunkCount}\n"
          "(Each chunk ~500 chars with 50 char overlap)",
          newIsLoading: false,
        );
        docController.clear();
      }
    } catch (e) {
      _updateState("❌ Save error: $e", newIsLoading: false);
    }
  }

  Future<void> importAndEmbedDocument() async {
    _updateState("Selecting file...", newIsLoading: true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'md', 'markdown'],
      );

      if (result == null || result.files.isEmpty) {
        _updateState("⚠️ No file selected", newIsLoading: false);
        return;
      }

      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) {
        _updateState("❌ Could not get file path", newIsLoading: false);
        return;
      }

      final importResult = await _importPickedDocument(file, filePath);
      if (importResult == null) {
        return;
      }
      final addResult = importResult.addResult;

      if (addResult.isDuplicate) {
        if (addResult.chunkCount > 0) {
          if (_isDefaultCollection) {
            await MobileRag.instance.rebuildIndex();
          } else {
            await _activeCollection.rebuildIndex();
          }
          await loadSources();
          _updateState(
            "✅ Resumed & Completed!\n"
            "📄 File: ${file.name}\n"
            "📦 ${addResult.message}",
            newIsLoading: false,
          );
        } else {
          _updateState(
            "ℹ️ Already processed.\n${file.name} is up to date.",
            newIsLoading: false,
          );
        }
      } else {
        if (_isDefaultCollection) {
          await MobileRag.instance.rebuildIndex();
        } else {
          await _activeCollection.rebuildIndex();
        }
        await loadSources();

        _updateState(
          "✅ Document imported!\n"
          "📄 File: ${file.name}\n"
          "${_formatImportedTextSummary(importResult)}\n"
          "📦 ${addResult.message}",
          newIsLoading: false,
        );
      }
    } catch (e, st) {
      _updateState("❌ Import error: $e\n$st", newIsLoading: false);
    }
  }

  String _extensionFor(PlatformFile file, String filePath) {
    final candidate = file.name.isNotEmpty ? file.name : filePath;
    final dot = candidate.lastIndexOf('.');
    if (dot < 0 || dot == candidate.length - 1) return '';
    return candidate.substring(dot + 1).toLowerCase();
  }

  bool _isUtf8TextExtension(String extension) =>
      extension == 'txt' || extension == 'md' || extension == 'markdown';

  ChunkingStrategy? _strategyForExtension(String extension) {
    if (extension == 'md' || extension == 'markdown') {
      return ChunkingStrategy.markdown;
    }
    return null;
  }

  String _sourceNameForFile(String fileName) =>
      _isDefaultCollection ? fileName : "[$activeCollectionId] $fileName";

  String _formatImportedTextSummary(_PickedImportResult result) {
    final textLength = result.textLength;
    if (textLength != null) {
      return "📝 Text: $textLength chars";
    }
    return "📝 Text: processed with low-memory file path";
  }

  void _onImportProgress(int done, int total) {
    if (done % 10 == 0 || done == total) {
      debugPrint('Embedding progress: $done/$total');
    }
    status = "Embedding chunks: $done/$total";
    notifyListeners();
  }

  Future<SourceAddResult> _addFromFilePath({
    required String filePath,
    required String fileName,
    required String metadata,
    required ChunkingStrategy? strategy,
  }) {
    final name = _sourceNameForFile(fileName);
    return _isDefaultCollection
        ? MobileRag.instance.addDocumentFromFile(
            filePath,
            metadata: metadata,
            name: name,
            strategy: strategy,
            onProgress: _onImportProgress,
          )
        : _activeCollection.addDocumentFromFile(
            filePath,
            metadata: metadata,
            name: name,
            strategy: strategy,
            onProgress: _onImportProgress,
          );
  }

  Future<SourceAddResult> _addUtf8Bytes({
    required Uint8List bytes,
    required String fileName,
    required String metadata,
    required ChunkingStrategy? strategy,
  }) {
    final name = _sourceNameForFile(fileName);
    return _isDefaultCollection
        ? MobileRag.instance.addDocumentUtf8(
            bytes,
            metadata: metadata,
            name: name,
            strategy: strategy,
            onProgress: _onImportProgress,
          )
        : _activeCollection.addDocumentUtf8(
            bytes,
            metadata: metadata,
            name: name,
            strategy: strategy,
            onProgress: _onImportProgress,
          );
  }

  Future<SourceAddResult> _addExtractedText({
    required String text,
    required String filePath,
    required String fileName,
    required String metadata,
  }) {
    final name = _sourceNameForFile(fileName);
    return _isDefaultCollection
        ? MobileRag.instance.addDocument(
            text,
            metadata: metadata,
            name: name,
            filePath: filePath,
            onProgress: _onImportProgress,
          )
        : _activeCollection.addDocument(
            text,
            metadata: metadata,
            name: name,
            filePath: filePath,
            onProgress: _onImportProgress,
          );
  }

  Future<_PickedImportResult?> _importPickedDocument(
    PlatformFile file,
    String filePath,
  ) async {
    final metadata = jsonEncode({'filename': file.name});
    final extension = _extensionFor(file, filePath);
    final strategy = _strategyForExtension(extension);

    status = "Importing ${file.name} with file path fast path...";
    notifyListeners();

    try {
      final addResult = await _addFromFilePath(
        filePath: filePath,
        fileName: file.name,
        metadata: metadata,
        strategy: strategy,
      );
      return _PickedImportResult(addResult: addResult);
    } on RagError catch (e) {
      debugPrint('File path ingest failed, falling back: $e');
    }

    final bytes = file.bytes ?? await File(filePath).readAsBytes();
    if (_isUtf8TextExtension(extension)) {
      status = "Falling back to UTF-8 ingest for ${file.name}...";
      notifyListeners();
      final addResult = await _addUtf8Bytes(
        bytes: bytes,
        fileName: file.name,
        metadata: metadata,
        strategy: strategy,
      );
      return _PickedImportResult(addResult: addResult);
    }

    status = "Extracting text from ${file.name}...";
    notifyListeners();
    final extractedText = await DocumentParser.parse(bytes.toList());
    if (extractedText.isEmpty) {
      _updateState("⚠️ No text extracted from file", newIsLoading: false);
      return null;
    }

    status =
        "Text extracted! (${extractedText.length} chars)\nProcessing chunks...";
    notifyListeners();
    final addResult = await _addExtractedText(
      text: extractedText,
      filePath: filePath,
      fileName: file.name,
      metadata: metadata,
    );
    return _PickedImportResult(
      addResult: addResult,
      textLength: extractedText.length,
    );
  }

  Future<void> searchDocuments() async {
    final query = queryController.text.trim();
    if (query.isEmpty) return;

    _updateState(
      'Searching "$activeCollectionId" chunks (Hybrid)...',
      newIsLoading: true,
    );

    try {
      final results = _isDefaultCollection
          ? await MobileRag.instance.searchHybrid(
              query,
              topK: topK,
              sourceIds: selectedSourceId != null ? [selectedSourceId!] : null,
            )
          : await _activeCollection.searchHybrid(
              query,
              topK: topK,
              sourceIds: selectedSourceId != null ? [selectedSourceId!] : null,
            );

      searchResults = results;
      _updateState(
        "✅ Search complete!\n"
        "Found ${results.length} relevant chunks (Hybrid Search)",
        newIsLoading: false,
      );
    } catch (e) {
      debugPrint(e.toString());
      _updateState("❌ Search error: $e", newIsLoading: false);
    }
  }

  Future<void> loadSampleDocuments() async {
    _updateState("Loading samples...", newIsLoading: true);
    try {
      final samples = [
        "Apple is a fruit rich in vitamins, and eating one a day is known to be good for your health.",
        "Apple Inc. is an American IT company that makes iPhones, MacBooks, iPads, and more. It was founded by Steve Jobs.",
        "To extend smartphone battery life, it's best to avoid full discharges and keep it between 20-80%.",
        "Research shows that standard charging is better for battery health than fast charging.",
        "The HNSW algorithm is a graph-based ANN search method that provides efficient vector search through a hierarchical structure.",
        "BM25 is a keyword search algorithm that improves upon TF-IDF by featuring document length normalization.",
        "Today's weather in New York is clear and the temperature is -5 degrees Celsius. Dress warmly when going out.",
        "Hawaii is one of the most popular travel destinations in the US, famous for its volcanoes and beaches.",
      ];
      int totalChunks = 0;
      for (var i = 0; i < samples.length; i++) {
        status =
            'Adding sample ${i + 1}/${samples.length} to "$activeCollectionId"...';
        notifyListeners();
        final result = _isDefaultCollection
            ? await MobileRag.instance.addDocument(
                samples[i],
                name: "Sample ${i + 1}",
              )
            : await _activeCollection.addDocument(
                samples[i],
                name: "[$activeCollectionId] Sample ${i + 1}",
              );
        totalChunks += result.chunkCount;
      }
      if (_isDefaultCollection) {
        await MobileRag.instance.rebuildIndex();
      } else {
        await _activeCollection.rebuildIndex();
      }
      await loadSources();

      _updateState(
        '✅ Saved ${samples.length} sample documents in "$activeCollectionId"!\n'
        "📦 Total chunks: $totalChunks",
        newIsLoading: false,
      );
    } catch (e) {
      _updateState("❌ Sample save error: $e", newIsLoading: false);
    }
  }

  Future<void> deleteAllDocuments() async {
    _updateState(
      'Deleting all documents in "$activeCollectionId"...',
      newIsLoading: true,
    );

    try {
      late final SourceStats stats;
      if (_isDefaultCollection) {
        stats = await MobileRag.instance.engine.getStats();
        await MobileRag.instance.clearAllData();
      } else {
        stats = await _activeCollection.getStats();
        final sourceIds = sources
            .map((s) => s.id.toInt())
            .toList(growable: false);
        for (final sourceId in sourceIds) {
          await _activeCollection.removeSource(sourceId);
        }
        await _activeCollection.rebuildIndex(force: true);
      }
      await loadSources();

      searchResults.clear();
      _updateState(
        '✅ Deleted all documents in "$activeCollectionId"!\n'
        "Previously had ${stats.sourceCount} sources.",
        newIsLoading: false,
      );
    } catch (e) {
      _updateState("❌ Delete error: $e", newIsLoading: false);
    }
  }
}
