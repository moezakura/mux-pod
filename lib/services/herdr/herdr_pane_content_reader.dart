import '../backend/domain/pane_content_reader.dart';
import 'herdr_adapter.dart';

/// herdr のペイン内容読み取り実装。
///
/// `herdr pane read <pane_id> --source <source> [--lines N] --raw` を
/// [HerdrAdapter.paneRead] 経由で実行する。カーソル位置・モード・ペイン
/// サイズは herdr には無いため、スナップショットでは 0 / 空文字のまま
/// 返す（表示側のフォールバックに任せる）。
class HerdrPaneContentReader implements PaneContentReader {
  final HerdrAdapter _adapter;

  HerdrPaneContentReader(this._adapter);

  @override
  Future<MultiplexerPaneSnapshot> readPane({
    required String paneId,
    int? historyLines,
    String source = 'recent',
  }) async {
    // AnsiTextView は ANSI 付き入力で色を描画するため、常に --raw で取得する
    // （tmux 側は pollPane/capturePane が escapeSequences: true 相当）。
    final content = await _adapter.paneRead(
      paneId,
      source: source,
      lines: historyLines?.abs(),
      ansi: true,
    );
    return MultiplexerPaneSnapshot(
      content: content.rawText,
      hasAnsi: content.hasAnsi,
    );
  }
}
