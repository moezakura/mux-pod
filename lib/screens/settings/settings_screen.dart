import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'category_list_view.dart';
import 'master_detail_view.dart';
import 'settings_breakpoints.dart';

/// 設定画面（エントリ・横幅で分岐）。
///
/// LayoutBuilder で幅判定し、<600dp はスマホ一覧（push 2階層）、
/// >=600dp はタブレット2ペイン。[SettingsBreakpoints.masterDetail] が分岐の単一ソース。
/// クラス名は不変（home_screen.dart:56 / terminal_screen.dart から参照）。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= SettingsBreakpoints.masterDetail) {
          return const SettingsMasterDetailView();
        }
        return const SettingsCategoryListView();
      },
    );
  }
}
