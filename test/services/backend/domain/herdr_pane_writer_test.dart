import 'package:flutter_muxpod/services/backend/backend_adapter.dart';
import 'package:flutter_muxpod/services/backend/domain/herdr_pane_writer.dart';
import 'package:flutter_muxpod/services/backend/domain/pane_writer.dart';
import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

// T7/T13/T14/T15: HerdrPaneWriter の単体テスト。
// - Phase 2（T13）で capability がフリップされ、mutation が解禁される。
//   `copyMode` / `absoluteResize` は設計上 false（herdr に copy-mode は無い・
//   resize は相対分数のみ Q-04）。`imageTransfer` は T15 で true にフリップ
//   （SFTP は provider 側・パス注入は pasteText = send-text）。
// - sendKey は PaneKeyMap の送信経路（Q-07）で 3 経路へ分岐する:
//   ①受理キー → send-keys / ②拒否キー → send-text + エスケープ /
//   ③制御文字 → send-text + 制御文字。
// - mutation メソッドは HerdrAdapter（_execMutation）へ委譲する。
// - resizePane は `changed:false`（分割境界外）を PaneOperationNoopException
//   （soft 失敗・情報通知）で通知する（T14・S4）。
// - focusPaneDirection は `changed:false` + `reason:"no_neighbor"`（隣接なし）を
//   PaneOperationNoopException で通知する（T20a・S4 の no_neighbor 補完）。

