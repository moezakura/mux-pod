import 'package:flutter/material.dart';
import 'app_theme_builder.dart';
import 'app_theme_palette.dart';
import 'app_text_theme.dart';

/// アプリテーマ定義（HTMLデザイン仕様準拠）の公開ファサード。
///
/// 責務を分割した部品を合成する（ロジックはビルダー側）:
/// - 色値・構造差分: [AppThemePalette]
/// - ThemeData 構築: [AppThemeBuilder]（単一ビルダー）
/// - テキストテーマ: [AppTextTheme]
class AppTheme {
  AppTheme._();

  /// ダークテーマ
  static ThemeData get dark =>
      AppThemeBuilder.build(AppThemePalette.dark, Brightness.dark);

  /// ライトテーマ
  static ThemeData get light =>
      AppThemeBuilder.build(AppThemePalette.light, Brightness.light);

  /// JetBrains Mono モノスペースフォント
  static TextStyle get monoTextStyle => AppTextTheme.mono;
}
