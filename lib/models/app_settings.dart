import 'package:flutter/material.dart';

/// Colour of the text-selection highlight. Chosen from the Okabe–Ito
/// colour-blind-safe palette (plus a neutral grey) rather than left to the
/// theme, whose default reads as green to some viewers. The page is always
/// white, so these work in both themes; alpha keeps the text readable.
enum SelectionHighlight {
  skyBlue('Sky blue', Color(0xFF56B4E9)),
  yellow('Yellow', Color(0xFFF0E442)),
  orange('Orange', Color(0xFFE69F00)),
  pink('Pink', Color(0xFFCC79A7)),
  grey('Grey', Color(0xFF9E9E9E));

  const SelectionHighlight(this.label, this.base);

  final String label;

  /// Opaque swatch colour.
  final Color base;

  /// The colour painted over the page: translucent so text stays legible.
  Color get overlay => base.withValues(alpha: 0.5);
}

/// What DNDReader remembers between runs. Nothing about *what was read or
/// searched* beyond document paths is stored; search cookies are never stored.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.zoom,
    this.lastDocument,
    this.lastPage,
    this.recents = const <String>[],
    this.selectionHighlight = SelectionHighlight.skyBlue,
  });

  final ThemeMode themeMode;

  /// Viewer zoom last used (absolute scale), or null for the viewer's default.
  final double? zoom;

  /// The document open when the app last ran, and the page it was on.
  final String? lastDocument;
  final int? lastPage;

  /// Most recently opened documents, newest first.
  final List<String> recents;

  final SelectionHighlight selectionHighlight;

  /// How many recent documents are kept.
  static const int maxRecents = 8;

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? zoom,
    String? lastDocument,
    int? lastPage,
    List<String>? recents,
    SelectionHighlight? selectionHighlight,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      zoom: zoom ?? this.zoom,
      lastDocument: lastDocument ?? this.lastDocument,
      lastPage: lastPage ?? this.lastPage,
      recents: recents ?? this.recents,
      selectionHighlight: selectionHighlight ?? this.selectionHighlight,
    );
  }
}
