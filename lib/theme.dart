import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const seed = Color(0xFFB7A0F8);
  static const accents = <String, ({String name, Color color})>{
    'purple': (name: '紫罗兰', color: seed),
    'blue': (name: '蓝色', color: Color(0xFF4D8BDF)),
    'teal': (name: '青绿', color: Color(0xFF008578)),
    'rose': (name: '玫瑰', color: Color(0xFFC45C89)),
    'amber': (name: '琥珀', color: Color(0xFFAE7200)),
  };
  static ThemeData make(Brightness brightness, {String accent = 'purple'}) {
    final dark = brightness == Brightness.dark;
    var colors = ColorScheme.fromSeed(
      seedColor: (accents[accent] ?? accents['purple']!).color,
      brightness: brightness,
    );
    if (dark && accent == 'purple') {
      colors = colors.copyWith(
        primary: const Color(0xFFCDBDFF),
        onPrimary: const Color(0xFF30234D),
        primaryContainer: const Color(0xFF3C3153),
        onPrimaryContainer: const Color(0xFFE9DEFF),
        surface: const Color(0xFF141218),
        surfaceContainerLow: const Color(0xFF1B181F),
        surfaceContainer: const Color(0xFF211E27),
        surfaceContainerHigh: const Color(0xFF2B2731),
        onSurface: const Color(0xFFECE6F0),
        onSurfaceVariant: const Color(0xFFBFB8CA),
        outline: const Color(0xFF91899E),
        outlineVariant: const Color(0xFF494351),
      );
    }
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      brightness: brightness,
      scaffoldBackgroundColor: colors.surface,
      fontFamily: 'NotoSansSC',
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: 'NotoSansSC',
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: colors.onInverseSurface, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          side: BorderSide(color: colors.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: .5),
        space: 1,
      ),
    );
  }
}
