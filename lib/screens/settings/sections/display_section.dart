import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/dialogs/font_family_dialog.dart';
import '../../../widgets/dialogs/font_size_dialog.dart';
import '../../../widgets/dialogs/min_font_size_dialog.dart';
import '../../../widgets/dialogs/theme_dialog.dart';
import '../pickers/adjust_mode_picker.dart';
import '../pickers/language_picker.dart';
import '../pickers/overlay_position_picker.dart';
import '../widgets/settings_section_header.dart';

/// Display（表示）カテゴリ: 外観 / ターミナル表示 / キーオーバーレイ の3グループ。
///
/// グループ見出しは一時的に旧 `settingsSection*` キーを参照する
/// （新 `settingsGroup*` キーは P1-C4 で追加されるため・M-3）。
class DisplaySection extends ConsumerWidget {
  const DisplaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          onTap: () => showLanguagePicker(context, ref, settings.language),
        ),
        const Divider(),
        SettingsSectionHeader(title: l10n.settingsSectionTerminal),
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
          onTap: () => showAdjustModePicker(context, ref, settings.adjustMode),
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
                    builder: (context) =>
                        FontSizeDialog(currentSize: settings.fontSize),
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
                : l10n.settingsMinFontSizeNotUsed(settings.minFontSize.toInt()),
          ),
          enabled: settings.isAutoFit,
          onTap: settings.isAutoFit
              ? () async {
                  final size = await showDialog<double>(
                    context: context,
                    builder: (context) =>
                        MinFontSizeDialog(currentSize: settings.minFontSize),
                  );
                  if (size != null) {
                    ref.read(settingsProvider.notifier).setMinFontSize(size);
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
      ],
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
}