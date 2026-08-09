import 'package:flutter_muxpod/services/backend/domain/pane_writer.dart';
import 'package:flutter_muxpod/services/backend/domain/tmux_pane_writer.dart';
import 'package:flutter_muxpod/services/tmux/tmux_command_builder.dart'
    show SplitDirection;
import 'package:flutter_muxpod/services/tmux/tmux_command_executor.dart';
import 'package:flutter_muxpod/services/tmux/tmux_contract.dart';
import 'package:flutter_test/flutter_test.dart';

// T6: TmuxPaneWriter の単体テスト。
// - 既存 tmuxFacade（TmuxContract）呼び出しへの委譲（後方互換・コマンド文字列
//   不変の前提）を、記録用 fake で検証する。
// - 未配線の interface メソッド（Phase 2 で導入）は UnsupportedPaneOperationException。

void main() {
  group('TmuxPaneWriter', () {
    test('capabilities: tmux は全操作能力を持つ', () {
      final writer = TmuxPaneWriter(_FakeTmuxContract(), _FakeExecutor());
      final caps = writer.capabilities;
      expect(caps.sendText, isTrue);
      expect(caps.sendKeys, isTrue);
      expect(caps.focus, isTrue);
      expect(caps.split, isTrue);
      expect(caps.close, isTrue);
      expect(caps.rename, isTrue);
      expect(caps.zoom, isTrue);
      expect(caps.resize, isTrue);
      expect(caps.paste, isTrue);
      expect(caps.copyMode, isTrue);
      expect(caps.imageTransfer, isTrue);
      expect(caps.workspaceCrud, isTrue);
      expect(caps.tabCrud, isTrue);
      expect(caps.absoluteResize, isTrue);
    });

    test('mapSpecialKey: tmux は同一キー名の send-keys 経路を返す', () {
      final writer = TmuxPaneWriter(_FakeTmuxContract(), _FakeExecutor());
      final route = writer.mapSpecialKey('Home');
      expect(route, isA<HerdrKeyRouteSendKeys>());
      expect((route as HerdrKeyRouteSendKeys).keyName, 'Home');
    });

    test('sendText: send-keys をリテラルで委譲する（従来の _sendKeyData 相当）', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.sendText('%0', 'hello');

      expect(facade.sendKeysNoWaitCalls, hasLength(1));
      final call = facade.sendKeysNoWaitCalls.single;
      expect(call.$1, '%0');
      expect(call.$2, 'hello');
      expect(call.$3, isTrue, reason: 'テキストはリテラル送信（-l）');
    });

    test('sendKey: send-keys を非リテラルで委譲する（従来の _sendSpecialKey 相当）',
        () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.sendKey('%0', 'Escape');

      final call = facade.sendKeysNoWaitCalls.single;
      expect(call.$2, 'Escape');
      expect(call.$3, isFalse, reason: '特殊キーは非リテラル送信');
    });

    test('selectPane: facade.selectPane へ委譲する（従来の _selectPane 相当）', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.selectPane('%1');

      expect(facade.selectPaneIds, ['%1']);
    });

    test('splitPane: right → 水平 / down → 垂直へ方向を変換して委譲する', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());

      await writer.splitPane('%0', 'right');
      await writer.splitPane('%0', 'down', ratio: 0.5, cwd: '/tmp');

      expect(facade.splitCalls, hasLength(2));
      expect(facade.splitCalls[0].$2, SplitDirection.horizontal);
      expect(facade.splitCalls[0].$3, isNull, reason: 'ratio 未指定なら -p なし');
      expect(facade.splitCalls[1].$2, SplitDirection.vertical);
      expect(facade.splitCalls[1].$3, 50, reason: 'ratio 0.5 → -p 50');
      expect(facade.splitCalls[1].$4, '/tmp');
    });

    test('closePane: killPane へ委譲する（従来の _killPane 相当）', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.closePane('%0');

      expect(facade.killPaneIds, ['%0']);
    });

    test('pasteText: pasteText へ委譲する（従来の _sendMultilineText 相当）', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.pasteText('%0', 'a\nb');

      expect(facade.pasteCalls.single.$1, '%0');
      expect(facade.pasteCalls.single.$2, 'a\nb');
    });

    test('resizePaneAbsolute: tmux 固有の絶対値 resize を委譲する', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.resizePaneAbsolute('%0', cols: 120, rows: 40);

      final call = facade.resizePaneCalls.single;
      expect(call.$1, '%0');
      expect(call.$2, 120);
      expect(call.$3, 40);
    });

    test('sendBracketedPaste: tmux 固有の bracketed paste を委譲する', () async {
      final facade = _FakeTmuxContract();
      final writer = TmuxPaneWriter(facade, _FakeExecutor());
      await writer.sendBracketedPaste(
        paneId: '%0',
        path: '/tmp/a.png',
        bracketedPaste: true,
        autoEnter: true,
      );

      final call = facade.bracketedPasteCalls.single;
      expect(call.$1, '%0');
      expect(call.$2, '/tmp/a.png');
      expect(call.$3, isTrue);
      expect(call.$4, isTrue);
    });

    test('未配線の操作は UnsupportedPaneOperationException を投げる', () {
      final writer = TmuxPaneWriter(_FakeTmuxContract(), _FakeExecutor());
      // 未配線メソッドは同期的に throw する（`_Phase0PaneWriter` と同じ失敗
      // ポリシー。呼び出し側は try/catch で捕捉する）。
      expect(
        () => writer.focusPaneDirection('%0', 'right'),
        throwsA(
          isA<UnsupportedPaneOperationException>()
              .having((e) => e.backend, 'backend', 'tmux')
              .having((e) => e.operation, 'operation', 'focusPaneDirection'),
        ),
      );
      expect(
        () => writer.zoomPane('%0'),
        throwsA(isA<UnsupportedPaneOperationException>()),
      );
      expect(
        () => writer.resizePane('%0', 'right', 0.1),
        throwsA(isA<UnsupportedPaneOperationException>()),
      );
      expect(
        () => writer.imageTransfer('/tmp/a.png'),
        throwsA(isA<UnsupportedPaneOperationException>()),
      );
    });
  });
}

