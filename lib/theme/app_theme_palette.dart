import 'package:flutter/material.dart';
import 'design_colors.dart';

/// dark / light の色値バンドルと構造差分フラグを保持する不変データ。
///
/// [AppThemeBuilder.build] が唯一の消費先。値はすべて解決済みの [Color] で、
/// ビルダー側に色演算（withValues 等）は置かない。
///
/// ## 対応表（HEAD の dark / light ビルダーからの抽出）
///
/// ColorScheme の差分（10 フィールド）:
/// - onPrimary / onSecondary: dark=Colors.black / light=Colors.white
/// - primaryContainer / secondaryContainer: dark=primary a0.2 / light=primary a0.1
/// - onPrimaryContainer / onSecondaryContainer: dark=primary / light=primaryDark
/// - surface: dark=surfaceDark / light=surfaceLight
/// - onSurface: dark=textPrimary / light=textPrimaryLight
/// - outline: dark=borderDark / light=borderLight
/// - outlineVariant: outline の a0.5
///
/// サブテーマの差分:
/// - scaffoldBackground: backgroundDark / backgroundLight
/// - appBarBackground: canvasDark a0.95 / canvasLight a0.95
/// - navBackground（bottomNav / navBar）: backgroundDark a0.9 / backgroundLight a0.9
/// - inputFill: inputDark / inputLight
/// - textMuted（input label / navBar 非選択 / segmented 非選択 fg / switch thumb 非選択）:
///   textMuted / textMutedLight
/// - hintColor: textMuted 系の a0.7
/// - textSecondary（iconTheme）: textSecondary / textSecondaryLight
///
/// ## 構造差分 6 箇所（色値ではなく「値の種類」が異なる箇所）
/// 1. [fabElevation]: dark=0 / light=2
/// 2. [fabForeground]: dark=Colors.black / light=Colors.white
/// 3. [elevatedButtonForeground]: dark=Colors.black / light=Colors.white
/// 4. [segmentedUnselectedBackground]: dark=Colors.black a0.4 / light=inputLight
/// 5. [enabledBorder]: dark=Colors.white a0.1 / light=borderLight
/// 6. [hasSwitchTheme]: dark=false（switchTheme なし）/ light=true
///    （[switchTrackSelected] は light 専用の track 選択色: primary a0.3）
class AppThemePalette {
  const AppThemePalette({
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.surface,
    required this.onSurface,
    required this.outline,
    required this.outlineVariant,
    required this.scaffoldBackground,
    required this.appBarBackground,
    required this.navBackground,
    required this.inputFill,
    required this.textMuted,
    required this.hintColor,
    required this.textSecondary,
    required this.fabElevation,
    required this.fabForeground,
    required this.elevatedButtonForeground,
    required this.segmentedUnselectedBackground,
    required this.segmentedSelectedForeground,
    required this.enabledBorder,
    required this.hasSwitchTheme,
    required this.switchTrackSelected,
  });

  /// ColorScheme.onPrimary（dark=black / light=white）
  final Color onPrimary;

  /// ColorScheme.primaryContainer（dark=primary a0.2 / light=primary a0.1）
  final Color primaryContainer;

  /// ColorScheme.onPrimaryContainer（dark=primary / light=primaryDark）
  final Color onPrimaryContainer;

  /// ColorScheme.onSecondary（dark=black / light=white）
  final Color onSecondary;

  /// ColorScheme.secondaryContainer（dark=primary a0.2 / light=primary a0.1）
  final Color secondaryContainer;

  /// ColorScheme.onSecondaryContainer（dark=primary / light=primaryDark）
  final Color onSecondaryContainer;

  /// ColorScheme.surface / cardTheme.color / snackBar・dialog・popupMenu・bottomSheet 背景
  final Color surface;

  /// ColorScheme.onSurface / textTheme 適用色 / appBar foreground・title 色 / snackBar 文字色 /
  /// dialog タイトル色
  final Color onSurface;

  /// ColorScheme.outline / card・snackBar・dialog・popupMenu の枠線 / divider /
  /// switch track 非選択色
  final Color outline;

  /// ColorScheme.outlineVariant（outline の a0.5）
  final Color outlineVariant;

  /// scaffoldBackgroundColor
  final Color scaffoldBackground;

  /// appBarTheme.backgroundColor（canvas a0.95）
  final Color appBarBackground;

  /// bottomNavigationBar / navigationBar の backgroundColor（background a0.9）
  final Color navBackground;

