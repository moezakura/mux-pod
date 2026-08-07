import '../backend/domain/pane_content_reader.dart';
import 'tmux_command_executor.dart';
import 'tmux_facade.dart';

/// tmux のペイン内容読み取り実装。
///
/// ライブポーリング（直近行 + カーソル + モード）は
/// [TmuxFacade.pollPane]（persistent チャネル）、深い履歴（スクロールバック
/// 全体）は [TmuxFacade.capturePane]（exec チャネル）を使う。深い履歴は
/// ポーリングとは別チャネルで取得し、ホットパス（キー入力等）を塞がない。
class TmuxPaneContentReader implements PaneContentReader {
  /// 深い履歴と判定する履歴行数の閾値。
  ///
  /// tmux capture-pane の `-S` は履歴上限までクランプされるため、この閾値
  /// より深い要求は [TmuxFacade.capturePane] で全履歴を取得する。
  /// （既存の `capturePaneAll` と同じ -32768 を使用。）
  static const int deepHistoryThreshold = -32768;

  final TmuxCommandExecutor _executor;

  TmuxPaneContentReader(this._executor);

  @override
  Future<MultiplexerPaneSnapshot> readPane({
    required String paneId,
    int? historyLines,
    String source = 'recent',
  }) async {
    // 深い履歴: poll（persistent）ではなく exec チャネルの capturePane で
    // スクロールバック全体を一括取得する。
    if (historyLines != null && historyLines < deepHistoryThreshold) {
      final content = await tmuxFacade.capturePane(
        _executor,
        target: paneId,
        escapeSequences: true,
        startLine: historyLines,
      );
      return MultiplexerPaneSnapshot(
        content: content.rawText,
        width: content.width,
        height: content.height,
        hasAnsi: content.hasAnsiColors,
      );
    }

    final snapshot = await tmuxFacade.pollPane(
      _executor,
      target: paneId,
      historyLines: historyLines ?? -120,
    );
    return MultiplexerPaneSnapshot(
      content: snapshot.content.rawText,
      width: snapshot.paneWidth,
      height: snapshot.paneHeight,
      cursorX: snapshot.cursorX,
      cursorY: snapshot.cursorY,
      paneMode: snapshot.paneMode,
      hasAnsi: snapshot.content.hasAnsiColors,
    );
  }
}
