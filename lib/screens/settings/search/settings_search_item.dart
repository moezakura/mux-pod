import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_category.dart';

/// 設定検索の項目 descriptor（UI 層のみ・AppSettings 不変）。
///
/// すべての文字列は [AppLocalizations] から解決する関数で保持する
/// （A4 規約: BuildContext 非依存）。検索インデックスは Provider 層
/// （BuildContext なし・`l10nForLanguage`）で構築されるため、
/// この関数群は `AppLocalizations` 引数で必ず解決できる。
///
/// - [title] / [description]: 項目タイトル・説明文（l10n）
/// - [valueLabels]: 静的選択肢の値ラベル（en/ja 両解決・現在値は subtitle が担う）
/// - [groupLabel]: 所属グループ見出し（フラットカテゴリは null）
/// - [icon]: 検索結果カタログ表示用（既存 ListTile の leading と同じ・無い項目は null）
class SettingsSearchItem {
  const SettingsSearchItem({
    required this.category,
    required this.orderInCategory,
    required this.id,
    required this.title,
    this.description,
    this.valueLabels = const [],
    this.groupLabel,
    this.icon,
  });

  /// 所属カテゴリ（ランキングの第2キー = enum 順）。
  final SettingsCategory category;

  /// カテゴリ内の表示順（ランキングの第3キー・sections の並びと一致）。
  final int orderInCategory;

  /// 安定キー（例: 'fontSize'。将来のカテゴリ遷移・自動スクロール用）。
  final String id;

  /// 項目タイトル（l10n）。
  final String Function(AppLocalizations) title;

  /// 説明文（subtitle・l10n）。無い項目は null。
  final String? Function(AppLocalizations)? description;

  /// 静的選択肢の値ラベル（en/ja 両解決）。
  final List<String Function(AppLocalizations)> valueLabels;

  /// 所属グループ見出し（l10n）。フラットカテゴリは null。
  final String? Function(AppLocalizations)? groupLabel;

  /// 検索結果タイルの leading アイコン。既存 ListTile の leading と同じもの。
  final IconData? icon;
}
