import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

/// Light and dark themes. Both are derived from one seed so contrast is
/// consistent; Material 3 supplies the accessible tone mappings.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );
    return base.copyWith(
      scaffoldBackgroundColor: brightness == Brightness.light
          ? AppColors.readingSurfaceLight
          : AppColors.readingSurfaceDark,
      textTheme: AppTypography.apply(base.textTheme),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }
}
