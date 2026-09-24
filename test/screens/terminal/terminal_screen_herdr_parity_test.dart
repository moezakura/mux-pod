// P4 回帰テスト（パリティ・herdr 切替）: `switchHerdrTarget` 時に view の
// content/caret が即時クリアされること（NG-1/NG-2 相当）を固定する。
//
// HEAD の `_switchHerdrTarget`（L4108-4120）は
// ① `viewNotifier.copyWith(content: '', caret: null)` ② `hasInitialScrolled = false`
// ③ `resetTerminalMode()` を 3 段で実行する。リファクタ後、`resetView`（= ①②）と
// `resetTerminalMode`（= ③）が herdr コントローラの `_switchTarget` から呼ばれる。
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/providers/connection.dart';
import 'package:flutter_muxpod/screens/terminal/terminal_screen.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import 'package:flutter_muxpod/services/backend/backend_type.dart';
import 'package:flutter_muxpod/services/backend/multiplexer_config.dart';

import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_layout_fixtures.dart'
    show kHerdrTwoPaneLayoutSnapshotFixture;

Connection _herdrConnection() {
  return Connection(
    id: 'test-conn',
    name: 'Herdr Server',
    host: 'testhost',
    port: 22,
    username: 'user',
    multiplexer: const MultiplexerConfig(backend: BackendType.herdr),
    createdAt: DateTime(2025, 1, 1),
  );
}

void main() {
  group('P4 parity: herdr 切替で view が即時クリアされる（NG-1）', () {
    testWidgets('switchHerdrTargetForTesting 直後に旧 pane の content が消える', (
      tester,
    ) async {
      final client = await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: _herdrConnection(),
        sessionName: 'lab-ws1',
        initialPaneId: 'w1:p1',
        execOutputs: {
          'herdr api snapshot': kHerdrTwoPaneLayoutSnapshotFixture,
          'herdr pane read': 'content from pane\n',
        },
        settle: false,
      );

      // 初期表示: w1:p1 の内容が表示されている
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      AnsiTextView ansi() =>
          tester.widget<AnsiTextView>(find.byType(AnsiTextView));
      expect(ansi().text, contains('content from pane'));

      // 切替 → 直後の 1 フレームで view がクリアされる（旧 content が残らない）
      final dynamic state = tester.state(find.byType(TerminalScreen));
      state.switchHerdrTargetForTesting('w1:p2');
      await tester.pump();
      expect(
        ansi().text,
        isEmpty,
        reason: '切替直後に旧 pane の content が残らない（HEAD は即クリア）',
      );

      // caret クリア（MuxPod カーソル span が出ない）ことも間接的に担保:
      // 新しいターゲット（w1:p2）へのポーリングが開始される
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        client.execCommands.any((c) => c.contains('herdr pane read w1:p2')),
        isTrue,
        reason: '切替後に新しい pane ID がポーリング対象になる',
      );
    });
  });
}
