/// ペイン内容読み取りの共通 domain。
///
/// tmux（`TmuxPaneContentReader`）と herdr（`HerdrPaneContentReader`）の
/// backend 差異（カーソル位置・モード・サイズの有無）を吸収し、
/// 表示コア（`AnsiTextView` / ポーリングループ）が同じコードで
/// 両 backend を扱えるようにする。
library;

/// ペイン内容読み取り結果の共通 domain スナップショット。
///
/// herdr にはカーソル位置・モードが無いため、それらは 0 / 空文字のまま
/// （フォールバック）で返す。サイズも不明なら 0 のまま（表示側は
/// `width > 0 && height > 0` のガードで既定値へフォールバックする）。
class MultiplexerPaneSnapshot {
  /// 表示用の生テキスト（ANSI エスケープ付きの場合あり）。
  final String content;

  /// ペインの文字幅（不明なら 0）。
  final int width;

  /// ペインの文字高さ（不明なら 0）。
  final int height;

  /// カーソル X（0-based。不明なら 0）。
  final int cursorX;

  /// カーソル Y（0-based。不明なら 0）。
  final int cursorY;

  /// モード文字列（tmux copy-mode 等。無い backend は空文字）。
  final String paneMode;

  /// 内容が ANSI エスケープを含むかどうか。
  final bool hasAnsi;

  const MultiplexerPaneSnapshot({
    required this.content,
    this.width = 0,
    this.height = 0,
    this.cursorX = 0,
    this.cursorY = 0,
    this.paneMode = '',
    this.hasAnsi = false,
  });

  @override
  String toString() =>
      'MultiplexerPaneSnapshot(${width}x$height, ${content.length} chars, '
      'cursor=$cursorX,$cursorY, mode="$paneMode", ansi: $hasAnsi)';
}

/// ペイン内容の読み取り抽象。
///
/// 表示コアはこの抽象だけに依存する。失敗時は例外
/// （`TmuxCommandException` / `HerdrCommandException`）を投げる。
abstract interface class PaneContentReader {
  /// [paneId] の内容を読み取る。
  ///
  /// [historyLines]: 末尾から遡る履歴行数。
  ///   - null: 可視領域のみ。
  ///   - 負の小さな値（例: -120）: 直近のライブポーリング内容。
  ///   - 負の大きな値（例: -100000）: スクロールバック全体（深い履歴）。
  /// [source]: herdr の `'visible'` / `'recent'`（tmux では無視）。
  Future<MultiplexerPaneSnapshot> readPane({
    required String paneId,
    int? historyLines,
    String source = 'recent',
  });
}
