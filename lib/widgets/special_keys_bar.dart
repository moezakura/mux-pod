import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/custom_keys/custom_key_button.dart';
import '../theme/design_colors.dart';
import 'special_keys_bar_rows.dart';
import 'special_keys_direct_input_engine.dart';
import 'special_keys_modifier_state.dart';
import 'special_keys_row_scrollers.dart';
import 'special_keys_token_view.dart';
import 'special_keys_tmux_composer.dart';

/// 特殊キーバー（HTMLデザイン仕様準拠）
///
/// tmuxコマンド方式でキーを送信するため、
/// tmux send-keys形式のキー名を使用する。
///
/// 責務ベース再設計（P2）の合成ルート: 協調クラス群・子Widget群を配線するだけ。
/// - DirectInput/IME 状態機械: [SpecialKeysDirectInputEngine]
/// - ソフトウェア修飾子状態: [SpecialKeysModifierState]
/// - tmuxキー名合成: [SpecialKeysTmuxComposer]
/// - 行スクロール制御: [SpecialKeysRowScrollers]
/// - トークン→ボタン解決: [SpecialKeysTokenView]
/// - 行レイアウト・行Widget: [SpecialKeysBarLayout] / 行Widget群
/// - ボタンWidget群: [SpecialKeysBarButtons] 配下
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

  /// CJK Mode: IME確定ごとに全文送信して入力欄をクリアする
  /// 旧来（v0.7.0-pre4）のDirectInput挙動を使うか。
  /// iOSのCJK系IMEで発生する多重送信回避用（設定画面はiOSのみ表示）。
  final bool cjkMode;

  /// DirectInput: Enter送信後もソフトウェアキーボードを開いたままにするか。
  /// フレームワーク既定では TextInputAction.send 受信時に unfocus されるため、
  /// 送信後に同期 requestFocus() で unfocus をキャンセルして実現する
  /// （ソフトキーボード経路のみ）。
  final bool keepKeyboardOnEnter;

  /// 画像転送ボタンが押された時のコールバック
  final VoidCallback? onImagePickRequested;

  /// カスタムキーボタン（ユーザー定義ボタン）
  final List<CustomKeyButton> customButtons;

  /// バーの行レイアウト（上から下）。各行は保持するトークン列。
  final List<List<String>> rows;

  /// カスタムボタン編集リクエスト（長押し）
  final void Function(CustomKeyButton)? onCustomButtonEdit;

  /// ボタン管理画面を開くリクエスト（鉛筆ボタン）
  final VoidCallback? onManageButtons;

  const SpecialKeysBar({
    super.key,
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    required this.rows,
    this.onInputTap,
    this.hapticFeedback = true,
    this.directInputEnabled = false,
    this.onDirectInputToggle,
    this.cjkMode = false,
    this.keepKeyboardOnEnter = false,
    this.onImagePickRequested,
    this.customButtons = const [],
    this.onCustomButtonEdit,
    this.onManageButtons,
  });

  @override
  State<SpecialKeysBar> createState() => _SpecialKeysBarState();
}

class _SpecialKeysBarState extends State<SpecialKeysBar> {
  /// ソフトウェア修飾子（CTRL/ALT/SHIFT）押下状態の唯一の所有者。
  final SpecialKeysModifierState _modifiers = SpecialKeysModifierState();

  /// 行水平スクロール制御の所有者。
  late final SpecialKeysRowScrollers _scrollers;

  /// DirectInput/IME 状態機械の唯一の所有者。
  late final SpecialKeysDirectInputEngine _engine;

  /// tmuxキー名合成（送信オーケストから使用）。
  final SpecialKeysTmuxComposer _composer = const SpecialKeysTmuxComposer();

