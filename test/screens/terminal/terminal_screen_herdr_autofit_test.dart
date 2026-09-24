import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_text_view.dart';
import '../../helpers/terminal_test_scaffold.dart';
import 'helpers/herdr_snapshot_fixtures.dart';
import 'helpers/herdr_test_helpers.dart';

void main() {
  group('TerminalScreen herdr AutoFit (bug1)', () {
    testWidgets('layout の pane rect から paneWidth が解決され AutoFit に反映される', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrLargeLayoutSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      // ポーリングで snapshot cache の layout rect（120x24）が解決され、
      // _viewNotifier の paneWidth / paneHeight が更新される。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      final terminal = tester.widget<AnsiTextView>(find.byType(AnsiTextView));
      expect(
        terminal.paneWidth,
        120,
        reason: 'herdr の snapshot layout rect から paneWidth が解決されること',
      );
      expect(
        terminal.paneHeight,
        24,
        reason: 'herdr の snapshot layout rect から paneHeight が解決されること',
      );
    });

    testWidgets('zoom 中は pane rect でなく layout.area（タブ全面）の幅で AutoFit が計算される', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotZoomedFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      final terminal = tester.widget<AnsiTextView>(find.byType(AnsiTextView));
      // pane rect は非 zoom 値（width 40）だが、表示はタブ全面（area 120）。
      expect(
        terminal.paneWidth,
        120,
        reason: 'zoom 中は pane rect でなく layout.area の幅が使われること',
      );
    });

    testWidgets('layout が無い（rect 取得不能）場合は既定 80 のまま（spec.md:75 フォールバック）', (
      tester,
    ) async {
      await TerminalTestScaffold.pumpTerminalScreen(
        tester,
        connection: herdrConnection(),
        sessionName: 'lab-ws1',
        execOutputs: {
          'herdr api snapshot': kHerdrSnapshotFixture,
          'herdr pane read': 'content\n',
        },
        settle: false,
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      final terminal = tester.widget<AnsiTextView>(find.byType(AnsiTextView));
      // _viewNotifier の既定値は paneWidth 80（_TerminalViewData 既定）。
      expect(
        terminal.paneWidth,
        80,
        reason: 'rect 取得不能時は既定 80 幅で AutoFit が計算される',
      );
    });
  });
}
