import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../services/terminal/font_calculator.dart';
import '../../../theme/design_colors.dart';

/// プリセットサイズ定義
class SizePreset {
  final String label;
  final int cols;
  final int rows;
  const SizePreset({
    required this.label,
    required this.cols,
    required this.rows,
  });

  /// 標準プリセット 4 種（80x24 / 120x40 / 160x50 / Match Screen）を生成する。
  ///
  /// 旧 resize_dialog.dart の各ダイアログ `_presets` getter（4 箇所の完全
  /// コピペ）の本体を 1:1 移設したもの。Match Screen は
  /// [FontCalculator.calculateMaxCols] / [FontCalculator.calculateMaxRows] で
  /// 算出し、計算順序・clamp 仕様を含め従来と同一の結果を返す。
  static List<SizePreset> standardSet({
    required AppLocalizations l10n,
    required double screenWidth,
    required double screenHeight,
    required double fontSize,
    required String fontFamily,
  }) {
    final matchCols = FontCalculator.calculateMaxCols(
      screenWidth: screenWidth,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
    final matchRows = FontCalculator.calculateMaxRows(
      screenHeight: screenHeight,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );
    return [
      SizePreset(label: l10n.resizePresetStandard, cols: 80, rows: 24),
      SizePreset(label: l10n.resizePresetWide, cols: 120, rows: 40),
      SizePreset(label: l10n.resizePresetFullHd, cols: 160, rows: 50),
      SizePreset(
        label: l10n.resizePresetMatchScreen(matchCols, matchRows),
        cols: matchCols,
        rows: matchRows,
      ),
    ];
  }
}

/// Cols / Rows 数値入力行（resize ダイアログ間共有の内部部品）。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class SizeInputRow extends StatelessWidget {
  /// ローカライズ済み文字列。
  final AppLocalizations l10n;

  /// 現在の Cols 値。
  final int cols;

  /// 現在の Rows 値。
  final int rows;

  /// Cols 変更コールバック。
  final ValueChanged<int> onColsChanged;

  /// Rows 変更コールバック。
  final ValueChanged<int> onRowsChanged;

  const SizeInputRow({
    super.key,
    required this.l10n,
    required this.cols,
    required this.rows,
    required this.onColsChanged,
    required this.onRowsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NumberInput(
            label: l10n.resizeCols,
            value: cols,
            onChanged: onColsChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _NumberInput(
            label: l10n.resizeRows,
            value: rows,
            onChanged: onRowsChanged,
          ),
        ),
      ],
    );
  }
}

