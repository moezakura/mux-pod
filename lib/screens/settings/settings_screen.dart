import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import 'sections/about_section.dart';
import 'sections/behavior_section.dart';
import 'sections/connection_section.dart';
import 'sections/display_section.dart';

/// 設定画面
///
/// P1-C2 時点では従来の単一スクロール表示を維持する
/// （エントリ分岐・一覧・2ペインは P1-C3 で導入・M-8）。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const DisplaySection(),
                const Divider(),
                const BehaviorSection(),
                const Divider(),
                const ConnectionSection(),
                const Divider(),
                const AboutSection(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 100,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Text(
          l10n.settingsTitle,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}