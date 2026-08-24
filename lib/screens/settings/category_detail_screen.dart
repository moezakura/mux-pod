import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import 'categories/settings_category_body.dart';
import 'settings_category.dart';
import 'widgets/settings_app_bar_title.dart';

/// スマホのカテゴリ詳細画面（root Navigator.push 先）。
///
/// 中身は [SettingsCategoryBody] と同一ウィジェットを流用する
/// （レスポンシブ差分は「並べるか push で分けるか」のみ）。
/// ボトムナビは覆われる（🤝A3・既存 CustomKeys / Licenses と同挙動）。
class SettingsCategoryDetailScreen extends StatelessWidget {
  final SettingsCategory category;

  const SettingsCategoryDetailScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: SettingsAppBarTitle(text: category.labelKey(l10n))),
      body: SettingsCategoryBody(category: category),
    );
  }
}