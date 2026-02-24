import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

/// Source list with delete, sample load, and delete-all actions.
class SourceListSection extends StatelessWidget {
  final String activeCollectionId;
  final List<SourceEntry> sources;
  final bool isReady;
  final bool isLoading;
  final VoidCallback onRefresh;
  final void Function(BuildContext context, int sourceId) onDelete;
  final VoidCallback onLoadSamples;
  final VoidCallback onDeleteAll;

  const SourceListSection({
    super.key,
    required this.activeCollectionId,
    required this.sources,
    required this.isReady,
    required this.isLoading,
    required this.onRefresh,
    required this.onDelete,
    required this.onLoadSamples,
    required this.onDeleteAll,
  });

  bool get _enabled => isReady && !isLoading;

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
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '📚 Sources in "$activeCollectionId" (${sources.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
              tooltip: 'Refresh Sources',
            ),
          ],
        ),

        // Source list or empty state
        if (sources.isEmpty)
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
              itemCount: sources.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final source = sources[index];
                return ListTile(
                  dense: true,
                  leading: _buildStatusIcon(source.status),
                  title: Text(
                    source.name ?? "Untitled Source ${source.id}",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    "${DateTime.fromMillisecondsSinceEpoch((source.createdAt * 1000).toInt()).toString().split('.')[0]} • ${source.status ?? 'completed'}",
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: _enabled
                        ? () => onDelete(ctx, source.id.toInt())
                        : null,
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // Sample data load button
        OutlinedButton.icon(
          onPressed: _enabled ? onLoadSamples : null,
          icon: const Icon(Icons.dataset),
          label: const Text('Load Sample Documents'),
        ),
        const SizedBox(height: 8),

        // Delete all button
        OutlinedButton.icon(
          onPressed: _enabled ? onDeleteAll : null,
          icon: const Icon(Icons.delete_forever, color: Colors.red),
          label: const Text(
            'Delete All Documents',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}
