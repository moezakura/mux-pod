import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/wheel_encoder.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/scroll_send_test_helpers.dart';

void main() {
  group('scrollSend P0: モード状態機械・単一選択・原子性（D9/C1）', () {
    testWidgets(
      'TERM-SCROLL-016 normal → scrollSend → select の 3 モード遷移（排他的単一選択）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: kKeySendSettings,
        );
        expect(mode(tester), TerminalMode.normal);

        // 設定メニューに 3 つの ListTile が並ぶ（Switch ではない）。
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        expect(find.text('Normal Mode'), findsOneWidget);
        expect(find.text('Scroll Send Mode'), findsOneWidget);
        expect(find.text('Select Mode'), findsOneWidget);
        expect(find.byType(Switch), findsNothing, reason: '2 値 Switch は廃止（D9）');

        // Scroll Send 選択 → 選択中は check アイコンのみ。
        await tester.tap(find.text('Scroll Send Mode'));
        await tester.pumpAndSettle();
        expect(mode(tester), TerminalMode.scrollSend);

        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        expectSelectedMode(tester, 'Scroll Send Mode', true);
        expectSelectedMode(tester, 'Normal Mode', false);
        expectSelectedMode(tester, 'Select Mode', false);
        await tester.tapAt(const Offset(20, 100)); // シートを閉じる
        await tester.pumpAndSettle();

        // Select 選択 → Scroll Send の選択は解除される（排他性）。
        await enterMode(tester, 'Select Mode');
        expect(mode(tester), TerminalMode.select);
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        expectSelectedMode(tester, 'Select Mode', true);
        expectSelectedMode(tester, 'Scroll Send Mode', false);
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();

        // Normal へ戻す。
        await enterMode(tester, 'Normal Mode');
        expect(mode(tester), TerminalMode.normal);
      },
    );

    testWidgets('TERM-SCROLL-018 原子性契約: scrollSend 入口で source==none・バッファ空', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kKeySendSettings,
      );

      // select でバッファを発生させた後に scrollSend へ入っても、
      // 原子性 setState（mode=scrollSend & source=none）+ バッファクリア（H5）
      // が成立する。
      await enterMode(tester, 'Select Mode');
      await enterMode(tester, 'Scroll Send Mode');

      final dynamic state = stateOf(tester);
      // source は none（C1）: copy-mode 自動検出が scrollSend 中も発火できる。
      expect(state.scrollModeSourceForTesting(), ScrollModeSource.none);
      expect(mode(tester), TerminalMode.scrollSend);
      expect(state.hasBufferedUpdateForTesting(), isFalse);
      expect(state.bufferedContentForTesting(), '');
    });

    testWidgets('TERM-SCROLL-028 scrollSend 突入時に末尾（ライブ画面）へスクロール', (
      tester,
    ) async {
      // 履歴を遡った位置（上端）から scrollSend へ入ると末尾へスクロールされる。
      // scrollSend 中はローカルスクロールが無効化（D5）されるため、突入時に
      // ライブ画面の末尾を表示する。
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kFixedFontSettings,
        execOutputs: {
          // ビューポート（1920px）を超える 300 行のコンテンツ。
          // ポーリングは結合コマンド（capture-pane; cursor; pane_mode）への
          // 1 応答を末尾 2 行で分割するため、cursor 行 + 空の pane_mode 行
          // で終わらせる（pane_mode が空 → copy-mode 検出は発火しない）。
          'capture-pane':
              '${List.generate(300, (i) => 'line-$i').join('\n')}\n'
              '1,299,80,300\n',
        },
      );

      ScrollPosition scrollPosition(WidgetTester tester) => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(AnsiTextView),
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            ),
          )
          .position;

      final initial = scrollPosition(tester);
      expect(
        initial.maxScrollExtent,
        greaterThan(0),
        reason: 'コンテンツがビューポートを超えスクロール可能な状態であること',
      );

      // 履歴を遡った（上端）状態を再現。
      initial.jumpTo(0);
      await tester.pump();
      expect(initial.pixels, 0);

      await enterMode(tester, 'Scroll Send Mode');
      expect(mode(tester), TerminalMode.scrollSend);

      // モード切替で physics が変わり ScrollPosition が再生成されるため再取得する。
      // scrollToBottom の animateTo(300ms) は pumpAndSettle で消化済み。
      final after = scrollPosition(tester);
      expect(
        after.pixels,
        closeTo(after.maxScrollExtent, 1.0),
        reason: 'scrollSend 突入時に末尾へスクロールされること',
      );
    });

    testWidgets(
      'TERM-SCROLL-019 scrollSend: SelectionArea なし + ドラッグで送信 + オフセット不動',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: kKeySendSettings,
        );
        await enterMode(tester, 'Scroll Send Mode');

        // テキスト選択は無効（select 専用・D12）。
        expect(find.byType(SelectionArea), findsNothing);

        client.sendKeysCommands.clear();
        await dragUpTicks(tester, 2);
        await tester.pump(const Duration(milliseconds: 100)); // flush
        await tester.pump();

        // ドラッグ → PgUp（kind=key）が送信される（scrollSendInput='key'）。
        expect(
          client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~')),
          isTrue,
          reason: '上ドラッグで PgUp が送信されること',
        );
      },
    );

    testWidgets('TERM-SCROLL-020 送信方式ゲート（D11）: wheel 有効時 SGR・key へフォールバック', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: kFixedFontSettings, // scrollSendInput はデフォルト 'wheel'
      );
      await enterMode(tester, 'Scroll Send Mode');

      // 既定（'wheel' + tmux wheelSend=true）→ SGR 1006 が送信される。
      client.sendKeysCommands.clear();
      await dragUpTicks(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[<64;1;1M')),
        isTrue,
        reason: "設定 'wheel' + wheelSend 有効なら SGR が送信される",
      );

      // テストフックで kind=key を強制（承認済み・既存 *ForTesting パターン）。
      final dynamic state = stateOf(tester);
      state.overrideScrollSendKindForTesting(ScrollSendKind.key);
      client.sendKeysCommands.clear();
      await dragUpTicks(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[5~')),
        isTrue,
        reason: 'kind=key 強制時は PgUp にフォールバックする（D11）',
      );
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[<64;1;1M')),
        isFalse,
      );

      // null で通常判定へ復帰。
      state.overrideScrollSendKindForTesting(null);
      client.sendKeysCommands.clear();
      await dragUpTicks(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[<64;1;1M')),
        isTrue,
        reason: 'override 解除後は通常判定（wheel）へ戻る',
      );
    });
  });
}
