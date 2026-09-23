import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/key_provider.dart';
import '../../theme/design_colors.dart';
import 'connection_form_components.dart';

/// 認証セクションの表示（authMethod toggle / password or key dropdown /
/// 破損キー警告）。
///
/// 状態を持たない view。状態とコールバックは親
/// （[ConnectionFormScreen] の State）から受領する。
/// フィールドの出現順は HEAD と同一に保つ（TextFormField の index 0..6 を
/// 固定している既存テストのため）。
class ConnectionAuthSection extends StatelessWidget {
  const ConnectionAuthSection({
    super.key,
    required this.keysState,
    required this.isEditing,
    required this.authMethod,
    required this.selectedKeyId,
    required this.obscurePassword,
    required this.passwordController,
    required this.onAuthMethodChanged,
    required this.onObscurePasswordChanged,
    required this.onKeySelected,
  });

  /// 鍵一覧状態（[KeyNotifier] 由来）。
  final KeysState keysState;

  /// 編集モードかどうか（新規作成時はパスワード必須）。
  final bool isEditing;

  /// 選択中の認証方式（'password' | 'key'）。
  final String authMethod;

  /// 選択中の鍵 ID。
  final String? selectedKeyId;

  /// パスワードをマスクするか。
  final bool obscurePassword;

  final TextEditingController passwordController;

  /// authMethod toggle のタップ（選択値を親へ通知）。
  final ValueChanged<String> onAuthMethodChanged;

  /// パスワード可視性トグルのタップ。
  final VoidCallback onObscurePasswordChanged;

  /// 鍵ドロップダウンの選択（値を親へ通知）。
  final ValueChanged<String?> onKeySelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConnectionSectionHeader(title: context.l10n.connSectionAuth),
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
            children: [
              _buildAuthMethodToggle(context),
              const SizedBox(height: 16),
              if (authMethod == 'password')
                _buildPasswordInput(context)
              else
                _buildKeyDropdown(context, keysState),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuthMethodToggle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: isDark ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onAuthMethodChanged('password'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: authMethod == 'password'
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: authMethod == 'password'
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  context.l10n.connAuthPassword,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: authMethod == 'password'
                        ? colorScheme.onPrimary
                        : mutedColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onAuthMethodChanged('key'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: authMethod == 'key'
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: authMethod == 'key'
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  context.l10n.connAuthPrivateKey,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: authMethod == 'key'
                        ? colorScheme.onPrimary
                        : mutedColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return TextFormField(
      controller: passwordController,
      obscureText: obscurePassword,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      decoration: ConnectionInputStyle.borderlessDecoration(
        hintText: '••••••••••••',
        hintStyle: GoogleFonts.jetBrainsMono(
          color: mutedColor.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(Icons.key, color: mutedColor, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: mutedColor,
            size: 20,
          ),
          onPressed: () => onObscurePasswordChanged(),
        ),
        fillColor: inputColor,
        primaryColor: colorScheme.primary,
        showFocusedBorder: true,
      ),
      validator: (value) {
        if (!isEditing && (value == null || value.isEmpty)) {
          return context.l10n.connPasswordRequired;
        }
        return null;
      },
    );
  }

  Widget _buildKeyDropdown(BuildContext context, KeysState keysState) {
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
        DropdownButtonFormField<String>(
          initialValue: selectedKeyId,
          decoration: ConnectionInputStyle.borderlessDecoration(
            fillColor: inputColor,
            prefixIcon: Icon(
              Icons.vpn_key_outlined,
              color: mutedColor,
              size: 20,
            ),
          ),
          dropdownColor: colorScheme.surface,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
          items: keysState.keys.map((key) {
            final damaged = !key.isAvailable;
            return DropdownMenuItem(
              value: key.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(key.name),
                  if (damaged) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: colorScheme.error,
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onChanged: (value) => onKeySelected(value),
          validator: (value) {
            if (authMethod == 'key' && value == null) {
              return context.l10n.connSelectKeyRequired;
            }
            return null;
          },
          hint: Text(
            keysState.keys.isEmpty
                ? context.l10n.connNoKeysAvailable
                : context.l10n.connSelectKey,
            style: GoogleFonts.spaceGrotesk(color: mutedColor),
          ),
        ),
        if (authMethod == 'key' && keysState.keys.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.connNoKeysFoundAddInKeys,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: colorScheme.error,
            ),
          ),
        ],
        if (authMethod == 'key' &&
            selectedKeyId != null &&
            isKeyDamaged(keysState, selectedKeyId)) ...[
          const SizedBox(height: 8),
          _buildDamagedKeyWarning(context),
        ],
      ],
    );
  }

  /// 破損キー選択中の警告表示
  Widget _buildDamagedKeyWarning(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.l10n.connDamagedKeyWarning,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
