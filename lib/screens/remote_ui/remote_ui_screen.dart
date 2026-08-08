import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/connection_provider.dart';
import '../../providers/remote_ui_chat_provider.dart';
import '../../providers/remote_ui_provider.dart';
import '../../services/agent/agent_types.dart';
import '../../services/agent/headless/chat_session_store.dart';
import '../../services/sftp/sftp_service.dart';
import '../../theme/design_colors.dart';
import 'remote_ui_model_intelligence_sheet.dart';
import 'remote_ui_permission_sheet.dart';
import 'remote_ui_plus_menu_sheet.dart';
import 'remote_ui_sessions_sheet.dart';

/// Remote UI tab: a Codex-app-style chat screen that controls AI CLI
/// agents (Claude Code, Codex CLI, Factory Droid) over SSH.
///
/// The screen is dual-mode:
///
/// - Live-pane mode: an agent process was detected in a tmux pane of the
///   connected server (`RemoteUiState.agent` != null). The chips show the
///   live agent configuration and apply changes through
///   [remoteUiProvider].
/// - Chat mode: no agent process detected. An agent picker chooses the
///   headless agent and the chips edit
///   `RemoteUiChatState.pendingConfig`; the options come from the
///   selected agent's capabilities.
///
/// The composer always talks to the headless chat path
/// ([remoteUiChatProvider]).
class RemoteUiScreen extends ConsumerStatefulWidget {
  const RemoteUiScreen({super.key});

  @override
  ConsumerState<RemoteUiScreen> createState() => _RemoteUiScreenState();
}

class _RemoteUiScreenState extends ConsumerState<RemoteUiScreen> {
  static const _modelChipKey = Key('remote_ui.model_chip');
  static const _permissionChipKey = Key('remote_ui.permission_chip');
  static const _plusButtonKey = Key('remote_ui.plus_button');
  static const _sendButtonKey = Key('remote_ui.send_button');
  static const _stopButtonKey = Key('remote_ui.stop_button');
  static const _composerKey = Key('remote_ui.composer');
  static const _agentPickerKey = Key('remote_ui.agent_picker');
  static const _historyButtonKey = Key('remote_ui.history_button');
  static const _newChatButtonKey = Key('remote_ui.new_chat_button');
  static const _messageListKey = Key('remote_ui.message_list');
  static const _streamingBubbleKey = Key('remote_ui.streaming_bubble');

