import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_ext.dart';
import '../../providers/key_provider.dart';
import '../../services/connection/proxy_config.dart';
import '../../theme/design_colors.dart';
import 'connection_form_components.dart';

/// hop 行の入力状態（view 用の参照・チェーン順）。
///
/// controller の所有者は親（[ConnectionFormScreen] の State）で、
/// このクラスは参照を運ぶだけのデータ。
class ProxyHopRowData {
  const ProxyHopRowData({
    required this.index,
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.passwordController,
    required this.authMethod,
    required this.selectedKeyId,
  });

  /// チェーン順（0 始まり）。proxy_password キーの hopIndex と対応する。
  final int index;

  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;

  /// パスワード入力（編集時の空欄 = 既存値維持）。
  final TextEditingController passwordController;

  /// 認証方式（`'password'` | `'key'`）。
  final String authMethod;

  /// 鍵認証時に選択された鍵 ID。
  final String? selectedKeyId;
}

/// ジャンプホストセクションの表示（🤝1: AuthSection 後・index 7+ 配置）。
///
/// 🤝2 multi-hop: hop 動的行（追加 / 削除・上限 [maxProxyHops]）・hop ごとの
/// Host / Port / Username / 認証方式 / credential 入力を担う。
/// 状態を持たない view。状態とコールバックは親から受領する。
/// 既存 `TextFormField.at(0..6)` の index 固定テストを壊さないよう、
/// 本セクションの全フィールドは [Key] ベースで参照する。
class ConnectionProxySection extends StatelessWidget {
  const ConnectionProxySection({
    super.key,
    required this.keysState,
    required this.isEditing,
    required this.enabled,
    required this.hopRows,
    required this.forwardHostController,
    required this.forwardPortController,
    required this.onEnabledChanged,
    required this.onHopAdded,
    required this.onHopRemoved,
    required this.onHopAuthChanged,
    required this.onHopKeySelected,
  });

  /// 鍵一覧状態（AuthSection と同一の [KeyNotifier] 由来）。
  final KeysState keysState;

  /// 編集モードかどうか（新規時は hop パスワード必須・AuthSection と同一規約）。
  final bool isEditing;

  /// ジャンプホスト経由スイッチの状態。
  final bool enabled;

  /// hop 行一覧（チェーン順）。
  final List<ProxyHopRowData> hopRows;

  final TextEditingController forwardHostController;
  final TextEditingController forwardPortController;

  /// スイッチの切替（選択値を親へ通知）。
  final ValueChanged<bool> onEnabledChanged;

  /// 「ホップを追加」のタップ。
  final VoidCallback onHopAdded;

  /// hop 行の削除タップ（[ProxyHopRowData.index] を親へ通知）。
  final ValueChanged<int> onHopRemoved;

  /// hop の認証方式変更（index と方式を親へ通知）。
  final void Function(int index, String method) onHopAuthChanged;

