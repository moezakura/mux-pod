import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// 設定画面のカテゴリ。表示順 = enum 順（display → about）。
///
/// labelKey / icon は P1-C4 で ARB 新キー追加と同一コミットで
/// 追加される（FIN-2）。それまでは本 enum は状態保持のみに使われる。
enum SettingsCategory { display, behavior, connection, about }

/// タブレット2ペインの選択カテゴリ状態。
///
/// - 初期値は先頭カテゴリ（display）。
/// - MaterialApp 再ビルド・タブ切替を跨いで保持するため autoDispose しない。
/// - テストからは overrideWith で制御できる。
class SettingsCategoryNotifier extends Notifier<SettingsCategory> {
  @override
  SettingsCategory build() => SettingsCategory.display;

  void select(SettingsCategory category) => state = category;
}

final settingsCategoryProvider =
    NotifierProvider<SettingsCategoryNotifier, SettingsCategory>(
      SettingsCategoryNotifier.new,
    );

/// カテゴリの表示名・アイコン（P1-C4 で ARB 新キー追加と同一コミットで導入・FIN-2）。
extension SettingsCategoryX on SettingsCategory {
  /// ローカライズ済みカテゴリ名。
  String labelKey(AppLocalizations l10n) => switch (this) {
    SettingsCategory.display => l10n.settingsCategoryDisplay,
    SettingsCategory.behavior => l10n.settingsCategoryBehavior,
    SettingsCategory.connection => l10n.settingsCategoryConnection,
    SettingsCategory.about => l10n.settingsCategoryAbout,
  };

  /// 一覧 / 詳細で使うアイコン。
  IconData get icon => switch (this) {
    SettingsCategory.display => Icons.palette_outlined,
    SettingsCategory.behavior => Icons.touch_app_outlined,
    SettingsCategory.connection => Icons.sync_alt,
    SettingsCategory.about => Icons.info_outline,
  };
}