  /// Maximum length of the session title derived from the first user
  /// message (mirrors `ChatSessionStore`'s title truncation).
  static const _titleMaxLength = 40;

  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  final _sftpService = SftpService();

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live-pane confirmations/errors.
    ref.listen<RemoteUiState>(remoteUiProvider, (prev, next) {
      final notice = next.notice;
      final error = next.error;
      if (!mounted) return;
      if (notice != null && notice.isNotEmpty && notice != prev?.notice) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(notice)),
        );
        ref.read(remoteUiProvider.notifier).clearMessages();
      } else if (error != null && error.isNotEmpty && error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        ref.read(remoteUiProvider.notifier).clearMessages();
      }
    });

    // Chat errors and auto-scroll on new content.
    ref.listen<RemoteUiChatState>(remoteUiChatProvider, (prev, next) {
      final error = next.error;
      if (mounted && error != null && error.isNotEmpty && error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        ref.read(remoteUiChatProvider.notifier).clearError();
      }
      if (next.messages.length != prev?.messages.length ||
          next.streamingText != prev?.streamingText) {
        _scrollToBottom();
      }
    });

    final remote = ref.watch(remoteUiProvider);
    final chat = ref.watch(remoteUiChatProvider);
    final chatNotifier = ref.read(remoteUiChatProvider.notifier);
    final connections = ref.watch(connectionsProvider).connections;

    final liveAgent = remote.agent;
    final isLiveMode = liveAgent != null;
    final capabilities =
        isLiveMode ? liveAgent.capabilities : chatNotifier.capabilities;
    final effectiveConfig = isLiveMode ? remote.config : chat.pendingConfig;

    final targetLabel = connections
            .where((c) => c.id == remote.connectionId)
            .firstOrNull
            ?.name ??
        'Select a server';

    final hasChatContent = chat.messages.isNotEmpty ||
        chat.streamingText.isNotEmpty ||
        chat.isStreaming;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.borderDark : DesignColors.borderLight;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBarRow(context, chat),
            Expanded(
              child: hasChatContent
                  ? _buildMessageList(context, chat)
                  : _buildEmptyState(
                      context,
                      remote: remote,
                      chat: chat,
                      isLiveMode: isLiveMode,
                      targetLabel: targetLabel,
                    ),
            ),
            _buildComposer(
              context,
              chat: chat,
              config: effectiveConfig,
              showPermissionChip: capabilities.permissionLevels.isNotEmpty,
              borderColor: border,
            ),
          ],
        ),
      ),
    );
  }

  // ===== App-bar row (sessions) =====

  Widget _buildAppBarRow(BuildContext context, RemoteUiChatState chat) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            key: _historyButtonKey,
            icon: const Icon(Icons.history),
            tooltip: 'Chat history',
            onPressed: _openSessionsSheet,
          ),
          Expanded(
            child: Text(
              _sessionTitle(chat),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: _newChatButtonKey,
            icon: const Icon(Icons.add),
            tooltip: 'New chat',
            onPressed: () =>
                ref.read(remoteUiChatProvider.notifier).newSession(),
          ),
        ],
      ),
    );
  }

  /// Title shown in the app-bar row: the stored session title when
  /// known, otherwise the first user message, otherwise "New chat".
  String _sessionTitle(RemoteUiChatState chat) {
    final activeId = chat.activeSessionId;
    if (activeId != null) {
      final session =
          chat.sessions.where((s) => s.id == activeId).firstOrNull;
      if (session != null && session.title.isNotEmpty) return session.title;
    }
    final firstUser =
        chat.messages.where((m) => m.role == ChatRole.user).firstOrNull;
    if (firstUser != null) {
      final firstLine = firstUser.text.trim().split('\n').first;
      if (firstLine.isNotEmpty) {
        return firstLine.length <= _titleMaxLength
            ? firstLine
            : '${firstLine.substring(0, _titleMaxLength)}…';
      }
    }
    return 'New chat';
  }

  Future<void> _openSessionsSheet() async {
    final chat = ref.read(remoteUiChatProvider);
    await RemoteUiSessionsSheet.show(
      context,
      sessions: chat.sessions,
      activeSessionId: chat.activeSessionId,
      onOpenSession: (sessionId) =>
          ref.read(remoteUiChatProvider.notifier).openSession(sessionId),
      onClearHistory: _confirmClearHistory,
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This deletes all chat sessions for this server and agent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: DesignColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ref.read(remoteUiChatProvider.notifier).clearHistory();
  }

  // ===== Empty state ("Let's work on …") =====

  Widget _buildEmptyState(
    BuildContext context, {
    required RemoteUiState remote,
    required RemoteUiChatState chat,
    required bool isLiveMode,
    required String targetLabel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted =
        isDark ? DesignColors.textMuted : DesignColors.textMutedLight;

    final String infoText;
    if (isLiveMode) {
      infoText = 'Detected: ${remote.agent!.kind.displayName} '
          '(pane ${remote.agentPaneId ?? '-'})';
    } else if (remote.connectionId == null) {
      infoText = 'Connect to a server to control Codex, Claude, or Droid.';
    } else {
      infoText = 'No agent process detected in tmux panes. Chat runs '
          '${chat.agentKind.displayName} headlessly on this server.';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Text(
            "Let's work on",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          _TargetPickerRow(
            label: targetLabel,
            onTap: _pickServer,
          ),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Workspace')),
              ButtonSegment(value: true, label: Text('Worktree')),
            ],
            selected: {chat.worktreeMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => ref
                .read(remoteUiChatProvider.notifier)
                .setWorktreeMode(selection.first),
          ),
          // Chat mode only: pick which agent the headless chat runs on.
          if (!isLiveMode) ...[
            const SizedBox(height: 18),
            _TargetPickerRow(
              key: _agentPickerKey,
              label: chat.agentKind.displayName,
              icon: Icons.smart_toy_outlined,
              onTap: _openAgentPicker,
            ),
          ],
          const SizedBox(height: 56),
          Text(
            infoText,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _pickServer() async {
    final selected = await _showServerPicker(context);
    if (selected == null || !mounted) return;
    final previousConnectionId = ref.read(remoteUiProvider).connectionId;
    await ref.read(remoteUiProvider.notifier).selectServer(selected.id);
    if (!mounted) return;
    // Sessions are stored per (connection, agent): switching servers must
    // drop the previous server's active session (its id is unknown to the
    // new server's store, so messages would silently fail to persist),
    // then load the new server's history.
    if (previousConnectionId != selected.id) {
      await ref.read(remoteUiChatProvider.notifier).newSession();
    }
    await ref.read(remoteUiChatProvider.notifier).loadSessions();
  }

  Future<void> _openAgentPicker() async {
    final currentKind = ref.read(remoteUiChatProvider).agentKind;
    final selected = await showModalBottomSheet<AgentKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Agent',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final kind in AgentKind.values)
              ListTile(
                title: Text(kind.displayName),
                trailing:
                    kind == currentKind ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, kind),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await ref.read(remoteUiChatProvider.notifier).selectAgent(selected);
  }

  // ===== Message list =====

  Widget _buildMessageList(BuildContext context, RemoteUiChatState chat) {
    final showStreaming = chat.isStreaming || chat.streamingText.isNotEmpty;
    return ListView.builder(
      key: _messageListKey,
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: chat.messages.length + (showStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= chat.messages.length) {
          return _StreamingBubble(
            key: _streamingBubbleKey,
            text: chat.streamingText,
          );
        }
        final message = chat.messages[index];
        return switch (message.role) {
          ChatRole.user => _UserMessageBubble(text: message.text),
          ChatRole.assistant => _AssistantMessageText(text: message.text),
        };
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ===== Composer =====

  Widget _buildComposer(
    BuildContext context, {
    required RemoteUiChatState chat,
    required AgentConfig config,
    required bool showPermissionChip,
    required Color borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PillChip(
                key: _modelChipKey,
                label: _modelChipLabel(config),
                icon: Icons.auto_awesome_outlined,
                onTap: _openModelAndIntelligenceSheet,
              ),
              if (showPermissionChip) ...[
                const SizedBox(width: 10),
                _PillChip(
                  key: _permissionChipKey,
                  label: config.permission?.label ?? 'Permissions',
                  icon: Icons.lock_outline,
                  onTap: _openPermissionSheet,
                ),
              ],
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                key: _plusButtonKey,
                onPressed: _openPlusMenu,
                icon: const Icon(Icons.add),
                tooltip: 'More',
              ),
              Expanded(
                child: TextField(
                  key: _composerKey,
                  controller: _composerController,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'What should we code next?',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 4),
              if (chat.isStreaming)
                IconButton(
                  key: _stopButtonKey,
                  onPressed: () =>
                      ref.read(remoteUiChatProvider.notifier).cancel(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  tooltip: 'Stop',
                )
              else
                IconButton(
                  key: _sendButtonKey,
                  onPressed: _send,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Send',
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Chip label: the configured model (or `Auto` when the agent picks
  /// the default) plus the reasoning-effort label when known.
  String _modelChipLabel(AgentConfig config) {
    final model = config.model ?? 'Auto';
    final intelligence = config.intelligence;
    return intelligence == null ? model : '$model ${intelligence.label}';
  }

  void _send() {
    if (ref.read(remoteUiChatProvider).isStreaming) return;
    final text = _composerController.text;
    if (text.trim().isEmpty) return;
    unawaited(ref.read(remoteUiChatProvider.notifier).send(text));
    _composerController.clear();
  }

  // ===== Chip sheets (dual-mode) =====

  Future<void> _openModelAndIntelligenceSheet() async {
    final remote = ref.read(remoteUiProvider);
    final agent = remote.agent;

    if (agent != null) {
      // Live-pane mode: show the running agent's config and apply
      // changes to it. Unchanged values are not re-applied (applying
      // can restart the agent, e.g. Codex).
      final capabilities = agent.capabilities;
      final result = await RemoteUiModelIntelligenceSheet.show(
        context,
        selectedModel: remote.config.model,
        selectedIntelligence: remote.config.intelligence,
        intelligenceLevels: capabilities.intelligenceLevels,
        availableModels: capabilities.availableModels,
      );
      if (!mounted || result == null) return;
      final notifier = ref.read(remoteUiProvider.notifier);
      final model = result.model;
      final intelligence = result.intelligence;
      if (model != null && model != remote.config.model) {
        await notifier.applyModel(model);
      }
      if (intelligence != null && intelligence != remote.config.intelligence) {
        await notifier.applyIntelligence(intelligence);
      }
      return;
    }

    // Chat mode: edit the pending headless configuration.
    final chatNotifier = ref.read(remoteUiChatProvider.notifier);
    final capabilities = chatNotifier.capabilities;
    final pending = ref.read(remoteUiChatProvider).pendingConfig;
    final result = await RemoteUiModelIntelligenceSheet.show(
      context,
      selectedModel: pending.model,
      selectedIntelligence: pending.intelligence,
      intelligenceLevels: capabilities.intelligenceLevels,
      availableModels: capabilities.availableModels,
    );
    if (!mounted || result == null) return;
    chatNotifier.setModel(result.model);
    final intelligence = result.intelligence;
    if (intelligence != null) {
      chatNotifier.setIntelligence(intelligence);
    }
  }

  Future<void> _openPermissionSheet() async {
    final remote = ref.read(remoteUiProvider);
    final agent = remote.agent;

    if (agent != null) {
      final permission = await RemoteUiPermissionSheet.show(
        context,
        selected: remote.config.permission,
        permissions: agent.capabilities.permissionLevels,
      );
      if (!mounted || permission == null) return;
      if (permission != remote.config.permission) {
        await ref
            .read(remoteUiProvider.notifier)
            .applyPermission(permission);
      }
      return;
    }

    final chatNotifier = ref.read(remoteUiChatProvider.notifier);
    final permission = await RemoteUiPermissionSheet.show(
      context,
      selected: ref.read(remoteUiChatProvider).pendingConfig.permission,
      permissions: chatNotifier.capabilities.permissionLevels,
    );
    if (!mounted || permission == null) return;
    chatNotifier.setPermission(permission);
  }

  // ===== "+" menu =====

  Future<void> _openPlusMenu() async {
    final remote = ref.read(remoteUiProvider);
    final agent = remote.agent;
    final chatNotifier = ref.read(remoteUiChatProvider.notifier);

    final planModeEnabled = agent != null
        ? remote.config.planModeActive
        : ref.read(remoteUiChatProvider).pendingConfig.planModeActive;
    final planModeSupported = agent != null
        ? agent.capabilities.supportsPlanMode
        : chatNotifier.capabilities.supportsPlanMode;

    await RemoteUiPlusMenuSheet.show(
      context,
      planModeEnabled: planModeEnabled,
      planModeSupported: planModeSupported,
      onPlanModeChanged: (enabled) {
        if (agent != null) {
          unawaited(
            ref.read(remoteUiProvider.notifier).setPlanMode(enabled),
          );
        } else {
          chatNotifier.setPlanMode(enabled);
        }
      },
      onUploadPhoto: _uploadPhoto,
    );
  }

  /// Picks a photo and uploads it to `/tmp` on the connected server via
  /// SFTP, then inserts the remote path into the composer.
  Future<void> _uploadPhoto() async {
    final client = ref.read(remoteUiProvider.notifier).client;
    if (client == null || !client.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to a server first to upload a photo.'),
        ),
      );
      return;
    }

    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    try {
      final bytes = await picked.readAsBytes();
      final filename = SftpService.generateFilename(
        'img_',
        _extensionFromPath(picked.path),
      );
      // The SFTP client is cached by SshClient and must not be closed
      // by the caller.
      final sftp = await client.openSftp();
      final result = await _sftpService.upload(
        sftp: sftp,
        remoteDir: '/tmp',
        filename: filename,
        bytes: bytes,
      );
      if (!mounted) return;
      _insertIntoComposer(result.remotePath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded ${result.remotePath}')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
    }
  }

  String _extensionFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'png';
    return path.substring(dot + 1).toLowerCase();
  }

  void _insertIntoComposer(String text) {
    final current = _composerController.text;
    final separator =
        current.isEmpty || current.endsWith(' ') || current.endsWith('\n')
            ? ''
            : ' ';
    final updated = '$current$separator$text';
    _composerController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  // ===== Server picker =====

  Future<_ServerPick?> _showServerPicker(BuildContext context) async {
    final connections = ref.read(connectionsProvider).connections;
    return showModalBottomSheet<_ServerPick>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Servers',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (connections.isEmpty)
              const ListTile(
                title: Text('No servers yet'),
                subtitle: Text('Add one in the Servers tab first.'),
              ),
            for (final c in connections)
              ListTile(
                title: Text(c.name),
                subtitle: Text('${c.username}@${c.host}:${c.port}'),
                onTap: () =>
                    Navigator.pop(context, _ServerPick(id: c.id, label: c.name)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServerPick {
  final String id;
  final String label;

  const _ServerPick({required this.id, required this.label});
}

/// User chat bubble: right-aligned with the cyan accent color.
class _UserMessageBubble extends StatelessWidget {
  final String text;

  const _UserMessageBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 56, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colorScheme.onPrimary),
        ),
      ),
    );
  }
}

/// Assistant reply: left-aligned plain text, no bubble.
class _AssistantMessageText extends StatelessWidget {
  final String text;

  const _AssistantMessageText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 56, top: 4, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

/// The in-flight assistant reply with a blinking cursor.
class _StreamingBubble extends StatefulWidget {
  final String text;

  const _StreamingBubble({super.key, required this.text});

  @override
  State<_StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<_StreamingBubble> {
  Timer? _timer;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 56, top: 4, bottom: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: widget.text),
              TextSpan(
                text: '▍',
                style: TextStyle(
                  color: _cursorVisible
                      ? DesignColors.primary
                      : Colors.transparent,
                ),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PillChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final border = isDark ? DesignColors.borderDark : DesignColors.borderLight;
    final fg = isDark ? DesignColors.textPrimary : DesignColors.textPrimaryLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style:
                    Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
              ),
              const SizedBox(width: 6),
              Icon(Icons.expand_more,
                  size: 18, color: fg.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable row used for the server picker and the chat-mode agent
/// picker.
class _TargetPickerRow extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _TargetPickerRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final border = isDark ? DesignColors.borderDark : DesignColors.borderLight;
    final fg = isDark ? DesignColors.textPrimary : DesignColors.textPrimaryLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg.withValues(alpha: 0.85)),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down,
                  color: fg.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }
}
