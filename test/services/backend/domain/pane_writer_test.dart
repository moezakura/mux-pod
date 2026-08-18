import 'package:flutter_muxpod/services/backend/domain/pane_writer.dart';
import 'package:flutter_muxpod/services/backend/domain/wheel_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HerdrKeyRoute', () {
    test('sendKeys creates a send-keys route with the key name', () {
      final route = HerdrKeyRoute.sendKeys('F5');
      expect(route, isA<HerdrKeyRouteSendKeys>());
      final sendKeys = route as HerdrKeyRouteSendKeys;
      expect(sendKeys.keyName, 'F5');
    });

    test('sendTextEscape creates a send-text escape route with the bytes', () {
      final route = HerdrKeyRoute.sendTextEscape('\x1b[H');
      expect(route, isA<HerdrKeyRouteSendTextEscape>());
      final escape = route as HerdrKeyRouteSendTextEscape;
      expect(escape.bytes, '\x1b[H');
    });

    test('sendTextControl creates a send-text control route with the byte', () {
      final route = HerdrKeyRoute.sendTextControl(0x04);
      expect(route, isA<HerdrKeyRouteSendTextControl>());
      final control = route as HerdrKeyRouteSendTextControl;
      expect(control.byte, 0x04);
    });

    test('routes are const-constructible value types', () {
      const a = HerdrKeyRoute.sendKeys('Enter');
      const b = HerdrKeyRoute.sendKeys('Enter');
      expect(a, isA<HerdrKeyRouteSendKeys>());
      expect(b, isA<HerdrKeyRouteSendKeys>());
    });
  });

  group('PaneCapabilities', () {
    test('defaults to all capabilities disabled (read-only equivalent)', () {
      const caps = PaneCapabilities();
      expect(caps.sendText, isFalse);
      expect(caps.sendKeys, isFalse);
      expect(caps.focus, isFalse);
      expect(caps.split, isFalse);
      expect(caps.close, isFalse);
      expect(caps.rename, isFalse);
      expect(caps.zoom, isFalse);
      expect(caps.resize, isFalse);
      expect(caps.paste, isFalse);
      expect(caps.copyMode, isFalse);
      expect(caps.imageTransfer, isFalse);
      expect(caps.workspaceCrud, isFalse);
      expect(caps.tabCrud, isFalse);
      expect(caps.absoluteResize, isFalse);
      // スクロール送信の wheel は Phase 0 実証（D11）まで false（15 項目目）。
      expect(caps.wheelSend, isFalse);
    });

    test('can enable individual capabilities', () {
      const caps = PaneCapabilities(
        sendText: true,
        focus: true,
        absoluteResize: true,
        wheelSend: true,
      );
      expect(caps.sendText, isTrue);
      expect(caps.focus, isTrue);
      expect(caps.absoluteResize, isTrue);
      expect(caps.wheelSend, isTrue);
      expect(caps.split, isFalse);
      expect(caps.resize, isFalse);
    });

    test('herdr-style capabilities disable absoluteResize (Q-04)', () {
      // herdr は相対分数のみ。絶対値 resize は false のまま。
      const herdr = PaneCapabilities(
        sendText: true,
        sendKeys: true,
        resize: true,
        absoluteResize: false,
      );
      expect(herdr.resize, isTrue);
      expect(herdr.absoluteResize, isFalse);
    });
  });

  group('UnsupportedPaneOperationException', () {
    test('carries operation and backend names', () {
      const e = UnsupportedPaneOperationException(
        operation: 'absoluteResize',
        backend: 'herdr',
        message: 'herdr は相対分数のみ対応です',
      );
      expect(e.operation, 'absoluteResize');
      expect(e.backend, 'herdr');
      expect(e.message, contains('相対分数'));
      expect(e.toString(), contains('herdr'));
      expect(e.toString(), contains('absoluteResize'));
    });
  });

  group('PaneWriter contract', () {
    test('a fake writer implements the full interface surface', () async {
      final writer = _FakePaneWriter();
      expect(writer.capabilities.sendText, isTrue);
      expect(writer.mapSpecialKey('Enter'), isA<HerdrKeyRouteSendKeys>());

      await writer.sendText('w1:p1', 'hello');
      await writer.sendKey('w1:p1', 'Enter');
      await writer.selectPane('w1:p1');
      await writer.focusPaneDirection('w1:p1', 'right');
      await writer.splitPane('w1:p1', 'right');
      await writer.closePane('w1:p1');
      await writer.renamePane('w1:p1', 'new');
      await writer.zoomPane('w1:p1');
      await writer.resizePane('w1:p1', 'right', 0.1);
      await writer.createTab('w1');
      await writer.closeTab('w1:t2');
      await writer.renameTab('w1:t2', 'tab');
      await writer.focusTab('w1:t2');
      await writer.createWorkspace('ws');
      await writer.closeWorkspace('w2');
      await writer.renameWorkspace('w2', 'ws2');
      await writer.focusWorkspace('w2');
      await writer.pasteText('w1:p1', 'line1\nline2');
      await writer.imageTransfer('/tmp/a.png');
      await writer.sendScroll(
        'w1:p1',
        kind: ScrollSendKind.wheel,
        up: true,
        ticks: 1,
      );

      expect(writer.calls, hasLength(20));
    });
  });
}

