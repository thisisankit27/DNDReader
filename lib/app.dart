import 'package:flutter/material.dart';

import 'features/reader/reader_screen.dart';
import 'theme/app_theme.dart';

/// Root widget: theme (follows the system light/dark setting) and the reader shell.
class DndReaderApp extends StatelessWidget {
  const DndReaderApp({super.key, this.initialPath});

  final String? initialPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DNDReader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: ReaderScreen(initialPath: initialPath),
    );
  }
}
