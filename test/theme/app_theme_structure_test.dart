import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/theme/app_theme.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

/// パレット化（app_theme_palette.dart）でエンコードした構造差分 6 箇所と
/// 主要色の回帰テスト。
///
/// 設計書 ansi-herdr-theme.md §2.3 / §7-R3 対応。
/// 等価性（HEAD 逐語ビルダーと新ビルダーの diff ゼロ）は移行時に一時テストで
/// 確認済み。ここでは将来のパレット編集時に「構造差分の取り違え」を検知する。
void main() {
  // AppTheme.dark/light 構築時に GoogleFonts のフォントロード（AssetManifest
  // 参照）が走るため、plain test でも ServicesBinding を初期化しておく。
  // （既存 app_theme_test は testWidgets の登録時に同名の初期化が走る）
  TestWidgetsFlutterBinding.ensureInitialized();

  group('構造差分（dark/light で値・有無が異なる 6 箇所）', () {
    test('1. FAB elevation: dark=0 / light=2', () {
      expect(AppTheme.dark.floatingActionButtonTheme.elevation, 0);
      expect(AppTheme.light.floatingActionButtonTheme.elevation, 2);
    });

    test('2. FAB foregroundColor: dark=black / light=white', () {
      expect(
        AppTheme.dark.floatingActionButtonTheme.foregroundColor,
        Colors.black,
      );
      expect(
        AppTheme.light.floatingActionButtonTheme.foregroundColor,
        Colors.white,
      );
    });

    test('3. elevatedButton foregroundColor: dark=black / light=white', () {
      expect(
        AppTheme.dark.elevatedButtonTheme.style!.foregroundColor?.resolve(
          const <WidgetState>{},
        ),
        Colors.black,
      );
      expect(
        AppTheme.light.elevatedButtonTheme.style!.foregroundColor?.resolve(
          const <WidgetState>{},
        ),
        Colors.white,
      );
    });

    test('4. segmentedButton 非選択背景: dark=black a0.4 / light=inputLight', () {
      final darkBg = AppTheme.dark.segmentedButtonTheme.style!.backgroundColor!
          .resolve(const <WidgetState>{});
      final lightBg = AppTheme
          .light
          .segmentedButtonTheme
          .style!
          .backgroundColor!
          .resolve(const <WidgetState>{});
      expect(darkBg, Colors.black.withValues(alpha: 0.4));
      expect(lightBg, DesignColors.inputLight);
      expect(darkBg, isNot(lightBg));
    });

    test('5. enabledBorder: dark=white a0.1 / light=borderLight', () {
      final darkBorder =
          AppTheme.dark.inputDecorationTheme.enabledBorder
              as OutlineInputBorder;
      final lightBorder =
          AppTheme.light.inputDecorationTheme.enabledBorder
              as OutlineInputBorder;
      expect(darkBorder.borderSide.color, Colors.white.withValues(alpha: 0.1));
      expect(lightBorder.borderSide.color, DesignColors.borderLight);
    });

    test('6. switchTheme: dark なし / light あり', () {
      // dark は未指定 → ThemeData 既定（const SwitchThemeData）のまま。
      expect(AppTheme.dark.switchTheme, const SwitchThemeData());
      final lightSwitch = AppTheme.light.switchTheme;
      expect(lightSwitch, isNot(const SwitchThemeData()));
      expect(
        lightSwitch.thumbColor?.resolve(const {WidgetState.selected}),
        DesignColors.primary,
      );
      expect(
        lightSwitch.trackColor?.resolve(const {WidgetState.selected}),
        DesignColors.primary.withValues(alpha: 0.3),
      );
    });
  });

  test('主要色: scheme とサブテーマの暗/明バンドルが期待値どおり', () {
    final dark = AppTheme.dark;
    final light = AppTheme.light;

    // ColorScheme
    expect(dark.colorScheme.onPrimary, Colors.black);
    expect(light.colorScheme.onPrimary, Colors.white);
    expect(
      dark.colorScheme.primaryContainer,
      DesignColors.primary.withValues(alpha: 0.2),
    );
    expect(
      light.colorScheme.primaryContainer,
      DesignColors.primary.withValues(alpha: 0.1),
    );
    expect(dark.colorScheme.surface, DesignColors.surfaceDark);
    expect(light.colorScheme.surface, DesignColors.surfaceLight);
    expect(dark.colorScheme.onSurface, DesignColors.textPrimary);
    expect(light.colorScheme.onSurface, DesignColors.textPrimaryLight);
    expect(dark.colorScheme.outline, DesignColors.borderDark);
    expect(light.colorScheme.outline, DesignColors.borderLight);

    // サブテーマ
    expect(dark.scaffoldBackgroundColor, DesignColors.backgroundDark);
    expect(light.scaffoldBackgroundColor, DesignColors.backgroundLight);
    expect(
      dark.floatingActionButtonTheme.backgroundColor,
      DesignColors.primary,
    );
    expect(
      light.floatingActionButtonTheme.backgroundColor,
      DesignColors.primary,
    );
    expect(dark.iconTheme.color, DesignColors.textSecondary);
    expect(light.iconTheme.color, DesignColors.textSecondaryLight);
    expect(
      dark.appBarTheme.backgroundColor,
      DesignColors.canvasDark.withValues(alpha: 0.95),
    );
    expect(
      light.appBarTheme.backgroundColor,
      DesignColors.canvasLight.withValues(alpha: 0.95),
    );
    expect(dark.inputDecorationTheme.fillColor, DesignColors.inputDark);
    expect(light.inputDecorationTheme.fillColor, DesignColors.inputLight);
  });
}
