// inventory: HERDR-READ-000
/// herdr のペイン内容読み取り実装。
///
/// `herdr pane read <pane_id> --source <source> [--lines N] --raw` を
/// [HerdrAdapter.paneRead] 経由で実行する。カーソル位置・モード・ペイン
/// サイズは herdr には無いため、スナップショットでは 0 / 空文字のまま
/// 返す（表示側のフォールバックに任せる）。
///
/// **ライブポーリング（直近行）は持続的シェル経由（`viaPersistent: true`）**、
/// **深い履歴（スクロールバック全体）は exec チャネル経由**（`viaPersistent:
/// false`）で取得する（バグ2: 描画遅延の修正。tmux の pollPane（persistent）/
/// capturePane（exec）の分離と対称）。
library;

import '../backend/domain/pane_content_reader.dart';
import 'herdr_adapter.dart';

class HerdrPaneContentReader implements PaneContentReader {
  /// 深い履歴と判定する履歴行数の閾値。
  ///
  /// ライブポーリングは常に `historyLines = -120`（terminal_screen の
  /// `_pollPaneContent`）で呼ばれ、深い履歴はスクロールモード・オーバースクロール
  /// 時の [_loadHistoryForScroll] が「ユーザー設定 scrollbackLines」分（クランプ
  /// [200, 20000]・バグ4）を要求する。よって「-120 より深い要求」は深い履歴と
  /// 判定し、大量出力を exec チャネル（`viaPersistent: false`）で取得する
  /// （バグ2: tmux の capturePane（exec）対比・ホットパスを塞がない）。
  static const int deepHistoryThreshold = -120;

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
    final deep = historyLines != null && historyLines < deepHistoryThreshold;
    final content = await _adapter.paneRead(
      paneId,
      source: source,
      lines: historyLines?.abs(),
      ansi: true,
      // ライブポーリングは持続的シェル経由（チャネル再利用・バグ2）。
      // 深い履歴は大量出力を伴うため exec チャネル（従来）のまま。
      viaPersistent: !deep,
    );
    return MultiplexerPaneSnapshot(
      content: content.rawText,
      hasAnsi: content.hasAnsi,
    );
  }
}
