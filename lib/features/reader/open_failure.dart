import 'package:flutter/material.dart';

/// Shown when a file could not be opened as a PDF. Deliberately free of raw
/// error strings.
class OpenFailure extends StatelessWidget {
  const OpenFailure({super.key, required this.fileName, this.onOpenAnother});

  final String fileName;
  final VoidCallback? onOpenAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This file couldn’t be opened',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '“$fileName” isn’t a readable PDF, or it is protected.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpenAnother,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open another PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
