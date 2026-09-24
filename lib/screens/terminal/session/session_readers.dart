// reader/writer の backend 生成（session-readers・移設元 L1521-1589 / L1754-1778）。
//
// - tmux: TmuxPaneContentReader を生成。
// - テスト注入: widget.paneContentReader を優先（content のみ・geometry なし）。
// - herdr: HerdrPaneContentReader / cache / frame reader は herdr 領域
//   （`SessionHerdrPort`）へ委譲（二重所有回避・arbitration §6）。

import '../../../../providers/ssh_provider.dart';
import '../../../../services/backend/domain/herdr_pane_writer.dart';
import '../../../../services/backend/domain/multiplexer_backend.dart'
    show MultiplexerBackendKind;
import '../../../../services/backend/domain/pane_content_reader.dart';
import '../../../../services/tmux/tmux_pane_content_reader.dart';
import '../../../../services/backend/domain/tmux_pane_writer.dart';
import '../../../../services/herdr/herdr_adapter.dart';
import '../../../../services/tmux/ssh_tmux_command_executor.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// reader/writer の生成（`SessionRuntimeController.recreatePaneReader` へ注入）。
class SessionReaderComposer {
  SessionReaderComposer(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  /// `_recreatePaneReader` の移設（herdr 固有部は Env 経由）。
  void recreatePaneReader() {
    recreatePaneWriter();
    final isHerdr = runtime.backendKind == MultiplexerBackendKind.herdr;
    final injected = env.host.injectedPaneContentReader;
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null) return;

    if (injected != null) {
      runtime.paneReader = injected as PaneContentReader;
      runtime.frameReader = null; // テスト注入 reader は content のみ（geometry なし）
      // herdr: スナップショット読み取りは content reader とは独立に cache
      // （唯一の read chokepoint・A5 / A3改）経由にする。テスト注入 reader でも
      // cache を生成してエポック照合・再解決を有効にする（HEAD 相当）。
      if (isHerdr) {
        env.herdr.rebuildInjectedReaderCache(sshClient);
      }
    } else if (isHerdr) {
      // herdr: content + geometry の合成キャッシュ / caret は herdr 領域
      // （SessionHerdrPort.rebuildReaders）が構成する。
      env.herdr.rebuildReaders();
    } else {
      runtime.paneReader = TmuxPaneContentReader(sshClient.tmuxExecutor);
      runtime.frameReader = null;
    }
  }

  /// `_recreatePaneWriter` の移設（T8・backend 切替点）。
  void recreatePaneWriter() {
    final sshClient = env.ref.read(sshProvider.notifier).client;
    if (sshClient == null) {
      runtime.paneWriter = null;
      return;
    }
    runtime.paneWriter = switch (runtime.backendKind) {
      MultiplexerBackendKind.herdr => HerdrPaneWriter(HerdrAdapter(sshClient)),
      MultiplexerBackendKind.tmux => TmuxPaneWriter(
        env.tmux,
        sshClient.tmuxExecutor,
      ),
      MultiplexerBackendKind.unknown => null,
    };
  }
}
