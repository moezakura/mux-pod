import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../../../theme/design_colors.dart';
import '../../custom_keys/custom_keys_screen.dart';
import '../pickers/overlay_position_picker.dart';
import '../pickers/scroll_send_input_picker.dart';
import '../search/settings_search_item.dart';
import '../settings_category.dart';
import '../widgets/settings_section_header.dart';

/// Behavior（操作）カテゴリ: キーオーバーレイ / 入力 / スクロール送信 の3グループ + フラット。
///
/// - wheelSendVerifiedProvider / settingsScrollSendUnverifiedNote を同梱（L3/D15）。
/// - CJK Mode の iOS 判定は `Theme.of(context).platform` を維持（M6/D12）。
class BehaviorSection extends ConsumerWidget {
  const BehaviorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const Divider(),
        SettingsSectionHeader(title: l10n.settingsGroupInput),
        ListTile(
          leading: const Icon(Icons.apps),
          title: Text(l10n.settingsCustomButtons),
          subtitle: Text(l10n.settingsCustomButtonsDescription),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CustomKeysScreen())),
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
            ref.read(settingsProvider.notifier).setKeepKeyboardOnEnter(value);
          },
        ),
        const Divider(),
        SettingsSectionHeader(title: l10n.settingsGroupScrollSend),
        // inventory: SETTINGS-UI-INPUT-001
        ListTile(
          leading: const Icon(Icons.mouse),
          title: Text(l10n.settingsScrollSendInput),
          subtitle: Text(_scrollSendInputLabel(l10n, settings.scrollSendInput)),
          onTap: () =>
              showScrollSendInputPicker(context, ref, settings.scrollSendInput),
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
        // inventory: SETTINGS-UI-INVERT-001
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.swipe),
          title: Text(l10n.settingsInvertPaneNavigation),
          subtitle: Text(l10n.settingsInvertPaneNavigationDescription),
          value: settings.invertPaneNavigation,
          onChanged: (value) {
            ref.read(settingsProvider.notifier).setInvertPaneNavigation(value);
          },
        ),
      ],
    );
  }

  String _scrollSendInputLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'key':
        return l10n.settingsScrollSendInputKey;
      default:
        return l10n.settingsScrollSendInputWheel;
    }
  }
}

/// Behavior セクションの検索 descriptor（全13項目・3グループ+フラット1）。
///
/// CJK Mode は iOS 限定表示だが、設定として有効な項目のため検索対象に含める（DR-10 と同趣旨）。
final List<SettingsSearchItem> behaviorSearchDescriptors = [
  // --- キーオーバーレイ（Key Overlay） ---
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 0,
    id: 'keyOverlay',
    title: (l10n) => l10n.settingsKeyOverlay,
    description: (l10n) => l10n.settingsKeyOverlayDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.visibility,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 1,
    id: 'modifierKeys',
    title: (l10n) => l10n.settingsModifierKeys,
    description: (l10n) => l10n.settingsModifierKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.keyboard,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 2,
    id: 'specialKeys',
    title: (l10n) => l10n.settingsSpecialKeys,
    description: (l10n) => l10n.settingsSpecialKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.space_bar,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 3,
    id: 'arrowKeys',
    title: (l10n) => l10n.settingsArrowKeys,
    description: (l10n) => l10n.settingsArrowKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.arrow_upward,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 4,
    id: 'shortcutKeys',
    title: (l10n) => l10n.settingsShortcutKeys,
    description: (l10n) => l10n.settingsShortcutKeysDescription,
    groupLabel: (l10n) => l10n.settingsGroupKeyOverlay,
    icon: Icons.shortcut,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 5,
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
  // --- 入力（Input） ---
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 6,
    id: 'customButtons',
    title: (l10n) => l10n.settingsCustomButtons,
    description: (l10n) => l10n.settingsCustomButtonsDescription,
    groupLabel: (l10n) => l10n.settingsGroupInput,
    icon: Icons.apps,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 7,
    id: 'cjkMode',
    title: (l10n) => l10n.settingsCjkMode,
    description: (l10n) => l10n.settingsCjkModeDescription,
    groupLabel: (l10n) => l10n.settingsGroupInput,
    icon: Icons.translate,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 8,
    id: 'keepKeyboardOnEnter',
    title: (l10n) => l10n.settingsKeepKeyboardOnEnter,
    description: (l10n) => l10n.settingsKeepKeyboardOnEnterDescription,
    groupLabel: (l10n) => l10n.settingsGroupInput,
    icon: Icons.keyboard,
  ),
  // --- スクロール送信（Scroll Send） ---
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 9,
    id: 'scrollSendInput',
    title: (l10n) => l10n.settingsScrollSendInput,
    valueLabels: [
      (l10n) => l10n.settingsScrollSendInputWheel,
      (l10n) => l10n.settingsScrollSendInputKey,
    ],
    groupLabel: (l10n) => l10n.settingsGroupScrollSend,
    icon: Icons.mouse,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 10,
    id: 'invertScrollSendDirection',
    title: (l10n) => l10n.settingsInvertScrollSendDirection,
    description: (l10n) => l10n.settingsInvertScrollSendDirectionDesc,
    groupLabel: (l10n) => l10n.settingsGroupScrollSend,
    icon: Icons.swipe,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 11,
    id: 'autoFitZoomOnScrollSend',
    title: (l10n) => l10n.settingsAutoFitZoomOnScrollSend,
    description: (l10n) => l10n.settingsAutoFitZoomOnScrollSendDesc,
    groupLabel: (l10n) => l10n.settingsGroupScrollSend,
    icon: Icons.zoom_out_map,
  ),
  // --- フラット（グループなし） ---
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 12,
    id: 'invertPaneNavigation',
    title: (l10n) => l10n.settingsInvertPaneNavigation,
    description: (l10n) => l10n.settingsInvertPaneNavigationDescription,
    icon: Icons.swipe,
  ),
];
