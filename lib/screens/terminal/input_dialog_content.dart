import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_colors.dart';
import '../../l10n/l10n_ext.dart';

/// 入力ダイアログのコンテンツ（Enter=改行、Ctrl/Cmd+Enter=送信）
class InputDialogContent extends StatefulWidget {
  // inventory: LEGACY-0088
  final String initialValue;
  final void Function(String value) onValueChanged;
  final Future<void> Function(String value) onSend;

  const InputDialogContent({
    super.key,
    this.initialValue = '',
    required this.onValueChanged,
    required this.onSend,
  });

  @override
  State<InputDialogContent> createState() => InputDialogContentState();
}

class InputDialogContentState extends State<InputDialogContent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    // キーイベントをハンドルするためにonKeyEventを設定
    _focusNode.onKeyEvent = _handleKeyEvent;
    // テキスト変更時に親へ通知
    _controller.addListener(_onTextChanged);
    // 自動フォーカス（カーソルを末尾に）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // カーソルを末尾に移動
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _onTextChanged() {
    widget.onValueChanged(_controller.text);
  }

  /// Returns true when an IME composition range is open.
  bool get _isImeActive {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.onKeyEvent = null;
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// キーイベントをハンドル（Enter=改行、Ctrl/Cmd+Enter=送信）。
  ///
  /// HW キーボードでは Enter を改行として挿入し、Ctrl/Cmd+Enter でのみ送信する。
  /// IME 変換中（composing）は plain Enter を IME に譲り（ignored）、
  /// Ctrl/Cmd+Enter は消費のみ行う（送信・改行ともしない・制御文字混入防止）。
  /// 送信は KeyDown イベントのみで、リピート（長押し）による再送信は行わない。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isEnterKey =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if ((event is KeyDownEvent || event is KeyRepeatEvent) && isEnterKey) {
      if (_isImeActive) {
        // IME 変換中: Ctrl/Cmd+Enter は消費のみ・plain Enter は IME に譲る
        if (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        // Ctrl/Cmd+Enter: 送信（KeyDown のみ・リピートは再送信しない）
        if (event is KeyDownEvent) {
          _handleSend();
        }
        return KeyEventResult.handled;
      }
      // Enter: 改行を挿入（KeyDown/KeyRepeat とも・長押しで連続改行）
      _insertNewline();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 現在のカーソル位置に改行を挿入
  void _insertNewline() {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '\n');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  Future<void> _handleSend() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.onSend(_controller.text);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.l10n.termEnterCommand,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.keyBackground
                      : DesignColors.keyBackgroundLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  context.l10n.termCtrlCmdEnterSend,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: isDark
                        ? DesignColors.textMuted
                        : DesignColors.textMutedLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 200, // 最大高さを制限してスクロール可能に
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              maxLines: null, // 無制限にして内部スクロール
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction
                  .newline, // ソフトキーボードの Enter を改行アクションにする（送信アクションは発生させない）
              style: GoogleFonts.jetBrainsMono(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: context.l10n.termCommandHint,
                hintStyle: GoogleFonts.jetBrainsMono(
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
                filled: true,
                fillColor: isDark
                    ? DesignColors.inputDark
                    : DesignColors.inputLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    side: BorderSide(
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    context.l10n.termCancel,
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _handleSend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          context.l10n.termExecute,
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Factory that exposes [InputDialogContent] for widget tests.
///
/// Production code must never call this function.
@visibleForTesting
// inventory: TERM-SCREEN-004
Widget buildInputDialogContentForTesting({
  String initialValue = '',
  required void Function(String value) onValueChanged,
  required Future<void> Function(String value) onSend,
}) {
  return InputDialogContent(
    initialValue: initialValue,
    onValueChanged: onValueChanged,
    onSend: onSend,
  );
}
