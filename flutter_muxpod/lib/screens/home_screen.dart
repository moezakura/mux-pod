import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/design_colors.dart';
import 'connections/connections_screen.dart';
import 'keys/keys_screen.dart';
import 'settings/settings_screen.dart';

/// 現在のタブインデックス Notifier
class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);

/// ホーム画面（Bottom Navigation付き）
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentTab,
        children: const [
          ConnectionsScreen(),
          _TerminalPlaceholder(),
          KeysScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, ref, currentTab),
    );
  }

  Widget _buildBottomNavigationBar(
    BuildContext context,
    WidgetRef ref,
    int currentTab,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: DesignColors.backgroundDark.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: DesignColors.surfaceDark),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                context,
                ref,
                index: 0,
                icon: Icons.lan,
                label: 'Net',
                isSelected: currentTab == 0,
              ),
              _buildNavItem(
                context,
                ref,
                index: 1,
                icon: Icons.terminal,
                label: 'Term',
                isSelected: currentTab == 1,
              ),
              _buildNavItem(
                context,
                ref,
                index: 2,
                icon: Icons.key,
                label: 'Keys',
                isSelected: currentTab == 2,
              ),
              _buildNavItem(
                context,
                ref,
                index: 3,
                icon: Icons.settings,
                label: 'Settings',
                isSelected: currentTab == 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => ref.read(currentTabProvider.notifier).setTab(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // アクティブインジケーター
            if (isSelected)
              Container(
                width: 32,
                height: 2,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: DesignColors.primary,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(
                      color: DesignColors.primary.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 10),
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? DesignColors.primary
                  : DesignColors.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: isSelected
                    ? DesignColors.primary
                    : DesignColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ターミナルタブプレースホルダー
class _TerminalPlaceholder extends StatelessWidget {
  const _TerminalPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.terminal,
              size: 64,
              color: DesignColors.textMuted,
            ),
            SizedBox(height: 16),
            Text(
              'No Active Terminal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: DesignColors.textMuted,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Connect to a server to open a terminal',
              style: TextStyle(
                fontSize: 14,
                color: DesignColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
