import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmux.freezed.dart';
part 'tmux.g.dart';

/// tmuxセッション
@freezed
class TmuxSession with _$TmuxSession {
  const factory TmuxSession({
    required String name,
    required DateTime created,
    required bool attached,
    required int windowCount,
    @Default([]) List<TmuxWindow> windows,
  }) = _TmuxSession;

  factory TmuxSession.fromJson(Map<String, dynamic> json) =>
      _$TmuxSessionFromJson(json);
}

/// tmuxウィンドウ
@freezed
class TmuxWindow with _$TmuxWindow {
  const factory TmuxWindow({
    required int index,
    required String name,
    required bool active,
    required int paneCount,
    @Default([]) List<TmuxPane> panes,
  }) = _TmuxWindow;

  factory TmuxWindow.fromJson(Map<String, dynamic> json) =>
      _$TmuxWindowFromJson(json);
}

/// tmuxペイン
@freezed
class TmuxPane with _$TmuxPane {
  const factory TmuxPane({
    required int index,
    required String id,
    required bool active,
    required String currentCommand,
    required String title,
    required int width,
    required int height,
    required int cursorX,
    required int cursorY,
  }) = _TmuxPane;

  factory TmuxPane.fromJson(Map<String, dynamic> json) =>
      _$TmuxPaneFromJson(json);
}

/// tmuxセッション拡張
extension TmuxSessionExtension on TmuxSession {
  /// アクティブなウィンドウを取得
  TmuxWindow? get activeWindow {
    try {
      return windows.firstWhere((w) => w.active);
    } catch (_) {
      return windows.isNotEmpty ? windows.first : null;
    }
  }
}

/// tmuxウィンドウ拡張
extension TmuxWindowExtension on TmuxWindow {
  /// アクティブなペインを取得
  TmuxPane? get activePane {
    try {
      return panes.firstWhere((p) => p.active);
    } catch (_) {
      return panes.isNotEmpty ? panes.first : null;
    }
  }
}
