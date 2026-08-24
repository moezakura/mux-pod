import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../pickers/clear_host_keys_confirmation.dart';
import '../pickers/output_format_picker.dart';
import '../pickers/resize_preset_picker.dart';
import '../pickers/slider_dialog.dart';
import '../pickers/text_input_dialog.dart';
import '../search/settings_search_item.dart';
import '../settings_category.dart';
import '../widgets/settings_section_header.dart';

/// Connection（接続と転送）カテゴリ: 画像転送グループ + Clear SSH Host Keys（フラット）。
class ConnectionSection extends ConsumerWidget {
  const ConnectionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(title: l10n.settingsGroupImageTransfer),
        ListTile(
          leading: const Icon(Icons.folder),
          title: Text(l10n.settingsRemotePath),
          subtitle: Text(settings.imageRemotePath),
          onTap: () => showTextInputDialog(
            context,
            ref,
            title: l10n.settingsRemotePath,
            currentValue: settings.imageRemotePath,
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setImageRemotePath(v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.image),
          title: Text(l10n.settingsOutputFormat),
          subtitle: Text(settings.imageOutputFormat),
          onTap: () =>
              showOutputFormatPicker(context, ref, settings.imageOutputFormat),
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
          onTap: () =>
              showResizePresetPicker(context, ref, settings.imageResizePreset),
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
              onSave: (v) =>
                  ref.read(settingsProvider.notifier).setImageMaxWidth(v),
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
              onSave: (v) =>
                  ref.read(settingsProvider.notifier).setImageMaxHeight(v),
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
            onSave: (v) =>
                ref.read(settingsProvider.notifier).setImagePathFormat(v),
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
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setImageBracketedPaste(v),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.key_off),
          title: Text(l10n.settingsClearHostKeys),
          subtitle: Text(l10n.settingsClearHostKeysDescription),
          onTap: () => confirmClearHostKeys(context),
        ),
      ],
    );
  }
}

/// Connection セクションの検索 descriptor（全10項目）。
///
/// 画像転送9項目はグループ「画像転送」（Image Transfer）に属し、
/// Clear SSH Host Keys はフラット（1項目グループの階層過剰回避・A2）。
/// JPEG Quality / Resize はゲート項目ではなく、ピッカー値は静的選択肢のみ。
final List<SettingsSearchItem> connectionSearchDescriptors = [
  // --- 画像転送（Image Transfer） ---
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 0,
    id: 'imageRemotePath',
    title: (l10n) => l10n.settingsRemotePath,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.folder,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 1,
    id: 'imageOutputFormat',
    title: (l10n) => l10n.settingsOutputFormat,
    valueLabels: [(_) => 'ORIGINAL', (_) => 'PNG', (_) => 'JPEG'],
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.image,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 2,
    id: 'imageJpegQuality',
    title: (l10n) => l10n.settingsJpegQuality,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.high_quality,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 3,
    id: 'imageResize',
    title: (l10n) => l10n.settingsResize,
    valueLabels: [
      (l10n) => l10n.settingsResizePresetOriginal,
      (l10n) => l10n.settingsResizePresetSmall(480),
      (l10n) => l10n.settingsResizePresetMedium(1080),
      (l10n) => l10n.settingsResizePresetLarge(1920),
      (l10n) => l10n.settingsResizePresetCustom,
    ],
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.photo_size_select_large,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 4,
    id: 'imageMaxWidth',
    title: (l10n) => l10n.settingsMaxWidth,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.open_in_full,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 5,
    id: 'imageMaxHeight',
    title: (l10n) => l10n.settingsMaxHeight,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.open_in_full,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 6,
    id: 'imagePathFormat',
    title: (l10n) => l10n.settingsPathFormat,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.text_format,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 7,
    id: 'imageAutoEnter',
    title: (l10n) => l10n.settingsAutoEnter,
    description: (l10n) => l10n.settingsAutoEnterDescription,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.keyboard_return,
  ),
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 8,
    id: 'imageBracketedPaste',
    title: (l10n) => l10n.settingsBracketedPaste,
    description: (l10n) => l10n.settingsBracketedPasteDescription,
    groupLabel: (l10n) => l10n.settingsGroupImageTransfer,
    icon: Icons.paste,
  ),
  // --- フラット（1項目グループ回避・A2） ---
  SettingsSearchItem(
    category: SettingsCategory.connection,
    orderInCategory: 9,
    id: 'clearHostKeys',
    title: (l10n) => l10n.settingsClearHostKeys,
    description: (l10n) => l10n.settingsClearHostKeysDescription,
    icon: Icons.key_off,
  ),
];