/// 記録用の fake [TmuxContract]。観測対象メソッドのみ明示 override し、残りは
/// `noSuchMethod` で吸収する（`_Phase0PaneWriter` と同じ noSuchMethod パターン）。
class _FakeTmuxContract implements TmuxContract {
  final List<(String, String, bool)> sendKeysNoWaitCalls = [];
  final List<String> selectPaneIds = [];
  final List<(String, SplitDirection, int?, String?)> splitCalls = [];
  final List<String> killPaneIds = [];
  final List<(String, String)> pasteCalls = [];
  final List<(String, int?, int?)> resizePaneCalls = [];
  final List<(String, String, bool, bool)> bracketedPasteCalls = [];

  @override
  Future<void> sendKeysNoWait(
    TmuxCommandExecutor executor,
    String target,
    String keys, {
    bool literal = false,
  }) async {
    sendKeysNoWaitCalls.add((target, keys, literal));
  }

  @override
  Future<void> selectPane(
    TmuxCommandExecutor executor,
    String paneId, {
    String? previousPaneId,
  }) async {
    selectPaneIds.add(paneId);
  }

  @override
  Future<void> splitPane(
    TmuxCommandExecutor executor, {
    required String target,
    required SplitDirection direction,
    String? startDirectory,
    int? percentage,
  }) async {
    splitCalls.add((target, direction, percentage, startDirectory));
  }

  @override
  Future<void> killPane(TmuxCommandExecutor executor, String paneId) async {
    killPaneIds.add(paneId);
  }

  @override
  Future<void> pasteText(
    TmuxCommandExecutor executor, {
    required String target,
    required String text,
    bool execute = true,
  }) async {
    pasteCalls.add((target, text));
  }

  @override
  Future<void> resizePane(
    TmuxCommandExecutor executor,
    String paneId, {
    int? cols,
    int? rows,
  }) async {
    resizePaneCalls.add((paneId, cols, rows));
  }

  @override
  Future<void> sendBracketedPaste(
    TmuxCommandExecutor executor, {
    required String paneId,
    required String path,
    bool autoEnter = false,
    bool bracketedPaste = true,
  }) async {
    bracketedPasteCalls.add((paneId, path, autoEnter, bracketedPaste));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeExecutor implements TmuxCommandExecutor {
  @override
  bool get isConnected => true;

  @override
  String? get tmuxPath => 'tmux';

  @override
  Future<String> exec(String command, {Duration? timeout}) async => '';

  @override
  Future<String> execPersistent(String command, {Duration? timeout}) async =>
      '';

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async => (stdout: '', stderr: '', exitCode: 0);

  @override
  Future<void> sendKeysCommand(String command) async {}

  @override
  Future<void> setWindowRestoreTrap(List<String> windowTargets) async {}

  @override
  Future<void> restoreWindowsNoWait(List<String> targets) async {}

  @override
  void write(String data) {}
}