  /// hop の鍵選択（index と鍵 ID を親へ通知）。
  final void Function(int index, String? keyId) onHopKeySelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConnectionSectionHeader(title: context.l10n.connSectionProxy),
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
              Text(
                context.l10n.connProxyScopeHint,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? DesignColors.textMuted
                          : DesignColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 8),
              _buildEnableSwitch(context),
              if (enabled) ...[
                const SizedBox(height: 8),
                for (final row in hopRows) ...[
                  _buildHopRow(context, row),
                  const SizedBox(height: 16),
                ],
                _buildForwardTarget(context),
                const SizedBox(height: 8),
                _buildAddHopButton(context),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// port 入力の正規化（空欄 = 22）を重複判定に使うための共通化。
  static int _normalizedPort(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 22;
    return int.tryParse(text) ?? 0;
  }

  /// チェーン内 host:port 重複の検証（🤝2・connector validate と共用文言）。
  String? _validateHopDuplicate(
    BuildContext context,
    List<ProxyHopRowData> rows,
    int index,
    String? value,
  ) {
    final host = value?.trim() ?? '';
    if (host.isEmpty) {
      return context.l10n.connHostRequired;
    }
    final myPort = _normalizedPort(rows[index].portController.text);
    for (final other in rows) {
      if (other.index == index) continue;
      final otherHost = other.hostController.text.trim();
      if (otherHost.isEmpty) continue;
      if (otherHost == host &&
          _normalizedPort(other.portController.text) == myPort) {
        return context.l10n.connProxyDuplicateHop(host, myPort);
      }
    }
    return null;
  }

  Widget _buildEnableSwitch(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.connProxyEnable,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        Switch(
          key: const Key('proxy_enable_switch'),
          value: enabled,
          onChanged: onEnabledChanged,
        ),
      ],
    );
  }

  Widget _buildHopRow(BuildContext context, ProxyHopRowData row) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.05 : 0.03,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.connProxyHopLabel(row.index + 1),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? DesignColors.textMuted
                            : DesignColors.textMutedLight,
                  ),
                ),
              ),
              if (hopRows.length > 1)
                IconButton(
                  key: Key('proxy_hop_remove_${row.index}'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: context.l10n.connProxyRemoveHop,
                  onPressed: () => onHopRemoved(row.index),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ConnectionFieldLabel(label: context.l10n.connProxyHost),
          const SizedBox(height: 8),
          _buildHopHostInput(context, row),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConnectionFieldLabel(label: context.l10n.connProxyPort),
                    const SizedBox(height: 8),
                    _buildHopPortInput(context, row),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConnectionFieldLabel(label: context.l10n.connProxyUsername),
                    const SizedBox(height: 8),
                    _buildHopUsernameInput(context, row),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHopAuthToggle(context, row),
          const SizedBox(height: 8),
          if (row.authMethod == 'key')
            _buildHopKeyDropdown(context, row)
          else
            _buildHopPasswordInput(context, row),
        ],
      ),
    );
  }

  Widget _buildHopHostInput(BuildContext context, ProxyHopRowData row) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      key: Key('proxy_hop_host_${row.index}'),
      controller: row.hostController,
      keyboardType: TextInputType.url,
      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: colorScheme.onSurface),
      decoration: ConnectionInputStyle.decoration(
        hintText: 'bastion.example.com',
        hintStyle: GoogleFonts.jetBrainsMono(
          color: _mutedColor(context).withValues(alpha: 0.5),
        ),
        fillColor: _inputColor(context),
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) => _validateHopDuplicate(
        context,
        hopRows,
        row.index,
        value,
      ),
    );
  }

  Widget _buildHopPortInput(BuildContext context, ProxyHopRowData row) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      key: Key('proxy_hop_port_${row.index}'),
      controller: row.portController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: colorScheme.onSurface),
      decoration: ConnectionInputStyle.decoration(
        hintText: '22',
        hintStyle: GoogleFonts.jetBrainsMono(
          color: _mutedColor(context).withValues(alpha: 0.5),
        ),
        fillColor: _inputColor(context),
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) {
          return null; // 空欄は既定 22 扱い
        }
        final port = int.tryParse(text);
        if (port == null || port < 1 || port > 65535) {
          return context.l10n.connPortInvalid;
        }
        return null;
      },
    );
  }

  Widget _buildHopUsernameInput(BuildContext context, ProxyHopRowData row) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      key: Key('proxy_hop_username_${row.index}'),
      controller: row.usernameController,
      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: colorScheme.onSurface),
      decoration: ConnectionInputStyle.decoration(
        hintText: 'root',
        hintStyle: GoogleFonts.jetBrainsMono(
          color: _mutedColor(context).withValues(alpha: 0.5),
        ),
        fillColor: _inputColor(context),
        outlineColor: colorScheme.outline.withValues(alpha: 0.2),
        primaryColor: colorScheme.primary,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return context.l10n.connUsernameRequired;
        }
        return null;
      },
    );
  }

  Widget _buildHopAuthToggle(BuildContext context, ProxyHopRowData row) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: Key('proxy_hop_auth_password_${row.index}'),
            onTap: () => onHopAuthChanged(row.index, 'password'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: row.authMethod == 'password'
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(
                        alpha: isDark ? 0.1 : 0.05,
                      ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.l10n.connAuthPassword,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: row.authMethod == 'password'
                      ? colorScheme.onPrimary
                      : _mutedColor(context),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: Key('proxy_hop_auth_key_${row.index}'),
            onTap: () => onHopAuthChanged(row.index, 'key'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: row.authMethod == 'key'
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(
                        alpha: isDark ? 0.1 : 0.05,
                      ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.l10n.connAuthPrivateKey,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: row.authMethod == 'key'
                      ? colorScheme.onPrimary
                      : _mutedColor(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHopPasswordInput(BuildContext context, ProxyHopRowData row) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = _mutedColor(context);
    return TextFormField(
      key: Key('proxy_hop_password_${row.index}'),
      controller: row.passwordController,
      obscureText: true,
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
        fillColor: _inputColor(context),
        primaryColor: colorScheme.primary,
        showFocusedBorder: true,
      ),
      validator: (value) {
        // 編集時の空欄 = 既存値維持（削除しない）。
        if (!isEditing && (value == null || value.isEmpty)) {
          return context.l10n.connPasswordRequired;
        }
        return null;
      },
    );
  }

  Widget _buildHopKeyDropdown(BuildContext context, ProxyHopRowData row) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = _mutedColor(context);
    final availableKeys = keysState.keys;
    return DropdownButtonFormField<String>(
      key: Key('proxy_hop_key_${row.index}'),
      initialValue: availableKeys.any((k) => k.id == row.selectedKeyId)
          ? row.selectedKeyId
          : null,
      dropdownColor: colorScheme.surface,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      items: availableKeys
          .map(
            (key) => DropdownMenuItem<String>(
              value: key.id,
              child: Text(key.name),
            ),
          )
          .toList(),
      onChanged: (keyId) => onHopKeySelected(row.index, keyId),
      decoration: ConnectionInputStyle.borderlessDecoration(
        fillColor: _inputColor(context),
        prefixIcon: Icon(
          Icons.vpn_key_outlined,
          color: mutedColor,
          size: 20,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return context.l10n.connSelectKeyRequired;
        }
        return null;
      },
      hint: Text(
        availableKeys.isEmpty
            ? context.l10n.connNoKeysAvailable
            : context.l10n.connSelectKey,
        style: GoogleFonts.spaceGrotesk(color: mutedColor),
      ),
    );
  }

  Widget _buildForwardTarget(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConnectionFieldLabel(label: context.l10n.connProxyForwardTarget),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                key: const Key('proxy_forward_host'),
                controller: forwardHostController,
                keyboardType: TextInputType.url,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
                decoration: ConnectionInputStyle.decoration(
                  hintText: '10.0.0.5',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    color: _mutedColor(context).withValues(alpha: 0.5),
                  ),
                  fillColor: _inputColor(context),
                  outlineColor: colorScheme.outline.withValues(alpha: 0.2),
                  primaryColor: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextFormField(
                key: const Key('proxy_forward_port'),
                controller: forwardPortController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
                decoration: ConnectionInputStyle.decoration(
                  hintText: '22',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    color: _mutedColor(context).withValues(alpha: 0.5),
                  ),
                  fillColor: _inputColor(context),
                  outlineColor: colorScheme.outline.withValues(alpha: 0.2),
                  primaryColor: colorScheme.primary,
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null; // 空欄は target ポート扱い
                  }
                  final port = int.tryParse(text);
                  if (port == null || port < 1 || port > 65535) {
                    return context.l10n.connPortInvalid;
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.connProxyForwardHint,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            color: _mutedColor(context).withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildAddHopButton(BuildContext context) {
    final canAdd = hopRows.length < maxProxyHops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          key: const Key('proxy_add_hop'),
          onPressed: canAdd ? onHopAdded : null,
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.l10n.connProxyAddHop),
        ),
        if (!canAdd) ...[
          const SizedBox(height: 4),
          Text(
            context.l10n.connProxyMaxHops(maxProxyHops),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: _mutedColor(context).withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  Color _mutedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
  }

  Color _inputColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? DesignColors.inputDark
        : DesignColors.inputLight;
  }
}
