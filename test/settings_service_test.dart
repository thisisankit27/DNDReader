import 'package:dndreader/models/app_settings.dart';
import 'package:dndreader/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults when nothing is stored', () async {
    final s = (await SettingsService.load()).settings;
    expect(s.themeMode, ThemeMode.system);
    expect(s.zoom, isNull);
    expect(s.lastDocument, isNull);
    expect(s.lastPage, isNull);
    expect(s.recents, isEmpty);
  });

  test('round-trips every field across a "restart"', () async {
    final first = await SettingsService.load();
    await first.setThemeMode(ThemeMode.dark);
    await first.setZoom(2.5);
    await first.setLastPosition('/docs/a.pdf', 7);
    await first.addRecent('/docs/a.pdf');

    final second = (await SettingsService.load()).settings;
    expect(second.themeMode, ThemeMode.dark);
    expect(second.zoom, 2.5);
    expect(second.lastDocument, '/docs/a.pdf');
    expect(second.lastPage, 7);
    expect(second.recents, ['/docs/a.pdf']);
  });

  test('recents are newest-first, deduplicated and capped', () async {
    final svc = await SettingsService.load();
    for (var i = 0; i < 12; i++) {
      await svc.addRecent('/d/$i.pdf');
    }
    await svc.addRecent('/d/5.pdf'); // re-opened: moves to the front
    final r = svc.settings.recents;
    expect(r.length, AppSettings.maxRecents);
    expect(r.first, '/d/5.pdf');
    expect(r.where((p) => p == '/d/5.pdf'), hasLength(1));
    expect((await SettingsService.load()).settings.recents, r);
  });

  test('removing a recent persists', () async {
    final svc = await SettingsService.load();
    await svc.addRecent('/a.pdf');
    await svc.addRecent('/b.pdf');
    await svc.removeRecent('/a.pdf');
    expect((await SettingsService.load()).settings.recents, ['/b.pdf']);
  });

  group('malformed stored values never break start-up', () {
    test('unknown theme, nonsense zoom, bad page', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'themeMode': 'solarized',
        'zoom': -3.0,
        'lastPage': 0,
        'lastDocument': '/x.pdf',
      });
      final s = (await SettingsService.load()).settings;
      expect(s.themeMode, ThemeMode.system);
      expect(s.zoom, isNull);
      expect(s.lastPage, isNull);
      expect(s.lastDocument, '/x.pdf');
    });

    test('wrongly typed values fall back to defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'zoom': 'big',
        'lastPage': 'three',
        'themeMode': 42,
        'recents': 'not-a-list',
        'lastDocument': 7,
      });
      final s = (await SettingsService.load()).settings;
      expect(s.zoom, isNull);
      expect(s.lastPage, isNull);
      expect(s.themeMode, ThemeMode.system);
      expect(s.recents, isEmpty);
      expect(s.lastDocument, isNull);
    });

    test('an absurd zoom is discarded', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'zoom': 1e9});
      expect((await SettingsService.load()).settings.zoom, isNull);
    });
  });

  test('clearLastPosition keeps theme, zoom and recents', () async {
    final svc = await SettingsService.load();
    await svc.setThemeMode(ThemeMode.light);
    await svc.setZoom(1.5);
    await svc.addRecent('/a.pdf');
    await svc.setLastPosition('/a.pdf', 3);
    await svc.clearLastPosition();

    final s = (await SettingsService.load()).settings;
    expect(s.lastDocument, isNull);
    expect(s.lastPage, isNull);
    expect(s.themeMode, ThemeMode.light);
    expect(s.zoom, 1.5);
    expect(s.recents, ['/a.pdf']);
  });
}
