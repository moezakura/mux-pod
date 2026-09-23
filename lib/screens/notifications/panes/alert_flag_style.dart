import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/tmux/tmux_models.dart';

import '../../../theme/design_colors.dart';

/// [TmuxWindowFlag] → 見た目 の純入出力マッピング（表示ロジックの分離）。
///
/// アラートカード（`alert_pane_card.dart`）から引数付きで呼ばれる。
/// 状態を持たないトップレベル関数のため単体テストが容易。

IconData alertFlagIcon(TmuxWindowFlag? flag) {
  return switch (flag) {
    TmuxWindowFlag.bell => Icons.notifications_active,
    TmuxWindowFlag.activity => Icons.trending_up,
    TmuxWindowFlag.silence => Icons.notifications_off,
    _ => Icons.notifications_outlined,
  };
}

Color alertFlagIconColor(TmuxWindowFlag? flag) {
  return switch (flag) {
    TmuxWindowFlag.bell => DesignColors.error,
    TmuxWindowFlag.activity => Colors.orange,
    TmuxWindowFlag.silence => Colors.grey,
    _ => Colors.grey,
  };
}

Color alertFlagBackgroundColor(TmuxWindowFlag? flag, bool isDark) {
  return switch (flag) {
    TmuxWindowFlag.bell => DesignColors.error.withValues(
      alpha: isDark ? 0.15 : 0.1,
    ),
    TmuxWindowFlag.activity => Colors.orange.withValues(
      alpha: isDark ? 0.15 : 0.1,
    ),
    TmuxWindowFlag.silence => Colors.grey.withValues(
      alpha: isDark ? 0.15 : 0.1,
    ),
    _ => isDark ? DesignColors.borderDark : DesignColors.borderLight,
  };
}

Color alertFlagBorderColor(TmuxWindowFlag? flag, bool isDark) {
  return switch (flag) {
    TmuxWindowFlag.bell => DesignColors.error.withValues(alpha: 0.3),
    TmuxWindowFlag.activity => Colors.orange.withValues(alpha: 0.3),
    TmuxWindowFlag.silence => Colors.grey.withValues(alpha: 0.3),
    _ => Colors.transparent,
  };
}

Color alertFlagBadgeBackground(TmuxWindowFlag? flag, bool isDark) {
  return switch (flag) {
    TmuxWindowFlag.bell => DesignColors.error.withValues(
      alpha: isDark ? 0.2 : 0.1,
    ),
    TmuxWindowFlag.activity => Colors.orange.withValues(
      alpha: isDark ? 0.2 : 0.1,
    ),
    TmuxWindowFlag.silence => Colors.grey.withValues(alpha: isDark ? 0.2 : 0.1),
    _ => isDark ? DesignColors.borderDark : DesignColors.borderLight,
  };
}

Color alertFlagBadgeBorder(TmuxWindowFlag? flag, bool isDark) {
  return switch (flag) {
    TmuxWindowFlag.bell => DesignColors.error.withValues(
      alpha: isDark ? 0.4 : 0.3,
    ),
    TmuxWindowFlag.activity => Colors.orange.withValues(
      alpha: isDark ? 0.4 : 0.3,
    ),
    TmuxWindowFlag.silence => Colors.grey.withValues(alpha: isDark ? 0.4 : 0.3),
    _ => isDark ? DesignColors.borderDark : DesignColors.borderLight,
  };
}

String alertFlagLabel(AppLocalizations l10n, TmuxWindowFlag? flag) {
  return switch (flag) {
    TmuxWindowFlag.bell => l10n.notifFlagBell,
    TmuxWindowFlag.activity => l10n.notifFlagActivity,
    TmuxWindowFlag.silence => l10n.notifFlagSilence,
    _ => l10n.notifFlagAlert,
  };
}
