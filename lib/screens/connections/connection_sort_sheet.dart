import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/connection_ui_state.dart'
    show ConnectionSortOption, connectionSortProvider;
import '../../theme/design_colors.dart';

/// ソート選択のボトムシートを表示する。
///
/// 元は接続一覧シェルの private メソッド（`_showSortDialog`）。
/// シェル（AppBar のソートボタン）から呼び出される。
void showSortDialog(BuildContext context, WidgetRef ref) {
  final currentSort = ref.read(connectionSortProvider);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet(
    context: context,
    backgroundColor: isDark
        ? DesignColors.surfaceDark
        : DesignColors.surfaceLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      final sheetColorScheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.sort, color: sheetColorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.connSortTitle,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: sheetColorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark
                  ? DesignColors.borderDark
                  : DesignColors.borderLight,
            ),
            SortOptionTile(
              title: context.l10n.connSortNameAsc,
              option: ConnectionSortOption.nameAsc,
              currentOption: currentSort,
              onTap: () {
                ref
                    .read(connectionSortProvider.notifier)
                    .setSort(ConnectionSortOption.nameAsc);
                Navigator.pop(context);
              },
            ),
            SortOptionTile(
              title: context.l10n.connSortNameDesc,
              option: ConnectionSortOption.nameDesc,
              currentOption: currentSort,
              onTap: () {
                ref
                    .read(connectionSortProvider.notifier)
                    .setSort(ConnectionSortOption.nameDesc);
                Navigator.pop(context);
              },
            ),
            SortOptionTile(
              title: context.l10n.connSortLastConnectedDesc,
              option: ConnectionSortOption.lastConnectedDesc,
              currentOption: currentSort,
              onTap: () {
                ref
                    .read(connectionSortProvider.notifier)
                    .setSort(ConnectionSortOption.lastConnectedDesc);
                Navigator.pop(context);
              },
            ),
            SortOptionTile(
              title: context.l10n.connSortLastConnectedAsc,
              option: ConnectionSortOption.lastConnectedAsc,
              currentOption: currentSort,
              onTap: () {
                ref
                    .read(connectionSortProvider.notifier)
                    .setSort(ConnectionSortOption.lastConnectedAsc);
                Navigator.pop(context);
              },
            ),
            SortOptionTile(
              title: context.l10n.connSortHostAsc,
              option: ConnectionSortOption.hostAsc,
              currentOption: currentSort,
              onTap: () {
                ref
                    .read(connectionSortProvider.notifier)
                    .setSort(ConnectionSortOption.hostAsc);
                Navigator.pop(context);
              },
            ),
            SortOptionTile(
              title: context.l10n.connSortHostDesc,
              option: ConnectionSortOption.hostDesc,
              currentOption: currentSort,
              onTap: () {
                ref
                    .read(connectionSortProvider.notifier)
                    .setSort(ConnectionSortOption.hostDesc);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

/// ソートオプションの選択タイル
class SortOptionTile extends StatelessWidget {
  final String title;
  final ConnectionSortOption option;
  final ConnectionSortOption currentOption;
  final VoidCallback onTap;

  const SortOptionTile({
    super.key,
    required this.title,
    required this.option,
    required this.currentOption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = option == currentOption;
    return ListTile(
      title: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
