import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0A0A0F);
  static const surface = Color(0xFF12121A);
  static const surfaceElevated = Color(0xFF1A1A26);
  static const border = Color(0xFF1E1E2E);

  /// Grafana-style blue — primary accent, “attention”, nav (replaces harsh orange).
  static const grafanaBlue = Color(0xFF5794F2);
  /// Muted Grafana yellow — secondary highlights only (easy on the eyes).
  static const grafanaYellow = Color(0xFFC9A25D);

  /// Primary UI accent (same as [grafanaBlue]). Legacy name kept for call sites.
  static const btcOrange = grafanaBlue;
  static const accent = grafanaBlue;
  static const accentSecondary = grafanaYellow;

  /// Softer up/down than neon (dark UI).
  static const positive = Color(0xFF2EB88A);
  static const negative = Color(0xFFD96A6A);
  static const neutral = Color(0xFF8A8A9A);

  static const textPrimary = Color(0xFFE8E8EE);
  static const textSecondary = Color(0xFF8A8A9A);
  static const textMuted = Color(0xFF5A5A6A);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: AppColors.textPrimary),
          displayMedium: TextStyle(color: AppColors.textPrimary),
          displaySmall: TextStyle(color: AppColors.textPrimary),
          headlineLarge: TextStyle(color: AppColors.textPrimary),
          headlineMedium: TextStyle(color: AppColors.textPrimary),
          headlineSmall: TextStyle(color: AppColors.textPrimary),
          titleLarge: TextStyle(color: AppColors.textPrimary),
          titleMedium: TextStyle(color: AppColors.textPrimary),
          titleSmall: TextStyle(color: AppColors.textSecondary),
          bodyLarge: TextStyle(color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textSecondary),
          bodySmall: TextStyle(color: AppColors.textMuted),
          labelLarge: TextStyle(color: AppColors.textPrimary),
          labelMedium: TextStyle(color: AppColors.textSecondary),
          labelSmall: TextStyle(color: AppColors.textMuted),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerColor: AppColors.border,
    );
  }
}
