import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

/// Search input, source filter, and results display.
class SearchSection extends StatelessWidget {
  final TextEditingController queryController;
  final String activeCollectionId;
  final int topK;
  final int? selectedSourceId;
  final List<SourceEntry> sources;
  final List<HybridSearchResult> searchResults;
  final bool isReady;
  final bool isLoading;
  final ValueChanged<int> onTopKChanged;
  final ValueChanged<int?> onSourceFilterChanged;
  final VoidCallback onSearch;

  const SearchSection({
    super.key,
    required this.queryController,
    required this.activeCollectionId,
    required this.topK,
    required this.selectedSourceId,
    required this.sources,
    required this.searchResults,
    required this.isReady,
    required this.isLoading,
    required this.onTopKChanged,
    required this.onSourceFilterChanged,
    required this.onSearch,
  });

  bool get _enabled => isReady && !isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '🔎 Semantic Search (Active Collection)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),

        // TopK slider
        Row(
          children: [
            const Text('Top K: '),
            Expanded(
              child: Slider(
                value: topK.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                label: topK.toString(),
                onChanged: isReady
                    ? (value) => onTopKChanged(value.round())
                    : null,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$topK',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Query input
        TextField(
          controller: queryController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter search query',
          ),
          enabled: isReady,
        ),
        const SizedBox(height: 8),

        // Source filter dropdown
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Filter by Source ($activeCollectionId)',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: selectedSourceId,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All Sources'),
                ),
                ...sources.map(
                  (s) => DropdownMenuItem<int?>(
                    value: s.id.toInt(),
                    child: Text(
                      '#${s.id} ${s.name ?? "Untitled"}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: isReady ? onSourceFilterChanged : null,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Search button
        ElevatedButton.icon(
          onPressed: _enabled ? onSearch : null,
          icon: const Icon(Icons.search),
          label: const Text('Search Similar Documents'),
        ),

        const SizedBox(height: 16),

        // Search results
        if (searchResults.isNotEmpty) ...[
          const Text(
            'Search Results (Hybrid):',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...List.generate(searchResults.length, (i) {
            final r = searchResults[i];
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
                      style: const TextStyle(
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
      ],
    );
  }
}
