// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
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
    final l10n = context.l10n;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionHeader(title: l10n.settingsSectionTerminal),
                SwitchListTile(
                  secondary: const Icon(Icons.abc),
                  title: Text(l10n.settingsShowCursor),
                  subtitle: Text(l10n.settingsShowCursorDescription),
                  value: settings.showTerminalCursor,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setShowTerminalCursor(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.settingsAdjustMode),
                  subtitle: Text(_adjustModeLabel(l10n, settings.adjustMode)),
                  onTap: () => _showAdjustModePicker(context, ref, settings.adjustMode),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: Text(l10n.settingsFontSize),
                  subtitle: Text(
                    settings.isAutoFit
                        ? l10n.settingsFontSizeAutoFit(settings.fontSize.toInt())
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
                  title: Text(l10n.settingsFontFamily),
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
                  title: Text(l10n.settingsMinimumFontSize),
                  subtitle: Text(
                    settings.isAutoFit
                        ? l10n.settingsMinFontSizeAutoFitLimit(settings.minFontSize.toInt())
                        : l10n.settingsMinFontSizeNotUsed(settings.minFontSize.toInt()),
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
                _SectionHeader(title: l10n.settingsSectionKeyOverlay),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility),
                  title: Text(l10n.settingsKeyOverlay),
                  subtitle: Text(l10n.settingsKeyOverlayDescription),
                  value: settings.showKeyOverlay,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setShowKeyOverlay(value);
                  },
                ),
                if (settings.showKeyOverlay) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard),
                    title: Text(l10n.settingsModifierKeys),
                    subtitle: Text(l10n.settingsModifierKeysDescription),
                    value: settings.keyOverlayModifier,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlayModifier(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.space_bar),
                    title: Text(l10n.settingsSpecialKeys),
                    subtitle: Text(l10n.settingsSpecialKeysDescription),
                    value: settings.keyOverlaySpecial,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlaySpecial(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.arrow_upward),
                    title: Text(l10n.settingsArrowKeys),
                    subtitle: Text(l10n.settingsArrowKeysDescription),
                    value: settings.keyOverlayArrow,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlayArrow(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.shortcut),
                    title: Text(l10n.settingsShortcutKeys),
                    subtitle: Text(l10n.settingsShortcutKeysDescription),
                    value: settings.keyOverlayShortcut,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setKeyOverlayShortcut(value);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(l10n.settingsOverlayPosition),
                    subtitle: Text(
                      switch (settings.keyOverlayPosition) {
                        'center' => l10n.settingsOverlayPositionCenter,
                        'belowHeader' => l10n.settingsOverlayPositionBelowHeader,
                        _ => l10n.settingsOverlayPositionAboveKeyboard,
                      },
                    ),
                    onTap: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: Text(l10n.settingsOverlayPosition),
                          children: [
                            _buildPositionOption(context, 'aboveKeyboard', l10n.settingsOverlayPositionAboveKeyboard, settings.keyOverlayPosition),
                            _buildPositionOption(context, 'center', l10n.settingsOverlayPositionCenter, settings.keyOverlayPosition),
                            _buildPositionOption(context, 'belowHeader', l10n.settingsOverlayPositionBelowHeader, settings.keyOverlayPosition),
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
                _SectionHeader(title: l10n.settingsSectionBehavior),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: Text(l10n.settingsHapticFeedback),
                  subtitle: Text(l10n.settingsHapticFeedbackDescription),
                  value: settings.enableVibration,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setEnableVibration(value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.brightness_high),
                  title: Text(l10n.settingsKeepScreenOn),
                  subtitle: Text(l10n.settingsKeepScreenOnDescription),
                  value: settings.keepScreenOn,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setKeepScreenOn(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.screen_rotation),
                  title: Text(l10n.settingsScreenOrientation),
                  subtitle: Text(_orientationLabel(l10n, settings.screenOrientation)),
                  onTap: () => _showOrientationPicker(
                    context,
                    ref,
                    settings.screenOrientation,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text(l10n.settingsMaxRefreshRate),
                  subtitle: Text(_refreshRateLabel(l10n, settings.refreshRate)),
                  onTap: () => _showRefreshRatePicker(
                    context,
                    ref,
                    settings.refreshRate,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe),
                  title: Text(l10n.settingsInvertPaneNavigation),
                  subtitle: Text(l10n.settingsInvertPaneNavigationDescription),
                  value: settings.invertPaneNavigation,
                  onChanged: (value) {
                    ref.read(settingsProvider.notifier).setInvertPaneNavigation(value);
                  },
                ),
                const Divider(),
                _SectionHeader(title: l10n.settingsSectionAppearance),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: Text(l10n.settingsTheme),
                  subtitle: Text(settings.darkMode ? l10n.themeDark : l10n.themeLight),
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
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(context.l10n.settingsLanguage),
                  subtitle: Text(_languageLabel(context, settings.language)),
                  onTap: () => _showLanguagePicker(context, ref, settings.language),
                ),
                const Divider(),
                _SectionHeader(title: l10n.settingsSectionImageTransfer),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(l10n.settingsRemotePath),
                  subtitle: Text(settings.imageRemotePath),
                  onTap: () => _showTextInputDialog(
                    context, ref,
                    title: l10n.settingsRemotePath,
                    currentValue: settings.imageRemotePath,
                    onSave: (v) => ref.read(settingsProvider.notifier).setImageRemotePath(v),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.image),
                  title: Text(l10n.settingsOutputFormat),
                  subtitle: Text(settings.imageOutputFormat),
                  onTap: () => _showFormatPicker(context, ref, settings.imageOutputFormat),
                ),
                if (settings.imageOutputFormat == 'jpeg')
                  ListTile(
                    leading: const Icon(Icons.high_quality),
                    title: Text(l10n.settingsJpegQuality),
                    subtitle: Text('${settings.imageJpegQuality}%'),
                    onTap: () => _showSliderDialog(
                      context, ref,
                      title: l10n.settingsJpegQuality,
                      value: settings.imageJpegQuality.toDouble(),
                      min: 1, max: 100,
                      onSave: (v) => ref.read(settingsProvider.notifier).setImageJpegQuality(v.round()),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_size_select_large),
                  title: Text(l10n.settingsResize),
                  subtitle: Text(settings.imageResizePreset.toUpperCase()),
                  onTap: () => _showResizePresetPicker(context, ref, settings.imageResizePreset),
                ),
                if (settings.imageResizePreset == 'custom') ...[
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: Text(l10n.settingsMaxWidth),
                    subtitle: Text('${settings.imageMaxWidth}px'),
                    onTap: () => _showNumberInputDialog(
                      context, ref,
                      title: l10n.settingsMaxWidth,
                      currentValue: settings.imageMaxWidth,
                      onSave: (v) => ref.read(settingsProvider.notifier).setImageMaxWidth(v),
                    ),
                  ),
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: Text(l10n.settingsMaxHeight),
                    subtitle: Text('${settings.imageMaxHeight}px'),
                    onTap: () => _showNumberInputDialog(
                      context, ref,
                      title: l10n.settingsMaxHeight,
                      currentValue: settings.imageMaxHeight,
                      onSave: (v) => ref.read(settingsProvider.notifier).setImageMaxHeight(v),
                    ),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.text_format),
                  title: Text(l10n.settingsPathFormat),
                  subtitle: Text(settings.imagePathFormat),
                  onTap: () => _showTextInputDialog(
                    context, ref,
                    title: l10n.settingsPathFormat,
                    currentValue: settings.imagePathFormat,
                    hint: l10n.settingsPathFormatHint('{path}'),
                    onSave: (v) => ref.read(settingsProvider.notifier).setImagePathFormat(v),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_return),
                  title: Text(l10n.settingsAutoEnter),
                  subtitle: Text(l10n.settingsAutoEnterDescription),
                  value: settings.imageAutoEnter,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setImageAutoEnter(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.paste),
                  title: Text(l10n.settingsBracketedPaste),
                  subtitle: Text(l10n.settingsBracketedPasteDescription),
                  value: settings.imageBracketedPaste,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setImageBracketedPaste(v),
                ),
                const Divider(),
                _SectionHeader(title: l10n.settingsSectionAbout),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: Text(l10n.settingsVersion),
                  subtitle: Text(VersionInfo.version),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(l10n.settingsSourceCode),
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
                  title: Text(l10n.settingsLicenses),
                  subtitle: Text(l10n.settingsLicensesDescription),
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
    final l10n = context.l10n;
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(l10n.commonSave),
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
    final l10n = context.l10n;
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null) onSave(v);
              Navigator.pop(ctx);
            },
            child: Text(l10n.commonSave),
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
    final l10n = context.l10n;
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.commonCancel)),
            FilledButton(
              onPressed: () {
                onSave(current);
                Navigator.pop(ctx);
              },
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  void _showFormatPicker(BuildContext context, WidgetRef ref, String current) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsOutputFormat),
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

  String _adjustModeLabel(AppLocalizations l10n, String mode) {
    switch (mode) {
      case 'autoFit':
        return l10n.settingsAdjustModeAutoFit;
      case 'autoResize':
        return l10n.settingsAdjustModeAutoResize;
      default:
        return l10n.settingsAdjustModeNone;
    }
  }

  void _showAdjustModePicker(BuildContext context, WidgetRef ref, String current) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsAdjustMode),
        children: [
          for (final entry in [
            ('none', l10n.settingsAdjustModeNone, l10n.settingsAdjustModeNoneDescription),
            ('autoFit', l10n.settingsAdjustModeAutoFit, l10n.settingsAdjustModeAutoFitDescription),
            ('autoResize', l10n.settingsAdjustModeAutoResize, l10n.settingsAdjustModeAutoResizeDescription),
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

  String _orientationLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'portrait':
        return l10n.settingsOrientationPortrait;
      case 'landscape':
        return l10n.settingsOrientationLandscape;
      default:
        return l10n.settingsOrientationAuto;
    }
  }

  /// 言語設定の現在値ラベル
  String _languageLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'ja':
        return l10n.languageJapanese;
      case 'en':
        return l10n.languageEnglish;
      default:
        // 'system' は説明付き表記（例: System (follow device)）
        return l10n.languageSystemDescription;
    }
  }

  /// 言語設定ピッカー: System / 日本語 / English の3択
  void _showLanguagePicker(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return SimpleDialog(
          title: Text(l10n.settingsLanguage),
          children: [
            for (final entry in [
              ('system', l10n.languageSystem, l10n.languageSystemDescription),
              ('ja', l10n.languageJapanese, null),
              ('en', l10n.languageEnglish, null),
            ])
              RadioListTile<String>(
                title: Text(entry.$2),
                subtitle: entry.$3 != null ? Text(entry.$3!) : null,
                value: entry.$1,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    ref.read(settingsProvider.notifier).setLanguage(v);
                  }
                  Navigator.pop(ctx);
                },
              ),
          ],
        );
      },
    );
  }

  void _showOrientationPicker(BuildContext context, WidgetRef ref, String current) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsScreenOrientation),
        children: [
          for (final entry in [
            ('auto', l10n.settingsOrientationAuto, l10n.settingsOrientationAutoDescription),
            ('portrait', l10n.settingsOrientationPortrait, l10n.settingsOrientationPortraitDescription),
            ('landscape', l10n.settingsOrientationLandscape, l10n.settingsOrientationLandscapeDescription),
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

  String _refreshRateLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case '120':
        return '120 Hz';
      case '90':
        return '90 Hz';
      case '60':
        return '60 Hz';
      default:
        return l10n.settingsRefreshRateAuto;
    }
  }

  void _showRefreshRatePicker(BuildContext context, WidgetRef ref, String current) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsMaxRefreshRate),
        children: [
          for (final entry in [
            ('auto', l10n.settingsRefreshRateAuto, l10n.settingsRefreshRateAutoDescription),
            ('120', '120 Hz', l10n.settingsRefreshRateCap(120)),
            ('90', '90 Hz', l10n.settingsRefreshRateCap(90)),
            ('60', '60 Hz', l10n.settingsRefreshRateCap(60)),
          ])
            RadioListTile<String>(
              title: Text(entry.$2),
              subtitle: Text(entry.$3),
              value: entry.$1,
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setRefreshRate(v);
                }
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  void _showResizePresetPicker(BuildContext context, WidgetRef ref, String current) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsResizePreset),
        children: [
          for (final entry in [
            ('original', l10n.settingsResizePresetOriginal),
            ('small', l10n.settingsResizePresetSmall(480)),
            ('medium', l10n.settingsResizePresetMedium(1080)),
            ('large', l10n.settingsResizePresetLarge(1920)),
            ('custom', l10n.settingsResizePresetCustom),
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
