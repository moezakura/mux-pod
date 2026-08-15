import 'package:flutter/material.dart';

import 'package:flutter_muxpod/l10n/l10n_ext.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_pane.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:flutter_muxpod/services/backend/domain/multiplexer_window.dart';
import 'package:flutter_muxpod/theme/design_colors.dart';
import 'package:flutter_muxpod/widgets/active_list_tile.dart';

/// 共通domainセッション用ListTile
///
/// TmuxSessionTile の共通domain版。tmux session / herdr workspace を
/// [MultiplexerSession] として表示する。
class MultiplexerSessionTile extends StatelessWidget {
  final MultiplexerSession session;
  final bool isActive;
  final VoidCallback? onTap;
  final Widget? trailing;

  const MultiplexerSessionTile({
    super.key,
    required this.session,
    required this.isActive,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ActiveListTile(
      isActive: isActive,
      leading: Icon(
        Icons.folder,
        color: ActiveListTile.iconColor(context, isActive: isActive),
      ),
      title: session.name,
      subtitle: context.l10n.muxWindowCount(session.windowCount),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// 共通domainウィンドウ用ListTile
///
/// TmuxWindowTile の共通domain版。tmux window / herdr tab を
/// [MultiplexerWindow] として表示する。
class MultiplexerWindowTile extends StatelessWidget {
  final MultiplexerWindow window;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onRename;
  final VoidCallback? onResize;
  final String? resizeLabel;
  final VoidCallback? onClose;

  const MultiplexerWindowTile({
    super.key,
    required this.window,
    required this.isActive,
    this.onTap,
    this.onRename,
    this.onResize,
    this.resizeLabel,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActiveListTile(
      isActive: isActive,
      leading: Icon(
        Icons.tab,
        color: ActiveListTile.iconColor(context, isActive: isActive),
      ),
      title: '${window.index}: ${window.name}',
      subtitle: context.l10n.muxPaneCount(window.paneCount),
      trailing: onRename != null || onResize != null || onClose != null
          ? PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (menuContext) => [
                if (onRename != null)
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline, size: 18,
                            color: colorScheme.onSurface),
                        const SizedBox(width: 8),
                        Text(context.l10n.muxRenameWindow),
                      ],
                    ),
                  ),
                if (onResize != null)
                  PopupMenuItem(
                    value: 'resize',
                    child: Row(
                      children: [
                        Icon(Icons.aspect_ratio, size: 18,
                            color: colorScheme.onSurface),
                        const SizedBox(width: 8),
                        Text(resizeLabel ?? context.l10n.muxResizeWindow),
                      ],
                    ),
                  ),
                if (onClose != null)
                  PopupMenuItem(
                    value: 'close',
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 18, color: DesignColors.error),
                        const SizedBox(width: 8),
                        Text(context.l10n.muxCloseWindow, style: TextStyle(color: DesignColors.error)),
                      ],
                    ),
                  ),
              ],
              onSelected: (value) {
                if (value == 'rename') {
                  onRename?.call();
                } else if (value == 'resize') {
                  onResize?.call();
                } else if (value == 'close') {
                  onClose?.call();
                }
              },
            )
          : null,
      onTap: onTap,
    );
  }
}

/// 共通domainペイン用ListTile
///
/// TmuxPaneTile の共通domain版。tmux pane / herdr pane を
/// [MultiplexerPane] として表示する。
///
/// subtitle は呼び出し側が指定する（tmux: 'WxH' / herdr: null または pane.id）。
class MultiplexerPaneTile extends StatelessWidget {
  final MultiplexerPane pane;
  final String paneTitle;
  final String? subtitle;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onResize;
  final VoidCallback? onClose;

  const MultiplexerPaneTile({
    super.key,
    required this.pane,
    required this.paneTitle,
    this.subtitle,
    required this.isActive,
    this.onTap,
    this.onLongPress,
    this.onResize,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActiveListTile(
      isActive: isActive,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.2)
              : colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Center(
          child: Text(
            '${pane.index}',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isActive
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      title: paneTitle,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onResize != null || onClose != null)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (menuContext) => [
                if (onResize != null)
                  PopupMenuItem(
                    value: 'resize',
                    child: Row(
                      children: [
                        Icon(Icons.aspect_ratio, size: 18,
                            color: colorScheme.onSurface),
                        const SizedBox(width: 8),
                        Text(context.l10n.muxResizePane),
                      ],
                    ),
                  ),
                if (onClose != null)
                  PopupMenuItem(
                    value: 'close',
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 18, color: DesignColors.error),
                        const SizedBox(width: 8),
                        Text(context.l10n.muxClosePane,
                            style: TextStyle(color: DesignColors.error)),
                      ],
                    ),
                  ),
              ],
              onSelected: (value) {
                if (value == 'resize') {
                  onResize?.call();
                } else if (value == 'close') {
                  onClose?.call();
                }
              },
            ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
