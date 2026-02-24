import 'package:flutter/material.dart';

/// Document input section — text entry and file import buttons.
class DocumentSection extends StatelessWidget {
  final TextEditingController docController;
  final bool isReady;
  final bool isLoading;
  final VoidCallback onSave;
  final VoidCallback onImport;

  const DocumentSection({
    super.key,
    required this.docController,
    required this.isReady,
    required this.isLoading,
    required this.onSave,
    required this.onImport,
  });

  bool get _enabled => isReady && !isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '📄 Save Document',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: docController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter document content to save',
          ),
          maxLines: 3,
          enabled: isReady,
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _enabled ? onSave : null,
          icon: const Icon(Icons.save),
          label: const Text('Save Document (Auto Embed)'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _enabled ? onImport : null,
          icon: const Icon(Icons.upload_file),
          label: const Text('Import PDF/DOCX'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