  /// widget の実行時 prop からコールバック値オブジェクトを生成する。
  /// コールバック関数のみ（状態を含めない。状態はエンジンが唯一所有）。
  SpecialKeysBarCallbacks _callbacksFor(SpecialKeysBar w) =>
      SpecialKeysBarCallbacks(
        onKeyPressed: w.onKeyPressed,
        onSpecialKeyPressed: w.onSpecialKeyPressed,
        hapticFeedback: w.hapticFeedback,
      );

  @override
  void initState() {
    super.initState();
    _scrollers = SpecialKeysRowScrollers(isActive: () => mounted);
    _engine = SpecialKeysDirectInputEngine(
      modifiers: _modifiers,
      callbacks: _callbacksFor(widget),
      isActive: () => mounted,
    )..attach(directInputEnabled: widget.directInputEnabled);
    _engine
      ..setCjkMode(widget.cjkMode)
      ..setKeepKeyboardOnEnter(widget.keepKeyboardOnEnter);
    _scrollers.sync(widget.rows.length);
    _modifiers.addListener(_onModifiersChanged);
  }

  /// 修飾子状態の変更を画面へ反映する（ChangeNotifier → setState）。
  void _onModifiersChanged() => setState(() {});

  @override
  void didUpdateWidget(SpecialKeysBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 【実行時 prop 伝播（設計書 v2-1）】無条件で毎回、最新の widget 値を
    // エンジンへ伝播する。送信時点での widget.keepKeyboardOnEnter /
    // widget.cjkMode / widget.hapticFeedback のライブ参照の意味論を維持する
    // ための必須配線（初期値固定・初回のみ注入は禁止）。
    _engine.setCallbacks(_callbacksFor(widget));
    _engine.setCjkMode(widget.cjkMode);
    _engine.setKeepKeyboardOnEnter(widget.keepKeyboardOnEnter);
    // これとは別に、従来どおりの分岐駆動の副作用（伝播と役割が異なる）。
    if (widget.directInputEnabled && !oldWidget.directInputEnabled) {
      _engine.resetToSentinel();
    } else if (!widget.directInputEnabled && oldWidget.directInputEnabled) {
      _engine.clearForDeactivation();
    }
    // CJKモード切替時は入力欄をリセットし、旧モードのdelta状態を残さない
    if (widget.cjkMode != oldWidget.cjkMode && widget.directInputEnabled) {
      _engine.resetToSentinel();
    }
    _scrollers.sync(widget.rows.length);
    // 新規トークンが追加された行を、その位置（先頭/末尾）まで自動スクロールする
    final shared = widget.rows.length < oldWidget.rows.length
        ? widget.rows.length
        : oldWidget.rows.length;
    for (var row = 0; row < shared; row++) {
      if (widget.rows[row].length > oldWidget.rows[row].length) {
        _scrollers.scheduleScrollToNewToken(
          row,
          atStart: SpecialKeysRowScrollers.grewAtStart(
            oldWidget.rows[row],
            widget.rows[row],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _modifiers.removeListener(_onModifiersChanged);
    _modifiers.dispose();
    _engine.dispose();
    _scrollers.dispose();
    super.dispose();
  }

  /// 特殊キーを送信（tmux形式）。
  /// haptic → 修飾子消費 → 合成（composer 委譲）→ コールバック発火の順序のみ保持。
  void _sendSpecialKey(String tmuxKey) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    final consumed = _modifiers.consumeAll();
    widget.onSpecialKeyPressed(
      _composer.composeSpecial(
        tmuxKey,
        shift: consumed.contains('S'),
        ctrl: consumed.contains('C'),
        alt: consumed.contains('M'),
      ),
    );
  }

  /// リテラルキーを送信（文字そのまま）。
  /// 修飾子付き単文字は tmux 形式（composer 委譲）、それ以外はリテラル送信。
  void _sendLiteralKey(String key) {
    if (widget.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    final consumed = _modifiers.consumeAll();
    final composed = _composer.composeLiteral(
      key,
      shift: consumed.contains('S'),
      ctrl: consumed.contains('C'),
      alt: consumed.contains('M'),
    );
    if (composed != null) {
      widget.onSpecialKeyPressed(composed);
      return;
    }

    // 修飾子なしの場合はリテラル送信
    widget.onKeyPressed(key);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final layout = SpecialKeysBarLayout.compute(
      widget.rows,
      directInputEnabled: widget.directInputEnabled,
      hasImage: widget.onImagePickRequested != null,
    );
    final tokenView = SpecialKeysTokenView(
      modifiers: _modifiers,
      callbacks: _callbacksFor(widget),
      customButtons: widget.customButtons,
      directInputEnabled: widget.directInputEnabled,
      onInputTap: widget.onInputTap,
      onDirectInputToggle: widget.onDirectInputToggle,
      onImagePickRequested: widget.onImagePickRequested,
      onCustomButtonEdit: widget.onCustomButtonEdit,
      sendSpecialKey: _sendSpecialKey,
      sendLiteralKey: _sendLiteralKey,
    );
    final visibleRows = layout.visibleRows;
    final pencilHost = layout.pencilHost;

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
            for (var row = 0; row < visibleRows.length; row++)
              _buildRow(
                row,
                visibleRows[row],
                hostsPencil: row == pencilHost,
                tokenView: tokenView,
              ),
            if (pencilHost < 0) _buildPencilOnlyRow(tokenView: tokenView),
            if (widget.directInputEnabled) DirectInputRow(engine: _engine),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// 1行を描画する。既定と完全一致する行だけ従来の固定描画を使い、それ以外は
  /// 汎用の水平スクロール行で描く（判定は行の内容だけで、行番号には依らない）。
  Widget _buildRow(
    int row,
    List<String> tokens, {
    required bool hostsPencil,
    required SpecialKeysTokenView tokenView,
  }) {
    final stored = widget.rows[row];
    if (listEquals(stored, CustomKeyRows.standardRow1)) {
      return LegacyModifierRow(
        withManageButton: hostsPencil,
        modifiers: _modifiers,
        onManage: widget.onManageButtons,
        hapticFeedback: widget.hapticFeedback,
        sendSpecialKey: _sendSpecialKey,
        sendLiteralKey: _sendLiteralKey,
      );
    }
    if (listEquals(stored, CustomKeyRows.standardRow2) && !hostsPencil) {
      return LegacyNavigationRow(
        directInputEnabled: widget.directInputEnabled,
        onImagePickRequested: widget.onImagePickRequested,
        onDirectInputToggle: widget.onDirectInputToggle,
        onInputTap: widget.onInputTap,
        hapticFeedback: widget.hapticFeedback,
        sendSpecialKey: _sendSpecialKey,
        sendLiteralKey: _sendLiteralKey,
      );
    }
    return _buildGenericTokenRow(
      tokens: tokens,
      height: 32,
      scrollController: _scrollers.controllerAt(row),
      showManageButton: hostsPencil,
      tokenView: tokenView,
    );
  }

  /// トークンを描く行が1つも無いときの受け皿（鉛筆ボタンのみ）。
  Widget _buildPencilOnlyRow({required SpecialKeysTokenView tokenView}) =>
      _buildGenericTokenRow(
        tokens: const <String>[],
        height: 32,
        scrollController: null,
        showManageButton: true,
        tokenView: tokenView,
      );

  /// 汎用の水平スクロール行（トークン列を [SpecialKeysTokenView] で描画）。
  Widget _buildGenericTokenRow({
    required List<String> tokens,
    required double height,
    ScrollController? scrollController,
    required bool showManageButton,
    required SpecialKeysTokenView tokenView,
  }) {
    return GenericTokenRow(
      tokens: tokens,
      height: height,
      scrollController: scrollController,
      showManageButton: showManageButton,
      onManage: widget.onManageButtons,
      hapticFeedback: widget.hapticFeedback,
      tokenView: tokenView,
    );
  }
}
