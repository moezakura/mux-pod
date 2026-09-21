// テーマ等価性回帰テスト（golden fixture 方式）。
//
// 背景: 責務ベース再設計（docs/design/refactor-p1/ansi-herdr-theme.md §2.3）の
// 移行時、HEAD 逐語ビルダーと新ビルダー（AppThemePalette + AppThemeBuilder）の
// 出力が deep compare で diff ゼロであることを一時テストで確認済み。その
// 「検証済み状態」を fixture（deep snapshot）として固定し、将来のパレット・
// ビルダー編集による全フィールドの回帰を検知する。
//
// 固定対象:
// - colorScheme の全色フィールド（brightness 含む全 34 フィールド）
// - 全サブテーマ: appBar / FAB / card / input / bottomNav / navBar / divider /
//   icon / textButton / elevatedButton / segmented / snackBar / dialog /
//   popupMenu / bottomSheet / switch / textTheme（15 スタイル全フィールド）
// - 構造差分 6 箇所（FAB elevation・foreground、elevatedButton foreground、
//   segmented 非選択背景、enabledBorder、switchTheme 有無）は上記に包含
// - WidgetStateProperty 系は {default, disabled, selected, hovered, focused,
//   pressed, disabled+selected} の各状態を解決した値で固定（_ResolvedProp）
//
// fixture の再生成方法:
//   1. 本ファイルと同じ buildFixtureSnapshot を一時テストから呼び、
//      test/theme/fixtures/theme_{dark,light}.txt を出力する
//   2. 差分をレビューし、意図した変更であることを確認してコミットする
//
// 決定論性のための処理:
// - WidgetStateProperty.resolveWith は値の == を持たない（Flutter SDK の
//   _WidgetStatePropertyWith に operator== がない）ため、状態バッテリーで
//   解決値を記録する _ResolvedProp へ置換してから文字列化する
// - toString(minLevel: DebugLevel.debug) の出力に含まれる object identity
//   hash（ClassName#xxxxx の #xxxxx）は実行ごとに変化するため除去する
// - 決定論性は生成時に「2 回生成して diff ゼロ」で確認済み
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/theme/app_theme.dart';

/// resolveWith プロパティを「状態バッテリー × 解決値」の記録へ置換し、
/// fixture 化可能（決定的な toString）にするラッパー。
class _ResolvedProp<T> implements WidgetStateProperty<T> {
  _ResolvedProp(WidgetStateProperty<T> original, this._battery)
    : _original = original,
      _resolved = {for (final s in _battery) s: original.resolve(s)};

  final WidgetStateProperty<T> _original;
  final List<Set<WidgetState>> _battery;
  final Map<Set<WidgetState>, T> _resolved;

  @override
  T resolve(Set<WidgetState> states) => _resolved.containsKey(states)
      ? _resolved[states]!
      : _original.resolve(states);

  @override
  String toString() {
    final buf = StringBuffer('Prop[');
    var first = true;
    for (final s in _battery) {
      if (!first) buf.write(' | ');
      first = false;
      final names = (s.map((e) => e.name).toList()..sort()).join(',');
      buf.write('$names => ${_resolved[s]}');
    }
    buf.write(']');
    return buf.toString();
  }
}

/// 状態バッテリー（WidgetStateProperty を固定する状態の集合）。
const _battery = <Set<WidgetState>>[
  <WidgetState>{}, // default
  {WidgetState.disabled},
  {WidgetState.selected},
  {WidgetState.hovered},
  {WidgetState.focused},
  {WidgetState.pressed},
  {WidgetState.disabled, WidgetState.selected},
];

WidgetStateProperty<T>? _wrap<T>(WidgetStateProperty<T>? prop) =>
    prop is WidgetStateProperty<T> ? _ResolvedProp<T>(prop, _battery) : null;

/// resolveWith プロパティを記録型へ置換した「正規化済みテーマ」。
ThemeData _normalized(ThemeData theme) {
  final nav = theme.navigationBarTheme;
  final seg = theme.segmentedButtonTheme;
  final sw = theme.switchTheme;
  return theme.copyWith(
    navigationBarTheme: nav.copyWith(
      labelTextStyle: _wrap(nav.labelTextStyle),
      iconTheme: _wrap(nav.iconTheme),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: seg.style?.copyWith(
        backgroundColor: _wrap(seg.style!.backgroundColor),
        foregroundColor: _wrap(seg.style!.foregroundColor),
      ),
    ),
    switchTheme: sw.copyWith(
      thumbColor: _wrap(sw.thumbColor),
      trackColor: _wrap(sw.trackColor),
    ),
  );
}

/// object identity hash（実行ごとに変化する #xxxxx）を除去する。
String _stripHashes(String s) => s.replaceAll(RegExp(r'#[0-9a-f]{4,5}'), '');

/// Diagnosticable は debug レベルで文字列化し、普通の値は素朴に文字列化する。
String _dump(Object? o) {
  final s = o is Diagnosticable
      ? (o as dynamic).toString(minLevel: DiagnosticLevel.debug)
      : o.toString();
  return _stripHashes(s);
}

/// 黄金 fixture スナップショットを構築する。
/// （fixture 再生成時はこの関数の出力を test/theme/fixtures/*.txt へ保存する）
String buildFixtureSnapshot(ThemeData theme, String mode) {
  final t = _normalized(theme);
  final buf = StringBuffer();
  void section(String name, Object? value) {
    buf.writeln('## $name ($mode)');
    buf.writeln(_dump(value));
    buf.writeln();
  }

  section('brightness', t.brightness);
  section('useMaterial3', t.useMaterial3);
  section('scaffoldBackgroundColor', t.scaffoldBackgroundColor);
  section('colorScheme', t.colorScheme);
  section('appBarTheme', t.appBarTheme);
  section('floatingActionButtonTheme', t.floatingActionButtonTheme);
  section('cardTheme', t.cardTheme);
  section('inputDecorationTheme', t.inputDecorationTheme);
  section('bottomNavigationBarTheme', t.bottomNavigationBarTheme);
  section('navigationBarTheme', t.navigationBarTheme);
  section('dividerTheme', t.dividerTheme);
  section('iconTheme', t.iconTheme);
  section('textButtonTheme', t.textButtonTheme);
  section('elevatedButtonTheme', t.elevatedButtonTheme);
  section('segmentedButtonTheme', t.segmentedButtonTheme);
  section('snackBarTheme', t.snackBarTheme);
  section('dialogTheme', t.dialogTheme);
  section('popupMenuTheme', t.popupMenuTheme);
  section('bottomSheetTheme', t.bottomSheetTheme);
  section('switchTheme', t.switchTheme);
  section('textTheme(15 styles)', t.textTheme);
  return buf.toString();
}

String _fixture(String name) =>
    File('test/theme/fixtures/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('golden fixture（HEAD 検証済み状態の deep snapshot）', () {
    test('dark: AppTheme.dark が theme_dark.txt と一致する', () {
      expect(
        buildFixtureSnapshot(AppTheme.dark, 'dark'),
        _fixture('theme_dark.txt'),
      );
    });

    test('light: AppTheme.light が theme_light.txt と一致する', () {
      expect(
        buildFixtureSnapshot(AppTheme.light, 'light'),
        _fixture('theme_light.txt'),
      );
    });
  });
}
