import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ansi_key_composer.dart';
import 'ansi_terminal_model.dart';

/// キーイベント処理の状態機械（P3-2）。
///
/// 修飾キー 4 状態（Ctrl / Alt / Shift / Meta）の唯一の所有者。
/// KeyDown/KeyRepeat でキー入力を加工し、KeyUp で修飾キーを解除する。
/// 特殊キーの分岐（Esc/Enter/Tab/矢印/F1-F12 …）と Consume 順（Shift→Ctrl→Alt）
/// は従来の `AnsiTextViewState._handleKeyEvent` と同一。
///
/// 実行時プロパティ（[onKeyInput] コールバック）はキャッシュせず、
/// [handleKeyEvent] の毎呼び出し引数で与える（ライブ参照・P2 critique §1.1）。
class AnsiKeyInputEngine {
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;
  bool _metaPressed = false;

  bool get ctrlPressed => _ctrlPressed;
  bool get altPressed => _altPressed;
  bool get shiftPressed => _shiftPressed;

  /// Ctrl トグル（外部制御用）
  void toggleCtrl() {
    _ctrlPressed = !_ctrlPressed;
  }

  /// Alt トグル（外部制御用）
  void toggleAlt() {
    _altPressed = !_altPressed;
  }

  /// Shift トグル（外部制御用）
  void toggleShift() {
    _shiftPressed = !_shiftPressed;
  }

  /// 修飾キー（Ctrl/Alt/Shift）をリセット（Meta は遷移専用のため対象外・従来どおり）
  void resetModifiers() {
    _ctrlPressed = false;
    _altPressed = false;
    _shiftPressed = false;
  }

