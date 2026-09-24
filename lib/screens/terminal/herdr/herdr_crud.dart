import 'package:flutter/material.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/backend/domain/multiplexer_session.dart';
import '../../../services/backend/domain/multiplexer_window.dart';
import '../../../services/backend/domain/pane_writer.dart';
import '../../../theme/design_colors.dart';
import 'herdr_types.dart';

/// herdr の pane/tab CRUD（close / rename / zoom / create tab）と確認ダイアログ。
class HerdrCrudFlow {
  HerdrCrudFlow(this._host);

  final HerdrHost _host;

  /// pane を閉じる確認ダイアログ（T17・Q-03/R2）。連鎖 close 警告を出し分ける。
  void confirmAndKillPane({
    required String paneId,
    required String paneTitle,
    required bool isLastPane,
    required bool isLastTab,
  }) {
    final isDark = Theme.of(_host.context).brightness == Brightness.dark;
    showDialog(
      context: _host.context,
      builder: (dialogContext) {
        final String message;
        if (isLastPane && isLastTab) {
          message = _host.context.l10n.termClosePaneHerdrLastBoth;
        } else if (isLastPane) {
          message = _host.context.l10n.termClosePaneHerdrLast;
        } else {
          message = _host.context.l10n.termClosePaneConfirm(paneTitle);
        }
        return AlertDialog(
          backgroundColor: isDark
              ? DesignColors.surfaceDark
              : DesignColors.surfaceLight,
          title: Text(
            _host.context.l10n.termClosePaneTitle,
            style: TextStyle(
              color: isDark
                  ? DesignColors.textPrimary
                  : DesignColors.textPrimaryLight,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: isDark
                  ? DesignColors.textSecondary
                  : DesignColors.textSecondaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                _host.context.l10n.termCancel,
                style: TextStyle(
                  color: isDark
                      ? DesignColors.textSecondary
                      : DesignColors.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                killPane(paneId: paneId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignColors.error,
                foregroundColor: Colors.white,
              ),
              child: Text(_host.context.l10n.termClose),
            ),
          ],
        );
      },
    );
  }

  /// herdr の pane を閉じる（`PaneWriter.closePane`）。成功後は単一経路で同期。
  Future<void> killPane({required String paneId}) async {
    if (!_host.can(const PaneCapabilities(close: true))) return;
    final writer = _host.paneWriter;
    if (writer == null) return;

    _host.cancelPollTimer();
    try {
      await writer.closePane(paneId);
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(eventLabel: 'close pane sync');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'close');
    } finally {
      if (_host.isMounted && !_host.isDisposed) _host.startPolling();
    }
  }

