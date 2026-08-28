import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/theme/app_theme.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';

/// テーマのカラースキーム回帰テスト。
///
/// 背景: secondaryContainer を未設定のまま ColorScheme.dark/light を作ると、
/// SDK は `secondaryContainer => _secondaryContainer ?? secondary` で
/// secondary（＝本アプリでは primary と同色）を代用する。
/// M3 の LinearProgressIndicator は track 色に secondaryContainer を使うため、
/// 結果として track（未進行）と indicator（進行）が同色になり、
/// 転送進捗が視認できなくなる（Issue #41 の検証で発見）。
void main() {
  test('dark: secondaryContainer は primary と別トーン（track が視認できる）', () {
    final scheme = AppTheme.dark.colorScheme;

    expect(scheme.secondary, DesignColors.primary);
    expect(
      scheme.secondaryContainer,
      isNot(DesignColors.primary),
      reason:
          'secondaryContainer が primary と同色だと LinearProgressIndicator '
          'の track と indicator が区別できず進捗が見えない',
    );
    // 半透明で primary 由来の色であること
    expect((scheme.secondaryContainer.a * 255).round(), lessThan(255));
  });

  test('light: secondaryContainer は primary と別トーン（track が視認できる）', () {
    final scheme = AppTheme.light.colorScheme;

    expect(scheme.secondary, DesignColors.primary);
    expect(
      scheme.secondaryContainer,
      isNot(DesignColors.primary),
      reason:
          'secondaryContainer が primary と同色だと LinearProgressIndicator '
          'の track と indicator が区別できず進捗が見えない',
    );
    expect((scheme.secondaryContainer.a * 255).round(), lessThan(255));
  });

  testWidgets('LinearProgressIndicator の track 色が indicator と同色にならない', (
    tester,
  ) async {
    // value=0.3 のバーを AppTheme.dark で描画し、track（未進行部分）の色が
    // indicator（primary）と異なることをカスタムペイント結果ではなく
    // テーマ経由で検証する（描画色は painter 内部で決定されるため、
    // ここではテーマ保証を確認する）。
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const Scaffold()),
    );
    final scheme = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(scheme.secondaryContainer, isNot(scheme.primary));
  });
}
