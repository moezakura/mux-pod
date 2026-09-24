// P4: ターミナル画面シェルの下部・右上のエリア部品。
//
// シェル（terminal_view_shell.dart）から切り出した責務単位のウィジェット。
// ペインインジケータ（右上）と特殊キー入力バー（下部）を担い、provider の
// watch は各 ConsumerWidget 内に閉じる（親 build の再実行を避ける）。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/custom_keys_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tmux_provider.dart';
import '../../services/backend/domain/multiplexer_backend.dart';
import '../../services/custom_keys/custom_key_button.dart';
import '../../widgets/special_keys_bar.dart';
import 'herdr/herdr_types.dart';
import 'pane_layout_painter.dart';
import 'selector_launch.dart';

/// ペインインジケータ（右上・backend 分岐）。
class TerminalPaneIndicatorArea extends ConsumerWidget {
  final MultiplexerBackendKind backendKind;
  final ValueListenable<HerdrPaneIndicatorData?> herdrPaneIndicatorNotifier;
  final VoidCallback? onHerdrPaneIndicatorTap;
  final SelectorLaunchActions tmuxActions;

  const TerminalPaneIndicatorArea({
    super.key,
    required this.backendKind,
    required this.herdrPaneIndicatorNotifier,
    required this.onHerdrPaneIndicatorTap,
    required this.tmuxActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      top: 8,
      right: 8,
      child: backendKind == MultiplexerBackendKind.herdr
          ? ValueListenableBuilder<HerdrPaneIndicatorData?>(
              valueListenable: herdrPaneIndicatorNotifier,
              builder: (context, data, _) {
                if (data == null) return const SizedBox.shrink();
                return PaneIndicatorShell(
                  panes: data.panes,
                  activePaneId: data.activePaneId,
                  onTap: onHerdrPaneIndicatorTap ?? () {},
                );
              },
            )
          : buildTmuxPaneIndicator(
              tmuxActions,
              ref.watch(tmuxProvider),
              onTap: () => showPaneSelectorTap(
                context,
                tmuxActions,
                ref.watch(tmuxProvider),
                showResizePaneChooser: () => showResizePaneChooserTap(
                  context,
                  tmuxActions,
                  ref.watch(tmuxProvider),
                ),
              ),
            ),
    );
  }
}

/// 特殊キー入力バー（Consumer で watch・親 build 再実行を避ける）。
class TerminalSpecialKeysArea extends ConsumerWidget {
  final void Function(String key) onKeyPressed;
  final void Function(String tmuxKey) onSpecialKeyPressed;
  final VoidCallback? onInputDialog;
  final bool directInputEnabled;
  final VoidCallback onToggleDirectInput;
  final VoidCallback? onImagePickRequested;
  final void Function(CustomKeyButton)? onCustomButtonEdit;
  final VoidCallback? onManageCustomKeys;

  const TerminalSpecialKeysArea({
    super.key,
    required this.onKeyPressed,
    required this.onSpecialKeyPressed,
    this.onInputDialog,
    required this.directInputEnabled,
    required this.onToggleDirectInput,
    this.onImagePickRequested,
    this.onCustomButtonEdit,
    this.onManageCustomKeys,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customKeys = ref.watch(customKeysProvider);
    // cjkMode / keepKeyboardOnEnter のみ select 監視: 親 build を
    // 再実行させず SpecialKeysBar サブツリーだけ再構築する
    final cjkMode = ref.watch(settingsProvider.select((s) => s.cjkMode));
    final keepKeyboardOnEnter = ref.watch(
      settingsProvider.select((s) => s.keepKeyboardOnEnter),
    );
    return SpecialKeysBar(
      // inventory: TERM-INPUT-006
      onKeyPressed: onKeyPressed,
      onSpecialKeyPressed: onSpecialKeyPressed,
      // inventory: TERM-INPUT-009
      onInputTap: onInputDialog,
      directInputEnabled: directInputEnabled,
      cjkMode: cjkMode,
      keepKeyboardOnEnter: keepKeyboardOnEnter,
      onDirectInputToggle: onToggleDirectInput,
      // inventory: TERM-FILE-002
      onImagePickRequested: onImagePickRequested,
      customButtons: customKeys.buttons,
      rows: customKeys.rows,
      onCustomButtonEdit: onCustomButtonEdit,
      onManageButtons: onManageCustomKeys,
    );
  }
}
