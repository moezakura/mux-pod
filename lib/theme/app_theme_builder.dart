import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme_palette.dart';
import 'app_text_theme.dart';
import 'design_colors.dart';

/// パレットと Brightness から単一の ThemeData を構築する。
///
/// dark / light の差分はすべて [AppThemePalette] にデータ化されているため、
/// ビルダー本体は 1 系統のみ（過去の 85% 重複を排除）。
/// 分岐は「M3 の ColorScheme プリセット選択」（次の点で必須）と
/// switchTheme の有無（構造差分 6）のみ:
/// - [ColorScheme.dark] と [ColorScheme.light] は未指定フィールドの既定値が
///   異なるため、明示引数が同一でもプリセット選択は分岐が必要。
class AppThemeBuilder {
  AppThemeBuilder._();

  /// パレットと明暗から ThemeData を構築する。
  static ThemeData build(AppThemePalette palette, Brightness brightness) {
    // 未設定だと SDK が secondary（＝primary）を代用し、M3 の track 色
    // （secondaryContainer）と indicator（primary）が同色になって
    // LinearProgressIndicator の進捗が視認できなくなるため明示設定する。
    final colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: DesignColors.primary,
            onPrimary: palette.onPrimary,
            primaryContainer: palette.primaryContainer,
            onPrimaryContainer: palette.onPrimaryContainer,
            secondary: DesignColors.primary,
            onSecondary: palette.onSecondary,
            secondaryContainer: palette.secondaryContainer,
            onSecondaryContainer: palette.onSecondaryContainer,
            surface: palette.surface,
            onSurface: palette.onSurface,
            error: DesignColors.error,
            onError: Colors.white,
            outline: palette.outline,
            outlineVariant: palette.outlineVariant,
          )
        : ColorScheme.light(
            primary: DesignColors.primary,
            onPrimary: palette.onPrimary,
            primaryContainer: palette.primaryContainer,
            onPrimaryContainer: palette.onPrimaryContainer,
            secondary: DesignColors.primary,
            onSecondary: palette.onSecondary,
            secondaryContainer: palette.secondaryContainer,
            onSecondaryContainer: palette.onSecondaryContainer,
            surface: palette.surface,
            onSurface: palette.onSurface,
            error: DesignColors.error,
            onError: Colors.white,
            outline: palette.outline,
            outlineVariant: palette.outlineVariant,
          );

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.scaffoldBackground,
      textTheme: AppTextTheme.spaceGrotesk.apply(
        bodyColor: palette.onSurface,
        displayColor: palette.onSurface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: palette.appBarBackground,
        foregroundColor: palette.onSurface,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: palette.onSurface,
          letterSpacing: -0.5,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: DesignColors.primary,
        foregroundColor: palette.fabForeground,
        elevation: palette.fabElevation,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.outline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.enabledBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DesignColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: TextStyle(color: palette.textMuted),
        hintStyle: TextStyle(color: palette.hintColor),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.navBackground,
        selectedItemColor: DesignColors.primary,
        unselectedItemColor: palette.textMuted,
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
        backgroundColor: palette.navBackground,
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
            color: palette.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DesignColors.primary);
          }
          return IconThemeData(color: palette.textMuted);
        }),
      ),
      dividerTheme: DividerThemeData(color: palette.outline, thickness: 1),
      iconTheme: IconThemeData(color: palette.textSecondary),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignColors.primary,
          textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignColors.primary,
          foregroundColor: palette.elevatedButtonForeground,
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
            return palette.segmentedUnselectedBackground;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.segmentedSelectedForeground;
            }
            return palette.textMuted;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surface,
        contentTextStyle: GoogleFonts.spaceGrotesk(color: palette.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.outline),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.outline),
        ),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: palette.onSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
    // 構造差分 6: switchTheme は light のみ（dark では ThemeData 既定の
    // const SwitchThemeData() のまま）。
    if (!palette.hasSwitchTheme) {
      return theme;
    }
    return theme.copyWith(
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DesignColors.primary;
          }
          return palette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.switchTrackSelected;
          }
          return palette.outline;
        }),
      ),
    );
  }
}
