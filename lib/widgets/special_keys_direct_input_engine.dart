import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'special_keys_modifier_state.dart';
import 'special_keys_tmux_composer.dart';

/// 特殊キーバーのコールバック値オブジェクト。
///
/// コールバック関数のみを保持する（状態を含めない。状態はエンジンが唯一所有）。
/// cjkMode / keepKeyboardOnEnter は状態フラグのためここには置かず、
/// エンジンの [SpecialKeysDirectInputEngine.setCjkMode] /
/// [SpecialKeysDirectInputEngine.setKeepKeyboardOnEnter] が保持する。
class SpecialKeysBarCallbacks {
  const SpecialKeysBarCallbacks({
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    required this.hapticFeedback,
  });

  /// リテラルキー送信（通常の文字）
  final void Function(String key) onKeyPressed;

  /// 特殊キー送信（tmux形式: Enter, Escape, C-c等）
  final void Function(String tmuxKey) onSpecialKeyPressed;

  /// ハプティックフィードバック（ライブ参照: setCallbacks で毎回更新される）
  final bool hapticFeedback;
}

/// DirectInput/IME の状態機械。
///
/// TextEditingController・FocusNode・sentinel・delta送信・composing追跡・
/// 二重入力抑制・外付けキーボードイベント処理の唯一の所有者。
/// 状態フラグ（cjkMode / keepKeyboardOnEnter）も唯一所有し、
/// 実行時伝播用 setter（[setCallbacks] / [setCjkMode] / [setKeepKeyboardOnEnter]）
/// を持つ。合成ルート State の didUpdateWidget で毎回（無条件）最新値を
/// 伝播すること（送信時のライブ参照の意味論を維持）。
class SpecialKeysDirectInputEngine {
  SpecialKeysDirectInputEngine({
    required SpecialKeysModifierState modifiers,
    required SpecialKeysBarCallbacks callbacks,
    required bool Function() isActive,
  }) : _modifiers = modifiers,
       _callbacks = callbacks,
       _isActive = isActive;

  final SpecialKeysModifierState _modifiers;
  final SpecialKeysTmuxComposer _composer = const SpecialKeysTmuxComposer();
  SpecialKeysBarCallbacks _callbacks;
  final bool Function() _isActive;

  /// dispose 後の postFrame 実行を遮断する二重ガード（isActive と併用）
  bool _disposed = false;

  final TextEditingController _directInputController = TextEditingController();
  final FocusNode _directInputFocusNode = FocusNode();

  /// DirectInput: 端末へ送信済みの可視テキスト（デルタ送信用）
  /// 入力欄にテキストを残したまま追加分のみ送信するために保持する
  String _sentText = '';

  /// 現在IME変換中かどうか
  bool _isComposing = false;

  /// IME composing中の最新テキスト（iOS重複検出用）
  /// iOSが自動確定時にcomposingテキストより長い確定テキストを返す場合、
  /// composingテキストを正とし余分な重複を除去する
  String? _lastComposingText;

  /// DirectInputモードでBackspace検出のためのsentinel文字（ゼロ幅スペース）
  /// iOS/iPadOSではTextField空の状態でBackspace押下時にKeyDownEventが
  /// 生成されないため、常にsentinelを保持して削除検出でBackspaceを検知する
  static const String _sentinel = '\u200B';

  /// sentinel リセット中の再入防止フラグ
  bool _isResettingController = false;

  /// 二重入力防止: _handleKeyEventで処理した最終時刻
  /// iPad外付けキーボードではFlutter KeyEventとiOSテキスト入力が
  /// 同一キーを二重に処理するため、タイムスタンプで抑制する
  DateTime? _lastKeyEventHandledAt;

  /// CJK Mode: IME確定ごとに全文送信して入力欄をクリアする。
  /// 実行時伝播: didUpdateWidget 経由の [setCjkMode] で毎回更新される。
  bool _cjkMode = false;

  /// DirectInput: Enter送信後もソフトウェアキーボードを開いたままにするか。
  /// 実行時伝播: didUpdateWidget 経由の [setKeepKeyboardOnEnter] で毎回更新される。
  bool _keepKeyboardOnEnter = false;

  TextEditingController get controller => _directInputController;
  FocusNode get focusNode => _directInputFocusNode;

