// inventory: HERDR-CMD-000
/// herdr CLI コマンド文字列の生成と preflight 検証。
///
/// 実装方式は CLI 先行方式（socket 直結は次の milestone）。コマンドは
/// [BackendAdapter.execWithExitCode] 経由で実行される。
library;

import 'herdr_models.dart';

// inventory: HERDR-CMD-PROTO-001
/// サポートする herdr protocol 番号。
///
/// G6 合意#2・#6: protocol 17 固定・最小対応版。
const int kHerdrSupportedProtocol = 17;

// inventory: HERDR-CMD-001
/// herdr CLI コマンド文字列を構築するヘルパー。
class HerdrCommands {
  HerdrCommands._();

  // inventory: HERDR-CMD-002
  /// 全階層（workspace/tab/pane/layout）のスナップショットを JSON で返す。
  static String snapshot() => 'herdr api snapshot';

  // inventory: HERDR-CMD-004
  /// protocol 確認用の status コマンド（JSON 出力）。
  static String preflightCommand() => 'herdr status --json';

  // inventory: HERDR-CMD-005
  /// pane の内容を読み取る（表示用）。
  ///
  /// コマンド形式:
  /// `herdr pane read <pane_id> --source <source> [--lines N] [--raw]`
  /// - [paneId]: 読み取り対象の pane ID（例: "w1:p1"。先頭に配置）。
  /// - [source]: `'visible'`（可視領域）または `'recent'`（履歴含む）。
  /// - [lines]: 読み取る行数（null なら全量）。
  /// - [ansi]: true なら `--raw` を付与し ANSI エスケープ付きで取得する。
  static String paneRead(
    String paneId, {
    String source = 'recent',
    int? lines,
    bool ansi = false,
  }) {
    final parts = ['herdr', 'pane', 'read', paneId, '--source', source];
    if (lines != null) parts.addAll(['--lines', lines.toString()]);
    if (ansi) parts.add('--raw');
    return parts.join(' ');
  }

  // ===== mutation コマンド（Q-02/Q-03/Q-06/Q-07。T0 実測の CLI 形式）=====

  // inventory: HERDR-CMD-100
  /// pane へテキストを送信する（Q-06: paste/copy-mode/画像パスの送信基盤）。
  ///
  /// コマンド形式: `herdr pane send-text <pane_id> <text>`
  /// 成功時 stdout は空（R7）。[text] はシェル引用符で括る（複数行・unicode
  /// 対応。`send-text` はバイナリ素通し・G4 実測）。
  static String paneSendText(String paneId, String text) {
    return 'herdr pane send-text $paneId ${_shellQuote(text)}';
  }

  // inventory: HERDR-CMD-101
  /// pane へキーを送信する（Q-07: `PaneKeyMap` の送信経路で変換済みキー名）。
  ///
  /// コマンド形式: `herdr pane send-keys <pane_id> <key>`
  /// 受理キーは F1-F12 / 基本 / 矢印 / C-c（T0 実測 1-a）。拒否キーは
  /// `paneSendText` でエスケープシーケンス / 制御文字を送る。
  static String paneSendKeys(String paneId, String keyName) {
    return 'herdr pane send-keys $paneId $keyName';
  }

  // inventory: HERDR-CMD-102
  /// 方向 focus（`--pane` 指定）。
  ///
  /// コマンド形式: `herdr pane focus --direction <dir> --pane <pane_id>`
  /// [direction]: `'up'` / `'down'` / `'left'` / `'right'`。
  /// 隣接なしはエラーではなく `reason:"no_neighbor"` + `changed:false`
  /// （T0 実測 5-b・soft 失敗）。
  static String paneFocus(String paneId, String direction) {
    return 'herdr pane focus --direction $direction --pane $paneId';
  }

  // inventory: HERDR-CMD-103
  /// 隣接方向の有無を返す。
  ///
  /// コマンド形式: `herdr pane edges --pane <pane_id>`
  /// 応答は `{up,down,left,right}` の bool + layout（T0 実測 5-a）。
  static String paneEdges(String paneId) {
    return 'herdr pane edges --pane $paneId';
  }

  // inventory: HERDR-CMD-104
  /// 相対分数 resize（Q-04）。
  ///
  /// コマンド形式:
  /// `herdr pane resize --direction <dir> --amount <FLOAT> --pane <pane_id>`
  /// [amount] は現在 ratio への加算・結果は [0.1, 0.9] にクランプ・
  /// 1 回の delta 上限 0.5（T0 実測 4-b）。
  static String paneResize(String paneId, String direction, double amount) {
    return 'herdr pane resize --direction $direction '
        '--amount ${amount.toString()} --pane $paneId';
  }