  /// pane ラベル変更（`PaneWriter.renamePane`）。
  Future<void> renamePane(String paneId, String label) async {
    if (!_host.can(const PaneCapabilities(rename: true))) return;
    final writer = _host.paneWriter;
    if (writer == null) return;
    try {
      await writer.renamePane(paneId, label);
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(eventLabel: 'rename pane sync');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'rename pane');
    }
  }

  /// pane zoom トグル（`PaneWriter.zoomPane`）。
  Future<void> zoomPane(String paneId) async {
    if (!_host.can(const PaneCapabilities(zoom: true))) return;
    final writer = _host.paneWriter;
    if (writer == null) return;
    try {
      await writer.zoomPane(paneId, mode: 'toggle');
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(eventLabel: 'zoom pane sync');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'zoom');
    }
  }

  /// tab ラベル変更ダイアログ（Q-05）。入力後は [renameTab] を実行する。
  void showRenameTabDialog(
    MultiplexerSession workspace,
    MultiplexerWindow tab,
  ) {
    final tabId = tab.id;
    if (tabId == null) return;
    _host
        .showLabelInputDialog(
          HerdrLabelDialogArgs(
            title: _host.context.l10n.termRenameTabTitle,
            labelText: _host.context.l10n.termTabLabel,
            hintText: _host.context.l10n.termRenameTabHint,
            initialValue: tab.name,
            confirmLabel: _host.context.l10n.termRename,
          ),
        )
        .then((label) {
          if (label == null || !_host.isMounted) return;
          final trimmed = label.trim();
          if (trimmed.isEmpty || trimmed == tab.name) return;
          renameTab(tabId, trimmed);
        });
  }

  /// New Tab ラベル入力ダイアログ（タスク②）。空欄はデフォルト名と同一視。
  void showCreateTabDialog(MultiplexerSession workspace) {
    final workspaceId = workspace.id;
    if (workspaceId == null) return;
    _host
        .showLabelInputDialog(
          HerdrLabelDialogArgs(
            title: _host.context.l10n.termNewTab,
            labelText: _host.context.l10n.termTabLabel,
            hintText: _host.context.l10n.termNewTabHint,
            confirmLabel: _host.context.l10n.termCreate,
            allowEmpty: true,
          ),
        )
        .then((label) {
          if (label == null || !_host.isMounted || _host.isDisposed) return;
          final normalized = label.trim().isEmpty ? null : label;
          createTab(workspaceId, label: normalized, focus: true);
        });
  }

  /// tab ラベル変更（`PaneWriter.renameTab`）。
  Future<void> renameTab(String tabId, String label) async {
    if (!_host.can(const PaneCapabilities(rename: true))) return;
    final writer = _host.paneWriter;
    if (writer == null) return;
    try {
      await writer.renameTab(tabId, label);
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(eventLabel: 'rename tab sync');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'rename tab');
    }
  }

  /// tab 作成（`PaneWriter.createTab`）。[focus] 付きは followBackendFocus で同期。
  Future<void> createTab(
    String workspaceId, {
    String? label,
    bool? focus,
  }) async {
    if (!_host.can(const PaneCapabilities(tabCrud: true))) return;
    final writer = _host.paneWriter;
    if (writer == null) return;
    try {
      await writer.createTab(workspaceId, label: label, focus: focus);
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(
        eventLabel: 'create tab sync',
        policy: focus == true
            ? HerdrSyncTargetPolicy.followBackendFocus
            : HerdrSyncTargetPolicy.preserveCurrent,
      );
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'create tab');
    }
  }

  /// tab を閉じる確認ダイアログ（Q-05・連鎖 close 確認）。
  void confirmAndCloseTab({
    required MultiplexerSession workspace,
    required MultiplexerWindow tab,
    required bool isLastTab,
  }) {
    final tabId = tab.id;
    if (tabId == null) return;
    final isDark = Theme.of(_host.context).brightness == Brightness.dark;
    final message = isLastTab
        ? _host.context.l10n.termCloseTabLast
        : _host.context.l10n.termCloseTabConfirm(tab.name);
    showDialog(
      context: _host.context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark
            ? DesignColors.surfaceDark
            : DesignColors.surfaceLight,
        title: Text(
          _host.context.l10n.termCloseTabTitle,
          style: TextStyle(
            color: isDark
                ? DesignColors.textPrimary
                : DesignColors.textPrimaryLight,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: isDark
                ? DesignColors.textSecondary
                : DesignColors.textSecondaryLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              _host.context.l10n.termCancel,
              style: TextStyle(
                color: isDark
                    ? DesignColors.textSecondary
                    : DesignColors.textSecondaryLight,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              closeTab(tabId: tabId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DesignColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(_host.context.l10n.termClose),
          ),
        ],
      ),
    );
  }

  /// tab を閉じる（`PaneWriter.closeTab`）。
  Future<void> closeTab({required String tabId}) async {
    if (!_host.can(const PaneCapabilities(tabCrud: true))) return;
    final writer = _host.paneWriter;
    if (writer == null) return;
    try {
      await writer.closeTab(tabId);
      if (!_host.isMounted || _host.isDisposed) return;
      await _host.syncAfterMutation(eventLabel: 'close tab sync');
    } catch (e) {
      await _host.handleMutationError(e, operationLabel: 'close tab');
    }
  }
}
