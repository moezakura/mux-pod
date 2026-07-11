import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/settings_provider.dart';
import '../../theme/design_colors.dart';
import '../../widgets/dialogs/font_size_dialog.dart';
import '../../widgets/dialogs/font_family_dialog.dart';
import '../../widgets/dialogs/min_font_size_dialog.dart';
import '../../widgets/dialogs/theme_dialog.dart';
import '../../services/version_info.dart';
import 'licenses_screen.dart';

/// 設定画面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _SectionHeader(title: 'Terminal'),
                SwitchListTile(
                  secondary: const Icon(Icons.abc),
                  title: const Text('Show Cursor'),
                  subtitle: const Text('Show terminal cursor indicator'),
                  value: settings.showTerminalCursor,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setShowTerminalCursor(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Adjust Mode'),
                  subtitle: Text(_adjustModeLabel(settings.adjustMode)),
                  onTap: () => _showAdjustModePicker(context, ref, settings.adjustMode),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: const Text('Font Size'),
                  subtitle: Text(
                    settings.isAutoFit
                        ? '${settings.fontSize.toInt()} pt (auto-fit enabled)'
                        : '${settings.fontSize.toInt()} pt',
                  ),
                  enabled: !settings.isAutoFit,
                  onTap: settings.isAutoFit
                      ? null
                      : () async {
                          final size = await showDialog<double>(
                            context: context,
                            builder: (context) => FontSizeDialog(
                              currentSize: settings.fontSize,
                            ),
                          );
                          if (size != null) {
                            ref.read(settingsProvider.notifier).setFontSize(size);
                          }
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.font_download),
                  title: const Text('Font Family'),
                  subtitle: Text(settings.fontFamily),
                  onTap: () async {
                    final family = await showDialog<String>(
                      context: context,
                      builder: (context) => FontFamilyDialog(
                        currentFamily: settings.fontFamily,
                      ),
                    );
                    if (family != null) {
                      ref.read(settingsProvider.notifier).setFontFamily(family);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('Minimum Font Size'),
                  subtitle: Text(
                    settings.isAutoFit
                        ? '${settings.minFontSize.toInt()} pt (auto-fit limit)'
                        : '${settings.minFontSize.toInt()} pt (not used)',
                  ),
                  enabled: settings.isAutoFit,
                  onTap: settings.isAutoFit
                      ? () async {
                          final size = await showDialog<double>(
                            context: context,
                            builder: (context) => MinFontSizeDialog(
                              currentSize: settings.minFontSize,
                            ),
                          );
                          if (size != null) {
                            ref.read(settingsProvider.notifier).setMinFontSize(size);
                          }
                        }
                      : null,
                ),
                const Divider(),
                const _SectionHeader(title: 'Key Overlay'),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility),
                  title: const Text('Key Overlay'),
                  subtitle: const Text('Show key name overlay on special key press'),
                  value: settings.showKeyOverlay,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setShowKeyOverlay(value);
                  },
                ),
                if (settings.showKeyOverlay) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard),
                    title: const Text('Modifier Keys'),
                    subtitle: const Text('Ctrl, Alt, Shift combinations'),
                    value: settings.keyOverlayModifier,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlayModifier(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.space_bar),
                    title: const Text('Special Keys'),
                    subtitle: const Text('ESC, TAB, ENTER, Shift+Enter'),
                    value: settings.keyOverlaySpecial,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlaySpecial(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.arrow_upward),
                    title: const Text('Arrow Keys'),
                    subtitle: const Text('Up, Down, Left, Right'),
                    value: settings.keyOverlayArrow,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlayArrow(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.shortcut),
                    title: const Text('Shortcut Keys'),
                    subtitle: const Text('/, -, 1, 2, 3, 4'),
                    value: settings.keyOverlayShortcut,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlayShortcut(value);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: const Text('Overlay Position'),
                    subtitle: Text(
                      switch (settings.keyOverlayPosition) {
                        'center' => 'Center of terminal',
                        'belowHeader' => 'Below header',
                        _ => 'Above keyboard',
                      },
                    ),
                    onTap: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('Overlay Position'),
                          children: [
                            _buildPositionOption(context, 'aboveKeyboard', 'Above Keyboard', settings.keyOverlayPosition),
                            _buildPositionOption(context, 'center', 'Center of Terminal', settings.keyOverlayPosition),
                            _buildPositionOption(context, 'belowHeader', 'Below Header', settings.keyOverlayPosition),
                          ],
                        ),
                      );
                      if (result != null) {
                        ref.read(settingsProvider.notifier).setKeyOverlayPosition(result);
                      }
                    },
                  ),
                ],
                const Divider(),
                const _SectionHeader(title: 'Behavior'),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Haptic Feedback'),
                  subtitle: const Text('Vibrate on key press'),
                  value: settings.enableVibration,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setEnableVibration(value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.brightness_high),
                  title: const Text('Keep Screen On'),
                  subtitle: const Text('Prevent screen from sleeping'),
                  value: settings.keepScreenOn,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setKeepScreenOn(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.screen_rotation),
                  title: const Text('Screen Orientation'),
                  subtitle: Text(_orientationLabel(settings.screenOrientation)),
                  onTap: () => _showOrientationPicker(
                    context,
                    ref,
                    settings.screenOrientation,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe),
                  title: const Text('Invert Pane Navigation'),
                  subtitle: const Text('Reverse swipe direction for pane switching'),
                  value: settings.invertPaneNavigation,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setInvertPaneNavigation(value);
                  },
                ),
                const Divider(),
                const _SectionHeader(title: 'Appearance'),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('Theme'),
                  subtitle: Text(settings.darkMode ? 'Dark' : 'Light'),
                  onTap: () async {
                    final isDark = await showDialog<bool>(
                      context: context,
                      builder: (context) => ThemeDialog(
                        isDarkMode: settings.darkMode,
                      ),
                    );
                    if (isDark != null) {
                      ref.read(settingsProvider.notifier).setDarkMode(isDark);
                    }
                  },
                ),
                const Divider(),
                const _SectionHeader(title: 'Image Transfer'),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('Remote Path'),
                  subtitle: Text(settings.imageRemotePath),
                  onTap: () => _showTextInputDialog(
                    context, ref,
                    title: 'Remote Path',
                    currentValue: settings.imageRemotePath,
                    onSave: (v) => ref.read(settingsProvider.notifier).setImageRemotePath(v),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.image),
                  title: const Text('Output Format'),
                  subtitle: Text(settings.imageOutputFormat),
                  onTap: () => _showFormatPicker(context, ref, settings.imageOutputFormat),
                ),
                if (settings.imageOutputFormat == 'jpeg')
                  ListTile(
                    leading: const Icon(Icons.high_quality),
                    title: const Text('JPEG Quality'),
                    subtitle: Text('${settings.imageJpegQuality}%'),
                    onTap: () => _showSliderDialog(
                      context, ref,
                      title: 'JPEG Quality',
                      value: settings.imageJpegQuality.toDouble(),
                      min: 1, max: 100,
                      onSave: (v) => ref.read(settingsProvider.notifier).setImageJpegQuality(v.round()),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_size_select_large),
                  title: const Text('Resize'),
                  subtitle: Text(settings.imageResizePreset.toUpperCase()),
                  onTap: () => _showResizePresetPicker(context, ref, settings.imageResizePreset),
                ),
                if (settings.imageResizePreset == 'custom') ...[
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: const Text('Max Width'),
                    subtitle: Text('${settings.imageMaxWidth}px'),
                    onTap: () => _showNumberInputDialog(
                      context, ref,
                      title: 'Max Width',
                      currentValue: settings.imageMaxWidth,
                      onSave: (v) => ref.read(settingsProvider.notifier).setImageMaxWidth(v),
                    ),
                  ),
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: const Text('Max Height'),
                    subtitle: Text('${settings.imageMaxHeight}px'),
                    onTap: () => _showNumberInputDialog(
                      context, ref,
                      title: 'Max Height',
                      currentValue: settings.imageMaxHeight,
                      onSave: (v) => ref.read(settingsProvider.notifier).setImageMaxHeight(v),
                    ),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.text_format),
                  title: const Text('Path Format'),
                  subtitle: Text(settings.imagePathFormat),
                  onTap: () => _showTextInputDialog(
                    context, ref,
                    title: 'Path Format',
                    currentValue: settings.imagePathFormat,
                    hint: 'Use {path} as placeholder. e.g. @{path}',
                    onSave: (v) => ref.read(settingsProvider.notifier).setImagePathFormat(v),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_return),
                  title: const Text('Auto Enter'),
                  subtitle: const Text('Send Enter after path injection'),
                  value: settings.imageAutoEnter,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setImageAutoEnter(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.paste),
                  title: const Text('Bracketed Paste'),
                  subtitle: const Text('Use bracketed paste protocol'),
                  value: settings.imageBracketedPaste,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setImageBracketedPaste(v),
                ),
                const Divider(),
                const _SectionHeader(title: 'About'),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('Version'),
                  subtitle: Text(VersionInfo.version),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Source Code'),
                  subtitle: const Text('github.com/moezakura/mux-pod'),
                  onTap: () async {
                    final url = Uri.parse('https://github.com/moezakura/mux-pod');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Licenses'),
                  subtitle: const Text('Open source licenses'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LicensesScreen(),
                      ),
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showTextInputDialog(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String currentValue,
    String? hint,
    required void Function(String) onSave,
  }) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showNumberInputDialog(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required int currentValue,
    required void Function(int) onSave,
  }) {
    final controller = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null) onSave(v);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSliderDialog(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required double value,
    required double min,
    required double max,
    required void Function(double) onSave,
  }) {
    var current = value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(value: current, min: min, max: max, onChanged: (v) => setState(() => current = v)),
              Text('${current.round()}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                onSave(current);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFormatPicker(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Output Format'),
        children: [
          for (final format in ['original', 'png', 'jpeg'])
            RadioListTile<String>(
              title: Text(format.toUpperCase()),
              value: format,
              groupValue: current,
              onChanged: (v) {
                if (v != null) ref.read(settingsProvider.notifier).setImageOutputFormat(v);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  String _adjustModeLabel(String mode) {
    switch (mode) {
      case 'autoFit':
        return 'Auto Fit';
      case 'autoResize':
        return 'Auto Resize';
      default:
        return 'None';
    }
  }

  void _showAdjustModePicker(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Adjust Mode'),
        children: [
          for (final entry in [
            ('none', 'None', 'Manual font and pane size'),
            ('autoFit', 'Auto Fit', 'Adjust font size to fit screen width'),
            ('autoResize', 'Auto Resize', 'Resize tmux pane to fit screen'),
          ])
            RadioListTile<String>(
              title: Text(entry.$2),
              subtitle: Text(entry.$3),
              value: entry.$1,
              groupValue: current,
              onChanged: (v) {
                if (v != null) ref.read(settingsProvider.notifier).setAdjustMode(v);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  String _orientationLabel(String value) {
    switch (value) {
      case 'portrait':
        return 'Portrait';
      case 'landscape':
        return 'Landscape';
      default:
        return 'Auto (follow device)';
    }
  }

  void _showOrientationPicker(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Screen Orientation'),
        children: [
          for (final entry in [
            ('auto', 'Auto', 'Follow device rotation'),
            ('portrait', 'Portrait', 'Lock to portrait'),
            ('landscape', 'Landscape', 'Lock to landscape'),
          ])
            RadioListTile<String>(
              title: Text(entry.$2),
              subtitle: Text(entry.$3),
              value: entry.$1,
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setScreenOrientation(v);
                }
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  void _showResizePresetPicker(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Resize Preset'),
        children: [
          for (final entry in [
            ('original', 'Original'),
            ('small', 'Small (480px)'),
            ('medium', 'Medium (1080px)'),
            ('large', 'Large (1920px)'),
            ('custom', 'Custom'),
          ])
            RadioListTile<String>(
              title: Text(entry.$2),
              value: entry.$1,
              groupValue: current,
              onChanged: (v) {
                if (v != null) ref.read(settingsProvider.notifier).setImageResizePreset(v);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
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
          'Settings',
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

  Widget _buildPositionOption(
    BuildContext context,
    String value,
    String label,
    String currentValue,
  ) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(
            value == currentValue ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? DesignColors.textMuted : DesignColors.textMutedLight,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