  // inventory: HERDR-CMD-105
  /// zoom。
  ///
  /// コマンド形式: `herdr pane zoom --pane <pane_id> --<mode>`
  /// [mode]: `'toggle'` / `'on'` / `'off'`（既定 `'toggle'`）。
  static String paneZoom(String paneId, {String mode = 'toggle'}) {
    return 'herdr pane zoom --pane $paneId --$mode';
  }

  // inventory: HERDR-CMD-106
  /// ラベル変更。
  ///
  /// コマンド形式: `herdr pane rename <pane_id> <label>...`
  static String paneRename(String paneId, String label) {
    return 'herdr pane rename $paneId ${_shellQuote(label)}';
  }

  // inventory: HERDR-CMD-107
  /// pane を閉じる（**破壊的 close の唯一経路**・Q-03）。
  ///
  /// コマンド形式: `herdr pane close <pane_id>`
  /// 最後の pane を閉じると tab → workspace が連鎖終了する（lifecycle 実測・
  /// R2）。対象不在は `pane_not_found`（`isHerdrTargetNotFound`）。
  static String paneClose(String paneId) {
    return 'herdr pane close $paneId';
  }

  // inventory: HERDR-CMD-108
  /// pane を分割する。
  ///
  /// コマンド形式:
  /// `herdr pane split <pane_id> --direction <dir> [--ratio <FLOAT>] [--cwd <path>]`
  /// [direction]: `'right'` / `'down'`。
  /// 応答は layout を含まない（`pane_info`。T0 実測 6-a）。layout 反映は
  /// 別途 `api snapshot` が必要。
  static String paneSplit(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
  }) {
    final parts = ['herdr', 'pane', 'split', paneId, '--direction', direction];
    if (ratio != null) parts.addAll(['--ratio', ratio.toString()]);
    if (cwd != null && cwd.isNotEmpty) {
      parts.addAll(['--cwd', _shellQuote(cwd)]);
    }
    return parts.join(' ');
  }

  // inventory: HERDR-CMD-109
  /// tab を作成する（Q-05）。
  ///
  /// コマンド形式:
  /// `herdr tab create --workspace <workspace_id> [--cwd <path>] [--label <label>] [--focus|--no-focus]`
  /// 応答は layout を含まない（`.result.tab.tab_id` / `.result.root_pane.pane_id`。
  /// herdr 0.7.5 CLI reference）。layout 反映は別途 `api snapshot` が必要。
  /// [focus]: null なら省略（herdr 既定: フォーカス不変）・true で `--focus`・
  /// false で `--no-focus`（既定を明示）。
  static String tabCreate(
    String workspaceId, {
    String? label,
    String? cwd,
    bool? focus,
  }) {
    final parts = ['herdr', 'tab', 'create', '--workspace', workspaceId];
    if (cwd != null && cwd.isNotEmpty) {
      parts.addAll(['--cwd', _shellQuote(cwd)]);
    }
    if (label != null && label.isNotEmpty) {
      parts.addAll(['--label', _shellQuote(label)]);
    }
    if (focus == true) {
      parts.add('--focus');
    } else if (focus == false) {
      parts.add('--no-focus');
    }
    return parts.join(' ');
  }

  // inventory: HERDR-CMD-110
  /// tab を閉じる。
  ///
  /// コマンド形式: `herdr tab close <tab_id>`
  /// workspace の最後の tab を閉じると workspace も連鎖終了する
  /// （herdr 0.7.5 CLI reference）。対象不在は `tab_not_found`
  /// （`isHerdrTargetNotFound`）。
  static String tabClose(String tabId) {
    return 'herdr tab close $tabId';
  }

  // inventory: HERDR-CMD-111
  /// tab のラベルを変更する。
  ///
  /// コマンド形式: `herdr tab rename <tab_id> <label>`
  static String tabRename(String tabId, String label) {
    return 'herdr tab rename $tabId ${_shellQuote(label)}';
  }

  // inventory: HERDR-CMD-112
  /// tab へフォーカスする。
  ///
  /// コマンド形式: `herdr tab focus <tab_id>`
  static String tabFocus(String tabId) {
    return 'herdr tab focus $tabId';
  }

  // inventory: HERDR-CMD-113
  /// workspace を作成する（Q-05）。
  ///
  /// コマンド形式:
  /// `herdr workspace create [--cwd <path>] [--label <label>] [--focus|--no-focus]`
  /// workspace 作成と同時に最初の tab と root pane も作られる。応答は layout
  /// を含まない（`.result.workspace.workspace_id` / `.result.tab.tab_id` /
  /// `.result.root_pane.pane_id`。herdr 0.7.5 CLI reference）。
  /// [focus]: null なら省略（herdr 既定: フォーカス不変）・true で `--focus`・
  /// false で `--no-focus`（既定を明示）。
  static String workspaceCreate({String? label, String? cwd, bool? focus}) {
    final parts = ['herdr', 'workspace', 'create'];
    if (cwd != null && cwd.isNotEmpty) {
      parts.addAll(['--cwd', _shellQuote(cwd)]);
    }
    if (label != null && label.isNotEmpty) {
      parts.addAll(['--label', _shellQuote(label)]);
    }
    if (focus == true) {
      parts.add('--focus');
    } else if (focus == false) {
      parts.add('--no-focus');
    }
    return parts.join(' ');
  }

  // inventory: HERDR-CMD-114
  /// workspace を閉じる。
  ///
  /// コマンド形式: `herdr workspace close <workspace_id>`
  /// 対象不在は `workspace_not_found`（`isHerdrTargetNotFound`）。
  static String workspaceClose(String workspaceId) {
    return 'herdr workspace close $workspaceId';
  }

  // inventory: HERDR-CMD-115
  /// workspace のラベルを変更する。
  ///
  /// コマンド形式: `herdr workspace rename <workspace_id> <label>`
  static String workspaceRename(String workspaceId, String label) {
    return 'herdr workspace rename $workspaceId ${_shellQuote(label)}';
  }

  // inventory: HERDR-CMD-116
  /// workspace へフォーカスする。
  ///
  /// コマンド形式: `herdr workspace focus <workspace_id>`
  static String workspaceFocus(String workspaceId) {
    return 'herdr workspace focus $workspaceId';
  }

  /// シェル引用符で囲む。`'` は `'\''` にエスケープする。
  ///
  /// コマンドは SSH 経由でシェルに渡るため、空白・改行・unicode を含む
  /// テキスト（send-text / rename label / split cwd）を安全に転送する。
  ///
  /// **制御文字（0x00-0x1F / 0x7F）を含む場合は bash の ANSI-C quoting
  /// （`$'...'`）で送る**。通常の単一引用符で囲むと、コマンドライン内の
  /// 制御文字（Ctrl+A = 行頭移動、Ctrl+O = 履歴操作、Ctrl+E = 行末移動等）
  /// を、対話シェルの readline が解釈して失うため。`$'...'` 形式なら
  /// 制御文字を `\xHH` のリテラル表現で送り、実行時に bash が制御文字へ
  /// 復元する（readline に吸われない）。
  static String _shellQuote(String value) {
    if (value.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      final buffer = StringBuffer("\$'");
      for (final rune in value.runes) {
        if (rune < 0x20 || rune == 0x7f) {
          buffer.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
        } else if (rune == 0x5c) {
          // backslash
          buffer.write(r'\\');
        } else if (rune == 0x27) {
          // single quote
          buffer.write(r"\'");
        } else {
          buffer.writeCharCode(rune);
        }
      }
      buffer.write("'");
      return buffer.toString();
    }
    return "'${value.replaceAll("'", r"'\''")}'";
  }
}