/// [PaneWriter] の契約を検証するための fake 実装。
class _FakePaneWriter implements PaneWriter {
  final List<String> calls = [];

  @override
  PaneCapabilities get capabilities => const PaneCapabilities(
    sendText: true,
    sendKeys: true,
    focus: true,
    split: true,
    close: true,
    rename: true,
    zoom: true,
    resize: true,
    paste: true,
    imageTransfer: true,
    workspaceCrud: true,
    tabCrud: true,
  );

  @override
  HerdrKeyRoute mapSpecialKey(String tmuxKey) =>
      HerdrKeyRoute.sendKeys(tmuxKey);

  @override
  Future<void> sendText(String paneId, String text) async {
    calls.add('sendText');
  }

  @override
  Future<void> sendKey(String paneId, String tmuxKey) async {
    calls.add('sendKey');
  }

  @override
  Future<void> selectPane(String paneId) async {
    calls.add('selectPane');
  }

  @override
  Future<void> focusPaneDirection(String paneId, String direction) async {
    calls.add('focusPaneDirection');
  }

  @override
  Future<void> splitPane(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
  }) async {
    calls.add('splitPane');
  }

  @override
  Future<void> closePane(String paneId) async {
    calls.add('closePane');
  }

  @override
  Future<void> renamePane(String paneId, String label) async {
    calls.add('renamePane');
  }

  @override
  Future<void> zoomPane(String paneId, {String mode = 'toggle'}) async {
    calls.add('zoomPane');
  }

  @override
  Future<void> resizePane(
    String paneId,
    String direction,
    double amount,
  ) async {
    calls.add('resizePane');
  }

  @override
  Future<void> createTab(
    String workspaceId, {
    String? label,
    bool? focus,
  }) async {
    calls.add('createTab');
  }

  @override
  Future<void> closeTab(String tabId) async {
    calls.add('closeTab');
  }

  @override
  Future<void> renameTab(String tabId, String label) async {
    calls.add('renameTab');
  }

  @override
  Future<void> focusTab(String tabId) async {
    calls.add('focusTab');
  }

  @override
  Future<void> createWorkspace(String label) async {
    calls.add('createWorkspace');
  }

  @override
  Future<void> closeWorkspace(String workspaceId) async {
    calls.add('closeWorkspace');
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String label) async {
    calls.add('renameWorkspace');
  }

  @override
  Future<void> focusWorkspace(String workspaceId) async {
    calls.add('focusWorkspace');
  }

  @override
  Future<void> pasteText(String paneId, String text) async {
    calls.add('pasteText');
  }

  @override
  Future<void> sendScroll(
    String paneId, {
    required ScrollSendKind kind,
    required bool up,
    required int ticks,
  }) async {
    calls.add('sendScroll');
  }

  @override
  Future<void> imageTransfer(String path) async {
    calls.add('imageTransfer');
  }
}
