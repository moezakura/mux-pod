import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/design_colors.dart';

/// 設定画面のセクション（グループ）見出し。
///
/// toUpperCase 廃止 + Semantics(header: true)（F-2・D6）。
/// 大文字化は ja では意味がなく、セマンティクス上も見出しとして公開する。
class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
