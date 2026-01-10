import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/enums.dart';
import '../../../providers/settings_provider.dart';

/// ターミナル設定セクション
class TerminalSettingsSection extends ConsumerWidget {
  const TerminalSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terminal = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.terminal, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Terminal',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Font Family
          ListTile(
            title: const Text('Font Family'),
            subtitle: Text(terminal.fontFamilyName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showFontFamilyPicker(context, ref, terminal.fontFamily),
          ),

          // Font Size
          ListTile(
            title: const Text('Font Size'),
            subtitle: Text('${terminal.fontSize.toInt()} pt'),
            trailing: SizedBox(
              width: 160,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: terminal.fontSize > terminal.minFontSize
                        ? () => notifier.setFontSize(terminal.fontSize - 1)
                        : null,
                  ),
                  Text(
                    '${terminal.fontSize.toInt()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: terminal.fontSize < terminal.maxFontSize
                        ? () => notifier.setFontSize(terminal.fontSize + 1)
                        : null,
                  ),
                ],
              ),
            ),
          ),

          // Color Theme
          ListTile(
            title: const Text('Color Theme'),
            subtitle: Text(_getThemeName(terminal.colorTheme)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showColorThemePicker(context, ref, terminal.colorTheme),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Cursor Blink
          SwitchListTile(
            title: const Text('Cursor Blink'),
            value: terminal.cursorBlink,
            onChanged: (value) async {
              await notifier.updateTerminalSettings(
                terminal.copyWith(cursorBlink: value),
              );
            },
          ),

          // Special Keys Bar
          SwitchListTile(
            title: const Text('Special Keys Bar'),
            subtitle: const Text('Show ESC, CTRL, ALT keys'),
            value: terminal.showSpecialKeysBar,
            onChanged: (value) async {
              await notifier.setShowSpecialKeysBar(value);
            },
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Bell Sound
          SwitchListTile(
            title: const Text('Bell Sound'),
            value: terminal.bellSound,
            onChanged: (value) async {
              await notifier.updateTerminalSettings(
                terminal.copyWith(bellSound: value),
              );
            },
          ),

          // Bell Vibrate
          SwitchListTile(
            title: const Text('Bell Vibrate'),
            value: terminal.bellVibrate,
            onChanged: (value) async {
              await notifier.updateTerminalSettings(
                terminal.copyWith(bellVibrate: value),
              );
            },
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Scrollback Lines
          ListTile(
            title: const Text('Scrollback Lines'),
            subtitle: Text('${terminal.scrollbackLines} lines'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showScrollbackPicker(context, ref, terminal.scrollbackLines),
          ),

          // Pinch to Zoom
          SwitchListTile(
            title: const Text('Pinch to Zoom'),
            subtitle: const Text('Use two-finger gesture to zoom'),
            value: terminal.pinchToZoom,
            onChanged: (value) async {
              await notifier.updateTerminalSettings(
                terminal.copyWith(pinchToZoom: value),
              );
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _getThemeName(ColorTheme theme) {
    return switch (theme) {
      ColorTheme.dracula => 'Dracula',
      ColorTheme.solarized => 'Solarized Dark',
      ColorTheme.monokai => 'Monokai',
      ColorTheme.nord => 'Nord',
      ColorTheme.custom => 'Custom',
    };
  }

  void _showFontFamilyPicker(BuildContext context, WidgetRef ref, FontFamily current) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Font Family',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...FontFamily.values.map((family) {
              final name = switch (family) {
                FontFamily.jetBrainsMono => 'JetBrains Mono',
                FontFamily.firaCode => 'Fira Code',
                FontFamily.meslo => 'Meslo',
                FontFamily.hackGen => 'HackGen',
                FontFamily.plemolJP => 'PlemolJP',
              };
              return ListTile(
                title: Text(name),
                trailing: family == current
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(appSettingsProvider.notifier).setFontFamily(family);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showColorThemePicker(BuildContext context, WidgetRef ref, ColorTheme current) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Color Theme',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...ColorTheme.values.map((theme) {
              return ListTile(
                leading: _buildThemePreview(theme),
                title: Text(_getThemeName(theme)),
                trailing: theme == current
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(appSettingsProvider.notifier).setColorTheme(theme);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildThemePreview(ColorTheme theme) {
    final colors = switch (theme) {
      ColorTheme.dracula => [
          const Color(0xFF282A36),
          const Color(0xFFBD93F9),
          const Color(0xFF50FA7B),
        ],
      ColorTheme.solarized => [
          const Color(0xFF002B36),
          const Color(0xFF268BD2),
          const Color(0xFF859900),
        ],
      ColorTheme.monokai => [
          const Color(0xFF272822),
          const Color(0xFFF92672),
          const Color(0xFFA6E22E),
        ],
      ColorTheme.nord => [
          const Color(0xFF2E3440),
          const Color(0xFF88C0D0),
          const Color(0xFFA3BE8C),
        ],
      ColorTheme.custom => [
          const Color(0xFF1E1E1E),
          const Color(0xFF569CD6),
          const Color(0xFF4EC9B0),
        ],
    };

    return Container(
      width: 40,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        children: colors.map((c) => Expanded(child: Container(color: c))).toList(),
      ),
    );
  }

  void _showScrollbackPicker(BuildContext context, WidgetRef ref, int current) {
    final options = [1000, 5000, 10000, 20000, 50000];

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Scrollback Lines',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((lines) {
              return ListTile(
                title: Text('$lines lines'),
                trailing: lines == current
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  final terminal = ref.read(terminalSettingsProvider);
                  await ref.read(appSettingsProvider.notifier).updateTerminalSettings(
                        terminal.copyWith(scrollbackLines: lines),
                      );
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