// inventory: HERDR-ERR-001
/// herdr CLI 実行の失敗を表す例外。
///
/// コマンドが非 0 で終了した場合や、出力が期待した形式でない場合に投げる。
class HerdrCommandException implements Exception {
  /// エラーメッセージ。
  final String message;

  /// コマンドの終了コード（不明な場合は null）。
  final int? exitCode;

  /// 構造化エラー JSON の `error.code`（machine-readable）。
  ///
  /// stdout/stderr のいずれかが
  /// `{"error":{"code":"...","message":"..."}}` 形式のとき抽出される
  /// （無ければ null）。`isServerDownException` / `isHerdrTargetNotFound`
  /// （herdr_errors.dart）の分類に使う。
  final String? errorCode;

  /// 元の例外（任意）。
  final Object? cause;

  HerdrCommandException(
    this.message, {
    this.exitCode,
    this.errorCode,
    this.cause,
  });

  @override
  String toString() => 'HerdrCommandException: $message';
}

// inventory: HERDR-ERR-004
/// 対象（pane/tab/workspace）が存在しないことの種別。
enum HerdrTargetNotFoundKind {
  /// pane 不在（errorCode: `pane_not_found`）
  pane,

  /// tab 不在（errorCode: `tab_not_found`）
  tab,

  /// workspace 不在（errorCode: `workspace_not_found`）
  workspace,
}

