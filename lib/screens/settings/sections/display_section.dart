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
import '../search/settings_search_item.dart';
import '../settings_category.dart';
import '../widgets/settings_section_header.dart';

/// Display（表示）カテゴリ: 外観 / ターミナル表示 / キーオーバーレイ の3グループ。
class DisplaySection extends ConsumerWidget {
  const DisplaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(title: l10n.settingsGroupAppearance),
        ListTile(
          leading: const Icon(Icons.dark_mode),
          title: Text(l10n.settingsTheme),
          subtitle: Text(settings.darkMode ? l10n.themeDark : l10n.themeLight),
          onTap: () async {
            final isDark = await showDialog<bool>(
              context: context,
              builder: (context) => ThemeDialog(isDarkMode: settings.darkMode),
            );
            if (isDark != null) {
              ref.read(settingsProvider.notifier).setDarkMode(isDark);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.settingsLanguage),
          subtitle: Text(_languageLabel(l10n, settings.language)),
          onTap: () => showLanguagePicker(context, ref, settings.language),
        ),
        const Divider(),
        SettingsSectionHeader(title: l10n.settingsGroupTerminal),
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
        SettingsSectionHeader(title: l10n.settingsGroupKeyOverlay),
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

  /// 言語設定の現在値ラベル（A4 規約: AppLocalizations 引数で BuildContext 非依存に統一・DR-11）
  String _languageLabel(AppLocalizations l10n, String value) {
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

/// Display セクションの検索 descriptor（全13項目・3グループ、P2-C6 で並置）。
///
/// 値ラベルは静的選択肢（en/ja 両解決）を descriptor に列挙する。
/// 現在値（subtitle）は動的のためヘイストックに含めない（DR-11・critic H2）。
final List<SettingsSearchItem> displaySearchDescriptors = [
  // --- 外観（Appearance） ---
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 0,
    id: 'theme',
    title: (l10n) => l10n.settingsTheme,
    valueLabels: [(l10n) => l10n.themeDark, (l10n) => l10n.themeLight],
    groupLabel: (l10n) => l10n.settingsGroupAppearance,
    icon: Icons.dark_mode,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 1,
    id: 'language',
    title: (l10n) => l10n.settingsLanguage,
    valueLabels: [
      (l10n) => l10n.languageSystemDescription,
      (l10n) => l10n.languageJapanese,
      (l10n) => l10n.languageEnglish,
    ],
    groupLabel: (l10n) => l10n.settingsGroupAppearance,
    icon: Icons.language,
  ),
  // --- ターミナル表示（Terminal） ---
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 2,
    id: 'showCursor',
    title: (l10n) => l10n.settingsShowCursor,
    description: (l10n) => l10n.settingsShowCursorDescription,
    groupLabel: (l10n) => l10n.settingsGroupTerminal,
    icon: Icons.abc,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 3,
    id: 'adjustMode',
    title: (l10n) => l10n.settingsAdjustMode,
    valueLabels: [
      (l10n) => l10n.settingsAdjustModeAutoFit,
      (l10n) => l10n.settingsAdjustModeAutoResize,
      (l10n) => l10n.settingsAdjustModeNone,
    ],
    groupLabel: (l10n) => l10n.settingsGroupTerminal,
    icon: Icons.tune,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 4,
    id: 'fontSize',
    title: (l10n) => l10n.settingsFontSize,
    groupLabel: (l10n) => l10n.settingsGroupTerminal,
    icon: Icons.text_fields,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 5,
    id: 'fontFamily',
    title: (l10n) => l10n.settingsFontFamily,
    groupLabel: (l10n) => l10n.settingsGroupTerminal,
    icon: Icons.font_download,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 6,
    id: 'minFontSize',
    title: (l10n) => l10n.settingsMinimumFontSize,
    groupLabel: (l10n) => l10n.settingsGroupTerminal,
    icon: Icons.format_size,
  ),
  // --- キーオーバーレイ（Key Overlay） ---
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 7,
    id: 'keyOverlay',
    title: (l10n) => l10n.settingsKeyOverlay,
    description: (l10n) => l10n.settingsKeyOverlayDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.visibility,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 8,
    id: 'modifierKeys',
    title: (l10n) => l10n.settingsModifierKeys,
    description: (l10n) => l10n.settingsModifierKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.keyboard,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 9,
    id: 'specialKeys',
    title: (l10n) => l10n.settingsSpecialKeys,
    description: (l10n) => l10n.settingsSpecialKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.space_bar,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 10,
    id: 'arrowKeys',
    title: (l10n) => l10n.settingsArrowKeys,
    description: (l10n) => l10n.settingsArrowKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.arrow_upward,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 11,
    id: 'shortcutKeys',
    title: (l10n) => l10n.settingsShortcutKeys,
    description: (l10n) => l10n.settingsShortcutKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.shortcut,
  ),
  SettingsSearchItem(
    category: SettingsCategory.display,
    orderInCategory: 12,
    id: 'overlayPosition',
    title: (l10n) => l10n.settingsOverlayPosition,
    valueLabels: [
      (l10n) => l10n.settingsOverlayPositionAboveKeyboard,
      (l10n) => l10n.settingsOverlayPositionCenter,
      (l10n) => l10n.settingsOverlayPositionBelowHeader,
    ],
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.place,
  ),
];