/// 単一の数値入力フィールド（ラベル + ◀ 値 ▶）
///
/// ステッパーの clamp 範囲は旧 `_buildNumberInput` のデフォルト値
/// （min=10 / max=500）をそのまま使用する。
class _NumberInput extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _NumberInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: DesignColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: DesignColors.inputDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DesignColors.borderDark),
          ),
          child: Row(
            children: [
              _StepButton(
                icon: Icons.chevron_left,
                onPressed: value > 10
                    ? () => onChanged((value - 1).clamp(10, 500))
                    : null,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DesignColors.textPrimary,
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.chevron_right,
                onPressed: value < 500
                    ? () => onChanged((value + 1).clamp(10, 500))
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ステップボタン（◀ / ▶）
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      color: DesignColors.textSecondary,
      disabledColor: DesignColors.textMuted,
      splashRadius: 18,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

/// プリセット Chip ボタン群（resize ダイアログ間共有の内部部品）。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class PresetChips extends StatelessWidget {
  /// 表示するプリセット一覧。
  final List<SizePreset> presets;

  /// プリセット選択コールバック。
  final ValueChanged<SizePreset> onSelect;

  const PresetChips({super.key, required this.presets, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: presets.map((preset) {
        return ActionChip(
          label: Text(
            preset.label,
            style: const TextStyle(
              fontSize: 11,
              color: DesignColors.textPrimary,
            ),
          ),
          backgroundColor: DesignColors.keyBackground,
          side: const BorderSide(color: DesignColors.borderDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onPressed: () => onSelect(preset),
        );
      }).toList(),
    );
  }
}

/// 警告メッセージ（resize ダイアログ間共有の内部部品）。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class WarningBox extends StatelessWidget {
  /// 警告メッセージ本文。
  final String message;

  const WarningBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DesignColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: DesignColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: DesignColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// リサイズダイアログ共通の骨格（resize ダイアログ間共有の内部部品）。
///
/// AlertDialog 骨格（backgroundColor / radius 12 / title style・content の
/// width 80% + SingleChildScrollView + Column(stretch)）と、Cols/Rows 入力行・
/// プリセットチップ・Cancel/Resize actions を合成する。4 ダイアログ共通の
/// コピペをここで吸収する（挙動不変の範囲内）。
///
/// [content] はプレビュー・警告等の上部コンテンツで、**間隔（`SizedBox(height:
/// 12)`）は呼出側が含めて明示**する（現行の Column children をそのまま渡す）。
/// これにより警告なしケースの縦間隔（現行: プレビューと入力の間に 24px）を含め
/// ピクセル単位で 1:1 を保証する。骨格側は content の直後に入力行・チップを
/// 続け、[footer]（HerdrResizeTerminalDialog の説明文のみ）があれば
/// 8px 間隔で末尾に追加する。
///
/// パッケージ外からの使用を意図しない内部部品（resize ダイアログ間共有）。
class ResizeDialogScaffold extends StatelessWidget {
  /// AlertDialog のタイトル（l10n 文字列）。
  final String title;

  /// 現在の Cols 値。
  final int cols;

  /// 現在の Rows 値。
  final int rows;

  /// Cols 変更コールバック。
  final ValueChanged<int> onColsChanged;

  /// Rows 変更コールバック。
  final ValueChanged<int> onRowsChanged;

  /// プリセット一覧（ダイアログ側で [SizePreset.standardSet] により生成）。
  final List<SizePreset> presets;

  /// プリセット選択コールバック。
  final ValueChanged<SizePreset> onSelectPreset;

  /// Cancel 押下時のコールバック（現行どおり Navigator.pop(context)）。
  final VoidCallback onCancel;

  /// Resize 押下時のコールバック（現行どおり
  /// Navigator.pop(context, ResizeResult(...))）。
  final VoidCallback onConfirm;

  /// Resize ボタンを有効化するか（ResizeWindowDialog: supportsResizeWindow
  /// false で無効化）。
  final bool confirmEnabled;

  /// プレビュー・警告等の上部コンテンツ（間隔 SizedBox は呼出側が明示）。
  final List<Widget> content;

  /// 末尾の説明文（HerdrResizeTerminalDialog のみ・8px 間隔を挟んで表示）。
  final Widget? footer;

  const ResizeDialogScaffold({
    super.key,
    required this.title,
    required this.cols,
    required this.rows,
    required this.onColsChanged,
    required this.onRowsChanged,
    required this.presets,
    required this.onSelectPreset,
    required this.onCancel,
    required this.onConfirm,
    this.confirmEnabled = true,
    this.content = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final footerWidget = footer;
    return AlertDialog(
      backgroundColor: DesignColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        title,
        style: const TextStyle(color: DesignColors.textPrimary),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...content,
              SizeInputRow(
                l10n: context.l10n,
                cols: cols,
                rows: rows,
                onColsChanged: onColsChanged,
                onRowsChanged: onRowsChanged,
              ),
              const SizedBox(height: 12),
              PresetChips(presets: presets, onSelect: onSelectPreset),
              if (footerWidget != null) ...[
                const SizedBox(height: 8),
                footerWidget,
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: onCancel, child: Text(context.l10n.resizeCancel)),
        FilledButton(
          onPressed: confirmEnabled ? onConfirm : null,
          style: FilledButton.styleFrom(backgroundColor: DesignColors.primary),
          child: Text(context.l10n.resizeConfirm),
        ),
      ],
    );
  }
}