// inventory: HERDR-ERR-005
/// 対象 pane/tab/workspace が存在しないことを表す例外。
///
/// target-not-found 系 errorCode（`pane_not_found` / `tab_not_found` /
/// `workspace_not_found`）を [HerdrAdapter] が検出したときに送出する。
///
/// [HerdrCommandException] は継承しない（既存例外の継承関係を変えない。
/// catch 順序で server-down と誤判定されるのを防ぐため例外の「種別」を
/// 分離する）。判定は `isHerdrTargetNotFound`（herdr_errors.dart）が行う。
class HerdrTargetNotFoundException implements Exception {
  /// 不在だった対象の種別。
  final HerdrTargetNotFoundKind kind;

  /// エラーメッセージ（stdout/stderr 由来）。
  final String message;

  /// 構造化エラー JSON の `error.code`（例: `pane_not_found`）。
  final String? errorCode;

  /// コマンドの終了コード（不明な場合は null）。
  final int? exitCode;

  /// 元の例外（任意）。
  final Object? cause;

  const HerdrTargetNotFoundException({
    required this.kind,
    required this.message,
    this.errorCode,
    this.exitCode,
    this.cause,
  });

  @override
  String toString() => 'HerdrTargetNotFoundException($kind): $message';
}

// inventory: HERDR-ERR-002
/// preflight で protocol が非対応（17 以外）の場合に投げる例外。
class HerdrProtocolMismatchException implements Exception {
  /// サポートする protocol 番号（17）。
  final int supported;

  /// 実測された protocol 番号。
  final int actual;

  HerdrProtocolMismatchException({
    required this.supported,
    required this.actual,
  });

  @override
  String toString() =>
      'HerdrProtocolMismatchException: protocol $actual is not supported '
      '(expected $supported)';
}

// inventory: HERDR-ERR-003
/// preflight で herdr server が稼働していない場合に投げる例外。
///
/// protocol 不整合（[HerdrProtocolMismatchException]）とは区別し、ユーザーに
/// 「サーバ未起動」であることを明示する。実測では未稼働時に
/// `server.protocol` が null となりパーサが 0 へ変換するため、protocol
/// 判定だけでは原因を誤報告する（`HerdrServerNotRunningException` で解決）。
///
/// 既存の `HerdrCommandException` を継承しない（接続画面の catch 順序で
/// 「herdr not found」と誤表示されるのを防ぐため）。
class HerdrServerNotRunningException implements Exception {
  /// ユーザー向けの案内文。
  final String message;

  HerdrServerNotRunningException()
    : message =
          "Herdr server is not running. Start it with 'herdr server' first.";

  @override
  String toString() => 'HerdrServerNotRunningException: $message';
}

// inventory: HERDR-PREFLIGHT-001
/// `herdr status --json` の結果から protocol 17 を検証する preflight。
///
/// コマンド実行は [HerdrAdapter.preflight] が行い、このクラスは検証のみを
/// 担当する。server 未稼働の場合は [HerdrServerNotRunningException]、
/// protocol が 17 以外の場合は [HerdrProtocolMismatchException] を投げる
/// （G6 合意#2・#6: protocol 17 固定・最小対応版）。
class HerdrPreflight {
  HerdrPreflight._();

  /// サポートする protocol 番号。
  static const int supportedProtocol = kHerdrSupportedProtocol;

  // inventory: HERDR-PREFLIGHT-002
  /// [status] の client/server protocol が 17 であることを検証する。
  ///
  /// 検証順序:
  /// 1. server 未稼働（[HerdrStatus.running] == false）なら
  ///    [HerdrServerNotRunningException] を投げる（protocol 判定より先）。
  /// 2. client/server protocol が 17 以外なら [HerdrProtocolMismatchException]。
  ///
  /// 検証に成功した場合は [status] をそのまま返す。
  static HerdrStatus validate(HerdrStatus status) {
    // server 未稼働は protocol 不整合より先に専用例外で報告する。
    // 実測では未稼働時に `server.protocol` が null となり `_asInt` が 0 へ
    // 変換されるため、protocol 判定だけでは「protocol 0 が非対応」と誤報告する。
    if (!status.running) {
      throw HerdrServerNotRunningException();
    }
    final client = status.clientProtocol;
    final server = status.serverProtocol;
    if (client != supportedProtocol || server != supportedProtocol) {
      // より具体的な方（server 優先）を actual として報告する。
      final actual = server != supportedProtocol ? server : client;
      throw HerdrProtocolMismatchException(
        supported: supportedProtocol,
        actual: actual,
      );
    }
    return status;
  }
}
