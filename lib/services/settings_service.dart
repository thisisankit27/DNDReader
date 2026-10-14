import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Reads and writes [AppSettings] with `shared_preferences`.
///
/// Values are validated on load: anything malformed falls back to its default,
/// so a hand-edited or truncated preferences file can never break start-up.
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs, this._settings);

  /// In-memory service for tests and previews (nothing is written to disk).
  factory SettingsService.inMemory([
    AppSettings initial = const AppSettings(),
  ]) {
    return SettingsService._(null, initial);
  }

  static const _kTheme = 'themeMode';
  static const _kZoom = 'zoom';
  static const _kLastDocument = 'lastDocument';
  static const _kLastPage = 'lastPage';
  static const _kRecents = 'recents';
  static const _kHighlight = 'selectionHighlight';

  final SharedPreferences? _prefs;
  AppSettings _settings;

  AppSettings get settings => _settings;

  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService._(prefs, _read(prefs));
  }

  static AppSettings _read(SharedPreferences prefs) {
    // `prefs.get` returns whatever is stored; check each type ourselves so a
    // wrongly-typed value falls back to its default instead of throwing.
    final themeName = prefs.get(_kTheme);
    var theme = ThemeMode.system;
    for (final mode in ThemeMode.values) {
      if (mode.name == themeName) theme = mode;
    }

    final rawZoom = prefs.get(_kZoom);
    double? zoom = rawZoom is num ? rawZoom.toDouble() : null;
    if (zoom != null && (!zoom.isFinite || zoom <= 0 || zoom > 50)) zoom = null;

    final rawPage = prefs.get(_kLastPage);
    final page = rawPage is int && rawPage >= 1 ? rawPage : null;

    final rawDoc = prefs.get(_kLastDocument);
    final rawRecents = prefs.get(_kRecents);
    final recents = rawRecents is List
        ? rawRecents
              .whereType<String>()
              .where((p) => p.isNotEmpty)
              .take(AppSettings.maxRecents)
              .toList(growable: false)
        : const <String>[];

    final highlightName = prefs.get(_kHighlight);
    var highlight = SelectionHighlight.skyBlue;
    for (final h in SelectionHighlight.values) {
      if (h.name == highlightName) highlight = h;
    }

    return AppSettings(
      selectionHighlight: highlight,
      themeMode: theme,
      zoom: zoom,
      lastDocument: rawDoc is String && rawDoc.isNotEmpty ? rawDoc : null,
      lastPage: page,
      recents: recents,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _prefs?.setString(_kTheme, mode.name);
    notifyListeners();
  }

  Future<void> setSelectionHighlight(SelectionHighlight value) async {
    _settings = _settings.copyWith(selectionHighlight: value);
    await _prefs?.setString(_kHighlight, value.name);
    notifyListeners();
  }

  Future<void> setZoom(double zoom) async {
    if (!zoom.isFinite || zoom <= 0) return;
    _settings = _settings.copyWith(zoom: zoom);
    await _prefs?.setDouble(_kZoom, zoom);
  }

  Future<void> setLastPosition(String path, int page) async {
    _settings = _settings.copyWith(lastDocument: path, lastPage: page);
    await _prefs?.setString(_kLastDocument, path);
    await _prefs?.setInt(_kLastPage, page);
  }

  /// Records [path] as the most recently opened document (deduplicated).
  Future<void> addRecent(String path) async {
    final next = <String>[
      path,
      ..._settings.recents.where((p) => p != path),
    ].take(AppSettings.maxRecents).toList(growable: false);
    _settings = _settings.copyWith(recents: next);
    await _prefs?.setStringList(_kRecents, next);
    notifyListeners();
  }

  Future<void> removeRecent(String path) async {
    final next = _settings.recents
        .where((p) => p != path)
        .toList(growable: false);
    _settings = _settings.copyWith(recents: next);
    await _prefs?.setStringList(_kRecents, next);
    notifyListeners();
  }

  /// Forgets the last document (e.g. it no longer exists).
  Future<void> clearLastPosition() async {
    _settings = AppSettings(
      themeMode: _settings.themeMode,
      zoom: _settings.zoom,
      recents: _settings.recents,
      selectionHighlight: _settings.selectionHighlight,
    );
    await _prefs?.remove(_kLastDocument);
    await _prefs?.remove(_kLastPage);
  }
}
