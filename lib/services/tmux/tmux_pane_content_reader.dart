import '../backend/domain/pane_content_reader.dart';
import '../backend/domain/pane_read.dart';
import 'tmux_command_executor.dart';
import 'tmux_facade.dart';

/// tmux のペイン内容読み取り実装。
///
/// ライブポーリング（直近行 + カーソル + モード）は
/// [TmuxFacade.pollPane]（persistent チャネル）、スクロールバック
/// （深い履歴）は [TmuxFacade.capturePane]（exec チャネル）を使う。
/// スクロールバックはポーリングとは別チャネルで取得し、ホットパス
/// （キー入力等）を塞がない。
class TmuxPaneContentReader implements PaneContentReader {
  final TmuxCommandExecutor _executor;

  TmuxPaneContentReader(this._executor);

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    // スクロールバック: poll（persistent）ではなく exec チャネルの capturePane
    // でスクロールバック全体を一括取得する（大量出力をホットパスから分離）。
    if (request.purpose == PaneReadPurpose.scrollback) {
      final content = await tmuxFacade.capturePane(
        _executor,
        target: request.paneId,
        escapeSequences: true,
        startLine: -request.maxLines,
      );
      return MultiplexerPaneSnapshot(
        content: content.rawText,
        geometry: PaneGeometry(width: content.width, height: content.height),
        hasAnsi: content.hasAnsiColors,
      );
    }

    final snapshot = await tmuxFacade.pollPane(
      _executor,
      target: request.paneId,
      historyLines: -request.maxLines,
    );
    return MultiplexerPaneSnapshot(
      content: snapshot.content.rawText,
      geometry: PaneGeometry(
        width: snapshot.paneWidth,
        height: snapshot.paneHeight,
      ),
      cursorX: snapshot.cursorX,
      cursorY: snapshot.cursorY,
      paneMode: snapshot.paneMode,
      hasAnsi: snapshot.content.hasAnsiColors,
    );
  }
}