void main() {
  late _FakeBackend backend;
  late HerdrPaneWriter writer;

  setUp(() {
    backend = _FakeBackend();
    writer = HerdrPaneWriter(HerdrAdapter(backend));
  });

  group('HerdrPaneWriter', () {
    test('capabilities: Phase 2 で mutation 解禁（Q-02/Q-07・T13/T15）', () {
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
      expect(caps.workspaceCrud, isTrue);
      expect(caps.tabCrud, isTrue);
      // 画像転送は T15 で解禁（SFTP は provider・パス注入は pasteText）。
      expect(caps.imageTransfer, isTrue);
      // 設計上 false（herdr に copy-mode は無い・resize は相対のみ）。
      expect(caps.copyMode, isFalse);
      expect(caps.absoluteResize, isFalse);
    });

    test('mapSpecialKey: PaneKeyMap の全キー送信経路を返す（Q-07）', () {
      expect(writer.mapSpecialKey('Enter'), isA<HerdrKeyRouteSendKeys>());
      expect(writer.mapSpecialKey('F5'), isA<HerdrKeyRouteSendKeys>());
      expect(
        writer.mapSpecialKey('Home'),
        isA<HerdrKeyRouteSendTextEscape>(),
      );
      expect(
        writer.mapSpecialKey('C-d'),
        isA<HerdrKeyRouteSendTextControl>(),
      );
    });

    test('sendText: send-text コマンドへ委譲する', () async {
      await writer.sendText('w1:p1', 'hello');
      expect(backend.commands.single, 'herdr pane send-text w1:p1 \'hello\'');
    });

    test('sendKey: 受理キーは send-keys で送信する', () async {
      await writer.sendKey('w1:p1', 'Enter');
      expect(backend.commands.single, 'herdr pane send-keys w1:p1 Enter');
    });

    test('sendKey: 拒否キーは send-text でエスケープシーケンスを送信する', () async {
      await writer.sendKey('w1:p1', 'Home');
      expect(backend.commands.single, contains('herdr pane send-text w1:p1'));
      expect(backend.commands.single, contains('\x1b[H'));
    });

    test('sendKey: 制御文字は send-text で制御文字そのものを送信する', () async {
      await writer.sendKey('w1:p1', 'C-d');
      expect(backend.commands.single, contains('herdr pane send-text w1:p1'));
      expect(backend.commands.single.codeUnits, contains(0x04));
    });

    test('focusPaneDirection: pane focus へ委譲する', () async {
      await writer.focusPaneDirection('w1:p1', 'right');
      expect(
        backend.commands.single,
        'herdr pane focus --direction right --pane w1:p1',
      );
    });

    test(
      'focusPaneDirection: changed:false（no_neighbor・隣接なし）は '
      'PaneOperationNoopException（S4/T20）',
      () async {
        // T0 実測 5-b: focus の soft 失敗（changed:false + reason:no_neighbor）。
        backend.execWithExitCodeResult = (
          stdout:
              '{"id":"cli:pane:focus","result":{"focus":{'
              '"changed":false,"focused_pane_id":"w1:p1",'
              '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
              '"focused_pane_id":"w1:p1","panes":[],"splits":[],'
              '"tab_id":"w1:t1","workspace_id":"w1","zoomed":false},'
              '"reason":"no_neighbor","source_pane_id":"w1:p1"},'
              '"type":"pane_focus_direction"}}',
          stderr: '',
          exitCode: 0,
        );
        await expectLater(
          writer.focusPaneDirection('w1:p1', 'right'),
          throwsA(
            isA<PaneOperationNoopException>()
                .having((e) => e.operation, 'operation', 'focusPaneDirection')
                .having((e) => e.reason, 'reason', 'no_neighbor'),
          ),
        );
      },
    );

    test('focusPaneDirection: changed:true（layout 応答）は例外なし', () async {
      // T0 実測 5-b の成功系（reason なし・layout 込み）→ soft 失敗にならない。
      backend.execWithExitCodeResult = (
        stdout:
            '{"id":"cli:pane:focus","result":{"focus":{'
            '"changed":true,"focused_pane_id":"w1:p2",'
            '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
            '"focused_pane_id":"w1:p2","panes":[],"splits":[],'
            '"tab_id":"w1:t1","workspace_id":"w1","zoomed":false},'
            '"reason":null,"source_pane_id":"w1:p1"},'
            '"type":"pane_focus_direction"}}',
        stderr: '',
        exitCode: 0,
      );
      await writer.focusPaneDirection('w1:p1', 'right');
      // 例外なし（throw されない）・コマンドは 1 回発行される。
      expect(
        backend.commands.single,
        'herdr pane focus --direction right --pane w1:p1',
      );
    });

    test('splitPane: pane split へ委譲する（ratio/cwd 付き）', () async {
      await writer.splitPane('w1:p1', 'right', ratio: 0.5, cwd: '/tmp');
      expect(
        backend.commands.single,
        'herdr pane split w1:p1 --direction right --ratio 0.5 --cwd \'/tmp\'',
      );
    });

    test('closePane: pane close へ委譲する（破壊的 close の唯一経路・Q-03）', () async {
      await writer.closePane('w1:p1');
      expect(backend.commands.single, 'herdr pane close w1:p1');
    });

    test('renamePane: pane rename へ委譲する', () async {
      await writer.renamePane('w1:p1', 'new label');
      expect(
        backend.commands.single,
        'herdr pane rename w1:p1 \'new label\'',
      );
    });

    test('zoomPane: pane zoom へ委譲する（mode 付き）', () async {
      await writer.zoomPane('w1:p1', mode: 'toggle');
      expect(backend.commands.single, 'herdr pane zoom --pane w1:p1 --toggle');
    });

    test('resizePane: pane resize へ委譲する（相対分数・Q-04）', () async {
      await writer.resizePane('w1:p1', 'right', 0.1);
      expect(
        backend.commands.single,
        'herdr pane resize --direction right --amount 0.1 --pane w1:p1',
      );
    });

    test('resizePane: changed:false（分割境界外）は PaneOperationNoopException', () async {
      // 応答 layout なし・changed:false（T0 実測 4-b の分割境界外）を返す。
      backend.execWithExitCodeResult = (
        stdout:
            '{"result":{"resize":{"changed":false,"reason":"unchanged",'
            '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
            '"focused_pane_id":"w1:p1","panes":[],"splits":[],'
            '"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}},'
            '"type":"pane_resize"}}',
        stderr: '',
        exitCode: 0,
      );
      await expectLater(
        writer.resizePane('w1:p1', 'right', 0.1),
        throwsA(
          isA<PaneOperationNoopException>()
              .having((e) => e.operation, 'operation', 'resizePane')
              .having((e) => e.reason, 'reason', 'unchanged'),
        ),
      );
    });

    test('pasteText: send-text で複数行を貼り付ける（Q-06）', () async {
      await writer.pasteText('w1:p1', 'a\nb');
      expect(
        backend.commands.single,
        contains("herdr pane send-text w1:p1 'a"),
      );
    });

    test('createTab: tab create へ委譲する（Q-05）', () async {
      await writer.createTab('w1');
      expect(backend.commands.single, 'herdr tab create --workspace w1');
    });

    test('closeTab: tab close へ委譲する（Q-05）', () async {
      await writer.closeTab('w1:t1');
      expect(backend.commands.single, 'herdr tab close w1:t1');
    });

    test('renameTab: tab rename へ委譲する（Q-05）', () async {
      await writer.renameTab('w1:t1', 'my tab');
      expect(backend.commands.single, "herdr tab rename w1:t1 'my tab'");
    });

    test('focusTab: tab focus へ委譲する（Q-05）', () async {
      await writer.focusTab('w1:t1');
      expect(backend.commands.single, 'herdr tab focus w1:t1');
    });

    test('createWorkspace: workspace create へ委譲する（Q-05）', () async {
      await writer.createWorkspace('api');
      expect(backend.commands.single, "herdr workspace create --label 'api'");
    });

    test('closeWorkspace: workspace close へ委譲する（Q-05）', () async {
      await writer.closeWorkspace('w1');
      expect(backend.commands.single, 'herdr workspace close w1');
    });

    test('renameWorkspace: workspace rename へ委譲する（Q-05）', () async {
      await writer.renameWorkspace('w1', 'my ws');
      expect(backend.commands.single, "herdr workspace rename w1 'my ws'");
    });

    test('focusWorkspace: workspace focus へ委譲する（Q-05）', () async {
      await writer.focusWorkspace('w1');
      expect(backend.commands.single, 'herdr workspace focus w1');
    });

    test('未対応の操作は UnsupportedPaneOperationException を投げる', () {
      // 未対応メソッドは同期的に throw する（呼び出し側は try/catch で捕捉）。
      // selectPane: herdr に `pane focus --pane <target>` 直接アクティブ化
      // コマンドが無いため未対応（OQ1・方向 focus + edges 反復で代替）。
      expect(
        () => writer.selectPane('w1:p1'),
        throwsA(
          isA<UnsupportedPaneOperationException>()
              .having((e) => e.backend, 'backend', 'herdr')
              .having((e) => e.operation, 'operation', 'selectPane'),
        ),
      );
      // imageTransfer: T15 で capability は true だが、interface メソッドは
      // paneId を持たないため直接は呼ばれない（実経路は _injectImagePath →
      // pasteText = send-text）。型付き例外で明示する。
      expect(
        () => writer.imageTransfer('/tmp/a.png'),
        throwsA(
          isA<UnsupportedPaneOperationException>()
              .having((e) => e.operation, 'operation', 'imageTransfer'),
        ),
      );
    });
  });
}

/// 記録用の fake [BackendAdapter]。`_execMutation` は rc=0 / stdout 空で成功する。
class _FakeBackend implements BackendAdapter {
  final List<String> commands = [];

  /// この値が null 以外なら `execWithExitCode` がこの結果を返す
  /// （`changed:false` 応答のテスト用）。
  ({String stdout, String stderr, int? exitCode})? execWithExitCodeResult;

  @override
  bool get isConnected => true;

  @override
  String? get userExecutablePath => null;

  @override
  BackendInputTransport? get inputTransport => null;

  @override
  void Function()? get onInputTransportRebooted => null;

  @override
  set onInputTransportRebooted(void Function()? value) {}

  @override
  Future<void> restartInputTransport() async {}

  @override
  Future<String> exec(String command, {Duration? timeout}) async {
    commands.add(command);
    return '';
  }

  @override
  Future<String> execPersistent(String command, {Duration? timeout}) async {
    commands.add(command);
    return '';
  }

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    commands.add(command);
    return execWithExitCodeResult ?? (stdout: '', stderr: '', exitCode: 0);
  }

  @override
  void write(String data) {}
}
