import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'package:mobile_rag_engine/models/quality_test_models.dart';

class QualityTestScreen extends StatefulWidget {
  const QualityTestScreen({super.key});

  @override
  State<QualityTestScreen> createState() => _QualityTestScreenState();
}

class _QualityTestScreenState extends State<QualityTestScreen> {
  bool _isRunning = false;
  String _progress = "";
  QualityTestSummary? _summary;

  Future<void> _runTest() async {
    setState(() {
      _isRunning = true;
      _summary = null;
      _progress = "Preparing test...";
    });

    try {
      final summary = await QualityTestService.runQualityTest(
        appDbPath: MobileRag.instance.engine.dbPath,
        onProgress: (msg, current, total) {
          setState(() => _progress = "$msg ($current/$total)");
        },
      );

      setState(() {
        _summary = summary;
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

  Color _getScoreColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎯 Search Quality Test')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Run button
            ElevatedButton.icon(
              onPressed: _isRunning ? null : _runTest,
              icon: _isRunning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isRunning ? 'Testing...' : 'Run Quality Test'),
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

            // Summary
            if (_summary != null) ...[
              Card(
                color: _getScoreColor(
                  _summary!.passRate,
                ).withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Pass Rate: ${(_summary!.passRate * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(_summary!.passRate),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_summary!.passed}/${_summary!.total} tests passed',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              Text(
                                '${(_summary!.avgRecallAt3 * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _getScoreColor(_summary!.avgRecallAt3),
                                ),
                              ),
                              const Text('Recall@3'),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                '${(_summary!.avgPrecision * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _getScoreColor(_summary!.avgPrecision),
                                ),
                              ),
                              const Text('Precision'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Text(
                '📋 Detailed Results',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              // Detailed results
              Expanded(
                child: ListView.builder(
                  itemCount: _summary!.results.length,
                  itemBuilder: (context, index) {
                    final r = _summary!.results[index];
                    return Card(
                      child: ExpansionTile(
                        leading: Icon(
                          r.passed ? Icons.check_circle : Icons.cancel,
                          color: r.passed ? Colors.green : Colors.red,
                        ),
                        title: Text('Query: "${r.query}"'),
                        subtitle: Text(
                          'Recall: ${(r.recallAt3 * 100).toStringAsFixed(0)}% | '
                          'Precision: ${(r.precision * 100).toStringAsFixed(0)}%',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Expected docs:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(r.expected.join(', ')),
                                const SizedBox(height: 8),
                                const Text(
                                  'Actual results:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                ...r.actual.asMap().entries.map(
                                  (e) => Text(
                                    '${e.key + 1}. ${e.value}',
                                    style: TextStyle(
                                      color:
                                          QualityTestService.testCases
                                              .firstWhere(
                                                (tc) => tc.query == r.query,
                                              )
                                              .relevantDocs
                                              .any(
                                                (doc) => e.value.contains(doc),
                                              )
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
