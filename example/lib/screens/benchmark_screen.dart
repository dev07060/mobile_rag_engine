// lib/screens/benchmark_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/services/benchmark_service.dart';
import 'package:mobile_rag_engine/models/benchmark_models.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  bool _isRunning = false;
  String _progress = "";
  List<BenchmarkResult> _results = [];
  String _dbPath = "";

  @override
  void initState() {
    super.initState();
    _initDbPath();
  }

  Future<void> _initDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    _dbPath = "${dir.path}/rag_db.sqlite";
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _results = [];
      _progress = "Starting benchmark...";
    });

    try {
      final results = await BenchmarkService.runFullBenchmark(
        dbPath: _dbPath,
        onProgress: (msg) {
          setState(() => _progress = msg);
        },
      );

      setState(() {
        _results = results;
        _isRunning = false;
        _progress = "Complete!";
      });
    } catch (e) {
      setState(() {
        _isRunning = false;
        _progress = "Error: $e";
      });
    }
  }

  List<BenchmarkResult> get _rustResults =>
      _results.where((r) => r.category == BenchmarkCategory.rust).toList();

  List<BenchmarkResult> get _onnxResults =>
      _results.where((r) => r.category == BenchmarkCategory.onnx).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🧪 Performance Benchmark')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Run button
            ElevatedButton.icon(
              onPressed: _isRunning ? null : _runBenchmark,
              icon: _isRunning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isRunning ? 'Running...' : 'Run Benchmark'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 16),

            // Progress status
            if (_progress.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(_progress, style: const TextStyle(fontSize: 14)),
                ),
              ),

            const SizedBox(height: 16),

            // Results
            if (_results.isNotEmpty)
              Expanded(
                child: ListView(
                  children: [
                    // Rust section header
                    _buildSectionHeader(
                      '⚡ Rust-Powered (Optimized)',
                      'Tokenization & HNSW Search - 10-100x faster than pure Dart',
                      Colors.green.shade50,
                      Colors.green.shade700,
                    ),
                    ..._rustResults.map(_buildResultCard),

                    const SizedBox(height: 24),

                    // ONNX section header
                    _buildSectionHeader(
                      '🧠 ONNX Runtime',
                      'Embedding generation - Standard ML inference speed',
                      Colors.orange.shade50,
                      Colors.orange.shade700,
                    ),
                    ..._onnxResults.map(_buildResultCard),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: textColor.withAlpha(180)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(BenchmarkResult r) {
    final isRust = r.category == BenchmarkCategory.rust;
    final color = isRust
        ? Colors.green
        : (r.avgMs < 100 ? Colors.orange : Colors.deepOrange);

    return Card(
      child: ListTile(
        leading: Icon(isRust ? Icons.bolt : Icons.memory, color: color),
        title: Text(r.name),
        subtitle: Text(
          'avg: ${r.avgMs.toStringAsFixed(2)}ms | '
          'min: ${r.minMs.toStringAsFixed(2)}ms | '
          'max: ${r.maxMs.toStringAsFixed(2)}ms',
        ),
        trailing: Text(
          r.avgMs < 1
              ? '${(r.avgMs * 1000).toStringAsFixed(0)}μs'
              : '${r.avgMs.toStringAsFixed(1)}ms',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
