import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_colors.dart';
import '../l10n/l10n_ext.dart';

/// 特殊キーバー（HTMLデザイン仕様準拠）
///
/// tmuxコマンド方式でキーを送信するため、
/// tmux send-keys形式のキー名を使用する。
class SpecialKeysBar extends StatefulWidget {
  /// リテラルキー送信（通常の文字）
  final void Function(String key) onKeyPressed;

  /// 特殊キー送信（tmux形式: Enter, Escape, C-c等）
  final void Function(String tmuxKey) onSpecialKeyPressed;

  final VoidCallback? onInputTap;
  final bool hapticFeedback;

  /// DirectInputモードが有効か
  final bool directInputEnabled;

  /// DirectInputモードのトグルコールバック
  final VoidCallback? onDirectInputToggle;

  /// 画像転送ボタンが押された時のコールバック
  final VoidCallback? onImagePickRequested;

  const SpecialKeysBar({
    super.key,
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    this.onInputTap,
    this.hapticFeedback = true,
    this.directInputEnabled = false,
    this.onDirectInputToggle,
    this.onImagePickRequested,
  });

  @override
  State<SpecialKeysBar> createState() => _SpecialKeysBarState();
}

class _SpecialKeysBarState extends State<SpecialKeysBar> {
  bool _ctrlPressed = false;
  bool _altPressed = false;
  bool _shiftPressed = false;
  final TextEditingController _directInputController = TextEditingController();
  final FocusNode _directInputFocusNode = FocusNode();

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

  @override
  void initState() {
    super.initState();
    if (widget.directInputEnabled) {
      _directInputController.value = TextEditingValue(
        text: _sentinel,
        selection: TextSelection.collapsed(offset: _sentinel.length),
      );
    }
    _directInputController.addListener(_onDirectInputChanged);
  }

