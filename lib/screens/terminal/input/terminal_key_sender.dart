import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/settings_provider.dart' show settingsProvider;
import '../../../services/backend/domain/wheel_encoder.dart'
    show ScrollSendKind;
import '../../../services/herdr/herdr_commands.dart' show HerdrCommandException;
import '../../../services/herdr/herdr_errors.dart' show isHerdrInvalidKey;
import '../../../services/ssh/input_queue.dart' show InputQueue;
import '../../../services/terminal/tmux_key_display.dart'
    show KeyOverlayCategory, TmuxKeyDisplay;
import '../../../widgets/key_overlay_widget.dart' show KeyOverlayState;
import '../widgets/ansi_terminal_model.dart' show KeyInputEvent;
import 'terminal_input_ports.dart'
    show TerminalInputCapabilities, TerminalInputHost, TerminalPaneSendPort;

/// キー / 特殊キー / paste / 入力キュー / copy-mode コマンド の単一所有者
/// （TERM-INPUT-001〜011・C2）。
///
/// [InputQueue] と [KeyOverlayState]・オーバーレイ 1500ms タイマーを所有し、
/// HEAD の `_sendKeyData` / `_sendKey` / `_sendSpecialKey` の例外挙動差
/// （sendKeyData は完全静黙・sendKey/sendSpecialKey は `invalid_key` のみ通知）を
/// 厳守する。
class TerminalKeySender {
  TerminalKeySender({
    required this.ref,
    required this.send,
    required this.caps,
    required this.host,
    required bool Function() copyModeDetected,
  }) : _copyModeDetected = copyModeDetected;

  final WidgetRef ref;
  final TerminalPaneSendPort send;
  final TerminalInputCapabilities caps;
  final TerminalInputHost host;
  final bool Function() _copyModeDetected;

  // 入力キュー（切断中の入力を保持）。
  final InputQueue _inputQueue = InputQueue();

  /// 滞留数（HEAD `_inputQueue.length`・root の `queuedCount` 表示用）。
  int get queuedLength => _inputQueue.length;

  /// 送信キューを破棄（HEAD `_inputQueue.clear()`・root の ClearQueue 導線）。
  void clearQueue() => _inputQueue.clear();

  // キーオーバーレイ。
  final KeyOverlayState _keyOverlayState = KeyOverlayState();
  Timer? _keyOverlayTimer;

  /// オーバーレイ表示状態（root がシェルへ渡す・HEAD `_keyOverlayState`
  /// 相当。1 インスタンスを入力側と表示側で共有する）。
  KeyOverlayState get keyOverlayState => _keyOverlayState;

  // --- 送信入口（SpecialKeysBar / AnsiTextView 配線） ---

  /// 特殊キー送信 + オーバーレイ表示（TERM-INPUT-004/007）。
  void sendSpecialKeyWithOverlay(String tmuxKey) {
    // ignore: unawaited_futures
    sendSpecialKey(tmuxKey);
    showKeyOverlay(tmuxKey);
  }

  /// リテラルキー送信 + ショートカットキーのオーバーレイ表示（TERM-INPUT-003）。
  void sendKeyWithOverlay(String key) {
    // ignore: unawaited_futures
    sendKey(key);
    if (TmuxKeyDisplay.isShortcutKey(key)) {
      showKeyOverlay(key);
    }
  }

  /// オーバーレイ表示ロジック（HEAD `_showKeyOverlay` と同一）。
  void showKeyOverlay(String key) {
    final settings = ref.read(settingsProvider);
    if (!settings.showKeyOverlay) return;

    final category = TmuxKeyDisplay.categoryOf(key);
    if (category == null) return;

    final enabled = switch (category) {
      KeyOverlayCategory.modifier => settings.keyOverlayModifier,
      KeyOverlayCategory.special => settings.keyOverlaySpecial,
      KeyOverlayCategory.arrow => settings.keyOverlayArrow,
      KeyOverlayCategory.shortcut => settings.keyOverlayShortcut,
    };
    if (!enabled) return;

    _keyOverlayState.show(TmuxKeyDisplay.displayText(key));
    _keyOverlayTimer?.cancel();
    _keyOverlayTimer = Timer(const Duration(milliseconds: 1500), () {
      _keyOverlayState.hide();
    });
  }

  // --- AnsiTextView からのキー入力 ---

