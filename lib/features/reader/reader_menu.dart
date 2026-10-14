import 'dart:io';

import 'package:flutter/material.dart';

/// Overflow menu: recent documents, theme, shortcuts, about.
class ReaderMenu extends StatelessWidget {
  const ReaderMenu({
    super.key,
    required this.themeMode,
    required this.onThemeMode,
    required this.recents,
    required this.onOpenRecent,
    required this.onShowShortcuts,
    required this.onShowAbout,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  final List<String> recents;
  final ValueChanged<String> onOpenRecent;
  final VoidCallback onShowShortcuts;
  final VoidCallback onShowAbout;

  static String _name(String path) => path.split(Platform.pathSeparator).last;

  @override
  Widget build(BuildContext context) {
    // Only documents that still exist are offered.
    final available = recents.where((p) => File(p).existsSync()).toList();

    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        tooltip: 'Menu',
        icon: const Icon(Icons.more_vert),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SubmenuButton(
          menuChildren: available.isEmpty
              ? const [MenuItemButton(child: Text('No recent documents'))]
              : [
                  for (final path in available)
                    MenuItemButton(
                      onPressed: () => onOpenRecent(path),
                      child: Tooltip(message: path, child: Text(_name(path))),
                    ),
                ],
          child: const Text('Open recent'),
        ),
        SubmenuButton(
          menuChildren: [
            for (final (mode, label) in const [
              (ThemeMode.system, 'Follow system'),
              (ThemeMode.light, 'Light'),
              (ThemeMode.dark, 'Dark'),
            ])
              RadioMenuButton<ThemeMode>(
                value: mode,
                groupValue: themeMode,
                onChanged: (m) {
                  if (m != null) onThemeMode(m);
                },
                child: Text(label),
              ),
          ],
          child: const Text('Theme'),
        ),
        MenuItemButton(
          onPressed: onShowShortcuts,
          child: const Text('Keyboard shortcuts'),
        ),
        MenuItemButton(
          onPressed: onShowAbout,
          child: const Text('About DNDReader'),
        ),
      ],
    );
  }
}

/// The keyboard shortcuts dialog.
Future<void> showShortcutsDialog(BuildContext context) {
  const rows = <(String, String)>[
    ('Ctrl+O', 'Open a PDF'),
    ('Ctrl+E', 'Find meaning of the selected text'),
    ('Ctrl+T', 'Show or hide the table of contents'),
    ('F11', 'Full screen on or off'),
    ('Ctrl+R', 'Rotate clockwise (Ctrl+Shift+R: counter-clockwise)'),
    (
      'Esc',
      'Leave full screen, or close the search panel / contents, then clear the selection',
    ),
    ('Ctrl + / Ctrl −', 'Zoom in / out'),
    ('Ctrl+0', 'Fit the page'),
    ('PgUp / PgDn, arrows', 'Move through the document'),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, what) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        keys,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Expanded(child: Text(what)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
