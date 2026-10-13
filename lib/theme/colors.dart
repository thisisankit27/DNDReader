import 'package:flutter/material.dart';

/// Colours for the app chrome. The PDF is the product; the chrome stays quiet.
abstract final class AppColors {
  /// Seed for the Material colour scheme (a muted teal).
  static const Color seed = Color(0xFF2F5D62);

  /// Behind the document pages, light theme.
  static const Color readingSurfaceLight = Color(0xFFECEAE4);

  /// Behind the document pages, dark theme.
  static const Color readingSurfaceDark = Color(0xFF151618);
}
