import 'package:flutter/material.dart';

/// Typography for the chrome. System UI fonts only: no font assets are bundled
/// and nothing is fetched at run time.
abstract final class AppTypography {
  static const List<String> fontFallback = <String>[
    'Ubuntu',
    'Noto Sans',
    'Cantarell',
    'DejaVu Sans',
  ];

  static TextTheme apply(TextTheme base) {
    return base.apply(fontFamilyFallback: fontFallback);
  }
}
