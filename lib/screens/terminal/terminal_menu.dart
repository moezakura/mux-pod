import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../settings/settings_screen.dart';
import '../../theme/design_colors.dart';
import '../../l10n/l10n_ext.dart';
import 'widgets/ansi_terminal_model.dart';

/// ターミナルメニュー（BottomSheet）。
///
/// モード切替（Normal / Scroll Send / Select・排他的単一選択・D9）、ズーム
/// リセット、設定画面遷移、切断の各アクションを持つ。データ・コールバックは
/// すべて呼び出し側（root State）から注入され、このクラスは表示と発火のみ
/// を担う。シートが閉じた後は [onSheetClosed] を呼ぶ（`_scrollToBottomKey`
/// の再表示など）。
class TerminalMenu {
  TerminalMenu._();

  /// モード切替（Normal / Scroll Send / Select の 3 択・排他的単一選択・D9）。
  ///
  /// Switch は 3 モードを表現できないため廃止（RadioListTile は Flutter
  /// 3.32+ で deprecated のため不使用）。選択中モードは warning 色 + 太字
  /// + check アイコンでハイライトする。
  static Future<void> show({
    required BuildContext context,
    required TerminalMode mode,
    required bool isZoomed,
    required double effectiveZoom,
    required VoidCallback onExitToNormalMode,
    required VoidCallback onEnterScrollSendMode,
    required VoidCallback onEnterSelectMode,
    required VoidCallback onResetZoom,
    required VoidCallback onOpenSettings,
    required VoidCallback onDisconnect,
    required VoidCallback onSheetClosed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBgColor = isDark
        ? DesignColors.surfaceDark
        : DesignColors.surfaceLight;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedTextColor = isDark ? Colors.white38 : Colors.black38;
    final inactiveIconColor = isDark ? Colors.white60 : Colors.black45;

    Widget modeTile({
      required IconData icon,
      required String label,
      required String subtitle,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(
          icon,
          color: selected ? DesignColors.warning : inactiveIconColor,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? DesignColors.warning : textColor,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: mutedTextColor, fontSize: 12),
        ),
        trailing: selected
            ? const Icon(Icons.check, size: 18, color: DesignColors.warning)
            : null,
        onTap: onTap,
      );
    }

    return showModalBottomSheet(
      context: context,
      backgroundColor: menuBgColor,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: DesignColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.termTerminalOptions,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300,
              ),
              // モード切り替え（3 択・排他的単一選択・D9。modeTile は上部で定義）
              modeTile(
                icon: Icons.keyboard,
                label: context.l10n.termNormalMode,
                subtitle: context.l10n.termNormalModeSubtitle,
                selected: mode == TerminalMode.normal,
                onTap: () {
                  onExitToNormalMode();
                  Navigator.pop(context);
                },
              ),
              modeTile(
                // inventory: TERM-SCROLL-008
                icon: Icons.swipe_up,
                label: context.l10n.termScrollSendMode,
                subtitle: context.l10n.termScrollSendModeSubtitle,
                selected: mode == TerminalMode.scrollSend,
                onTap: () {
                  onEnterScrollSendMode();
                  Navigator.pop(context);
                },
              ),
              modeTile(
                icon: Icons.unfold_more,
                label: context.l10n.termSelectMode,
                subtitle: context.l10n.termSelectModeSubtitle,
                selected: mode == TerminalMode.select,
                onTap: () {
                  onEnterSelectMode();
                  Navigator.pop(context);
                },
              ),
              // ズームリセット
              ListTile(
                leading: Icon(
                  Icons.zoom_out_map,
                  color: isZoomed ? DesignColors.warning : inactiveIconColor,
                ),
                title: Text(
                  context.l10n.termResetZoom,
                  style: TextStyle(
                    color: isZoomed ? textColor : mutedTextColor,
                  ),
                ),
                subtitle: Text(
                  isZoomed
                      ? context.l10n.termCurrentZoom(
                          (effectiveZoom * 100).round(),
                        )
                      : context.l10n.termPinchToZoom,
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                enabled: isZoomed,
                onTap: isZoomed
                    ? () {
                        onResetZoom();
                        Navigator.pop(context);
                      }
                    : null,
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300,
              ),
              // 設定画面へ
              ListTile(
                leading: Icon(Icons.settings, color: inactiveIconColor),
                title: Text(
                  context.l10n.termSettings,
                  style: TextStyle(color: textColor),
                ),
                subtitle: Text(
                  context.l10n.termSettingsSubtitle,
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF2A2B36) : Colors.grey.shade300,
              ),
              // 切断ボタン
              ListTile(
                leading: Icon(
                  Icons.power_settings_new,
                  color: DesignColors.error,
                ),
                title: Text(
                  context.l10n.termDisconnect,
                  style: TextStyle(
                    color: DesignColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  context.l10n.termCloseSshConnection,
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // inventory: TERM-DIALOG-011
                  onDisconnect();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ).then((_) {
      onSheetClosed();
    });
  }
}
