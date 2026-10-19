import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../services/path_names.dart';

/// Overflow menu: recent documents, theme, shortcuts, about.
class ReaderMenu extends StatelessWidget {
  const ReaderMenu({
    super.key,
    required this.themeMode,
    required this.onThemeMode,
    required this.selectionHighlight,
    required this.onSelectionHighlight,
    required this.recents,
    required this.onOpenRecent,
    required this.onShowShortcuts,
    required this.onShowAbout,
    this.touch = false,
    this.onRotate,
    this.onFitPage,
    this.onToggleFullscreen,
    this.fullscreen = false,
    this.controller,
    this.onOpenChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  final SelectionHighlight selectionHighlight;
  final ValueChanged<SelectionHighlight> onSelectionHighlight;
  final List<String> recents;
  final ValueChanged<String> onOpenRecent;
  final VoidCallback onShowShortcuts;
  final VoidCallback onShowAbout;

  /// Touch layout: the shortcuts entry is "Gestures and shortcuts".
  final bool touch;

  /// Rotate / fit page / full screen, offered here when the header has no room for their buttons (phones).
  final VoidCallback? onRotate;
  final VoidCallback? onFitPage;
  final VoidCallback? onToggleFullscreen;
  final bool fullscreen;

  /// Lets the owner close the menu (system back) and learn when it opens or closes.
  final MenuController? controller;
  final ValueChanged<bool>? onOpenChanged;

  @override
  Widget build(BuildContext context) {
    // Only documents that still exist are offered.
    final available = recents.where((p) => File(p).existsSync()).toList();

    return MenuAnchor(
      controller: controller,
      onOpen: () => onOpenChanged?.call(true),
      onClose: () => onOpenChanged?.call(false),
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
                      child: Tooltip(
                        message: path,
                        child: Text(baseName(path)),
                      ),
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
        SubmenuButton(
          menuChildren: [
            for (final h in SelectionHighlight.values)
              RadioMenuButton<SelectionHighlight>(
                value: h,
                groupValue: selectionHighlight,
                onChanged: (v) {
                  if (v != null) onSelectionHighlight(v);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // As it looks over the (always white) page, not over the
                    // dark menu, where the translucent colour would mislead.
                    Container(
                      width: 28,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(h.overlay, Colors.white),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(h.label),
                  ],
                ),
              ),
          ],
          child: const Text('Selection colour'),
        ),
        if (onRotate != null)
          MenuItemButton(onPressed: onRotate, child: const Text('Rotate page')),
        if (onFitPage != null)
          MenuItemButton(onPressed: onFitPage, child: const Text('Fit page')),
        if (onToggleFullscreen != null)
          MenuItemButton(
            onPressed: onToggleFullscreen,
            child: Text(fullscreen ? 'Exit full screen' : 'Full screen'),
          ),
        MenuItemButton(
          onPressed: onShowShortcuts,
          child: Text(touch ? 'Gestures and shortcuts' : 'Keyboard shortcuts'),
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
Future<void> showShortcutsDialog(BuildContext context, {bool touch = false}) {
  const gestures = <(String, String)>[
    ('Long-press', 'Select a word; drag the handles to extend it'),
    ('Double-tap', 'Select a word'),
    (
      'Find meaning',
      'Search the selected text in a panel; swipe it down to close',
    ),
    ('Pinch, − / +', 'Zoom in / out'),
    ('Back', 'Closes the panel, contents or selection, then leaves'),
  ];
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
      title: Text(touch ? 'Gestures and shortcuts' : 'Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (touch) ...[
                for (final (keys, what) in gestures)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            keys,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        Expanded(child: Text(what)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    'With a keyboard attached',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
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
