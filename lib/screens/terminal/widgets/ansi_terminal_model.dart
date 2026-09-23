/// ターミナル入力プロトコルと操作モードの値型定義（P3-2）。
///
/// `ansi_text_view.dart` は本ファイルを re-export するため、外部（terminal_screen
/// やテスト）の import パスは変更されない。
library;

/// キー入力イベント
class KeyInputEvent {
  /// キーデータ（エスケープシーケンスまたは文字）
  final String data;

  /// 特殊キーかどうか
  final bool isSpecialKey;

  /// tmux形式のキー名（Enterの場合は'Enter'など）
  /// isSpecialKeyがtrueの場合に使用
  final String? tmuxKeyName;

  const KeyInputEvent({
    required this.data,
    this.isSpecialKey = false,
    this.tmuxKeyName,
  });
}

/// ターミナルの操作モード
///
/// 3 モードは排他的（同時に成立しない）: 「Scroll 送信」と「選択」が混在
/// しないことを enum 値の分離で構造的に担保する（D1）。
enum TerminalMode {
  /// 通常モード（キー入力が有効・ライブ表示）
  normal,

  /// 選択モード（履歴閲覧＋テキスト選択・tmux copy-mode / SelectionArea・バッファ保持）
  ///
  /// 旧 `TerminalMode.scroll` のリネーム（D1）。
  select,

  /// スクロール送信モード（アプリへ SGR ホイール / PgUp・PgDn / 文字キーを送信・
  /// ローカルスクロール無効・テキスト選択なし・ライブ表示）
  scrollSend,
}
