import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/widgets/special_keys_bar.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr mutation enabled (T13)', () {
    testWidgets('mutation UI is enabled: SpecialKeysBar shown, '
        'no disconnected banner', (tester) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'hello\n',
        },
        settle: false,
      );

      // Q-02/T13: herdr でも mutation UI が有効化される。
      // 未接続バナーは表示されない（H6 の opt-in は廃止）。
      expect(find.byType(SpecialKeysBar), findsOneWidget);
      expect(find.text('Not connected — viewing only'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
      'special key tap routes accepted keys via PaneKeyMap to send-keys '
      '(Q-07 ①)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // ESC（受理キー）→ `herdr pane send-keys w1:p1 Escape`
        await tester.tap(find.text('ESC'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          client.execCommands.any(
            (c) => c == 'herdr pane send-keys w1:p1 Escape',
          ),
          isTrue,
          reason: '受理キー（ESC）は PaneKeyMap 経由で send-keys に送られること',
        );

        // キーオーバーレイの 1500ms タイマーを消化してクリーンに終了。
        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets(
      'special key tap routes rejected keys via PaneKeyMap to send-text '
      'escape (Q-07 ②)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // PgUp（拒否キー）→ `herdr pane send-text w1:p1` + `\x1b[5~`
        await tester.tap(find.text('PgUp'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          client.execCommands.any(
            (c) =>
                c.startsWith('herdr pane send-text w1:p1') &&
                c.contains(r'\x1b[5~'),
          ),
          isTrue,
          reason: '拒否キー（PgUp）は send-text でエスケープシーケンスが送られること',
        );

        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets(
      'special key tap routes control characters via PaneKeyMap to send-text '
      '(Q-07 ③)',
      (tester) async {
        final client = await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
          },
          settle: false,
        );

        // C-d（制御文字）→ `herdr pane send-text w1:p1` + 0x04
        // （`sendSpecialKeyForTesting` は SpecialKeysBar のタップが最終的に
        // 到達する `_sendSpecialKeyWithOverlay` → `_sendSpecialKey` と同じ経路）。
        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.sendSpecialKeyForTesting('C-d');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          client.execCommands.any(
            (c) =>
                c.startsWith('herdr pane send-text w1:p1') &&
                c.contains(r'\x04'),
          ),
          isTrue,
          reason: '制御文字（C-d）は send-text で制御文字そのものが送られること',
        );

        await tester.pump(const Duration(milliseconds: 1500));
      },
    );

    testWidgets(
      'defensive invalid_key notification is shown when send-keys rejects a key',
      (tester) async {
        await TerminalTestScaffold.pumpTerminalScreen(
          tester,
          connection: herdrConnection(),
          sessionName: 'lab-ws1',
          // send-keys が未知キー名を `invalid_key` で拒否する（防御的経路・R9）。
          execOutputs: {
            'herdr api snapshot': kHerdrSnapshotFixture,
            'herdr pane read': 'hello\n',
            'herdr pane send-keys w1:p1 UnknownKey123':
                '{"error":{"code":"invalid_key","message":"unsupported key"}}',
          },
          execExitCodes: {'herdr pane send-keys w1:p1 UnknownKey123': 1},
          settle: false,
        );

        final dynamic state = tester.state(find.byType(TerminalScreen));
        state.sendSpecialKeyForTesting('UnknownKey123');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.text('This key could not be sent via herdr'),
          findsOneWidget,
          reason: 'invalid_key は防御的に SnackBar 通知されること',
        );

        // SnackBar の自動クローズ（4s）まで進めて pending timer を消化する。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 750));
      },
    );
  });
}
