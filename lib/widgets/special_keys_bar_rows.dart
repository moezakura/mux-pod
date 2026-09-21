import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/l10n_ext.dart';
import '../theme/design_colors.dart';
import 'special_keys_bar_buttons.dart';
import 'special_keys_bar_tool_buttons.dart';
import 'special_keys_direct_input_engine.dart';
import 'special_keys_modifier_state.dart';
import 'special_keys_token_view.dart';

/// 行レイアウトの計算結果。
class RowLayout {
  const RowLayout({required this.visibleRows, required this.pencilHost});

  /// モード依存スキップ適用後の可視トークン列（行数は widget.rows と同一）。
  final List<List<String>> visibleRows;

  /// 鉛筆（manage）ボタンをホストする最初の非空行のインデックス。
  /// 非空行が無ければ -1（鉛筆のみの受け皿行を描画する）。
  final int pencilHost;
}

/// 行レイアウトの決定（レガシー行判定 `listEquals`・pencilホスト判定・
/// 可視行計算）。純粋（単体テスト可能）。
class SpecialKeysBarLayout {
  SpecialKeysBarLayout._();

  /// 可視行と pencil ホスト行を計算する。判定は行の内容だけに依り、
  /// 行番号には依らない（現行 build の判定を一字不変で抽出）。
  static RowLayout compute(
    List<List<String>> rows, {
    required bool directInputEnabled,
    required bool hasImage,
  }) {
    // Rows render exactly the tokens they hold, subject to mode skips.
    final visibleRows = [
      for (final row in rows)
        SpecialKeysTokenView.visibleOf(
          row,
          directInputEnabled: directInputEnabled,
          hasImage: hasImage,
        ),
    ];

    // The manage (pencil) button is pinned to the end of the first row that
    // renders anything — the top row is the custom row, so it lands next to
    // the user's own buttons. When no row renders (every row empty, or no rows
    // at all) a pencil-only strip keeps the editor reachable.
    final pencilHost = visibleRows.indexWhere((row) => row.isNotEmpty);

    return RowLayout(visibleRows: visibleRows, pencilHost: pencilHost);
  }
}

/// 行1の従来レイアウト（ESC…dash、必要なら鉛筆ボタン）。既定レイアウト専用。
class LegacyModifierRow extends StatelessWidget {
  const LegacyModifierRow({
    super.key,
    required this.withManageButton,
    required this.modifiers,
    required this.onManage,
    required this.hapticFeedback,
    required this.sendSpecialKey,
    required this.sendLiteralKey,
  });

  final bool withManageButton;
  final SpecialKeysModifierState modifiers;
  final VoidCallback? onManage;
  final bool hapticFeedback;
  final void Function(String tmuxKey) sendSpecialKey;
  final void Function(String key) sendLiteralKey;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
      // Plain Row on purpose: these builders return Expanded, so they share the
      // width. Wrapping this in a horizontal scroll view makes the row
      // unbounded and every flex child an error — the backspace key is just a
      // tenth flex child, and they all get slightly narrower.
      child: Row(
        children: [
          SpecialKeyButton(
            label: 'ESC',
            onTap: () => sendSpecialKey('Escape'),
            hapticFeedback: hapticFeedback,
          ),
          SpecialKeyButton(
            label: 'TAB',
            onTap: () => sendSpecialKey('Tab'),
            hapticFeedback: hapticFeedback,
          ),
          ModifierButton(
            label: 'CTRL',
            isPressed: modifiers.ctrl,
            onPressed: modifiers.toggleCtrl,
            hapticFeedback: hapticFeedback,
          ),
          ModifierButton(
            label: 'ALT',
            isPressed: modifiers.alt,
            onPressed: modifiers.toggleAlt,
            hapticFeedback: hapticFeedback,
          ),
          ModifierButton(
            label: 'SHIFT',
            isPressed: modifiers.shift,
            onPressed: modifiers.toggleShift,
            hapticFeedback: hapticFeedback,
          ),
          EnterKeyButton(
            onTap: () => sendSpecialKey('Enter'),
            hapticFeedback: hapticFeedback,
          ),
          ShiftEnterKeyButton(
            onTap: () => sendSpecialKey('S-Enter'),
            hapticFeedback: hapticFeedback,
          ),
          LiteralKeyButton(
            label: '/',
            onTap: () => sendLiteralKey('/'),
            hapticFeedback: hapticFeedback,
          ),
          LiteralKeyButton(
            label: '-',
            onTap: () => sendLiteralKey('-'),
            hapticFeedback: hapticFeedback,
          ),
          SpecialKeyButton(
            label: '\u232b',
            onTap: () => sendSpecialKey('BSpace'),
            hapticFeedback: hapticFeedback,
          ),
          if (withManageButton)
            ManageButton(onTap: onManage, hapticFeedback: hapticFeedback),
        ],
      ),
    );
  }
}

/// 行2の従来レイアウト（ナビゲーション + 数字/Input）。既定レイアウト専用。
class LegacyNavigationRow extends StatelessWidget {
  const LegacyNavigationRow({
    super.key,
    required this.directInputEnabled,
    required this.onImagePickRequested,
    required this.onDirectInputToggle,
    required this.onInputTap,
    required this.hapticFeedback,
    required this.sendSpecialKey,
    required this.sendLiteralKey,
  });

