import 'package:flutter/material.dart';

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
  });

  final ThemeMode themeMode;

  /// Viewer zoom last used (absolute scale), or null for the viewer's default.
  final double? zoom;

  /// The document open when the app last ran, and the page it was on.
  final String? lastDocument;
  final int? lastPage;

  /// Most recently opened documents, newest first.
  final List<String> recents;

  /// How many recent documents are kept.
  static const int maxRecents = 8;

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? zoom,
    String? lastDocument,
    int? lastPage,
    List<String>? recents,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      zoom: zoom ?? this.zoom,
      lastDocument: lastDocument ?? this.lastDocument,
      lastPage: lastPage ?? this.lastPage,
      recents: recents ?? this.recents,
    );
  }
}
