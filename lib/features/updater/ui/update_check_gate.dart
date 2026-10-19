import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../release_info.dart';
import '../update_controller.dart';
import 'update_screen.dart';

/// Wraps the home screen: once per launch, runs the throttled automatic
/// check and offers the update if one is available. Purely additive — it
/// renders [child] unchanged.
class UpdateCheckGate extends ConsumerStatefulWidget {
  const UpdateCheckGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends ConsumerState<UpdateCheckGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheck());
  }

  Future<void> _autoCheck() async {
    final release = await ref
        .read(updateControllerProvider.notifier)
        .autoCheckIfDue();
    if (release == null || !mounted) return;
    await _prompt(release);
  }

  Future<void> _prompt(ReleaseInfo release) async {
    final l10n = context.l10n;
    final choice = await showDialog<_Choice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update),
        title: Text(l10n.updaterDialogTitle),
        content: Text(l10n.updaterAvailable(release.tag)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _Choice.skip),
            child: Text(l10n.updaterSkipVersion),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _Choice.later),
            child: Text(l10n.updaterLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _Choice.view),
            child: Text(l10n.updaterView),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _Choice.skip:
        await ref.read(updateControllerProvider.notifier).skip(release.tag);
      case _Choice.view:
        await Navigator.push(context, UpdateScreen.route());
      case _Choice.later || null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _Choice { skip, later, view }
