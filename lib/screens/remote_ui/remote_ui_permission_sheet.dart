import 'package:flutter/material.dart';

import '../../services/agent/agent_types.dart';

/// Bottom sheet picking the agent's autonomy/permission level.
class RemoteUiPermissionSheet {
  RemoteUiPermissionSheet._();

  /// Shows the sheet with [permissions] (from the agent's capabilities)
  /// and returns the chosen level, or null when the sheet is dismissed.
  static Future<UnifiedPermission?> show(
    BuildContext context, {
    required UnifiedPermission? selected,
    required List<UnifiedPermission> permissions,
  }) {
    return showModalBottomSheet<UnifiedPermission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Permissions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final permission in permissions)
              ListTile(
                title: Text(permission.label),
                subtitle: Text(permission.description),
                trailing:
                    permission == selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, permission),
              ),
          ],
        ),
      ),
    );
  }
}
