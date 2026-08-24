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
import '../custom_keys/custom_keys_screen.dart';
import 'pickers/adjust_mode_picker.dart';
import 'pickers/clear_host_keys_confirmation.dart';
import 'pickers/language_picker.dart';
import 'pickers/orientation_picker.dart';
import 'pickers/output_format_picker.dart';
import 'pickers/overlay_position_picker.dart';
import 'pickers/refresh_rate_picker.dart';
import 'pickers/resize_preset_picker.dart';
import 'pickers/scroll_send_input_picker.dart';
import 'pickers/slider_dialog.dart';
import 'pickers/text_input_dialog.dart';
import 'widgets/settings_section_header.dart';

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
                SettingsSectionHeader(title: l10n.settingsSectionTerminal),
                SwitchListTile(
                  secondary: const Icon(Icons.abc),
                  title: Text(l10n.settingsShowCursor),
                  subtitle: Text(l10n.settingsShowCursorDescription),
                  value: settings.showTerminalCursor,
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .setShowTerminalCursor(value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.settingsAdjustMode),
                  subtitle: Text(_adjustModeLabel(l10n, settings.adjustMode)),
                  onTap: () =>
                      showAdjustModePicker(context, ref, settings.adjustMode),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: Text(l10n.settingsFontSize),
                  subtitle: Text(
                    settings.isAutoFit
                        ? l10n.settingsFontSizeAutoFit(
                            settings.fontSize.toInt(),
                          )
                        : '${settings.fontSize.toInt()} pt',
                  ),
                  enabled: !settings.isAutoFit,
                  onTap: settings.isAutoFit
                      ? null
                      : () async {
                          final size = await showDialog<double>(
                            context: context,
                            builder: (context) =>
                                FontSizeDialog(currentSize: settings.fontSize),
                          );
                          if (size != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .setFontSize(size);
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
                      builder: (context) =>
                          FontFamilyDialog(currentFamily: settings.fontFamily),
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
                        ? l10n.settingsMinFontSizeAutoFitLimit(
                            settings.minFontSize.toInt(),
                          )
                        : l10n.settingsMinFontSizeNotUsed(
                            settings.minFontSize.toInt(),
                          ),
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
                            ref
                                .read(settingsProvider.notifier)
                                .setMinFontSize(size);
                          }
                        }
                      : null,
                ),
                const Divider(),
                SettingsSectionHeader(title: l10n.settingsSectionKeyOverlay),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility),
                  title: Text(l10n.settingsKeyOverlay),
                  subtitle: Text(l10n.settingsKeyOverlayDescription),
                  value: settings.showKeyOverlay,
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .setShowKeyOverlay(value);
                  },
                ),
                if (settings.showKeyOverlay) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard),
                    title: Text(l10n.settingsModifierKeys),
                    subtitle: Text(l10n.settingsModifierKeysDescription),
                    value: settings.keyOverlayModifier,
                    onChanged: (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setKeyOverlayModifier(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.space_bar),
                    title: Text(l10n.settingsSpecialKeys),
                    subtitle: Text(l10n.settingsSpecialKeysDescription),
                    value: settings.keyOverlaySpecial,
                    onChanged: (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setKeyOverlaySpecial(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.arrow_upward),
                    title: Text(l10n.settingsArrowKeys),
                    subtitle: Text(l10n.settingsArrowKeysDescription),
                    value: settings.keyOverlayArrow,
                    onChanged: (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setKeyOverlayArrow(value);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.shortcut),
                    title: Text(l10n.settingsShortcutKeys),
                    subtitle: Text(l10n.settingsShortcutKeysDescription),
                    value: settings.keyOverlayShortcut,
                    onChanged: (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setKeyOverlayShortcut(value);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(l10n.settingsOverlayPosition),
                    subtitle: Text(switch (settings.keyOverlayPosition) {
                      'center' => l10n.settingsOverlayPositionCenter,
                      'belowHeader' => l10n.settingsOverlayPositionBelowHeader,
                      _ => l10n.settingsOverlayPositionAboveKeyboard,
                    }),
                    onTap: () => showOverlayPositionPicker(
                      context,
                      ref,
                      settings.keyOverlayPosition,
                    ),
                  ),
                ],
                const Divider(),
                // TODO(i18n): localize once arb keys exist for these entries.
                const SettingsSectionHeader(title: 'Buttons'),
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text('Custom Buttons'),
                  subtitle: const Text(
                    'Add buttons and action sequences to the key bar',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CustomKeysScreen()),
                  ),
                ),
                const Divider(),
                const SettingsSectionHeader(title: 'Security'),
                ListTile(
                  leading: const Icon(Icons.key_off),
                  title: const Text('Clear SSH Host Keys'),
                  subtitle: const Text('Reset saved server fingerprints'),
                  onTap: () => confirmClearHostKeys(context),
                ),
                const Divider(),
                SettingsSectionHeader(title: l10n.settingsSectionBehavior),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: Text(l10n.settingsHapticFeedback),
                  subtitle: Text(l10n.settingsHapticFeedbackDescription),
                  value: settings.enableVibration,
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .setEnableVibration(value);
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
                  subtitle: Text(
                    _orientationLabel(l10n, settings.screenOrientation),
                  ),
                  onTap: () => showOrientationPicker(
                    context,
                    ref,
                    settings.screenOrientation,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text(l10n.settingsMaxRefreshRate),
                  subtitle: Text(_refreshRateLabel(l10n, settings.refreshRate)),
                  onTap: () => showRefreshRatePicker(
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
                    ref
                        .read(settingsProvider.notifier)
                        .setInvertPaneNavigation(value);
                  },
                ),
                // CJK Mode: iOSのCJK系IMEでDirectInputが多重送信される場合の
                // 回避手段として旧来（v0.7.0-pre4）の確定送信挙動へ戻す（iOSのみ表示）
                if (Theme.of(context).platform == TargetPlatform.iOS)
                  SwitchListTile(
                    secondary: const Icon(Icons.translate),
                    title: Text(l10n.settingsCjkMode),
                    subtitle: Text(l10n.settingsCjkModeDescription),
                    value: settings.cjkMode,
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setCjkMode(value);
                    },
                  ),
                // DirectInput: Enter送信後もソフトウェアキーボードを開いたままにする
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard),
                  title: Text(l10n.settingsKeepKeyboardOnEnter),
                  subtitle: Text(l10n.settingsKeepKeyboardOnEnterDescription),
                  value: settings.keepKeyboardOnEnter,
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .setKeepKeyboardOnEnter(value);
                  },
                ),
                // inventory: SETTINGS-UI-INPUT-001
                ListTile(
                  leading: const Icon(Icons.mouse),
                  title: Text(l10n.settingsScrollSendInput),
                  subtitle: Text(
                    _scrollSendInputLabel(l10n, settings.scrollSendInput),
                  ),
                  onTap: () => showScrollSendInputPicker(
                    context,
                    ref,
                    settings.scrollSendInput,
                  ),
                ),
                // inventory: SETTINGS-UI-INPUT-NOTE-001
                if (!ref.watch(wheelSendVerifiedProvider))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: DesignColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.settingsScrollSendUnverifiedNote,
                            style: const TextStyle(
                              color: DesignColors.warning,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // inventory: SETTINGS-UI-INVERT-001
                SwitchListTile(
                  secondary: const Icon(Icons.swipe),
                  title: Text(l10n.settingsInvertScrollSendDirection),
                  subtitle: Text(l10n.settingsInvertScrollSendDirectionDesc),
                  value: settings.invertScrollSendDirection,
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .setInvertScrollSendDirection(value);
                  },
                ),
                // inventory: SETTINGS-UI-AUTO-FIT-ZOOM-001
                SwitchListTile(
                  secondary: const Icon(Icons.zoom_out_map),
                  title: Text(l10n.settingsAutoFitZoomOnScrollSend),
                  subtitle: Text(l10n.settingsAutoFitZoomOnScrollSendDesc),
                  value: settings.autoFitZoomOnScrollSend,
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .setAutoFitZoomOnScrollSend(value);
                  },
                ),
                const Divider(),
                SettingsSectionHeader(title: l10n.settingsSectionAppearance),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: Text(l10n.settingsTheme),
                  subtitle: Text(
                    settings.darkMode ? l10n.themeDark : l10n.themeLight,
                  ),
                  onTap: () async {
                    final isDark = await showDialog<bool>(
                      context: context,
                      builder: (context) =>
                          ThemeDialog(isDarkMode: settings.darkMode),
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
                  onTap: () =>
                      showLanguagePicker(context, ref, settings.language),
                ),
                const Divider(),
                SettingsSectionHeader(
                  title: l10n.settingsSectionImageTransfer,
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(l10n.settingsRemotePath),
                  subtitle: Text(settings.imageRemotePath),
                  onTap: () => showTextInputDialog(
                    context,
                    ref,
                    title: l10n.settingsRemotePath,
                    currentValue: settings.imageRemotePath,
                    onSave: (v) => ref
                        .read(settingsProvider.notifier)
                        .setImageRemotePath(v),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.image),
                  title: Text(l10n.settingsOutputFormat),
                  subtitle: Text(settings.imageOutputFormat),
                  onTap: () => showOutputFormatPicker(
                    context,
                    ref,
                    settings.imageOutputFormat,
                  ),
                ),
                if (settings.imageOutputFormat == 'jpeg')
                  ListTile(
                    leading: const Icon(Icons.high_quality),
                    title: Text(l10n.settingsJpegQuality),
                    subtitle: Text('${settings.imageJpegQuality}%'),
                    onTap: () => showSliderDialog(
                      context,
                      ref,
                      title: l10n.settingsJpegQuality,
                      value: settings.imageJpegQuality.toDouble(),
                      min: 1,
                      max: 100,
                      onSave: (v) => ref
                          .read(settingsProvider.notifier)
                          .setImageJpegQuality(v.round()),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_size_select_large),
                  title: Text(l10n.settingsResize),
                  subtitle: Text(settings.imageResizePreset.toUpperCase()),
                  onTap: () => showResizePresetPicker(
                    context,
                    ref,
                    settings.imageResizePreset,
                  ),
                ),
                if (settings.imageResizePreset == 'custom') ...[
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: Text(l10n.settingsMaxWidth),
                    subtitle: Text('${settings.imageMaxWidth}px'),
                    onTap: () => showNumberInputDialog(
                      context,
                      ref,
                      title: l10n.settingsMaxWidth,
                      currentValue: settings.imageMaxWidth,
                      onSave: (v) => ref
                          .read(settingsProvider.notifier)
                          .setImageMaxWidth(v),
                    ),
                  ),
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: Text(l10n.settingsMaxHeight),
                    subtitle: Text('${settings.imageMaxHeight}px'),
                    onTap: () => showNumberInputDialog(
                      context,
                      ref,
                      title: l10n.settingsMaxHeight,
                      currentValue: settings.imageMaxHeight,
                      onSave: (v) => ref
                          .read(settingsProvider.notifier)
                          .setImageMaxHeight(v),
                    ),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.text_format),
                  title: Text(l10n.settingsPathFormat),
                  subtitle: Text(settings.imagePathFormat),
                  onTap: () => showTextInputDialog(
                    context,
                    ref,
                    title: l10n.settingsPathFormat,
                    currentValue: settings.imagePathFormat,
                    hint: l10n.settingsPathFormatHint('{path}'),
                    onSave: (v) => ref
                        .read(settingsProvider.notifier)
                        .setImagePathFormat(v),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_return),
                  title: Text(l10n.settingsAutoEnter),
                  subtitle: Text(l10n.settingsAutoEnterDescription),
                  value: settings.imageAutoEnter,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setImageAutoEnter(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.paste),
                  title: Text(l10n.settingsBracketedPaste),
                  subtitle: Text(l10n.settingsBracketedPasteDescription),
                  value: settings.imageBracketedPaste,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setImageBracketedPaste(v),
                ),
                const Divider(),
                SettingsSectionHeader(title: l10n.settingsSectionAbout),
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
                    final url = Uri.parse(
                      'https://github.com/moezakura/mux-pod',
                    );
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
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

  String _scrollSendInputLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'key':
        return l10n.settingsScrollSendInputKey;
      default:
        return l10n.settingsScrollSendInputWheel;
    }
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