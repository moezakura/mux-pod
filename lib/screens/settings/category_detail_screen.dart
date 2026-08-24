import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: SettingsAppBarTitle(text: _title(context))),
      body: SettingsCategoryBody(category: category),
    );
  }

  // 一時英語直書き（P1-C3・M-3）: C4 で labelKey に差し替える（FIN-2）。
  String _title(BuildContext context) => switch (category) {
    SettingsCategory.display => 'Display',
    SettingsCategory.behavior => 'Behavior',
    SettingsCategory.connection => 'Connection & Transfer',
    SettingsCategory.about => 'About',
  };
}