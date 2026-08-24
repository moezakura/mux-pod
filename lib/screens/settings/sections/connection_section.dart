import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../pickers/clear_host_keys_confirmation.dart';
import '../pickers/output_format_picker.dart';
import '../pickers/resize_preset_picker.dart';
import '../pickers/slider_dialog.dart';
import '../pickers/text_input_dialog.dart';
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