  /// inputDecorationTheme.fillColor
  final Color inputFill;

  /// input label 色 / navBar 非選択・segmented 非選択前景 / bottomNav 非選択 /
  /// switch thumb 非選択色（textMuted 系）
  final Color textMuted;

  /// inputDecorationTheme.hintStyle 色（textMuted 系の a0.7）
  final Color hintColor;

  /// iconTheme 色
  final Color textSecondary;

  /// 構造差分 1: FAB elevation（dark=0 / light=2）
  final double fabElevation;

  /// 構造差分 2: FAB foregroundColor（dark=black / light=white）
  final Color fabForeground;

  /// 構造差分 3: elevatedButton foregroundColor（dark=black / light=white）
  final Color elevatedButtonForeground;

  /// 構造差分 4: segmentedButton 非選択背景色
  /// （dark=Colors.black a0.4 / light=DesignColors.inputLight）
  final Color segmentedUnselectedBackground;

  /// segmentedButton 選択時 foregroundColor（dark=black / light=white）
  final Color segmentedSelectedForeground;

  /// 構造差分 5: input の enabledBorder 色（dark=Colors.white a0.1 / light=borderLight）
  final Color enabledBorder;

  /// 構造差分 6: switchTheme を含めるか（dark=false / light=true）
  final bool hasSwitchTheme;

  /// switchTheme の track 選択色（light 専用: primary a0.3。dark では未使用）
  final Color switchTrackSelected;

  /// ダークテーマ用パレット。
  static final AppThemePalette dark = AppThemePalette(
    onPrimary: Colors.black,
    primaryContainer: DesignColors.primary.withValues(alpha: 0.2),
    onPrimaryContainer: DesignColors.primary,
    onSecondary: Colors.black,
    secondaryContainer: DesignColors.primary.withValues(alpha: 0.2),
    onSecondaryContainer: DesignColors.primary,
    surface: DesignColors.surfaceDark,
    onSurface: DesignColors.textPrimary,
    outline: DesignColors.borderDark,
    outlineVariant: DesignColors.borderDark.withValues(alpha: 0.5),
    scaffoldBackground: DesignColors.backgroundDark,
    appBarBackground: DesignColors.canvasDark.withValues(alpha: 0.95),
    navBackground: DesignColors.backgroundDark.withValues(alpha: 0.9),
    inputFill: DesignColors.inputDark,
    textMuted: DesignColors.textMuted,
    hintColor: DesignColors.textMuted.withValues(alpha: 0.7),
    textSecondary: DesignColors.textSecondary,
    fabElevation: 0,
    fabForeground: Colors.black,
    elevatedButtonForeground: Colors.black,
    segmentedUnselectedBackground: Colors.black.withValues(alpha: 0.4),
    segmentedSelectedForeground: Colors.black,
    enabledBorder: Colors.white.withValues(alpha: 0.1),
    hasSwitchTheme: false,
    switchTrackSelected: DesignColors.primary.withValues(alpha: 0.3),
  );

  /// ライトテーマ用パレット。
  static final AppThemePalette light = AppThemePalette(
    onPrimary: Colors.white,
    primaryContainer: DesignColors.primary.withValues(alpha: 0.1),
    onPrimaryContainer: DesignColors.primaryDark,
    onSecondary: Colors.white,
    secondaryContainer: DesignColors.primary.withValues(alpha: 0.1),
    onSecondaryContainer: DesignColors.primaryDark,
    surface: DesignColors.surfaceLight,
    onSurface: DesignColors.textPrimaryLight,
    outline: DesignColors.borderLight,
    outlineVariant: DesignColors.borderLight.withValues(alpha: 0.5),
    scaffoldBackground: DesignColors.backgroundLight,
    appBarBackground: DesignColors.canvasLight.withValues(alpha: 0.95),
    navBackground: DesignColors.backgroundLight.withValues(alpha: 0.9),
    inputFill: DesignColors.inputLight,
    textMuted: DesignColors.textMutedLight,
    hintColor: DesignColors.textMutedLight.withValues(alpha: 0.7),
    textSecondary: DesignColors.textSecondaryLight,
    fabElevation: 2,
    fabForeground: Colors.white,
    elevatedButtonForeground: Colors.white,
    segmentedUnselectedBackground: DesignColors.inputLight,
    segmentedSelectedForeground: Colors.white,
    enabledBorder: DesignColors.borderLight,
    hasSwitchTheme: true,
    switchTrackSelected: DesignColors.primary.withValues(alpha: 0.3),
  );
}
