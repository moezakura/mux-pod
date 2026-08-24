import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../sections/about_section.dart';
import '../sections/behavior_section.dart';
import '../sections/connection_section.dart';
import '../sections/display_section.dart';
import '../settings_category.dart';
import '../widgets/settings_section_header.dart';

/// カテゴリの内容（タブレット右ペイン IndexedStack 子 / スマホ詳細 push 中身 共用）。
///
/// 先頭にカテゴリ名ヘッダ（Semantics heading は P1-C4 で付与）を置き、
/// その下に対応セクションを表示する。Behavior・About はフラット。
class SettingsCategoryBody extends ConsumerWidget {
  final SettingsCategory category;

  const SettingsCategoryBody({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListView(
      key: const Key('settingsScrollArea'),
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        SettingsSectionHeader(title: category.labelKey(l10n)),
        switch (category) {
          SettingsCategory.display => const DisplaySection(),
          SettingsCategory.behavior => const BehaviorSection(),
          SettingsCategory.connection => const ConnectionSection(),
          SettingsCategory.about => const AboutSection(),
        },
      ],
    );
  }
}
