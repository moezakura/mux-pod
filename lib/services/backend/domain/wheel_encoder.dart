// inventory: WHEEL-ENCODER-000
/// スクロール送信の種別。
///
/// [ScrollSendKind.wheel] は SGR 1006 マウスプロトコルのホイールイベント
/// （`ESC[<64;X;YM` = 上 / `ESC[<65;X;YM` = 下）を送信し、
/// [ScrollSendKind.key] は PgUp / PgDn キー（`ESC[5~` / `ESC[6~`）を送信する。
/// 送信方式の切替（設定 `scrollSendInput`）で UI が選択する。
enum ScrollSendKind { wheel, key }

// inventory: WHEEL-ENCODER-001
/// SGR 1006 ホイール / PgUp・PgDn のエンコード純関数。
///
/// UI（`TerminalScreen` の合流送信）と backend（[PaneWriter.sendScroll]）の
/// 両方から再利用できるよう、エンコード文字列の生成を 1 箇所に分離する
/// （D10）。**純関数**（同期・副作用なし・throw しない）。
///
/// エスケープ値の根拠:
/// - SGR 1006 ホイール: ボタン番号 64 = 上 / 65 = 下（xterm マウスプロトコル）。
///   座標は送信側で無意味のため最小値 `1;1` をデフォルトとする（D7）。
/// - PgUp / PgDn: xterm の CSI シーケンス `ESC[5~` / `ESC[6~`
///   （`herdr_keymap.dart` の PPage / NPage と同一値・G4 実測でバイナリ素通し）。
class WheelEncoder {
  const WheelEncoder._();

  /// SGR 1006 ホイールイベントを [ticks] 個連結して返す。
  ///
  /// [up] が true なら上スクロール（ボタン 64）、false なら下スクロール
  /// （ボタン 65）。[x] / [y] は SGR 座標（デフォルト `1;1`・D7）。
  /// [ticks] が 1 以下の場合は空文字を返す（純関数・throw しない）。
  static String encodeSgr({
    required bool up,
    required int ticks,
    int x = 1,
    int y = 1,
  }) {
    if (ticks <= 0) return '';
    final button = up ? 64 : 65;
    final seq = '\x1b[<$button;$x;${y}M';
    return seq * ticks;
  }

  /// PgUp（[up] true = `ESC[5~`）/ PgDn（[up] false = `ESC[6~`）を [ticks] 個
  /// 連結して返す。
  ///
  /// [ticks] が 1 以下の場合は空文字を返す（純関数・throw しない）。
  static String encodePage({required bool up, required int ticks}) {
    if (ticks <= 0) return '';
    final seq = up ? '\x1b[5~' : '\x1b[6~';
    return seq * ticks;
  }
}
