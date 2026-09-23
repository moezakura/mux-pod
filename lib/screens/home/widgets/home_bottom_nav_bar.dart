import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../theme/design_colors.dart';

/// ホーム画面のボトムナビゲーションバー。
///
/// home 画面内部専用の表示部品。タブ状態は外部（[currentTab] / [onSelectTab]）
/// から受け取り、自身では保持しない（状態所有権は中立
/// `lib/navigation/current_tab_provider.dart` の [CurrentTabNotifier]）。
class HomeBottomNavBar extends StatelessWidget {
  const HomeBottomNavBar({
    super.key,
    required this.currentTab,
    required this.onSelectTab,
  });

  /// 現在のタブインデックス（0=Servers, 1=Keys, 2=Dashboard, 3=Notify, 4=Settings）。
  final int currentTab;

  /// タブ選択時のコールバック（親がタブ状態へ反映する）。
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.backgroundDark.withValues(alpha: 0.9)
            : DesignColors.footerBackgroundLight.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? DesignColors.surfaceDark : DesignColors.borderLight,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 通常のナビゲーションアイテム（5つ均等配置）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Servers（左端）
                  _buildNavItem(
                    context,
                    index: 0,
                    icon: Icons.dns,
                    label: context.l10n.homeServers,
                    isSelected: currentTab == 0,
                  ),
                  // Keys（左寄り）
                  _buildNavItem(
                    context,
                    index: 1,
                    icon: Icons.key,
                    label: context.l10n.homeKeys,
                    isSelected: currentTab == 1,
                  ),
                  // 中央スペーサー（Dashboardボタンの場所）
                  const SizedBox(width: 64),
                  // Notify（右寄り）
                  _buildNavItem(
                    context,
                    index: 3,
                    icon: Icons.notifications_outlined,
                    label: context.l10n.homeNotify,
                    isSelected: currentTab == 3,
                  ),
                  // Settings（右端）
                  _buildNavItem(
                    context,
                    index: 4,
                    icon: Icons.settings,
                    label: context.l10n.homeSettings,
                    isSelected: currentTab == 4,
                  ),
                ],
              ),
              // Dashboard（中央・大きくはみ出すボタン）
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: _buildCenterButton(
                    context,
                    isSelected: currentTab == 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 中央のDashboardボタン（大きくはみ出す）
  Widget _buildCenterButton(BuildContext context, {required bool isSelected}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => onSelectTab(2),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    DesignColors.primary,
                    DesignColors.primary.withValues(alpha: 0.8),
                  ],
                )
              : null,
          color: isSelected
              ? null
              : (isDark ? DesignColors.surfaceDark : DesignColors.surfaceLight),
          border: Border.all(
            color: isSelected
                ? DesignColors.primary
                : (isDark ? DesignColors.borderDark : DesignColors.borderLight),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? DesignColors.primary.withValues(alpha: 0.5)
                  : Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          Icons.terminal,
          size: 36,
          color: isSelected
              ? Colors.white
              : (isDark
                    ? DesignColors.textSecondary
                    : DesignColors.textSecondaryLight),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    return GestureDetector(
      onTap: () => onSelectTab(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // アクティブインジケーター
              if (isSelected)
                Container(
                  width: 24,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: DesignColors.primary,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: [
                      BoxShadow(
                        color: DesignColors.primary.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 8),
              Icon(
                icon,
                size: 22,
                color: isSelected ? DesignColors.primary : inactiveColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  color: isSelected ? DesignColors.primary : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
