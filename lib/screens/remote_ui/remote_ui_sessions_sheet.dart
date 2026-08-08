import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/agent/headless/chat_session_store.dart';
import '../../theme/design_colors.dart';

/// Modal bottom sheet listing the stored chat sessions of the current
/// (server, agent) pair.
class RemoteUiSessionsSheet {
  RemoteUiSessionsSheet._();

  static final _dateFormat = DateFormat.yMMMd().add_Hm();

  /// Shows the sheet.
  ///
  /// Actions are delivered through callbacks: [onOpenSession] with the
  /// tapped session id, and [onClearHistory] when the destructive
  /// "Clear history" entry is tapped (the caller asks for confirmation
  /// before clearing). Both run after the sheet has closed.
  static Future<void> show(
    BuildContext context, {
    required List<ChatSessionRecord> sessions,
    required String? activeSessionId,
    required ValueChanged<String> onOpenSession,
    required VoidCallback onClearHistory,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Chats',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (sessions.isEmpty)
              const ListTile(
                title: Text('No previous chats'),
                subtitle: Text('Start a new chat below.'),
              ),
            for (final session in sessions)
              ListTile(
                title: Text(
                  session.title.isEmpty ? 'New chat' : session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_dateFormat.format(session.createdAt)),
                trailing: session.id == activeSessionId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onOpenSession(session.id);
                },
              ),
            if (sessions.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: DesignColors.error,
                ),
                title: const Text(
                  'Clear history',
                  style: TextStyle(color: DesignColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onClearHistory();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
