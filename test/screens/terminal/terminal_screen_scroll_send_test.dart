import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/domain/wheel_encoder.dart';
import 'package:flutter_muxpod/services/ssh/ssh_client.dart';
import 'package:flutter_muxpod/widgets/key_overlay_widget.dart';

import '../../helpers/terminal_test_scaffold.dart';

/// 1 ティック = `_lineHeight × 1.5` = (fontSize 10 × 1.4) × 1.5 = 21.0px。
/// fontSize 10・adjustMode 'none' に固定して、整数倍が浮動小数点誤差なく
/// 正確にティック換算されるようにする。
const double _kTickPx = 21.0;

const _kFixedFontSettings = AppSettings(
  keepScreenOn: false,
  adjustMode: 'none',
  fontSize: 10.0,
);

const _kKeySendSettings = AppSettings(
  keepScreenOn: false,
  adjustMode: 'none',
  fontSize: 10.0,
  scrollSendInput: 'key',
);

dynamic _state(WidgetTester tester) =>
    tester.state(find.byType(TerminalScreen));

TerminalMode _mode(WidgetTester tester) =>
    tester.widget<AnsiTextView>(find.byType(AnsiTextView)).mode;

/// 設定メニュー → モード ListTile をタップしてモードを切り替える。
Future<void> _enterMode(WidgetTester tester, String modeLabel) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel));
  await tester.pumpAndSettle();
}

