import '../backend/domain/multiplexer_pane.dart';
import '../backend/domain/multiplexer_session.dart';
import '../backend/domain/multiplexer_window.dart';
import 'tmux_models.dart';

/// [TmuxSession] を共通 domain の [MultiplexerSession] に変換する。
///
/// 既存の tmux モデルは変更しない（変換はこの拡張側で吸収する）。
extension TmuxSessionDomainMapping on TmuxSession {
  MultiplexerSession toDomain() => MultiplexerSession(
        name: name,
        id: id,
        windowCount: windowCount,
        attached: attached,
        windows: windows.map((w) => w.toDomain()).toList(),
      );
}

/// [TmuxWindow] を共通 domain の [MultiplexerWindow] に変換する。
extension TmuxWindowDomainMapping on TmuxWindow {
  MultiplexerWindow toDomain() => MultiplexerWindow(
        index: index,
        id: id,
        name: name,
        active: active,
        paneCount: paneCount,
        panes: panes.map((p) => p.toDomain()).toList(),
      );
}

/// [TmuxPane] を共通 domain の [MultiplexerPane] に変換する。
extension TmuxPaneDomainMapping on TmuxPane {
  MultiplexerPane toDomain() => MultiplexerPane(
        index: index,
        id: id,
        active: active,
        currentPath: currentPath,
        left: left,
        top: top,
        width: width,
        height: height,
      );
}
