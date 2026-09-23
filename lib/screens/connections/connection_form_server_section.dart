import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../services/backend/backend_type.dart';
import '../../theme/design_colors.dart';
import 'connection_form_components.dart';

/// サーバー設定セクションの表示（name / host / Row(port | username) /
/// backend toggle / multiplexer path / deep link ID）。
///
/// 状態を持たない view。コントローラ・値・コールバックは親
/// （[ConnectionFormScreen] の State）から受領する。
/// フィールドの出現順は HEAD と同一に保つ（TextFormField の index 0..6 を
/// 固定している既存テストのため）。
class ConnectionServerSection extends StatelessWidget {
  const ConnectionServerSection({
    super.key,
    required this.nameController,
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.multiplexerPathController,
    required this.deepLinkIdController,
    required this.backend,
    required this.onBackendChanged,
    required this.onHostChanged,
  });

  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController multiplexerPathController;
  final TextEditingController deepLinkIdController;

  /// 選択中の backend（Tmux / Herdr）。
  final BackendType backend;

  /// backend toggle のタップ（選択値を親へ通知）。
  final ValueChanged<BackendType> onBackendChanged;

  /// host 入力欄の変更（親の setState を起動し dot インジケータを更新）。
  final VoidCallback onHostChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConnectionSectionHeader(title: context.l10n.connSectionServer),
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
              // Connection name
              ConnectionFieldLabel(label: context.l10n.connFieldConnectionName),
              const SizedBox(height: 8),
              _buildNameInput(context),
              const SizedBox(height: 16),
              // Host field
              ConnectionFieldLabel(label: context.l10n.connFieldHost),
              const SizedBox(height: 8),
              _buildHostInput(context),
              const SizedBox(height: 16),
              // Port & Username row
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConnectionFieldLabel(label: context.l10n.connFieldPort),
                        const SizedBox(height: 8),
                        _buildPortInput(context),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConnectionFieldLabel(
                          label: context.l10n.connFieldUsername,
                        ),
                        const SizedBox(height: 8),
                        _buildUsernameInput(context),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // backend toggle
              ConnectionFieldLabel(label: context.l10n.connFieldBackend),
              const SizedBox(height: 8),
              _buildBackendToggle(context),
              const SizedBox(height: 16),
              // multiplexer path
              ConnectionFieldLabel(
                label: backend == BackendType.herdr
                    ? context.l10n.connFieldHerdrPath
                    : context.l10n.connFieldMultiplexerPath,
              ),
              const SizedBox(height: 8),
              _buildMultiplexerPathInput(context),
              const SizedBox(height: 16),
              // Deep Link ID
              ConnectionFieldLabel(label: context.l10n.connFieldDeepLinkId),
              const SizedBox(height: 4),
              Text(
                context.l10n.connDeepLinkIdDescription,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 8),
              _buildDeepLinkIdInput(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNameInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return TextFormField(
      controller: nameController,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      decoration: ConnectionInputStyle.decoration(
        hintText: context.l10n.connNameHint,
        hintStyle: GoogleFonts.spaceGrotesk(
          color: mutedColor.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(Icons.label_outline, color: mutedColor, size: 20),
        fillColor: inputColor,
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return context.l10n.connNameRequired;
        }
        return null;
      },
    );
  }

  Widget _buildHostInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return TextFormField(
      controller: hostController,
      keyboardType: TextInputType.url,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      decoration: ConnectionInputStyle.decoration(
        hintText: context.l10n.connHostHint,
        hintStyle: GoogleFonts.jetBrainsMono(
          color: mutedColor.withValues(alpha: 0.5),
        ),
        fillColor: inputColor,
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
        suffixIcon: Container(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: hostController.text.isNotEmpty
                  ? DesignColors.success
                  : mutedColor,
              shape: BoxShape.circle,
              boxShadow: hostController.text.isNotEmpty
                  ? [
                      BoxShadow(
                        color: DesignColors.success.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return context.l10n.connHostRequired;
        }
        return null;
      },
      onChanged: (_) => onHostChanged(),
    );
  }

  Widget _buildPortInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return TextFormField(
      controller: portController,
      keyboardType: TextInputType.number,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      decoration: ConnectionInputStyle.decoration(
        hintText: '22',
        hintStyle: GoogleFonts.jetBrainsMono(
          color: mutedColor.withValues(alpha: 0.5),
        ),
        fillColor: inputColor,
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return context.l10n.connPortRequired;
        }
        final port = int.tryParse(value);
        if (port == null || port < 1 || port > 65535) {
          return context.l10n.connPortInvalid;
        }
        return null;
      },
    );
  }

  Widget _buildUsernameInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return TextFormField(
      controller: usernameController,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      decoration: ConnectionInputStyle.decoration(
        hintText: 'root',
        hintStyle: GoogleFonts.jetBrainsMono(
          color: mutedColor.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(Icons.person_outline, color: mutedColor, size: 20),
        fillColor: inputColor,
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return context.l10n.connUsernameRequired;
        }
        return null;
      },
    );
  }

  Widget _buildMultiplexerPathInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    final isHerdr = backend == BackendType.herdr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: multiplexerPathController,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
          decoration: ConnectionInputStyle.decoration(
            hintText: isHerdr
                ? context.l10n.connMultiplexerPathHint('/usr/local/bin/herdr')
                : context.l10n.connMultiplexerPathHint('/usr/bin/tmux'),
            hintStyle: GoogleFonts.jetBrainsMono(
              color: mutedColor.withValues(alpha: 0.5),
            ),
            prefixIcon: Icon(
              Icons.terminal_outlined,
              color: mutedColor,
              size: 20,
            ),
            fillColor: inputColor,
            outlineColor: colorScheme.outline.withValues(alpha: 0.2),
            primaryColor: colorScheme.primary,
          ),
          validator: (value) {
            if (value != null && value.isNotEmpty && !value.startsWith('/')) {
              return isHerdr
                  ? context.l10n.connAbsolutePathRequired(
                      '/usr/local/bin/herdr',
                    )
                  : context.l10n.connAbsolutePathRequired('/usr/bin/tmux');
            }
            return null;
          },
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.connLeaveEmptyForAutoDetect,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            color: mutedColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildDeepLinkIdInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    final inputColor = isDark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
    return TextFormField(
      controller: deepLinkIdController,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      decoration: ConnectionInputStyle.decoration(
        hintText: context.l10n.connDeepLinkIdHint,
        hintStyle: GoogleFonts.jetBrainsMono(
          color: mutedColor.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(Icons.link, color: mutedColor, size: 20),
        fillColor: inputColor,
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) {
        if (value != null && value.isNotEmpty && value.contains(' ')) {
          return context.l10n.connDeepLinkIdNoSpaces;
        }
        return null;
      },
    );
  }

  Widget _buildBackendToggle(BuildContext context) {
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
              onTap: () => onBackendChanged(BackendType.tmux),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: backend == BackendType.tmux
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: backend == BackendType.tmux
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
                  'Tmux',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: backend == BackendType.tmux
                        ? colorScheme.onPrimary
                        : mutedColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onBackendChanged(BackendType.herdr),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: backend == BackendType.herdr
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: backend == BackendType.herdr
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
                  'Herdr',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: backend == BackendType.herdr
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
}
