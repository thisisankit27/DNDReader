import 'package:flutter/material.dart';

import 'features/reader/reader_screen.dart';
import 'features/search/search_presentation.dart';
import 'services/document_access.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

/// Root widget: theme (system / light / dark, remembered) and the reader shell.
class DndReaderApp extends StatefulWidget {
  const DndReaderApp({
    super.key,
    this.initialPath,
    this.settings,
    this.documents,
    this.searchPresentation = SearchPresentation.sidePanel,
  });

  final String? initialPath;

  /// Null in tests that don't care about persistence (an in-memory service is used).
  final SettingsService? settings;

  /// Where documents come from on Android; null elsewhere.
  final DocumentAccess? documents;

  /// How the search panel is presented; the side panel unless the platform says otherwise.
  final SearchPresentation searchPresentation;

  @override
  State<DndReaderApp> createState() => _DndReaderAppState();
}

class _DndReaderAppState extends State<DndReaderApp> {
  late final SettingsService _settings =
      widget.settings ?? SettingsService.inMemory();

  /// The chosen selection highlight, applied through the theme so the PDF
  /// viewer and text fields use the same colour.
  ThemeData _withSelection(ThemeData base) => base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: _settings.settings.selectionHighlight.overlay,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        title: 'DNDReader',
        // Lets Android restore the panel after the process was killed in the background.
        restorationScopeId: 'dndreader',
        debugShowCheckedModeBanner: false,
        theme: _withSelection(AppTheme.light()),
        darkTheme: _withSelection(AppTheme.dark()),
        themeMode: _settings.settings.themeMode,
        home: ReaderScreen(
          initialPath: widget.initialPath,
          settings: _settings,
          documents: widget.documents,
          searchPresentation: widget.searchPresentation,
        ),
      ),
    );
  }
}