  /// キーイベントをハンドリング。
  ///
  /// [node] は Focus の onKeyEvent シグネチャ互換のための引数（未使用）。
  /// [onKeyInput] が null の間は何も送らず ignored を返す（従来どおり）。
  KeyEventResult handleKeyEvent(
    FocusNode node,
    KeyEvent event, {
    required void Function(KeyInputEvent)? onKeyInput,
  }) {
    if (onKeyInput == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;

      // 修飾キーの状態を更新
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _ctrlPressed = true;
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        _altPressed = true;
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        _shiftPressed = true;
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        _metaPressed = true;
        return KeyEventResult.handled;
      }

      // 特殊キーの処理
      String? data;
      bool isSpecialKey = false;
      String? tmuxKeyName;

      if (key == LogicalKeyboardKey.escape) {
        data = '\x1b';
        isSpecialKey = true;
        tmuxKeyName = 'Escape';
      } else if (key == LogicalKeyboardKey.enter) {
        // Shift+Enterの場合は別のキー名で送信
        if (_shiftPressed) {
          data = '\x1b[27;2;13~'; // xterm拡張: Shift+Enter
          isSpecialKey = true;
          tmuxKeyName = 'S-Enter';
          _shiftPressed = false;
        } else {
          data = '\r';
          isSpecialKey = true;
          tmuxKeyName = 'Enter';
        }
      } else if (key == LogicalKeyboardKey.backspace) {
        data = '\x7f';
        isSpecialKey = true;
        tmuxKeyName = 'BSpace';
      } else if (key == LogicalKeyboardKey.delete) {
        data = _paramSequence(3, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('DC');
      } else if (key == LogicalKeyboardKey.tab) {
        if (_shiftPressed) {
          data = '\x1b[Z';
          tmuxKeyName = 'BTab';
          _shiftPressed = false;
        } else {
          data = '\t';
          tmuxKeyName = 'Tab';
        }
        isSpecialKey = true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        data = _arrowSequence('A');
        isSpecialKey = true;
        tmuxKeyName = _arrowTmuxKey('Up');
      } else if (key == LogicalKeyboardKey.arrowDown) {
        data = _arrowSequence('B');
        isSpecialKey = true;
        tmuxKeyName = _arrowTmuxKey('Down');
      } else if (key == LogicalKeyboardKey.arrowRight) {
        data = _arrowSequence('C');
        isSpecialKey = true;
        tmuxKeyName = _arrowTmuxKey('Right');
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        data = _arrowSequence('D');
        isSpecialKey = true;
        tmuxKeyName = _arrowTmuxKey('Left');
      } else if (key == LogicalKeyboardKey.home) {
        data = _finalCharSequence('H');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('Home');
      } else if (key == LogicalKeyboardKey.end) {
        data = _finalCharSequence('F');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('End');
      } else if (key == LogicalKeyboardKey.pageUp) {
        data = _paramSequence(5, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('PPage');
      } else if (key == LogicalKeyboardKey.pageDown) {
        data = _paramSequence(6, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('NPage');
      } else if (key == LogicalKeyboardKey.f1) {
        data = _fKeySequence('P');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F1');
      } else if (key == LogicalKeyboardKey.f2) {
        data = _fKeySequence('Q');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F2');
      } else if (key == LogicalKeyboardKey.f3) {
        data = _fKeySequence('R');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F3');
      } else if (key == LogicalKeyboardKey.f4) {
        data = _fKeySequence('S');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F4');
      } else if (key == LogicalKeyboardKey.f5) {
        data = _paramSequence(15, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F5');
      } else if (key == LogicalKeyboardKey.f6) {
        data = _paramSequence(17, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F6');
      } else if (key == LogicalKeyboardKey.f7) {
        data = _paramSequence(18, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F7');
      } else if (key == LogicalKeyboardKey.f8) {
        data = _paramSequence(19, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F8');
      } else if (key == LogicalKeyboardKey.f9) {
        data = _paramSequence(20, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F9');
      } else if (key == LogicalKeyboardKey.f10) {
        data = _paramSequence(21, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F10');
      } else if (key == LogicalKeyboardKey.f11) {
        data = _paramSequence(23, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F11');
      } else if (key == LogicalKeyboardKey.f12) {
        data = _paramSequence(24, '~');
        isSpecialKey = true;
        tmuxKeyName = _modifiedTmuxKey('F12');
      } else if (event.character != null && event.character!.isNotEmpty) {
        // 通常文字
        data = event.character!;

        // Alt/Meta(Cmd)押下時: OS が合成した非 ASCII 文字
        // (例: iPadOS の Option+O → 'ø' U+00F8) をそのまま使うと ESC+ø (1b c3 b8)
        // になりリモートの Meta キー(ESC+o)として解釈されない (Issue #116)。
        // logicalKey から ASCII 文字を導出する。ASCII 文字の場合は従来どおり
        // character を使用（Linux/Windows/通常キーは挙動不変）。
        if ((_altPressed || _metaPressed) &&
            !AnsiKeyComposer.isAsciiPrintable(data)) {
          final derived = AnsiKeyComposer.deriveBaseChar(
            event.logicalKey.keyLabel,
            shiftPressed: _shiftPressed,
          );
          if (derived != null) {
            data = derived;
          }
        }

        // Ctrl+文字の処理
        if (_ctrlPressed && data.length == 1) {
          final code = data.codeUnitAt(0);
          if ((code >= 0x61 && code <= 0x7a) ||
              (code >= 0x41 && code <= 0x5a)) {
            data = String.fromCharCode(code & 0x1f);
          }
        }

        // Alt+文字の処理
        if (_altPressed) {
          data = '\x1b$data';
        }

        // Meta(Cmd)+文字の処理（xterm の ESC 前置・ユーザー要望）
        if (_metaPressed) {
          data = '\x1b$data';
        }
      }

      if (data != null) {
        onKeyInput(
          KeyInputEvent(
            data: data,
            isSpecialKey: isSpecialKey,
            tmuxKeyName: tmuxKeyName,
          ),
        );
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      final key = event.logicalKey;

      // 修飾キーの解除
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _ctrlPressed = false;
      } else if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        _altPressed = false;
      } else if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        _shiftPressed = false;
      } else if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        _metaPressed = false;
      }
    }

    return KeyEventResult.ignored;
  }

  // === シーケンス合成（AnsiKeyComposer への委譲ヘルパ） ===

  String _arrowSequence(String code) {
    return AnsiKeyComposer.arrowSequence(
      code,
      shiftPressed: _shiftPressed,
      ctrlPressed: _ctrlPressed,
      altPressed: _altPressed,
    );
  }

  String _arrowTmuxKey(String direction) {
    return AnsiKeyComposer.arrowTmuxKey(
      direction,
      shiftPressed: _shiftPressed,
      ctrlPressed: _ctrlPressed,
      altPressed: _altPressed,
    );
  }

  /// 修飾子付き tmux キー名を取得（汎用）し、使った修飾子フラグを消費する。
  String _modifiedTmuxKey(String baseKey) {
    final result = AnsiKeyComposer.modifiedTmuxKey(
      baseKey,
      shiftPressed: _shiftPressed,
      ctrlPressed: _ctrlPressed,
      altPressed: _altPressed,
    );
    switch (result.modifierUsed) {
      case 'shift':
        _shiftPressed = false;
      case 'ctrl':
        _ctrlPressed = false;
      case 'alt':
        _altPressed = false;
    }
    return result.name;
  }

  String _finalCharSequence(String finalChar) {
    return AnsiKeyComposer.finalCharSequence(
      finalChar,
      shiftPressed: _shiftPressed,
      ctrlPressed: _ctrlPressed,
      altPressed: _altPressed,
    );
  }

  String _paramSequence(int param, String suffix) {
    return AnsiKeyComposer.paramSequence(
      param,
      suffix,
      shiftPressed: _shiftPressed,
      ctrlPressed: _ctrlPressed,
      altPressed: _altPressed,
    );
  }

  String _fKeySequence(String code) {
    return AnsiKeyComposer.fKeySequence(
      code,
      shiftPressed: _shiftPressed,
      ctrlPressed: _ctrlPressed,
      altPressed: _altPressed,
    );
  }
}
