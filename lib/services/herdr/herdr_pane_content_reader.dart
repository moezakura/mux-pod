// inventory: HERDR-READ-000
/// herdr のペイン内容読み取り実装。
///
/// `herdr pane read <pane_id> --source <source> [--lines N] --raw` を
/// [HerdrAdapter.paneRead] 経由で実行する。カーソル位置・モードは herdr には
/// 無いため、スナップショットでは 0 / 空文字のまま返す（表示側のフォール
/// バックに任せる）。ペインサイズも `pane read` からは得られないため
/// [MultiplexerPaneSnapshot.geometry] は null（既定 80x24 へフォールバック）。
///
/// ライブ / スクロールバックの両方とも持続的シェル経由（`viaPersistent`）で
/// 取得する。`pane read --lines N` は行数を指定する単一コマンドであり、
/// tmux のような live/deep のコマンド経路差は無いため、行数閾値
/// （`-120`/`-32768`）による暗黙のチャネル分離は行わない（バグ2 / バグ4
/// 根本対応）。
library;

import '../backend/domain/pane_content_reader.dart';
import '../backend/domain/pane_read.dart';
import 'herdr_adapter.dart';

class HerdrPaneContentReader implements PaneContentReader {
  final HerdrAdapter _adapter;

  HerdrPaneContentReader(this._adapter);

  @override
  Future<MultiplexerPaneSnapshot> readPane(PaneReadRequest request) async {
    // AnsiTextView は ANSI 付き入力で色を描画するため、常に --raw で取得する
    // （tmux 側は pollPane/capturePane が escapeSequences: true 相当）。
    final content = await _adapter.paneRead(
      request.paneId,
      source: 'recent',
      lines: request.maxLines,
      ansi: true,
      viaPersistent: true,
    );
    return MultiplexerPaneSnapshot(
      content: content.rawText,
      hasAnsi: content.hasAnsi,
    );
  }
}
