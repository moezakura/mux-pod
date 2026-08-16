import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/command/command_result.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_facade.dart';

/// pollPane 出力パースの回帰テスト（Issue #70 データ層の根本対応）。
///
/// 従来の「最後の改行で逆から切る」パースは、capture-pane 出力の最終行が空行の
/// ときにその改行が「カーソル行との区切り」として消費され、最終空行がドロップ
/// していた（キャレットが1行上にズレる原因）。マーカー区切りでは空行が保持される。
class _FakeExecutor implements TmuxCommandExecutor {
  _FakeExecutor(this.output);

  final String output;

  @override
  Future<CommandResult> execute(CommandRequest request) async =>
      CommandResult(
        mergedOutput: output,
        outputSeparation: CommandOutputSeparation.merged,
        actualTransport: CommandTransport.persistent,
      );

  @override
  bool get isConnected => true;

  @override
  String? get tmuxPath => '/usr/bin/tmux';

  @override
  Future<void> sendKeysCommand(String command) async {}

  @override
  Future<void> setWindowRestoreTrap(List<String> windowTargets) async {}

  @override
  Future<void> restoreWindowsNoWait(List<String> targets) async {}

  @override
  void write(String data) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// PersistentShell 通過後（先頭/末尾の改行1つずつ除去後）のバイト列を模倣し、
  /// マーカー区切りの pollPane 出力を構築する。
  String framed(String capture, String cursorLine, String modeLine) {
    final sep = tmuxPollSeparator('deadbeef12345678');
    return '$sep\n$capture$sep$cursorLine\n$sep$modeLine\n$sep';
  }

  group('pollPane (marker-separated output)', () {
    test('preserves trailing empty line of capture (Issue #70)', () async {
      // Claude Code 等の TUI: UI行 + 下部の空行（最終行が空行）＋履歴
      final rows = [
        ...List.generate(41, (i) => 'hist-$i'),
        ...List.generate(20, (i) => 'ui-row-$i'),
        ...List.generate(19, (i) => ''),
      ];
      final capture = '${rows.join('\n')}\n';
      final snap = await TmuxFacade().pollPane(
        _FakeExecutor(framed(capture, '2,17,44,39', '')),
        target: '%0',
      );

      expect(snap.cursorX, 2);
      expect(snap.cursorY, 17);
      expect(snap.paneWidth, 44);
      expect(snap.paneHeight, 39);
      expect(snap.paneMode, '');
      // 41(履歴) + 39(ペイン行) = 80 行。末尾の空行が失われてはならない。
      final lines = snap.content.rawText.split('\n');
      expect(lines.length, 80);
      // アプリのキャレット行計算: 80 - 39 + 17 = 58 (0-based) = ui-row-17
      expect(lines[80 - 39 + 17], 'ui-row-17');
    });

    test('preserves capture first line when empty', () async {
      final capture = '\nB\n\n';
      final snap = await TmuxFacade().pollPane(
        _FakeExecutor(framed(capture, '0,1,10,3', '')),
        target: '%0',
      );
      expect(snap.content.rawText.split('\n'), ['', 'B', '']);
    });

    test('parses copy-mode pane mode', () async {
      final capture = 'a\nb\n';
      final snap = await TmuxFacade().pollPane(
        _FakeExecutor(framed(capture, '3,0,10,2', 'copy-mode')),
        target: '%0',
      );
      expect(snap.paneMode, 'copy-mode');
      expect(snap.content.rawText.split('\n'), ['a', 'b']);
    });

    test('cursor line with trailing content is split exactly', () async {
      final capture = 'x\n';
      final snap = await TmuxFacade().pollPane(
        _FakeExecutor(framed(capture, '10,0,80,1', '')),
        target: '%0',
      );
      expect(snap.cursorX, 10);
      expect(snap.content.rawText, 'x');
    });
  });

  group('pollPane (legacy unframed output fallback)', () {
    test('parses legacy fixtures without markers', () async {
      final snap = await TmuxFacade().pollPane(
        _FakeExecutor('hello\n7,8,90,30\n'),
        target: '%0',
      );
      expect(snap.content.rawText, 'hello');
      expect(snap.cursorX, 7);
      expect(snap.cursorY, 8);
      expect(snap.paneHeight, 30);
    });
  });
}
