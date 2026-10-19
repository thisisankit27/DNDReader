import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Status and navigation bar styling for an app that draws edge to edge (Android).
///
/// Transparent bars with icons that contrast with the theme, so they stay legible in both light and dark.
/// Applied only when the theme brightness changes.
class SystemBars {
  SystemBars._();

  static Brightness? _applied;

  static void apply(Brightness brightness) {
    if (_applied == brightness) return;
    _applied = brightness;
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        statusBarBrightness: brightness,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }
}
