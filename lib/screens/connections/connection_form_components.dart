import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_colors.dart';

/// フォーム入力フィールドの共有クローム。
///
/// 入力欄 8 箇所に現れていた重複する [InputDecoration] をパラメータ化して
/// 1 箇所に集約する。パラメータ→InputDecoration のマッピングは
/// HEAD（connection_form_screen.dart の各フィールド実装）と 1:1 である。
class ConnectionInputStyle {
  const ConnectionInputStyle._();

  /// 通常フィールド（name / host / port / username / path / deepLinkId）の
  /// 枠: 角丸 12・filled・outline 罫線（enabled/focused あり）。
  static InputDecoration decoration({
    required String hintText,
    required TextStyle hintStyle,
    required Color fillColor,
    required Color outlineColor,
    required Color primaryColor,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outlineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  /// 枠なし（実線なし）フィールド（password / key dropdown）。
  ///
  /// [showFocusedBorder] が false のとき [InputDecoration.focusedBorder] を
  /// 設定しない（key dropdown が該当）。
  static InputDecoration borderlessDecoration({
    String? hintText,
    TextStyle? hintStyle,
    required Color fillColor,
    Color? primaryColor,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool showFocusedBorder = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: showFocusedBorder
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor!),
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

/// セクション見出し（大文字・スペーシング付き）。
class ConnectionSectionHeader extends StatelessWidget {
  const ConnectionSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: mutedColor,
        ),
      ),
    );
  }
}

/// 入力フィールドのラベル（大文字・小さめ）。
class ConnectionFieldLabel extends StatelessWidget {
  const ConnectionFieldLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.spaceGrotesk(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
        color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
      ),
    );
  }
}
