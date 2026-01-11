import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_colors.dart';

/// アプリテーマ定義（HTMLデザイン仕様準拠）
class AppTheme {
  AppTheme._();

  /// Space Grotesk ベースのテキストテーマ
  static TextTheme get _textTheme {
    return GoogleFonts.spaceGroteskTextTheme(const TextTheme(
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
    ));
  }

  /// JetBrains Mono モノスペースフォント
  static TextStyle get monoTextStyle {
    return GoogleFonts.jetBrainsMono(
      fontWeight: FontWeight.w400,
    );
  }

  /// ダークテーマ
  static ThemeData get dark {
    final colorScheme = ColorScheme.dark(
      primary: DesignColors.primary,
      onPrimary: Colors.black,
      primaryContainer: DesignColors.primary.withValues(alpha: 0.2),
      onPrimaryContainer: DesignColors.primary,
      secondary: DesignColors.primary,
      onSecondary: Colors.black,
      surface: DesignColors.surfaceDark,
      onSurface: DesignColors.textPrimary,
      error: DesignColors.error,
      onError: Colors.white,
      outline: DesignColors.borderDark,
      outlineVariant: DesignColors.borderDark.withValues(alpha: 0.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignColors.backgroundDark,
      textTheme: _textTheme.apply(
        bodyColor: DesignColors.textPrimary,
        displayColor: DesignColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: DesignColors.canvasDark.withValues(alpha: 0.95),
        foregroundColor: DesignColors.textPrimary,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: DesignColors.textPrimary,
          letterSpacing: -0.5,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: DesignColors.primary,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        extendedTextStyle: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: DesignColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DesignColors.borderDark),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignColors.inputDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: DesignColors.textMuted),
        hintStyle: TextStyle(color: DesignColors.textMuted.withValues(alpha: 0.7)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: DesignColors.backgroundDark.withValues(alpha: 0.9),
        selectedItemColor: DesignColors.primary,
        unselectedItemColor: DesignColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DesignColors.backgroundDark.withValues(alpha: 0.9),
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: DesignColors.primary,
            );
          }
          return GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: DesignColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DesignColors.primary);
          }
          return const IconThemeData(color: DesignColors.textMuted);
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: DesignColors.borderDark,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(
        color: DesignColors.textSecondary,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignColors.primary,
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignColors.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return DesignColors.primary;
            }
            return Colors.black.withValues(alpha: 0.4);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.black;
            }
            return DesignColors.textMuted;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DesignColors.surfaceDark,
        contentTextStyle: GoogleFonts.spaceGrotesk(
          color: DesignColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DesignColors.borderDark),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DesignColors.borderDark),
        ),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: DesignColors.textPrimary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: DesignColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DesignColors.borderDark),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DesignColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  /// ライトテーマ
  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: DesignColors.primary,
      onPrimary: Colors.white,
      primaryContainer: DesignColors.primary.withValues(alpha: 0.1),
      onPrimaryContainer: DesignColors.primaryDark,
      secondary: DesignColors.primary,
      onSecondary: Colors.white,
      surface: DesignColors.surfaceLight,
      onSurface: DesignColors.textPrimaryLight,
      error: DesignColors.error,
      onError: Colors.white,
      outline: DesignColors.borderLight,
      outlineVariant: DesignColors.borderLight.withValues(alpha: 0.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignColors.backgroundLight,
      textTheme: _textTheme.apply(
        bodyColor: DesignColors.textPrimaryLight,
        displayColor: DesignColors.textPrimaryLight,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: DesignColors.canvasLight.withValues(alpha: 0.95),
        foregroundColor: DesignColors.textPrimaryLight,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: DesignColors.textPrimaryLight,
          letterSpacing: -0.5,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: DesignColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        extendedTextStyle: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: DesignColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DesignColors.borderLight),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignColors.inputLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: DesignColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: DesignColors.textMutedLight),
        hintStyle: TextStyle(color: DesignColors.textMutedLight.withValues(alpha: 0.7)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: DesignColors.backgroundLight.withValues(alpha: 0.9),
        selectedItemColor: DesignColors.primary,
        unselectedItemColor: DesignColors.textMutedLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DesignColors.backgroundLight.withValues(alpha: 0.9),
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: DesignColors.primary,
            );
          }
          return GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: DesignColors.textMutedLight,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DesignColors.primary);
          }
          return const IconThemeData(color: DesignColors.textMutedLight);
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: DesignColors.borderLight,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(
        color: DesignColors.textSecondaryLight,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignColors.primary,
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return DesignColors.primary;
            }
            return DesignColors.inputLight;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return DesignColors.textMutedLight;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DesignColors.surfaceLight,
        contentTextStyle: GoogleFonts.spaceGrotesk(
          color: DesignColors.textPrimaryLight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DesignColors.borderLight),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DesignColors.borderLight),
        ),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: DesignColors.textPrimaryLight,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: DesignColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DesignColors.borderLight),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DesignColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DesignColors.primary;
          }
          return DesignColors.textMutedLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DesignColors.primary.withValues(alpha: 0.3);
          }
          return DesignColors.borderLight;
        }),
      ),
    );
  }

  /// テーマモードを取得
  static ThemeMode getThemeMode(String theme) {
    switch (theme) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
