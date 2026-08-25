import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 設定画面の AppBar / 詳細画面タイトルの共通スタイル（Space Grotesk 24）。
class SettingsAppBarTitle extends StatelessWidget {
  final String text;

  const SettingsAppBarTitle({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
        letterSpacing: -0.5,
      ),
    );
  }
}
