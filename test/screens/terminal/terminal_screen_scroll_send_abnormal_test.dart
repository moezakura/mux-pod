import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/terminal_zoom.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/scroll_send_test_helpers.dart';

void main() {
  group('scrollSend P2: 異常系（R6/M4/H4②）', () {
    testWidgets('TERM-SCROLL-025 切断時は合流ティックを破棄し送信しない（R6）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kKeySendSettings,
      );
      await enterMode(tester, 'Scroll Send Mode');

      client.setConnected(SshConnectionState.disconnected);
      client.sendKeysCommands.clear();
      await dragUpTicks(tester, 3);
      // 100ms flush を複数回回しても送信されない（破棄・キューなし）。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands,
        isEmpty,
        reason: '切断時は保留ティックを破棄し送信しない（R6）',
      );
    });

    testWidgets(
      'TERM-SCROLL-026 copy-mode 検出で select へ遷移し、遷移前の合流ティックは送信しない（D2）',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: kKeySendSettings,
        );
        await enterMode(tester, 'Scroll Send Mode');

        // ポーリング間隔を最小（50ms）にブーストしてから、copy-mode を永続出力。
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp); // _boostPolling
        await tester.pump();
        client.sendKeysCommands.clear();
        client.execOutputs['capture-pane'] =
            'copy body\n11,12,100,40\ncopy-mode';

        // 検出ポーリング（≤50ms 後）が flush（100ms 後）より先に走るよう、
        // 検出を確認できるまで小刻みに pump する。
        await dragUpTicks(tester, 2);
        for (var i = 0; i < 6 && mode(tester) != TerminalMode.select; i++) {
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(
          mode(tester),
          TerminalMode.select,
          reason: 'scrollSend 中の copy-mode 検出で select(tmux) へ自動遷移（L0-a #7）',
        );

        // 遷移後に flush を回しても、遷移前に積んだティックは送信されない。
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(
          client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~')),
          isFalse,
          reason: 'copy-mode 検出で合流バッファがクリアされ送信されない（D2）',
        );
        // 最小監視（A8）: copy-mode 自動遷移が記録されている。
        final dynamic state = stateOf(tester);
        final events = (state.herdrSwitchEventsForTesting() as List)
            .cast<String>();
        expect(
          events.any((e) => e.contains('copy-mode auto transition')),
          isTrue,
          reason: 'C12: copy-mode 自動遷移がリングバッファへ記録される',
        );
      },
    );

    testWidgets('TERM-SCROLL-027 モード切替で合流タイマー cancel・保留ティック破棄（M4）', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kKeySendSettings,
      );
      await enterMode(tester, 'Scroll Send Mode');

      client.sendKeysCommands.clear();
      await dragUpTicks(tester, 3); // 累積（100ms タイマー起動）

      // 100ms の flush が発火する前に indicator の閉じるボタンで Normal へ
      // 戻す（C11: `_exitToNormalMode` → `_discardPendingScrollTicks`・M4）。
      // タップはテスト時間を進めないため、flush より確実に先行する
      // （pumpAndSettle は内部で 100ms 進めるため使わない）。
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(mode(tester), TerminalMode.normal);

      // タイマーが cancel され保留ティックが破棄されていることを、flush 周期を
      // 十分に回しても送信されないことで検証する。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands,
        isEmpty,
        reason: 'モード切替で保留ティックが破棄される（M4）',
      );
    });

    // inventory: TEST-SCROLL-FIT-ZOOM-001
    testWidgets('scrollSend 自動フィットズーム: 突入で縮小・終了で復元', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kFitZoomSettings,
      );
      expect(currentZoom(tester), kMaxZoomFactor);

      // scrollSend 突入 → ターミナル全体が画面に収まるズームへ縮小される。
      await enterMode(tester, 'Scroll Send Mode');
      final fitZoom = currentZoom(tester);
      expect(
        fitZoom,
        lessThan(kMaxZoomFactor),
        reason: 'ズーム 5.0 ではターミナルがはみ出すため縮小されること',
      );
      expect(mode(tester), TerminalMode.scrollSend);

      // normal へ戻す → 元のズーム倍率へ復元される。
      await enterMode(tester, 'Normal Mode');
      expect(mode(tester), TerminalMode.normal);
      expect(
        currentZoom(tester),
        kMaxZoomFactor,
        reason: 'scrollSend 終了で適用前のズームへ復元されること',
      );
    });

    // inventory: TEST-SCROLL-FIT-ZOOM-002
    testWidgets('autoFitZoomOnScrollSend OFF ではズームを変更しない', (tester) async {
      const offSettings = AppSettings(
        keepScreenOn: false,
        adjustMode: 'none',
        fontSize: 10.0,
        zoomFactor: kMaxZoomFactor,
        autoFitZoomOnScrollSend: false,
      );
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: offSettings,
      );
      expect(currentZoom(tester), kMaxZoomFactor);

      await enterMode(tester, 'Scroll Send Mode');
      expect(mode(tester), TerminalMode.scrollSend);
      expect(
        currentZoom(tester),
        kMaxZoomFactor,
        reason: '設定 OFF では zoomFactor を変更しないこと',
      );
    });
  });
}
