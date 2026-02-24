import 'package:flutter/material.dart';

/// Displays the current engine status with a loading/success/error icon.
class StatusCard extends StatelessWidget {
  final String status;
  final bool isLoading;
  final bool isReady;

  const StatusCard({
    super.key,
    required this.status,
    required this.isLoading,
    required this.isReady,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                isReady ? Icons.check_circle : Icons.error,
                color: isReady ? Colors.green : Colors.red,
              ),
            const SizedBox(width: 12),
            Expanded(child: Text(status, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}
