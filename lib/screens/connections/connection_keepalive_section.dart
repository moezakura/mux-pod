import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/design_colors.dart';
import 'connection_form_components.dart';
import 'connection_form_values.dart'
    show maxKeepaliveSeconds, minKeepaliveSeconds;

/// キープアライブセクションの表示（🤝3: ProxySection 後・index 7+ 配置）。
///
/// 接続毎 keepalive プローブタイムアウト（秒）の入力を担う。
/// 空欄 = 未設定（全体設定または自動式に従う）。有効範囲は
/// [minKeepaliveSeconds]..[maxKeepaliveSeconds]。
class ConnectionKeepaliveSection extends StatelessWidget {
  const ConnectionKeepaliveSection({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConnectionSectionHeader(title: context.l10n.connSectionKeepalive),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionFieldLabel(label: context.l10n.connKeepaliveTimeout),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('keepalive_timeout_field'),
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
                decoration: ConnectionInputStyle.decoration(
                  hintText: '10',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    color: mutedColor.withValues(alpha: 0.5),
                  ),
                  fillColor: inputColor,
                  outlineColor: colorScheme.outline.withValues(alpha: 0.2),
                  primaryColor: colorScheme.primary,
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null; // 空欄 = 未設定（自動）
                  }
                  final seconds = int.tryParse(text);
                  if (seconds == null ||
                      seconds < minKeepaliveSeconds ||
                      seconds > maxKeepaliveSeconds) {
                    return context.l10n.connKeepaliveRange;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.connKeepaliveHint,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: mutedColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