  final bool directInputEnabled;
  final VoidCallback? onImagePickRequested;
  final VoidCallback? onDirectInputToggle;
  final VoidCallback? onInputTap;
  final bool hapticFeedback;
  final void Function(String tmuxKey) sendSpecialKey;
  final void Function(String key) sendLiteralKey;

  @override
  Widget build(BuildContext context) {
    if (directInputEnabled) {
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
          Expanded(child: CmdInputButton(onTap: onInputTap)),
        ],
      ),
    );
  }

  List<Widget> _buildNavigationControls() {
    return [
      NavigationKeyButton(
        label: 'PgUp',
        onTap: () => sendSpecialKey('PPage'),
        hapticFeedback: hapticFeedback,
      ),
      const SizedBox(width: 2),
      NavigationKeyButton(
        label: 'PgDn',
        onTap: () => sendSpecialKey('NPage'),
        hapticFeedback: hapticFeedback,
      ),
      const SizedBox(width: 2),
      ArrowKeyButton(
        icon: Icons.arrow_left,
        onTap: () => sendSpecialKey('Left'),
        hapticFeedback: hapticFeedback,
      ),
      const SizedBox(width: 2),
      ArrowKeyButton(
        icon: Icons.arrow_drop_up,
        onTap: () => sendSpecialKey('Up'),
        hapticFeedback: hapticFeedback,
      ),
      const SizedBox(width: 2),
      ArrowKeyButton(
        icon: Icons.arrow_drop_down,
        onTap: () => sendSpecialKey('Down'),
        hapticFeedback: hapticFeedback,
      ),
      const SizedBox(width: 2),
      ArrowKeyButton(
        icon: Icons.arrow_right,
        onTap: () => sendSpecialKey('Right'),
        hapticFeedback: hapticFeedback,
      ),
      const SizedBox(width: 8),
      if (onImagePickRequested != null) ...[
        SpecialKeysImageButton(
          onTap: onImagePickRequested,
          hapticFeedback: hapticFeedback,
        ),
        const SizedBox(width: 2),
      ],
      DirectInputToggleButton(
        isEnabled: directInputEnabled,
        onTap: onDirectInputToggle,
        hapticFeedback: hapticFeedback,
      ),
    ];
  }

  /// 数字キーボタン（DirectInput有効時に矢印キー行に表示）
  Widget _buildNumberKeyButton(String label) {
    return NumberKeyButton(
      label: label,
      onTap: () => sendLiteralKey(label),
      hapticFeedback: hapticFeedback,
    );
  }
}

/// 汎用の水平スクロール行：保持トークンを順に描画し、必要なら
/// 鉛筆ボタンをスクロールの外に固定する。
class GenericTokenRow extends StatelessWidget {
  const GenericTokenRow({
    super.key,
    required this.tokens,
    required this.height,
    required this.showManageButton,
    required this.onManage,
    required this.hapticFeedback,
    required this.tokenView,
    this.scrollController,
  });

  final List<String> tokens;
  final double height;
  final ScrollController? scrollController;
  final bool showManageButton;
  final VoidCallback? onManage;
  final bool hapticFeedback;
  final SpecialKeysTokenView tokenView;

  @override
  Widget build(BuildContext context) {
    if (tokens.isEmpty && !showManageButton) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight,
      child: Row(
        children: [
          if (tokens.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final token in tokens) ...[
                      tokenView.build(context, token, height: height),
                      const SizedBox(width: 2),
                    ],
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          if (showManageButton)
            ManageButton(onTap: onManage, hapticFeedback: hapticFeedback),
        ],
      ),
    );
  }
}

/// DirectInput専用行（入力フィールドのみ）。RET/BSはネイティブキーボードのものを使用。
///
/// エンジンから controller/focusNode/handleSubmitted/handleHardwareKeyEvent を
/// 配線する（設計書 v2-4）。TextField はこの行に内包され、
/// `find.byType(TextField)` がそのまま当たる構成を維持する。
class DirectInputRow extends StatelessWidget {
  const DirectInputRow({super.key, required this.engine});

  final SpecialKeysDirectInputEngine engine;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Focus(
        onKeyEvent: engine.handleHardwareKeyEvent,
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
                  controller: engine.controller,
                  focusNode: engine.focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  // ターミナルへのパススルー入力のため、OSによるテキスト書き換えを
                  // 無効化する（iOS自動補正の ".."→"‥" 置換、Smart Dashes /
                  // Smart Quotes、スペルチェックによる確定も防止）。
                  // ※ enableSuggestions: false は設定しないこと:
                  //   Androidエンジン（TextInputPlugin.inputTypeFromTextInputType）が
                  //   inputType に TYPE_TEXT_VARIATION_VISIBLE_PASSWORD を付加し、
                  //   IME変換（日本語入力）が不可能になるため。
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  onSubmitted: engine.handleSubmitted,
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
      ),
    );
  }
}