  @override
  void didUpdateWidget(SpecialKeysBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.directInputEnabled && !oldWidget.directInputEnabled) {
      _resetToSentinel();
    } else if (!widget.directInputEnabled && oldWidget.directInputEnabled) {
      _isResettingController = true;
      _directInputController.clear();
      _isResettingController = false;
    }
  }

  @override
  void dispose() {
    _directInputController.removeListener(_onDirectInputChanged);
    _directInputController.dispose();
    _directInputFocusNode.dispose();
    super.dispose();
  }

  /// DirectInput: テキスト変更時の処理
  /// sentinelアプローチでBackspaceを検出（iOS/iPadOS対応）
  void _onDirectInputChanged() {
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
      if ((_ctrlPressed || _altPressed) && _lastComposingText!.length == 1) {
        final char = _lastComposingText!;
        if (RegExp(r'^[A-Za-z]$').hasMatch(char)) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
          final List<String> modifiers = [];
          if (_ctrlPressed) {
            modifiers.add('C');
            setState(() => _ctrlPressed = false);
          }
          if (_altPressed) {
            modifiers.add('M');
            setState(() => _altPressed = false);
          }
          final prefix = modifiers.join('-');
          widget.onSpecialKeyPressed('$prefix-${char.toLowerCase()}');
          _lastComposingText = null;
          _resetToSentinel();
          return;
        }
      }

      return;
    }

    // Sentinelが削除された = Backspaceが押された（iOS/iPadOS対応）
    if (text.isEmpty) {
      _lastComposingText = null;
      _sendDirectBackspace();
      _resetToSentinel();
      return;
    }

    // Sentinelを除去して実際の入力テキストを取得
    final actualText = text.replaceAll(_sentinel, '');

    // 実際のテキストがあれば送信
    if (actualText.isNotEmpty) {
      // 外付けキーボードの二重入力防止: _handleKeyEventで処理済みならスキップ
      if (_isRecentKeyEventHandled()) {
        _lastComposingText = null;
        _resetToSentinel();
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
      if ((_ctrlPressed || _altPressed) &&
          textToSend.length == 1 &&
          RegExp(r'^[A-Za-z]$').hasMatch(textToSend)) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        final List<String> modifiers = [];
        if (_ctrlPressed) {
          modifiers.add('C');
          setState(() => _ctrlPressed = false);
        }
        if (_altPressed) {
          modifiers.add('M');
          setState(() => _altPressed = false);
        }
        final prefix = modifiers.join('-');
        widget.onSpecialKeyPressed('$prefix-${textToSend.toLowerCase()}');
      } else {
        widget.onKeyPressed(textToSend);
      }

      // 送信後にsentinelにリセット
      _resetToSentinel();
    }
  }

  /// DirectInput: ソフトウェアキーボードのEnter（送信）で呼ばれる
  void _onDirectInputSubmitted(String value) {
    // 外付けキーボードの二重入力防止: _handleKeyEventで処理済みならスキップ
    if (_isRecentKeyEventHandled()) return;

    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed('Enter');
    _resetToSentinel();
  }

  /// DirectInput: Backspaceキー送信
  void _sendDirectBackspace() {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed('BSpace');
  }

  /// DirectInput: sentinelにリセット（Backspace検出用）
  ///
  /// _isResettingControllerの解除を次フレームまで遅延することで、
  /// iOSプラットフォームがIME確定時に送る遅延テキスト更新を吸収する。
  /// PostFrameCallbackでcontrollerが上書きされていれば再度sentinelにリセットする。
  void _resetToSentinel() {
    _isResettingController = true;
    _directInputController.value = TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: _sentinel.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

  /// 外付けキーボードの修飾子を検出してtmux形式キー名に変換
  String _applyHardwareModifiers(String baseKey) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;

    // 特殊ケース: Shift+Tab → BTab
    if (isShift && baseKey == 'Tab') return 'BTab';

    final mods = <String>[];
    if (isShift) mods.add('S');
    if (isCtrl) mods.add('C');
    if (isAlt) mods.add('M');
    if (isMeta) mods.add('M');
    if (mods.isEmpty) return baseKey;
    return '${mods.join('-')}-$baseKey';
  }

  /// 外付けキーボード → tmuxキー名マッピング
  static final _hwSpecialKeyMap = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.arrowUp: 'Up',
    LogicalKeyboardKey.arrowDown: 'Down',
    LogicalKeyboardKey.arrowLeft: 'Left',
    LogicalKeyboardKey.arrowRight: 'Right',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PPage',
    LogicalKeyboardKey.pageDown: 'NPage',
    LogicalKeyboardKey.delete: 'DC',
    LogicalKeyboardKey.f1: 'F1',
    LogicalKeyboardKey.f2: 'F2',
    LogicalKeyboardKey.f3: 'F3',
    LogicalKeyboardKey.f4: 'F4',
    LogicalKeyboardKey.f5: 'F5',
    LogicalKeyboardKey.f6: 'F6',
    LogicalKeyboardKey.f7: 'F7',
    LogicalKeyboardKey.f8: 'F8',
    LogicalKeyboardKey.f9: 'F9',
    LogicalKeyboardKey.f10: 'F10',
    LogicalKeyboardKey.f11: 'F11',
    LogicalKeyboardKey.f12: 'F12',
  };

  /// 外付けキーボード用の特殊キー送信（デバウンス付き）
  void _sendHwSpecialKey(String baseKey) {
    _markKeyEventHandled();
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed(_applyHardwareModifiers(baseKey));
    // 外付けキーボード使用時はソフトウェア修飾子トグルをリセット
    _resetSoftwareModifiers();
  }

  /// ソフトウェア修飾子ボタンの状態をリセット
  void _resetSoftwareModifiers() {
    if (_shiftPressed || _ctrlPressed || _altPressed) {
      setState(() {
        _shiftPressed = false;
        _ctrlPressed = false;
        _altPressed = false;
      });
    }
  }

  /// キーイベントハンドラ（外付けキーボード用: 全特殊キーをキャプチャ）
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
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
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        widget.onSpecialKeyPressed('C-${keyLabel.toLowerCase()}');
        _resetSoftwareModifiers();
        return KeyEventResult.handled;
      }
    }

    // Cmd/Meta + A-Z は M- として送信（ユーザー要望: Meta/Super として伝える）
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    if (isMetaPressed) {
      final keyLabel = key.keyLabel;
      if (keyLabel.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(keyLabel)) {
        _markKeyEventHandled();
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
        widget.onSpecialKeyPressed('M-${keyLabel.toLowerCase()}');
        _resetSoftwareModifiers();
        return KeyEventResult.handled;
      }
    }

    // Enterキー
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _markKeyEventHandled();
      _sendDirectEnterAndClear();
      _resetSoftwareModifiers();
      return KeyEventResult.handled;
    }

    // Backspaceキー: sentinelアプローチで_onDirectInputChangedにて処理
    if (key == LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }

    // マップに登録された特殊キー（Escape/Tab/矢印/Nav/F1-F12）
    final tmuxKey = _hwSpecialKeyMap[key];
    if (tmuxKey != null) {
      _sendHwSpecialKey(tmuxKey);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// DirectInput: Enterキー送信して入力欄をリセット
  void _sendDirectEnterAndClear() {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }
    widget.onSpecialKeyPressed('Enter');
    _resetToSentinel();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.footerBackground
            : DesignColors.footerBackgroundLight,
        border: Border(top: BorderSide(color: colorScheme.outline, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModifierKeysRow(),
            _buildArrowKeysRow(),
            if (widget.directInputEnabled) _buildDirectInputRow(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// 上部の修飾キー行（ESC, TAB, CTRL, ALT, SHIFT, ENTER, S-RET, /, -）
  Widget _buildModifierKeysRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
      child: Row(
        children: [
          _buildSpecialKeyButton('ESC', 'Escape'),
          _buildSpecialKeyButton('TAB', 'Tab'),
          _buildModifierButton('CTRL', _ctrlPressed, () {
            setState(() => _ctrlPressed = !_ctrlPressed);
          }),
          _buildModifierButton('ALT', _altPressed, () {
            setState(() => _altPressed = !_altPressed);
          }),
          _buildModifierButton('SHIFT', _shiftPressed, () {
            setState(() => _shiftPressed = !_shiftPressed);
          }),
          _buildEnterKeyButton(),
          _buildShiftEnterKeyButton(),
          _buildLiteralKeyButton('/', '/'),
          _buildLiteralKeyButton('-', '-'),
        ],
      ),
    );
  }

  /// Shift+Enterキーボタン（Claude CodeのAcceptEdits等用）
  Widget _buildShiftEnterKeyButton() {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendSpecialKey('S-Enter'),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: DesignColors.secondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: DesignColors.secondary.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'S-RET',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: DesignColors.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ENTERキーボタン（単体でEnterを送信）
  Widget _buildEnterKeyButton() {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendSpecialKey('Enter'),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: DesignColors.primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: DesignColors.primary.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_return,
                    size: 12,
                    color: DesignColors.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'RET',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 下部の矢印キー + Inputボタン行
  Widget _buildArrowKeysRow() {
    if (widget.directInputEnabled) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              ..._buildNavigationControls(),
              const SizedBox(width: 8),
              _buildNumberKeyButton('1'),
              const SizedBox(width: 2),
              _buildNumberKeyButton('2'),
              const SizedBox(width: 2),
              _buildNumberKeyButton('3'),
              const SizedBox(width: 2),
              _buildNumberKeyButton('4'),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          ..._buildNavigationControls(),
          const SizedBox(width: 4),
          Expanded(child: _buildInputButton()),
        ],
      ),
    );
  }

  List<Widget> _buildNavigationControls() {
    return [
      _buildNavigationKeyButton('PgUp', 'PPage'),
      const SizedBox(width: 2),
      _buildNavigationKeyButton('PgDn', 'NPage'),
      const SizedBox(width: 2),
      _buildArrowButton(Icons.arrow_left, 'Left'),
      const SizedBox(width: 2),
      _buildArrowButton(Icons.arrow_drop_up, 'Up'),
      const SizedBox(width: 2),
      _buildArrowButton(Icons.arrow_drop_down, 'Down'),
      const SizedBox(width: 2),
      _buildArrowButton(Icons.arrow_right, 'Right'),
      const SizedBox(width: 8),
      if (widget.onImagePickRequested != null) ...[
        _buildImageTransferButton(),
        const SizedBox(width: 2),
      ],
      _buildDirectInputToggle(),
    ];
  }

  /// DirectInput専用行（入力フィールドのみ）
  /// RET/BSはネイティブキーボードのものを使用
  Widget _buildDirectInputRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: _buildDirectInputField(),
    );
  }

  /// DirectInputモードのトグルボタン
  Widget _buildDirectInputToggle() {
    final isEnabled = widget.directInputEnabled;
    return GestureDetector(
      onTap: () {
        if (widget.hapticFeedback) {
          HapticFeedback.selectionClick();
        }
        widget.onDirectInputToggle?.call();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isEnabled
              ? DesignColors.success.withValues(alpha: 0.3)
              : DesignColors.keyBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEnabled
                ? DesignColors.success.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Center(
          child: Icon(
            isEnabled ? Icons.flash_on : Icons.flash_off,
            size: 18,
            color: isEnabled ? DesignColors.success : Colors.white70,
          ),
        ),
      ),
    );
  }

  /// DirectInput用テキストフィールド（リアルタイム送信）
  Widget _buildDirectInputField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: DesignColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: DesignColors.success.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            // LIVEインジケーター（左側に配置）
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: DesignColors.success.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: DesignColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: DesignColors.success.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 入力フィールド
            Expanded(
              child: TextField(
                controller: _directInputController,
                focusNode: _directInputFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.send,
                onSubmitted: _onDirectInputSubmitted,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: context.l10n.keyBarTypeHere,
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: DesignColors.success.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 特殊キーボタン（tmux形式で送信）
  Widget _buildSpecialKeyButton(String label, String tmuxKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendSpecialKey(tmuxKey),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.keyBackground
                : DesignColors.keyBackgroundLight,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.black : Colors.grey.shade400,
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// リテラルキーボタン（そのまま文字として送信）
  Widget _buildLiteralKeyButton(String label, String key) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: () => _sendLiteralKey(key),
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.keyBackground
                : DesignColors.keyBackgroundLight,
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.black : Colors.grey.shade400,
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModifierButton(
    String label,
    bool isPressed,
    VoidCallback onPressed,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) {
          if (widget.hapticFeedback) {
            HapticFeedback.lightImpact();
          }
        },
        onTap: onPressed,
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isPressed
                ? colorScheme.primary
                : (isDark
                      ? DesignColors.keyBackground
                      : DesignColors.keyBackgroundLight),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              bottom: BorderSide(
                color: isPressed
                    ? colorScheme.primary
                    : (isDark ? Colors.black : Colors.grey.shade400),
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isPressed ? colorScheme.onPrimary : colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrowButton(IconData icon, String tmuxKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendSpecialKey(tmuxKey),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 16, color: colorScheme.onSurface),
      ),
    );
  }

  Widget _buildNavigationKeyButton(String label, String tmuxKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendSpecialKey(tmuxKey),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// 画像転送ボタン
  Widget _buildImageTransferButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: widget.onImagePickRequested,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Icon(
          Icons.image_outlined,
          size: 16,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 数字キーボタン（DirectInput有効時に矢印キー行に表示）
  Widget _buildNumberKeyButton(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        if (widget.hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      onTap: () => _sendLiteralKey(label),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.keyBackground
              : DesignColors.keyBackgroundLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputButton() {
    return GestureDetector(
      onTap: widget.onInputTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: DesignColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: DesignColors.primary.withValues(alpha: 0.2),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard,
                  size: 15,
                  color: DesignColors.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  // "Cmd" keeps the non-direct toolbar compact enough for fixed nav keys.
                  'Cmd',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: DesignColors.primary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 特殊キーを送信（tmux形式）
  void _sendSpecialKey(String tmuxKey) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    String key = tmuxKey;

    // 特殊なケース: Shift+Tab → BTab (Back Tab)
    if (_shiftPressed && tmuxKey == 'Tab') {
      setState(() => _shiftPressed = false);
      // Ctrl/Altの状態もリセット
      if (_ctrlPressed) setState(() => _ctrlPressed = false);
      if (_altPressed) setState(() => _altPressed = false);
      widget.onSpecialKeyPressed('BTab');
      return;
    }

    // 修飾子を組み合わせる（Shift, Ctrl, Alt順）
    final List<String> modifiers = [];
    if (_shiftPressed) {
      modifiers.add('S');
      setState(() => _shiftPressed = false);
    }
    if (_ctrlPressed) {
      modifiers.add('C');
      setState(() => _ctrlPressed = false);
    }
    if (_altPressed) {
      modifiers.add('M');
      setState(() => _altPressed = false);
    }

    // tmux形式で修飾子を適用
    if (modifiers.isNotEmpty) {
      // 例: S-Enter, C-M-a など
      final prefix = modifiers.join('-');
      key = '$prefix-$tmuxKey';
    }

    widget.onSpecialKeyPressed(key);
  }

  /// リテラルキーを送信（文字そのまま）
  void _sendLiteralKey(String key) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    // 修飾子を組み合わせる
    final List<String> modifiers = [];
    if (_shiftPressed) {
      modifiers.add('S');
      setState(() => _shiftPressed = false);
    }
    if (_ctrlPressed) {
      modifiers.add('C');
      setState(() => _ctrlPressed = false);
    }
    if (_altPressed) {
      modifiers.add('M');
      setState(() => _altPressed = false);
    }

    // 修飾子がある場合はtmux形式で送信
    if (modifiers.isNotEmpty && key.length == 1) {
      final prefix = modifiers.join('-');
      widget.onSpecialKeyPressed('$prefix-$key');
      return;
    }

    // 修飾子なしの場合はリテラル送信
    widget.onKeyPressed(key);
  }
}
