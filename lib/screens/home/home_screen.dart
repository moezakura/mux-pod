import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/current_tab_provider.dart';
import '../connections/connections_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../keys/keys_screen.dart';
import '../notifications/notification_panes_screen.dart';
import '../settings/settings_screen.dart';

import 'widgets/home_bottom_nav_bar.dart';

/// ホーム画面（Bottom Navigation付き）。
///
/// タブ順序: Servers | Keys | [Dashboard] | Notify | Settings。
/// タブ状態は中立モジュール `lib/navigation/current_tab_provider.dart`、
/// ボトムナビの表示は [HomeBottomNavBar]（props 受け取りの表示専用）
/// へ委譲する合成ルート（画面の状態・UI 詳細は持たない）。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentTab,
        children: const [
          ConnectionsScreen(), // 0: Servers
          KeysScreen(), // 1: Keys
          DashboardScreen(), // 2: Dashboard（中央）
          NotificationPanesScreen(), // 3: Alerts
          SettingsScreen(), // 4: Settings
        ],
      ),
      bottomNavigationBar: HomeBottomNavBar(
        currentTab: currentTab,
        onSelectTab: (index) =>
            ref.read(currentTabProvider.notifier).setTab(index),
      ),
    );
  }
}
