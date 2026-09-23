import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/design_colors.dart';

/// 接続一覧の「検索0件」表示。
///
/// 元は `ConnectionsScreen._buildNoResultsState`（private）。
/// 検索クリアは呼出元（シェル）が [_onClearSearch] で提供する
/// （検索状態 provider はシェルが所有するため）。
Widget buildConnectionNoResultsState(
  BuildContext context, {
  required VoidCallback onClearSearch,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colorScheme = Theme.of(context).colorScheme;
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.surfaceDark
                : DesignColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? DesignColors.borderDark
                  : DesignColors.borderLight,
            ),
          ),
          child: Icon(
            Icons.search_off,
            size: 64,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.l10n.connNoResults,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: isDark
                ? DesignColors.textSecondary
                : DesignColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.connNoResultsHint,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onClearSearch,
          icon: const Icon(Icons.clear),
          label: Text(context.l10n.connClearSearch),
          style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
        ),
      ],
    ),
  );
}

/// 接続一覧の「空」表示。
///
/// 元は `ConnectionsScreen._buildEmptyState`（private）。
Widget buildConnectionEmptyState(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.surfaceDark
                : DesignColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? DesignColors.borderDark
                  : DesignColors.borderLight,
            ),
          ),
          child: Icon(
            Icons.dns_outlined,
            size: 64,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.l10n.connEmpty,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: isDark
                ? DesignColors.textSecondary
                : DesignColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.connEmptyHint,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
        ),
      ],
    ),
  );
}
