import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../update_controller.dart';
import 'update_screen.dart';

/// Entry point to the updater for the settings "About" category.
/// Renders nothing on platforms without APK updates.
class UpdateSettingsTile extends ConsumerWidget {
  const UpdateSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    if (state.phase == UpdatePhase.unsupported) return const SizedBox.shrink();

    final l10n = context.l10n;
    final tag = state.release?.tag ?? '';
    final hasUpdate = const {
      UpdatePhase.available,
      UpdatePhase.downloading,
      UpdatePhase.verifying,
      UpdatePhase.ready,
      UpdatePhase.installing,
    }.contains(state.phase);

    return ListTile(
      leading: Badge(
        isLabelVisible: hasUpdate,
        child: const Icon(Icons.system_update),
      ),
      title: Text(l10n.updaterTitle),
      subtitle: Text(
        hasUpdate ? l10n.updaterAvailable(tag) : l10n.updaterCheckNow,
      ),
      onTap: () => Navigator.push(context, UpdateScreen.route()),
    );
  }
}
