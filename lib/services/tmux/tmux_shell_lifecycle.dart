library;

import 'tmux_command_builder.dart';
import 'tmux_executable_resolver.dart';

/// tmux セッション・ウィンドウ・ペインのライフサイクルで使用するコマンド文字列を構築する。
///
/// リモートへの書き込み自体は呼び出し側（[TmuxCommandExecutor] 実装）の責務。
class TmuxShellLifecycle {
  TmuxShellLifecycle({required TmuxExecutableResolver resolver})
    : _resolver = resolver;

  final TmuxExecutableResolver _resolver;

  String? _currentRestoreTrapCommand;

  /// 現在設定されている restore trap コマンド（未設定なら null）。
  String? get currentRestoreTrapCommand => _currentRestoreTrapCommand;

  /// restore trap コマンドを保持する。`null` は「trap 解除済み」を表す。
  void setRestoreTrapCommand(String? command) {
    _currentRestoreTrapCommand = command;
  }

  /// AutoResize で縮めたウィンドウを接続断時に自動サイズへ戻す trap コマンドを構築する。
  String buildRestoreTrapCommand(
    List<String> targets, {
    required String tmuxBin,
  }) {
    final raw = TmuxCommands.windowRestoreTrap(targets, tmuxBin: tmuxBin);
    return _resolver.resolve(raw);
  }

  /// [buildRestoreTrapCommand] で設定した trap を解除するコマンドを構築する。
  String buildClearRestoreTrapCommand() {
    return TmuxCommands.clearWindowRestoreTrap();
  }

  /// ウィンドウを自動サイズ（クライアント追従）に戻すコマンドを構築する。
  String buildResizeAutoCommand(String target, {required String tmuxBin}) {
    final raw = TmuxCommands.resizeWindowAuto(target);
    final quoted = TmuxExecutableResolver.shQuote(tmuxBin);
    final withBin = raw.replaceAllMapped(
      RegExp(r'(^|;\s*)tmux\b'),
      (m) => '${m[1]}$quoted',
    );
    return _resolver.resolve(withBin);
  }
}