/// scrollSend 中に指定ティック数ぶん上ドラッグして累積する。
Future<void> _dragUpTicks(WidgetTester tester, int ticks) async {
  final center = tester.getCenter(find.byType(AnsiTextView));
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(Offset(0, -_kTickPx * ticks));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// 設定メニューで該当モードの ListTile が選択状態（check アイコン付き）か検証する。
void _expectSelectedMode(WidgetTester tester, String label, bool selected) {
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

void main() {
  group('scrollSend P0: モード状態機械・単一選択・原子性（D9/C1）', () {
    testWidgets(
      'TERM-SCROLL-016 normal → scrollSend → select の 3 モード遷移（排他的単一選択）',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: _kKeySendSettings,
        );
        expect(_mode(tester), TerminalMode.normal);

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
        expect(_mode(tester), TerminalMode.scrollSend);

        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        _expectSelectedMode(tester, 'Scroll Send Mode', true);
        _expectSelectedMode(tester, 'Normal Mode', false);
        _expectSelectedMode(tester, 'Select Mode', false);
        await tester.tapAt(const Offset(20, 100)); // シートを閉じる
        await tester.pumpAndSettle();

        // Select 選択 → Scroll Send の選択は解除される（排他性）。
        await _enterMode(tester, 'Select Mode');
        expect(_mode(tester), TerminalMode.select);
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();
        _expectSelectedMode(tester, 'Select Mode', true);
        _expectSelectedMode(tester, 'Scroll Send Mode', false);
        await tester.tapAt(const Offset(20, 100));
        await tester.pumpAndSettle();

        // Normal へ戻す。
        await _enterMode(tester, 'Normal Mode');
        expect(_mode(tester), TerminalMode.normal);
      },
    );

    testWidgets('TERM-SCROLL-018 原子性契約: scrollSend 入口で source==none・バッファ空', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: _kKeySendSettings,
      );

      // select でバッファを発生させた後に scrollSend へ入っても、
      // 原子性 setState（mode=scrollSend & source=none）+ バッファクリア（H5）
      // が成立する。
      await _enterMode(tester, 'Select Mode');
      await _enterMode(tester, 'Scroll Send Mode');

      final dynamic state = _state(tester);
      // source は none（C1）: copy-mode 自動検出が scrollSend 中も発火できる。
      expect(state.scrollModeSourceForTesting(), ScrollModeSource.none);
      expect(_mode(tester), TerminalMode.scrollSend);
      expect(state.hasBufferedUpdateForTesting(), isFalse);
      expect(state.bufferedContentForTesting(), '');
    });

    testWidgets(
      'TERM-SCROLL-019 scrollSend: SelectionArea なし + ドラッグで送信 + オフセット不動',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          settings: _kKeySendSettings,
        );
        await _enterMode(tester, 'Scroll Send Mode');

        // テキスト選択は無効（select 専用・D12）。
        expect(find.byType(SelectionArea), findsNothing);

        client.sendKeysCommands.clear();
        await _dragUpTicks(tester, 2);
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
        settings: _kFixedFontSettings, // scrollSendInput はデフォルト 'wheel'
      );
      await _enterMode(tester, 'Scroll Send Mode');

      // 既定（'wheel' + tmux wheelSend=true）→ SGR 1006 が送信される。
      client.sendKeysCommands.clear();
      await _dragUpTicks(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[<64;1;1M')),
        isTrue,
        reason: "設定 'wheel' + wheelSend 有効なら SGR が送信される",
      );

      // テストフックで kind=key を強制（承認済み・既存 *ForTesting パターン）。
      final dynamic state = _state(tester);
      state.overrideScrollSendKindForTesting(ScrollSendKind.key);
      client.sendKeysCommands.clear();
      await _dragUpTicks(tester, 1);
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
      await _dragUpTicks(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        client.sendKeysCommands.any((c) => c.contains(r'\x1b[<64;1;1M')),
        isTrue,
        reason: 'override 解除後は通常判定（wheel）へ戻る',
      );
    });
  });

  group('scrollSend P1: 合流送信・キー入力・方向反転（D6/H3/L0-a #4/#6）', () {
    testWidgets('TERM-SCROLL-021 合流送信: 最大 8 ティックを 1 コマンドに連結し超過分は保持', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: _kKeySendSettings,
      );
      await _enterMode(tester, 'Scroll Send Mode');
      client.sendKeysCommands.clear();

      // 10 ティック分をドラッグで累積（timer は 100ms 周期）。
      await _dragUpTicks(tester, 10);
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
          settings: _kKeySendSettings,
        );
        await _enterMode(tester, 'Scroll Send Mode');
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
        settings: _kKeySendSettings,
      );
      await _enterMode(tester, 'Scroll Send Mode');
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
      await _enterMode(tester, 'Scroll Send Mode');
      client.sendKeysCommands.clear();

      // 上ドラッグ → 反転により「下スクロール送信」（PgDn）になる。
      await _dragUpTicks(tester, 1);
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

  group('scrollSend P2: 異常系（R6/M4/H4②）', () {
    testWidgets('TERM-SCROLL-025 切断時は合流ティックを破棄し送信しない（R6）', (tester) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        settings: _kKeySendSettings,
      );
      await _enterMode(tester, 'Scroll Send Mode');

      client.setConnected(SshConnectionState.disconnected);
      client.sendKeysCommands.clear();
      await _dragUpTicks(tester, 3);
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
          settings: _kKeySendSettings,
        );
        await _enterMode(tester, 'Scroll Send Mode');

        // ポーリング間隔を最小（50ms）にブーストしてから、copy-mode を永続出力。
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp); // _boostPolling
        await tester.pump();
        client.sendKeysCommands.clear();
        client.execOutputs['capture-pane'] =
            'copy body\n11,12,100,40\ncopy-mode';

        // 検出ポーリング（≤50ms 後）が flush（100ms 後）より先に走るよう、
        // 検出を確認できるまで小刻みに pump する。
        await _dragUpTicks(tester, 2);
        for (var i = 0; i < 6 && _mode(tester) != TerminalMode.select; i++) {
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(
          _mode(tester),
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
        final dynamic state = _state(tester);
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
        settings: _kKeySendSettings,
      );
      await _enterMode(tester, 'Scroll Send Mode');

      client.sendKeysCommands.clear();
      await _dragUpTicks(tester, 3); // 累積（100ms タイマー起動）

      // 100ms の flush が発火する前に indicator の閉じるボタンで Normal へ
      // 戻す（C11: `_exitToNormalMode` → `_discardPendingScrollTicks`・M4）。
      // タップはテスト時間を進めないため、flush より確実に先行する
      // （pumpAndSettle は内部で 100ms 進めるため使わない）。
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(_mode(tester), TerminalMode.normal);

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
  });
}
