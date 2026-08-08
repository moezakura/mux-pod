import 'package:flutter/material.dart';

/// The composer's "+" menu: photo upload and plan mode.
///
/// Actions are delivered through callbacks (instead of a result object)
/// so a plan-mode toggle applies even when the sheet is dismissed by a
/// barrier tap afterwards.
class RemoteUiPlusMenuSheet {
  RemoteUiPlusMenuSheet._();

  /// Shows the menu.
  ///
  /// [planModeSupported] disables the plan-mode switch with an
  /// explanation when the current agent has no plan/spec mode.
  /// [onUploadPhoto] runs after the sheet has closed.
  static Future<void> show(
    BuildContext context, {
    required bool planModeEnabled,
    required bool planModeSupported,
    required ValueChanged<bool> onPlanModeChanged,
    required VoidCallback onUploadPhoto,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _RemoteUiPlusMenuSheetContent(
        planModeEnabled: planModeEnabled,
        planModeSupported: planModeSupported,
        onPlanModeChanged: onPlanModeChanged,
        onUploadPhoto: onUploadPhoto,
      ),
    );
  }
}

class _RemoteUiPlusMenuSheetContent extends StatefulWidget {
  final bool planModeEnabled;
  final bool planModeSupported;
  final ValueChanged<bool> onPlanModeChanged;
  final VoidCallback onUploadPhoto;

  const _RemoteUiPlusMenuSheetContent({
    required this.planModeEnabled,
    required this.planModeSupported,
    required this.onPlanModeChanged,
    required this.onUploadPhoto,
  });

  @override
  State<_RemoteUiPlusMenuSheetContent> createState() =>
      _RemoteUiPlusMenuSheetContentState();
}

class _RemoteUiPlusMenuSheetContentState
    extends State<_RemoteUiPlusMenuSheetContent> {
  late bool _planModeEnabled = widget.planModeEnabled;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Upload photo'),
            onTap: () {
              Navigator.pop(context);
              widget.onUploadPhoto();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.rule_folder_outlined),
            title: const Text('Plan mode'),
            subtitle: widget.planModeSupported
                ? null
                : const Text('Not supported by this agent'),
            value: _planModeEnabled,
            onChanged: widget.planModeSupported
                ? (value) {
                    setState(() => _planModeEnabled = value);
                    widget.onPlanModeChanged(value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
