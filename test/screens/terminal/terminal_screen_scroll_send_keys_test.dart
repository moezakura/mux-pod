import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/widgets/key_overlay_widget.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/scroll_send_test_helpers.dart';

void main() {
  group('scrollSend P1: 合流送信・キー入力・方向反転（D6/H3/L0-a #4/#6）', () {
    testWidgets('TERM-SCROLL-021 合流送信: 最大 8 ティックを 1 コマンドに連結し超過分は保持', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kKeySendSettings,
      );
      await enterMode(tester, 'Scroll Send Mode');
      client.sendKeysCommands.clear();

      // 10 ティック分をドラッグで累積（timer は 100ms 周期）。
      await dragUpTicks(tester, 10);
      expect(client.sendKeysCommands, isEmpty, reason: 'flush 前に送信されない');

      // 1 回目の flush: 最大 8 ティックを 1 コマンドに連結、超過分（2）は保持。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~' * 8)),
        isTrue,
        reason: '8 ティック分が 1 コマンドに連結される（D6）',
      );
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~' * 9)),
        isFalse,
        reason: '1 コマンドあたり最大 8 ティック（超過分は送らない）',
      );

      // 2 回目の flush: 保持された 2 ティックが送信される。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~' * 2)),
        isTrue,
        reason: '超過分は次回 flush で送信される',
      );
    });

    testWidgets(
      'TERM-SCROLL-022 PgUp/PgDn キー → \\x1b[5~ / \\x1b[6~ を sendScroll(key) で送信',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: kKeySendSettings,
        );
        await enterMode(tester, 'Scroll Send Mode');
        client.sendKeysCommands.clear();

        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pump();
        expect(
          client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~')),
          isTrue,
          reason: 'PgUp で PgUp シーケンスが送信される（L2-2 #3 DoD）',
        );

        client.sendKeysCommands.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pump();
        expect(
          client.sendKeysCommands.any((c) => c.contains(r'\x1b[6~')),
          isTrue,
          reason: 'PgDn で PgDn シーケンスが送信される',
        );
      },
    );

    testWidgets('TERM-SCROLL-023 文字キーは sendText 経由・オーバーレイなし・キューなし', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kKeySendSettings,
      );
      await enterMode(tester, 'Scroll Send Mode');
      client.sendKeysCommands.clear();

      // 文字キー 'a' → sendText（tmux send-keys -l）で送信される。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(' -- a')),
        isTrue,
        reason: '文字キーが sendText 経由で送信される（(b) 全キー送信）',
      );

      // キーオーバーレイは表示されない（H3: _showKeyOverlay を呼ばない）。
      // SpecialKeysBar に常時表示される 'PgUp' ボタンと区別するため、
      // KeyOverlayWidget 配下のテキストのみを対象にする（隠れ時は shrink）。
      final overlay = find.byType(KeyOverlayWidget);
      expect(
        find.descendant(of: overlay, matching: find.text('PgUp')),
        findsNothing,
        reason: 'scrollSend 中はキーオーバーレイに PgUp が表示されない（H3）',
      );
      expect(
        find.descendant(of: overlay, matching: find.text('a')),
        findsNothing,
      );

      // 未接続時はキューしない（即ドロップ・R6）。
      client.setConnected(SshConnectionState.disconnected);
      client.sendKeysCommands.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'b');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(client.sendKeysCommands, isEmpty, reason: '未接続時は即ドロップしキューに積まない');
    });

    testWidgets('TERM-SCROLL-024 方向反転設定 ON でドラッグ方向が反転する（L0-a #4）', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: const AppSettings(
          keepScreenOn: false,
          adjustMode: 'none',
          fontSize: 10.0,
          scrollSendInput: 'key',
          invertScrollSendDirection: true,
        ),
      );
      await enterMode(tester, 'Scroll Send Mode');
      client.sendKeysCommands.clear();

      // 上ドラッグ → 反転により「下スクロール送信」（PgDn）になる。
      await dragUpTicks(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[6~')),
        isTrue,
        reason: '反転 ON: ドラッグ上 = 下スクロール送信',
      );
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~')),
        isFalse,
      );
    });
  });
}