  /// 通常モードのキー入力（HEAD `_handleKeyInput` と同一）。
  void handleKeyInput(KeyInputEvent event) {
    // テキスト送信不可時はキー入力を無効化。
    if (!caps.canSendText) return;
    // 特殊キーの場合は tmux 形式で送信（オーバーレイ付き）。
    if (event.isSpecialKey && event.tmuxKeyName != null) {
      sendSpecialKeyWithOverlay(event.tmuxKeyName!);
    } else {
      // 通常の文字はリテラル送信。
      // ignore: unawaited_futures
      sendKeyData(event.data);
    }
  }

  // inventory: TERM-INPUT-011
  /// scrollSend 専用キーハンドラ（オーバーレイなし・キューなし・D2）。
  void handleScrollSendKeyInput(KeyInputEvent event) {
    // D2: copy-mode 検出中は送信即ドロップ（R1 対策）。
    if (_copyModeDetected()) return;
    // 未接続時は即ドロップ（キューしない・R6）。
    if (!send.isConnected) return;

    if (event.isSpecialKey && event.tmuxKeyName == 'PPage') {
      // ignore: unawaited_futures
      sendScrollKey(up: true);
    } else if (event.isSpecialKey && event.tmuxKeyName == 'NPage') {
      // ignore: unawaited_futures
      sendScrollKey(up: false);
    } else {
      // 文字キー・その他の特殊キーは sendText 能力ゲート（(b)・literal 依存）。
      if (!caps.canSendText) return;
      // ignore: unawaited_futures
      sendScrollText(event.data);
    }
  }

  /// scrollSend 中の PgUp/PgDn 送信（`sendScroll(kind: key)`・C8）。
  Future<void> sendScrollKey({required bool up}) async {
    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    if (writer == null || paneId == null) return;
    try {
      await writer.sendScroll(
        paneId,
        kind: ScrollSendKind.key,
        up: up,
        ticks: 1,
      );
      send.boostPolling();
    } on HerdrCommandException catch (e) {
      send.recordHerdrSwitchEvent(
        'scrollSend key send error (${e.runtimeType})',
      );
    } catch (e) {
      send.recordHerdrSwitchEvent(
        'scrollSend key send error (${e.runtimeType})',
      );
    }
  }

  /// scrollSend 中の文字キー送信（`writer.sendText`・キューなし・C8）。
  Future<void> sendScrollText(String data) async {
    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    if (writer == null || paneId == null) return;
    try {
      await writer.sendText(paneId, data);
      send.boostPolling();
    } on HerdrCommandException catch (e) {
      send.recordHerdrSwitchEvent(
        'scrollSend text send error (${e.runtimeType})',
      );
    } catch (e) {
      send.recordHerdrSwitchEvent(
        'scrollSend text send error (${e.runtimeType})',
      );
    }
  }

  // --- 送信本体 ---

  /// キーデータを PaneWriter 経由で送信（tmux: send-keys -l / herdr: send-text）。
  ///
  /// **例外は完全静黙**（`_sendKey` と違い `invalid_key` 通知なし）。
  Future<void> sendKeyData(String data) async {
    // テキスト送信不可時は送信しない。
    if (!caps.canSendText) return;

    // 接続が切れている場合はキューに追加。
    if (!send.isConnected) {
      final wasOverflow = _inputQueue.isOverflow;
      _inputQueue.enqueue(data);
      if (!wasOverflow && _inputQueue.isOverflow && host.isMounted) {
        host.notifyInputQueueFull();
      }
      if (host.isMounted) host.markNeedsBuild(); // キューイング状態を更新
      return;
    }

    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    if (writer == null || paneId == null) return;

    try {
      await writer.sendText(paneId, data);
      send.boostPolling();
    } catch (_) {
      // キー送信エラーは静かに無視。
    }
  }

