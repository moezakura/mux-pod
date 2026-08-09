/// ペイン操作の共通 domain（write 側抽象）。
///
/// read 側の [PaneContentReader]（`pane_content_reader.dart`）と対をなす
/// write 抽象。tmux（`TmuxPaneWriter`）と herdr（`HerdrPaneWriter`）の
/// 2 実装がこの interface を実装し、UI（`TerminalScreen`）からバックエンド
/// 分岐を排除する（R3: stale tmuxProvider への誤送信の構造的対策）。
library;

/// 非対応操作を表す例外。
///
/// バックエンドが持たない操作（例: herdr の絶対値 resize・copy-mode）を
/// 呼んだときに [PaneWriter] 実装が投げる。UI はこの例外をキャッチして
/// SnackBar 通知またはボタン無効化に使う（失敗の swallow を止める R4/R9）。
class UnsupportedPaneOperationException implements Exception {
  /// 非対応の操作名（例: "absoluteResize" / "copyMode"）。
  final String operation;

  /// バックエンド名（例: "herdr" / "tmux"）。
  final String backend;

  /// ユーザー向けの案内文（任意）。
  final String? message;

  const UnsupportedPaneOperationException({
    required this.operation,
    required this.backend,
    this.message,
  });

  @override
  String toString() =>
      'UnsupportedPaneOperationException($backend.$operation)';
}

/// 操作は実行されたが状態が変化しなかった（soft 失敗）ことを表す例外。
///
/// herdr の resize が `changed:false`（分割境界外）・focus が
/// `reason:"no_neighbor"`（隣接なし）を返したときなどに [PaneWriter] 実装が
/// 投げる。**失敗（エラー）ではなく情報通知（S4）**を意図する例外であり、
/// UI はキャッチして SnackBar（情報）を表示する。
class PaneOperationNoopException implements Exception {
  /// 操作名（例: `"resizePane"` / `"focusPaneDirection"`）。
  final String operation;

  /// 応答の `reason`（`"unchanged"` / `"no_neighbor"` 等・無ければ null）。
  final String? reason;

  const PaneOperationNoopException({required this.operation, this.reason});

  @override
  String toString() =>
      'PaneOperationNoopException($operation, reason: $reason)';
}

/// キー送信経路。
///
/// [PaneWriter.mapSpecialKey] が tmux キー名を herdr の送信経路へ変換した
/// 結果を表す sealed な値型。3 経路（send-keys / send-text エスケープ /
/// send-text 制御文字）は T0 実測
/// （`tool/herdr-mutation-baseline/mutation-baseline-report.md`）に基づく。
sealed class HerdrKeyRoute {
  const HerdrKeyRoute();

  /// `herdr pane send-keys <PANE> <KEY>` で送信する経路。
  ///
  /// T0 実測 1-a の受理キー（F1-F12 / Enter / Tab / Space / Backspace / BS /
  /// Escape / 矢印 / C-c）に使う。
  const factory HerdrKeyRoute.sendKeys(String keyName) =
      HerdrKeyRouteSendKeys._;

  /// `herdr pane send-text <PANE> <BYTES>` でエスケープシーケンスを送信する
  /// 経路。
  ///
  /// send-keys が拒否するキー（Home/End/PgUp/PgDn/Delete/Insert・修飾キー等）
  /// の代替。send-text はバイナリ素通し（G4 実測）のためシーケンスがそのまま
  /// アプリに届く（T0 実測②）。
  const factory HerdrKeyRoute.sendTextEscape(String bytes) =
      HerdrKeyRouteSendTextEscape._;

  /// `herdr pane send-text <PANE> <BYTE>` で制御文字（0x00-0x1f / 0x7f）を
  /// 送信する経路。
  ///
  /// C-d=0x04 / C-x=0x18 等の C-* 制御文字（T0 実測③）。
  const factory HerdrKeyRoute.sendTextControl(int byte) =
      HerdrKeyRouteSendTextControl._;
}

/// [HerdrKeyRoute.sendKeys] の実体（`send-keys` 受理キー名）。
final class HerdrKeyRouteSendKeys extends HerdrKeyRoute {
  /// herdr `send-keys` に渡すキー名。
  final String keyName;

  const HerdrKeyRouteSendKeys._(this.keyName);
}

/// [HerdrKeyRoute.sendTextEscape] の実体（`send-text` エスケープシーケンス）。
final class HerdrKeyRouteSendTextEscape extends HerdrKeyRoute {
  /// 送信するバイト列（例: `\x1b[H` = Home）。
  final String bytes;

  const HerdrKeyRouteSendTextEscape._(this.bytes);
}

/// [HerdrKeyRoute.sendTextControl] の実体（`send-text` 制御文字）。
final class HerdrKeyRouteSendTextControl extends HerdrKeyRoute {
  /// 送信する制御文字のバイト値（例: 0x04 = C-d）。
  final int byte;

  const HerdrKeyRouteSendTextControl._(this.byte);
}