  /// 実行時 prop 伝播の正式経路。didUpdateWidget で毎回（無条件）呼び、
  /// 最新の widget 値を反映する（初期値固定・初回のみ注入は禁止）。
  void setCallbacks(SpecialKeysBarCallbacks callbacks) =>
      _callbacks = callbacks;

  void setCjkMode(bool value) => _cjkMode = value;

  void setKeepKeyboardOnEnter(bool value) => _keepKeyboardOnEnter = value;

  /// initState 相当: sentinel 値を設定してから listener を張る
  /// （現行 initState の順序を維持）。
  void attach({required bool directInputEnabled}) {
    if (directInputEnabled) {
      _directInputController.value = TextEditingValue(
        text: _sentinel,
        selection: TextSelection.collapsed(offset: _sentinel.length),
      );
    }
    _directInputController.addListener(handleTextChanged);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _directInputController.removeListener(handleTextChanged);
    _directInputController.dispose();
    _directInputFocusNode.dispose();
  }

  /// DirectInput: テキスト変更時の処理
  /// sentinelアプローチでBackspaceを検出（iOS/iPadOS対応）
  void handleTextChanged() {
    if (_isResettingController) return;

    final text = _directInputController.text;
    final value = _directInputController.value;

    // composingが空でない = IME変換中
    _isComposing = value.composing.isValid && !value.composing.isCollapsed;

    if (_isComposing) {
      // Record composing text for iOS duplicate detection
      _lastComposingText = text.replaceAll(_sentinel, '');

      // Samsung IME composing workaround:
      // Samsung (and some Android IMEs) treat English letters as composing,
      // so composing=false may NEVER arrive while the user keeps typing.
      // When a modifier (CTRL/ALT) is active, intercept the first composing
      // character immediately instead of waiting for composing to end.
      // Guards:
      //   - length == 1: only the first composing char (avoids accumulated repeats)
      //   - ASCII letter regex: don't intercept Korean (ㅊ) or other non-ASCII composing
      if ((_modifiers.ctrl || _modifiers.alt) &&
          _lastComposingText!.length == 1) {
        final char = _lastComposingText!;
        if (RegExp(r'^[A-Za-z]$').hasMatch(char)) {
          if (_callbacks.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
          // 修飾子を消費（C→M順）してからtmux形式で合成して送信
          final ctrl = _modifiers.consumeCtrl();
          final alt = _modifiers.consumeAlt();
          _callbacks.onSpecialKeyPressed(
            _composer.composeSpecial(
              char.toLowerCase(),
              shift: false,
              ctrl: ctrl,
              alt: alt,
            ),
          );
          _lastComposingText = null;
          resetToSentinel();
          return;
        }
      }

      return;
    }

    // Sentinelが削除された = 全テキスト削除（iOS/iPadOS対応のBackspace検出）
    if (text.isEmpty) {
      _lastComposingText = null;
      _sendDirectBackspace();
      resetToSentinel();
      return;
    }

    // Sentinelを除去して実際の入力テキストを取得
    final actualText = text.replaceAll(_sentinel, '');

    // CJK Mode（v0.7.0-pre4挙動）: 確定テキストを全文送信してからsentinelへ
    // リセットする。入力欄にテキストを残さないためiOSの自動補正（".."→"‥"
    // 等）が働かず、IME確定時の重複挿入もcomposingテキストとの比較で除去される。
    if (_cjkMode) {
      if (actualText.isEmpty) return;

      // 外付けキーボードの二重入力防止: _handleKeyEventで処理済みならスキップ
      if (_isRecentKeyEventHandled()) {
        _lastComposingText = null;
        resetToSentinel();
        return;
      }

      // iOS重複検出: 確定テキストがcomposingテキストより長く、
      // composingテキストで始まる場合、iOSの重複挿入とみなしcomposingテキストを使用
      String textToSend = actualText;
      if (_lastComposingText != null &&
          actualText.length > _lastComposingText!.length &&
          actualText.startsWith(_lastComposingText!)) {
        textToSend = _lastComposingText!;
      }
      _lastComposingText = null;

      // Send modifier+key when CTRL/ALT is active (non-composing path)
      // This handles IMEs that commit without composing (e.g. Gboard English)
      // tmux format: C-c (Ctrl+C), M-a (Alt+A), C-M-x (Ctrl+Alt+X)
      if ((_modifiers.ctrl || _modifiers.alt) &&
          textToSend.length == 1 &&
          RegExp(r'^[A-Za-z]$').hasMatch(textToSend)) {
        if (_callbacks.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        final ctrl = _modifiers.consumeCtrl();
        final alt = _modifiers.consumeAlt();
        _callbacks.onSpecialKeyPressed(
          _composer.composeSpecial(
            textToSend.toLowerCase(),
            shift: false,
            ctrl: ctrl,
            alt: alt,
          ),
        );
      } else {
        _callbacks.onKeyPressed(textToSend);
      }

      // 送信後にsentinelにリセット
      resetToSentinel();
      return;
    }

    // 外付けキーボードの二重入力防止: _handleKeyEventで処理済みならスキップ
    if (_isRecentKeyEventHandled()) {
      _lastComposingText = null;
      // キーイベント側で送信済みなので、欄のテキストは残したまま送信済みとして記録
      _sentText = actualText;
      return;
    }

    // 変化なし（IMEノイズ）なら何もしない
    if (actualText == _sentText) return;
    _lastComposingText = null;

    // デルタ送信: 送信済みテキストとの共通接頭辞を除いた差分のみを送信する。
    // 入力欄にテキストを残して可視化しつつ、追加分は逐次送信、
    // 削除分はBSpaceを送信する。
    var common = 0;
    final minLen = _sentText.length < actualText.length
        ? _sentText.length
        : actualText.length;
    while (common < minLen && _sentText[common] == actualText[common]) {
      common++;
    }
    final removed = _sentText.length - common;
    final appended = actualText.substring(common);

    if (removed > 0) {
      for (var r = 0; r < removed; r++) {
        _sendDirectBackspace();
      }
    }

    if (appended.isNotEmpty) {
      // Send modifier+key when CTRL/ALT is active (non-composing path)
      // This handles IMEs that commit without composing (e.g. Gboard English)
      // tmux format: C-c (Ctrl+C), M-a (Alt+A), C-M-x (Ctrl+Alt+X)
      if ((_modifiers.ctrl || _modifiers.alt) &&
          appended.length == 1 &&
          RegExp(r'^[A-Za-z]$').hasMatch(appended)) {
        if (_callbacks.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        final ctrl = _modifiers.consumeCtrl();
        final alt = _modifiers.consumeAlt();
        _callbacks.onSpecialKeyPressed(
          _composer.composeSpecial(
            appended.toLowerCase(),
            shift: false,
            ctrl: ctrl,
            alt: alt,
          ),
        );

        // 修飾キーとして消費した文字を入力欄から除去し、可視テキストと整合させる
        final kept = actualText.substring(0, common);
        _isResettingController = true;
        _directInputController.value = TextEditingValue(
          text: _sentinel + kept,
          selection: TextSelection.collapsed(offset: kept.length + 1),
        );
        _isResettingController = false;
        _sentText = kept;
        return;
      }

      _callbacks.onKeyPressed(appended);
    }

    _sentText = actualText;
  }

  /// DirectInput: ソフトウェアキーボードのEnter（送信）で呼ばれる
  void handleSubmitted(String value) {
    // 外付けキーボードの二重入力防止: _handleKeyEventで処理済みならスキップ
    if (_isRecentKeyEventHandled()) return;

    if (_callbacks.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    _callbacks.onSpecialKeyPressed('Enter');
    resetToSentinel();

    // 「Enterでキーボードを閉じない」設定:
    // unfocus() はマイクロタスク適用（focus_manager._markNextFocus）のため、
    // onSubmitted 内の同期 requestFocus() で実質キャンセルでき、フィールドは
    // フォーカスを一切失わない。フレームワークはこのパターンを明示サポート
    // （editable_text.dart L3899-3906: onSubmitted内でフォーカスを戻した場合は
    // _restartConnectionIfNeeded が接続を張り直してキーボードを開いたままリセット）。
    // ここでは keepKeyboardOnEnter は実行時伝播された最新値（setter反映値）を参照する。
    if (_keepKeyboardOnEnter) {
      _directInputFocusNode.requestFocus();
    }
  }

  /// DirectInput: Backspaceキー送信
  void _sendDirectBackspace() {
    if (_callbacks.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    _callbacks.onSpecialKeyPressed('BSpace');
  }

  /// DirectInput: sentinelにリセット（Backspace検出用）
  ///
  /// _isResettingControllerの解除を次フレームまで遅延することで、
  /// iOSプラットフォームがIME確定時に送る遅延テキスト更新を吸収する。
  /// PostFrameCallbackでcontrollerが上書きされていれば再度sentinelにリセットする。
  void resetToSentinel() {
    _sentText = '';
    _isResettingController = true;
    _directInputController.value = TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: _sentinel.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 合成ルートの mounted 置換（isActive）と dispose 後の遮断（_disposed）の
      // 二重ガード（設計書 v2 §7 リスク3）。
      if (!_isActive() || _disposed) return;
      final currentValue = _directInputController.value;
      final hasActiveComposing =
          currentValue.composing.isValid && !currentValue.composing.isCollapsed;
      // composing進行中ならiOSの入力を尊重して再リセットしない
      if (!hasActiveComposing && _directInputController.text != _sentinel) {
        _directInputController.value = TextEditingValue(
          text: _sentinel,
          selection: TextSelection.collapsed(offset: _sentinel.length),
        );
      }
      _isResettingController = false;
    });
  }

  /// 無効化パス: DirectInput無効化時に入力欄をクリアする
  /// （同期発火ガードの順序を保持: ガード→clear→解除→delta状態破棄）。
  void clearForDeactivation() {
    _isResettingController = true;
    _directInputController.clear();
    _isResettingController = false;
    _sentText = '';
  }

  /// 二重入力防止: _handleKeyEventで処理したことをマーク
  void _markKeyEventHandled() {
    _lastKeyEventHandledAt = DateTime.now();
  }

  /// 二重入力防止: 直近100ms以内に_handleKeyEventで処理されたか
  bool _isRecentKeyEventHandled() {
    if (_lastKeyEventHandledAt == null) return false;
    return DateTime.now().difference(_lastKeyEventHandledAt!) <
        const Duration(milliseconds: 100);
  }

  /// 外付けキーボード用の特殊キー送信（デバウンス付き）
  void _sendHwSpecialKey(String baseKey) {
    _markKeyEventHandled();
    if (_callbacks.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    _callbacks.onSpecialKeyPressed(_composer.applyHardwareModifiers(baseKey));
    // 外付けキーボード使用時はソフトウェア修飾子トグルをリセット
    _modifiers.clearAll();
  }

  /// キーイベントハンドラ（外付けキーボード用: 全特殊キーをキャプチャ）
  KeyEventResult handleHardwareKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // IME変換中はキーイベントを処理しない
    if (_isComposing) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Ctrl + A-Z のショートカット処理（Cmd/Meta は Ctrl として扱わない）
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    if (isCtrlPressed) {
      final keyLabel = key.keyLabel;
      if (keyLabel.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(keyLabel)) {
        _markKeyEventHandled();
        if (_callbacks.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        _callbacks.onSpecialKeyPressed('C-${keyLabel.toLowerCase()}');
        _modifiers.clearAll();
        return KeyEventResult.handled;
      }
    }

    // Cmd/Meta + A-Z は M- として送信（ユーザー要望: Meta/Super として伝える）
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    if (isMetaPressed) {
      final keyLabel = key.keyLabel;
      if (keyLabel.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(keyLabel)) {
        _markKeyEventHandled();
        if (_callbacks.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        _callbacks.onSpecialKeyPressed('M-${keyLabel.toLowerCase()}');
        _modifiers.clearAll();
        return KeyEventResult.handled;
      }
    }

    // Enterキー
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _markKeyEventHandled();
      _sendDirectEnterAndClear();
      _modifiers.clearAll();
      return KeyEventResult.handled;
    }

    // Backspaceキー: sentinelアプローチで_onDirectInputChangedにて処理
    if (key == LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }

    // マップに登録された特殊キー（Escape/Tab/矢印/Nav/F1-F12）
    final tmuxKey = SpecialKeysTmuxComposer.hwSpecialKeyMap[key];
    if (tmuxKey != null) {
      _sendHwSpecialKey(tmuxKey);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// DirectInput: Enterキー送信して入力欄をリセット
  void _sendDirectEnterAndClear() {
    if (_callbacks.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    _callbacks.onSpecialKeyPressed('Enter');
    resetToSentinel();
  }
}