  /// キーを PaneWriter 経由で送信（リテラル / 特殊キー両対応・Q-07)。
  Future<void> sendKey(String key, {bool literal = true}) async {
    // テキスト送信不可時は送信しない。非リテラル（特殊キー）は sendKeys 能力で
    // 判定する。
    if (literal ? !caps.canSendText : !caps.canSendSpecialKey) return;

    // 接続が切れている場合はキューに追加（リテラルの場合のみ）。
    if (!send.isConnected) {
      if (literal) {
        final wasOverflow = _inputQueue.isOverflow;
        _inputQueue.enqueue(key);
        if (!wasOverflow && _inputQueue.isOverflow && host.isMounted) {
          host.notifyInputQueueFull();
        }
        if (host.isMounted) host.markNeedsBuild(); // キューイング状態を更新
      }
      return;
    }

    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    if (writer == null || paneId == null) return;

    try {
      if (literal) {
        await writer.sendText(paneId, key);
      } else {
        await writer.sendKey(paneId, key);
      }
      send.boostPolling();
    } on HerdrCommandException catch (e) {
      // 防御的（Q-07 の全キー送信経路により通常は発生しない・R9）:
      // `invalid_key` のみ分類通知し、それ以外は従来どおり静かに無視する。
      if (isHerdrInvalidKey(e)) {
        host.notifyHerdrInvalidKey();
      }
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）。
    }
  }

  /// tmux 特殊キーを PaneWriter 経由で送信（Ctrl+C, Escape 等・T8）。
  Future<void> sendSpecialKey(String tmuxKey) async {
    // 特殊キー送信不可時は送信しない。
    if (!caps.canSendSpecialKey) return;

    // 特殊キーは接続が切れている場合は送信しない（キューしない）。
    if (!send.isConnected) return;

    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    if (writer == null || paneId == null) return;

    try {
      // PaneWriter 経由（tmux: send-keys / herdr: PaneKeyMap の送信経路）。
      await writer.sendKey(paneId, tmuxKey);
      send.boostPolling();
    } on HerdrCommandException catch (e) {
      if (isHerdrInvalidKey(e)) {
        host.notifyHerdrInvalidKey();
      }
    } catch (_) {
      // キー送信エラーは静かに無視（ポーリングで状態は更新される）。
    }
  }

  /// 複数行テキストを送信（tmux: load-buffer + paste-buffer / herdr: send-text）。
  Future<void> sendMultilineText(String text) async {
    if (text.isEmpty) return;

    // paste 不可時は送信しない。
    if (!caps.canPaste) return;

    final writer = send.paneWriter;
    final paneId = send.currentPaneId;
    if (writer == null || paneId == null) return;

    final payload = text;

    if (!send.isConnected) {
      // Multi-line paste via send-keys would re-introduce the race condition
      // fixed by PR #51. Reject the operation and ask the user to retry once
      // connected rather than silently queuing via the legacy path.
      if (text.contains('\n') && host.isMounted) {
        host.notifyMultilineNeedsConnection();
      } else {
        _inputQueue.enqueue(text);
        if (host.isMounted) host.markNeedsBuild();
      }
      return;
    }

    try {
      await writer.pasteText(paneId, payload);
      send.boostPolling();
    } catch (e) {
      debugPrint('[Terminal] paste-buffer send failed: $e');
      // TODO: surface a SnackBar after repeated failures.
    }
  }

  /// キューされた入力を送信（C2・session `_onReconnectSuccess` から呼ばれる）。
  Future<void> flushInputQueue() async {
    if (_inputQueue.isEmpty) return;

    final queuedInput = _inputQueue.flush();
    if (queuedInput.isNotEmpty) {
      // inventory: TERM-INPUT-002
      await sendKeyData(queuedInput);
    }
  }

  // --- tmux copy-mode ---

  /// tmux copy-mode に入る（TERM-COPY-001）。
  Future<void> enterTmuxCopyMode() async {
    if (!caps.canCopyMode) return;
    if (!send.isConnected) return;
    final target = send.currentTmuxTarget;
    if (target == null) return;
    try {
      await send.enterCopyMode(target);
    } catch (_) {}
  }

  /// tmux copy-mode を終了する（TERM-COPY-002）。
  Future<void> cancelTmuxCopyMode() async {
    if (!caps.canCopyMode) return;
    if (!send.isConnected) return;
    final target = send.currentTmuxTarget;
    if (target == null) return;
    try {
      await send.exitCopyMode(target);
    } catch (_) {}
  }

  /// テストフック: 特殊キー送信（root が転送）。
  void sendSpecialKeyForTesting(String tmuxKey) {
    // ignore: unawaited_futures
    sendSpecialKey(tmuxKey);
  }

  /// P5: オーバーレイ 1500ms タイマーと [KeyOverlayState] を破棄する。
  void dispose() {
    _keyOverlayTimer?.cancel();
    _keyOverlayTimer = null;
    _keyOverlayState.dispose();
  }
}
