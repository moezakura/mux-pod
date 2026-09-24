// P5 helper: scrollSend テスト専用の定数・助関数（H3）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/terminal_zoom.dart';

/// 1 ティック = `_lineHeight × 1.5` = (fontSize 10 × 1.4) × 1.5 = 21.0px。
/// fontSize 10・adjustMode 'none' に固定して、整数倍が浮動小数点誤差なく
/// 正確にティック換算されるようにする。
const double kTickPx = 21.0;

const kFixedFontSettings = AppSettings(
  keepScreenOn: false,
  adjustMode: 'none',
  fontSize: 10.0,
);

const kKeySendSettings = AppSettings(
  keepScreenOn: false,
  adjustMode: 'none',
  fontSize: 10.0,
  scrollSendInput: 'key',
);

/// scrollSend 自動フィットズーム検証用: ズーム 5.0（最大）から開始。
const kFitZoomSettings = AppSettings(
  keepScreenOn: false,
  adjustMode: 'none',
  fontSize: 10.0,
  zoomFactor: kMaxZoomFactor,
  autoFitZoomOnScrollSend: true,
);

dynamic stateOf(WidgetTester tester) =>
    tester.state(find.byType(TerminalScreen));

TerminalMode mode(WidgetTester tester) =>
    tester.widget<AnsiTextView>(find.byType(AnsiTextView)).mode;

/// 現在の設定プロバイダー状態の zoomFactor を取得する。
double currentZoom(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TerminalScreen)),
  );
  return container.read(settingsProvider).zoomFactor;
}

/// 設定メニュー → モード ListTile をタップしてモードを切り替える。
Future<void> enterMode(WidgetTester tester, String modeLabel) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel));
  await tester.pumpAndSettle();
}

/// scrollSend 中に指定ティック数ぶん上ドラッグして累積する。
Future<void> dragUpTicks(WidgetTester tester, int ticks) async {
  final center = tester.getCenter(find.byType(AnsiTextView));
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(Offset(0, -kTickPx * ticks));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// 設定メニューで該当モードの ListTile が選択状態（check アイコン付き）か検証する。
void expectSelectedMode(WidgetTester tester, String label, bool selected) {
  final tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(ListTile),
  );
  expect(
    find.descendant(of: tile, matching: find.byIcon(Icons.check)),
    selected ? findsOneWidget : findsNothing,
    reason: '$label は選択${selected ? 'されている' : 'されていない'}こと',
  );
}
