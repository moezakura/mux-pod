import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../../../theme/design_colors.dart';
import '../../custom_keys/custom_keys_screen.dart';
import '../pickers/orientation_picker.dart';
import '../pickers/refresh_rate_picker.dart';
import '../pickers/scroll_send_input_picker.dart';
import '../search/settings_search_item.dart';
import '../settings_category.dart';

/// Behavior（操作）カテゴリ（フラット・グループ見出しなし）。
///
/// - wheelSendVerifiedProvider / settingsScrollSendUnverifiedNote を同梱（L3/D15）。
/// - CJK Mode の iOS 判定は `Theme.of(context).platform` を維持（M6/D12）。
/// - Haptic Feedback（enableVibration）は既知: 現在この設定はハプティクスに
///   反映されない（A3 注記・別 issue 化推奨）。
class BehaviorSection extends ConsumerWidget {
  const BehaviorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.apps),
          title: Text(l10n.settingsCustomButtons),
          subtitle: Text(l10n.settingsCustomButtonsDescription),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CustomKeysScreen())),
        ),
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
          onTap: () =>
              showOrientationPicker(context, ref, settings.screenOrientation),
        ),
        ListTile(
          leading: const Icon(Icons.speed),
          title: Text(l10n.settingsMaxRefreshRate),
          subtitle: Text(_refreshRateLabel(l10n, settings.refreshRate)),
          onTap: () =>
              showRefreshRatePicker(context, ref, settings.refreshRate),
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
      ],
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

  String _scrollSendInputLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'key':
        return l10n.settingsScrollSendInputKey;
      default:
        return l10n.settingsScrollSendInputWheel;
    }
  }
}

/// Behavior セクションの検索 descriptor（全11項目・フラット）。
///
/// フラットのため groupLabel は null（検索結果 subtitle は所属カテゴリ名表示）。
/// CJK Mode は iOS 限定表示だが、設定として有効な項目のため検索対象に含める（DR-10 と同趣旨）。
/// Haptic Feedback（enableVibration）は既知: ハプティクス未反映（A3 注記）。
final List<SettingsSearchItem> behaviorSearchDescriptors = [
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 0,
    id: 'customButtons',
    title: (l10n) => l10n.settingsCustomButtons,
    description: (l10n) => l10n.settingsCustomButtonsDescription,
    icon: Icons.apps,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 1,
    id: 'hapticFeedback',
    title: (l10n) => l10n.settingsHapticFeedback,
    description: (l10n) => l10n.settingsHapticFeedbackDescription,
    icon: Icons.vibration,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 2,
    id: 'keepScreenOn',
    title: (l10n) => l10n.settingsKeepScreenOn,
    description: (l10n) => l10n.settingsKeepScreenOnDescription,
    icon: Icons.brightness_high,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 3,
    id: 'screenOrientation',
    title: (l10n) => l10n.settingsScreenOrientation,
    valueLabels: [
      (l10n) => l10n.settingsOrientationPortrait,
      (l10n) => l10n.settingsOrientationLandscape,
      (l10n) => l10n.settingsOrientationAuto,
    ],
    icon: Icons.screen_rotation,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 4,
    id: 'maxRefreshRate',
    title: (l10n) => l10n.settingsMaxRefreshRate,
    valueLabels: [
      (l10n) => l10n.settingsRefreshRateAuto,
      (_) => '120 Hz',
      (_) => '90 Hz',
      (_) => '60 Hz',
    ],
    icon: Icons.speed,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 5,
    id: 'invertPaneNavigation',
    title: (l10n) => l10n.settingsInvertPaneNavigation,
    description: (l10n) => l10n.settingsInvertPaneNavigationDescription,
    icon: Icons.swipe,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 6,
    id: 'cjkMode',
    title: (l10n) => l10n.settingsCjkMode,
    description: (l10n) => l10n.settingsCjkModeDescription,
    icon: Icons.translate,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 7,
    id: 'keepKeyboardOnEnter',
    title: (l10n) => l10n.settingsKeepKeyboardOnEnter,
    description: (l10n) => l10n.settingsKeepKeyboardOnEnterDescription,
    icon: Icons.keyboard,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 8,
    id: 'scrollSendInput',
    title: (l10n) => l10n.settingsScrollSendInput,
    valueLabels: [
      (l10n) => l10n.settingsScrollSendInputWheel,
      (l10n) => l10n.settingsScrollSendInputKey,
    ],
    icon: Icons.mouse,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 9,
    id: 'invertScrollSendDirection',
    title: (l10n) => l10n.settingsInvertScrollSendDirection,
    description: (l10n) => l10n.settingsInvertScrollSendDirectionDesc,
    icon: Icons.swipe,
  ),
  SettingsSearchItem(
    category: SettingsCategory.behavior,
    orderInCategory: 10,
    id: 'autoFitZoomOnScrollSend',
    title: (l10n) => l10n.settingsAutoFitZoomOnScrollSend,
    description: (l10n) => l10n.settingsAutoFitZoomOnScrollSendDesc,
    icon: Icons.zoom_out_map,
  ),
];
