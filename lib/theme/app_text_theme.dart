import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Space Grotesk のテキストテーマと JetBrains Mono のモノスペーススタイルを定義する。
class AppTextTheme {
  AppTextTheme._();

  /// Space Grotesk ベースのテキストテーマ（暗/明共通）。
  static TextTheme get spaceGrotesk {
    return GoogleFonts.spaceGroteskTextTheme(
      const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w700),
        displayMedium: TextStyle(fontWeight: FontWeight.w700),
        displaySmall: TextStyle(fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontWeight: FontWeight.w400),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        labelMedium: TextStyle(fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
    );
  }

  /// JetBrains Mono モノスペースフォント。
  static TextStyle get mono {
    return GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w400);
  }
}
