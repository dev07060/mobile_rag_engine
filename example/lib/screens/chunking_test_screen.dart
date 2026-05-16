// lib/screens/chunking_test_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

/// Test center for comparing different chunking strategies.
class ChunkingTestScreen extends StatefulWidget {
  const ChunkingTestScreen({super.key});

  @override
  State<ChunkingTestScreen> createState() => _ChunkingTestScreenState();
}

class _ChunkingTestScreenState extends State<ChunkingTestScreen> {
  final TextEditingController _textController = TextEditingController();
  double _maxChars = 300;

  List<SemanticChunk> _recursiveChunks = [];
  List<StructuredChunk> _markdownChunks = [];

  bool _isLoading = false;
  int _recursiveTimeMs = 0;
  int _markdownTimeMs = 0;

  @override
  void initState() {
    super.initState();
    _textController.text = _sampleMarkdown;
  }

  Future<void> _runComparison() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _recursiveChunks = [];
      _markdownChunks = [];
    });

    // Recursive chunking
    final recursiveStart = DateTime.now();
    final recursive = await TextChunker.recursive(
      text,
      maxChars: _maxChars.toInt(),
    );
    final recursiveEnd = DateTime.now();
    _recursiveTimeMs = recursiveEnd.difference(recursiveStart).inMilliseconds;

    // Markdown chunking
    final markdownStart = DateTime.now();
    final markdown = await TextChunker.markdown(
      text,
      maxChars: _maxChars.toInt(),
    );
    final markdownEnd = DateTime.now();
    _markdownTimeMs = markdownEnd.difference(markdownStart).inMilliseconds;

    setState(() {
      _recursiveChunks = recursive;
      _markdownChunks = markdown;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 Chunking Test Center'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Input
            TextField(
              controller: _textController,
              maxLines: 6,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Input Text (Markdown supported)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            // Max chars slider
            Row(
              children: [
                const Text('Max Chunk Size:'),
                Expanded(
                  child: Slider(
                    value: _maxChars,
                    min: 100,
                    max: 800,
                    divisions: 14,
                    label: '${_maxChars.toInt()}',
                    onChanged: (v) => setState(() => _maxChars = v),
                  ),
                ),
                Text(
                  '${_maxChars.toInt()}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            // Run button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _runComparison,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isLoading ? 'Processing...' : 'Compare Chunking'),
            ),
            const SizedBox(height: 12),

            // Results header
            Row(
              children: [
                Expanded(
                  child: _buildHeader(
                    'Recursive',
                    Colors.blue,
                    _recursiveChunks.length,
                    _recursiveTimeMs,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildHeader(
                    'Markdown',
                    Colors.green,
                    _markdownChunks.length,
                    _markdownTimeMs,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Results
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildRecursiveList()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMarkdownList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, Color color, int count, int timeMs) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            '$count chunks · ${timeMs}ms',
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecursiveList() {
    if (_recursiveChunks.isEmpty) {
      return const Center(
        child: Text('No results', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: _recursiveChunks.length,
      itemBuilder: (context, index) {
        final chunk = _recursiveChunks[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.blue,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        chunk.chunkType,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${chunk.content.length}c',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  chunk.content,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarkdownList() {
    if (_markdownChunks.isEmpty) {
      return const Center(
        child: Text('No results', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: _markdownChunks.length,
      itemBuilder: (context, index) {
        final chunk = _markdownChunks[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.green,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(chunk.chunkType),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        chunk.chunkType,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${chunk.content.length}c',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                // Header path badge
                if (chunk.headerPath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '📍 ${chunk.headerPath}',
                      style: TextStyle(fontSize: 10, color: Colors.green[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  chunk.content,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    return switch (type) {
      'code' => Colors.purple[100]!,
      'table' => Colors.orange[100]!,
      'header' => Colors.blue[100]!,
      _ => Colors.grey[200]!,
    };
  }
}

const _sampleMarkdown = '''
# Mobile RAG Engine

A high-performance, on-device RAG engine for Flutter.

## Features

### Vector Search
- HNSW indexing for fast approximate nearest neighbor search
- Support for 384 and 1024 dimensional embeddings

### Text Processing
- Rust-based tokenization
- Semantic chunking with structure preservation

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mobile_rag_engine: ^0.18.2
```

## API Reference

| Function | Description |
|----------|-------------|
| `MobileRag.initialize()` | Initialize the local RAG engine |
| `addDocumentFromFile()` | Add and chunk a local document |
| `searchHybridWithContext()` | Search and assemble LLM-ready context |

## License

MIT License. See LICENSE file for details.
''';
