import 'package:flutter/material.dart';

/// Collection switcher card — allows switching between RAG collections.
class CollectionSection extends StatelessWidget {
  final TextEditingController collectionController;
  final String activeCollectionId;
  final Set<String> knownCollectionIds;
  final bool isReady;
  final bool isLoading;
  final VoidCallback onApply;
  final ValueChanged<String> onChipSelected;
  final VoidCallback onWaitWarmup;
  final VoidCallback onRebuild;

  const CollectionSection({
    super.key,
    required this.collectionController,
    required this.activeCollectionId,
    required this.knownCollectionIds,
    required this.isReady,
    required this.isLoading,
    required this.onApply,
    required this.onChipSelected,
    required this.onWaitWarmup,
    required this.onRebuild,
  });

  bool get _enabled => isReady && !isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🧩 Collection Test Mode',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: collectionController,
                    decoration: const InputDecoration(
                      labelText: 'Collection ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: _enabled,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _enabled ? onApply : null,
                  child: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final id in knownCollectionIds)
                  ActionChip(
                    label: Text(id),
                    onPressed: _enabled ? () => onChipSelected(id) : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Active: $activeCollectionId',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _enabled ? onWaitWarmup : null,
                  icon: const Icon(Icons.hourglass_bottom),
                  label: const Text('Wait Warmup'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _enabled ? onRebuild : null,
                  icon: const Icon(Icons.build),
                  label: const Text('Rebuild Active'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