/// バックエンドの操作能力セット。
///
/// UI は `_can(capability)` で操作を有効/無効にする。`_isReadOnly` の
/// boolean では操作単位の解禁/遮断を表現できない（H4 等価性テスト）ため、
/// 操作単位の判定をこの値に集約する。判定は純データで副作用なし。
class PaneCapabilities {
  /// テキスト送信（`send-text`）が可能か。
  final bool sendText;

  /// 特殊キー送信（`send-keys` / エスケープ / 制御文字）が可能か。
  final bool sendKeys;

  /// フォーカス移動（方向 focus / 直接選択）が可能か。
  final bool focus;

  /// 分割（split）が可能か。
  final bool split;

  /// クローズが可能か。
  final bool close;

  /// リネームが可能か。
  final bool rename;

  /// zoom が可能か。
  final bool zoom;

  /// resize が可能か。
  final bool resize;

  /// paste（複数行貼り付け）が可能か。
  final bool paste;

  /// copy-mode（履歴選択モード）が可能か。
  final bool copyMode;

  /// 画像転送が可能か。
  final bool imageTransfer;

  /// workspace CRUD が可能か。
  final bool workspaceCrud;

  /// tab CRUD が可能か。
  final bool tabCrud;

  /// 絶対値 resize（cols/rows 指定）が可能か。
  ///
  /// herdr は相対分数のみのため false（Q-04）。
  final bool absoluteResize;

  const PaneCapabilities({
    this.sendText = false,
    this.sendKeys = false,
    this.focus = false,
    this.split = false,
    this.close = false,
    this.rename = false,
    this.zoom = false,
    this.resize = false,
    this.paste = false,
    this.copyMode = false,
    this.imageTransfer = false,
    this.workspaceCrud = false,
    this.tabCrud = false,
    this.absoluteResize = false,
  });
}

/// ペイン操作の write 抽象（tmux / herdr 共通）。
///
/// 非対応操作は [UnsupportedPaneOperationException] を throw する。
/// 失敗時は各実装の例外（`TmuxCommandException` / `HerdrCommandException` /
/// [HerdrTargetNotFoundException] 等）を投げる。
abstract interface class PaneWriter {
  /// このバックエンドが持つ操作能力。
  PaneCapabilities get capabilities;

  /// tmux キー名を送信経路へ変換する。
  ///
  /// **全キーで送信経路が返る**（「送信できないキー」なし・Q-07）。herdr は
  /// `PaneKeyMap` で変換し、tmux は同一キー名の send-keys を返す。
  HerdrKeyRoute mapSpecialKey(String tmuxKey);

  /// [paneId] へテキストを送信する。
  Future<void> sendText(String paneId, String text);

  /// [paneId] へ tmux キー名のキーを送信する。
  ///
  /// 送信経路は [mapSpecialKey] の結果に従う（send-keys / send-text
  /// エスケープ / send-text 制御文字）。
  Future<void> sendKey(String paneId, String tmuxKey);

  /// [paneId] を選択（フォーカス）する。
  Future<void> selectPane(String paneId);

  /// [paneId] から [direction] 方向の隣接 pane へフォーカスを移す。
  ///
  /// [direction]: `'up'` / `'down'` / `'left'` / `'right'`。
  Future<void> focusPaneDirection(String paneId, String direction);

  /// [paneId] を [direction] 方向に分割する。
  ///
  /// [direction]: `'right'` / `'down'`。
  Future<void> splitPane(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
  });

  /// [paneId] を閉じる（破壊的 close の唯一経路・Q-03）。
  Future<void> closePane(String paneId);

  /// [paneId] のラベルを [label] に変更する。
  Future<void> renamePane(String paneId, String label);

  /// [paneId] を zoom する。
  ///
  /// [mode]: `'toggle'` / `'on'` / `'off'`。
  Future<void> zoomPane(String paneId, {String mode = 'toggle'});

  /// [paneId] を [direction] 方向に [amount] だけ resize する。
  ///
  /// [amount] は相対分数（herdr）。絶対値 resize は
  /// [UnsupportedPaneOperationException]（Q-04）。
  Future<void> resizePane(String paneId, String direction, double amount);

  /// [workspaceId] に tab を作成する。
  Future<void> createTab(String workspaceId);

  /// [tabId] を閉じる。
  Future<void> closeTab(String tabId);

  /// [tabId] のラベルを変更する。
  Future<void> renameTab(String tabId, String label);

  /// [tabId] へフォーカスする。
  Future<void> focusTab(String tabId);

  /// [label] の workspace を作成する。
  Future<void> createWorkspace(String label);

  /// [workspaceId] を閉じる。
  Future<void> closeWorkspace(String workspaceId);

  /// [workspaceId] のラベルを変更する。
  Future<void> renameWorkspace(String workspaceId, String label);

  /// [workspaceId] へフォーカスする。
  Future<void> focusWorkspace(String workspaceId);

  /// [paneId] へ複数行テキストを貼り付ける（Q-06）。
  Future<void> pasteText(String paneId, String text);

  /// [path] の画像を転送する（Q-06）。
  Future<void> imageTransfer(String path);
}
