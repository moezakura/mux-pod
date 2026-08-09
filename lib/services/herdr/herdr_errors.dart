// inventory: HERDR-ERR-000
/// herdr 例外の分類述語と errorCode 集合。
///
/// 例外の**種別判定**（server-down / target-not-found）をここに集約する。
/// 画面側の catch 種別分岐（A1/A2）はこの述語を使う。純 Dart（Flutter /
/// SSH 依存なし。ただし transport 層の [SshConnectionError] 型だけ参照する）。
library;

import '../connection_error.dart';
import 'herdr_commands.dart';

// inventory: HERDR-ERR-006
/// server 未稼働を表す errorCode の集合。
///
/// A1 条件2の machine-readable 判定に使う。`herdr` CLI が構造化エラー
/// `{"error":{"code":"..."}}` で返す server 未稼働系コードを列挙する。
const Set<String> kHerdrServerDownErrorCodes = {
  'server_not_running',
  'connection_refused',
  'socket_not_found',
  'connect_error',
  'server_unavailable',
  'not_connected',
  'no_server',
};

// inventory: HERDR-ERR-007
/// 対象（pane/tab/workspace）不在を表す errorCode の集合。
const Set<String> kHerdrTargetNotFoundErrorCodes = {
  'pane_not_found',
  'tab_not_found',
  'workspace_not_found',
};

/// errorCode を [HerdrTargetNotFoundKind] に変換する。
///
/// target-not-found 系コード以外は null を返す。[HerdrAdapter] が
/// [HerdrTargetNotFoundException] を送出するときの kind 解決に使う。
HerdrTargetNotFoundKind? herdrTargetNotFoundKindForCode(String? code) {
  if (code == null) return null;
  return switch (code) {
    'pane_not_found' => HerdrTargetNotFoundKind.pane,
    'tab_not_found' => HerdrTargetNotFoundKind.tab,
    'workspace_not_found' => HerdrTargetNotFoundKind.workspace,
    _ => null,
  };
}

// inventory: HERDR-ERR-008
/// server 未稼働の判定述語（A1）。
///
/// 以下 **3 条件のいずれか** が真のとき true:
/// 1. [HerdrServerNotRunningException]（preflight 由来・既存）
/// 2. [HerdrCommandException] かつ errorCode が server 未稼働系 code
///    （[kHerdrServerDownErrorCodes]）に一致、または message（stderr 由来）
///    が接続拒否・socket 不在・server 停止を示す
/// 3. SSH/transport 層の**確定的接続断**（[SshConnectionError]）のみ。
///    一過性エラー（タイムアウト・コマンド実行失敗）は server-down と
///    判定しない（呼び出し側の「その他」分岐で自動再接続に流し自然復旧させる）
///
/// target-not-found はここでは true に**しない**（別述語
/// [isHerdrTargetNotFound]）。再接続ループ防止（R1）のため、server-down は
/// 呼び出し側で「ポーリング停止 + 通知」に分岐させる。
bool isServerDownException(Object e) {
  if (e is HerdrServerNotRunningException) return true;
  if (e is HerdrCommandException) {
    final code = e.errorCode;
    if (code != null && kHerdrServerDownErrorCodes.contains(code)) return true;
    return _messageIndicatesServerDown(e.message);
  }
  if (e is SshConnectionError) {
    return _sshErrorIndicatesConnectionLost(e.message);
  }
  return false;
}

// inventory: HERDR-ERR-010
/// [SshConnectionError] が「確定的接続断（server-down）」を示すか（A1 条件3）。
///
/// [SshConnectionError] は `ssh_client.dart` で一過性・非 server-down エラー
/// （タイムアウト "Command execution timed out"、コマンド実行失敗
/// "Failed to execute command: ..." など）にも広く使われる。全捕捉すると
/// timeout 等まで server-down に分類され、ポーリング停止 + SnackBar で
/// 自然復旧しなくなる（M1 過検知）。
///
/// ここでは
/// 1. タイムアウト / コマンド実行失敗は false（呼び出し側の「その他」分岐で
///    自動再接続に流す）
/// 2. それ以外でメッセージが確定的接続断（connection lost / not connected /
///    socket・channel closed 等）を示す場合のみ true
/// とする。
bool _sshErrorIndicatesConnectionLost(String message) {
  if (_transientSshFailurePatterns.any((p) => p.hasMatch(message))) {
    return false;
  }
  return _sshConnectionLostPatterns.any((p) => p.hasMatch(message));
}

/// 一過性・非接続断（server-down ではない）を示す [SshConnectionError] の
/// メッセージパターン。
final List<RegExp> _transientSshFailurePatterns = [
  RegExp(r'timed out', caseSensitive: false),
  RegExp(r'failed to execute command', caseSensitive: false),
];

/// 確定的接続断を示す [SshConnectionError] のメッセージパターン（A1 条件3）。
final List<RegExp> _sshConnectionLostPatterns = [
  RegExp(r'connection lost', caseSensitive: false),
  RegExp(r'not connected', caseSensitive: false),
  RegExp(r'disconnected', caseSensitive: false),
  RegExp(r'connection closed', caseSensitive: false),
  RegExp(r'connection reset', caseSensitive: false),
  RegExp(r'socket closed', caseSensitive: false),
  RegExp(r'channel closed', caseSensitive: false),
  RegExp(r'connection refused', caseSensitive: false),
  RegExp(r'econnrefused', caseSensitive: false),
  RegExp(r'broken pipe', caseSensitive: false),
];

// inventory: HERDR-ERR-009
/// 対象（pane/tab/workspace）不在の判定述語。
///
/// [HerdrTargetNotFoundException] の直接インスタンス、または
/// [HerdrCommandException].errorCode が
/// `pane_not_found` / `tab_not_found` / `workspace_not_found` のとき true。
/// target-not-found は再接続せず再解決（`HerdrSnapshotCache.get(force: true)`）
/// → 終端エスカレーションに分岐させる（A2）。
bool isHerdrTargetNotFound(Object e) {
  if (e is HerdrTargetNotFoundException) return true;
  if (e is HerdrCommandException) {
    final code = e.errorCode;
    if (code != null && kHerdrTargetNotFoundErrorCodes.contains(code)) {
      return true;
    }
  }
  return false;
}

// inventory: HERDR-ERR-011
/// 非対応キー（`invalid_key`）を表す errorCode の集合。
///
/// Q-07 の全キー送信経路（`PaneKeyMap`）により通常は発生しないが、万一
/// `send-keys` が未知のキー名を拒否した場合の**防御的**分類に使う（R9）。
const Set<String> kHerdrInvalidKeyErrorCodes = {
  'invalid_key',
};

// inventory: HERDR-ERR-012
/// 非対応キーの判定述語。
///
/// [HerdrCommandException].errorCode が `invalid_key` のとき true。UI はこの
/// 述語で「このキーは herdr で送信できませんでした」の防御的 SnackBar 通知に
/// 分岐する（T19）。target-not-found / server-down とは独立した分類。
bool isHerdrInvalidKey(Object e) {
  if (e is HerdrCommandException) {
    final code = e.errorCode;
    if (code != null && kHerdrInvalidKeyErrorCodes.contains(code)) {
      return true;
    }
  }
  return false;
}

/// message / stderr 由来のテキストが「接続拒否・socket 不在・server 停止」を
/// 示すかどうか。
bool _messageIndicatesServerDown(String message) {
  for (final pattern in _serverDownMessagePatterns) {
    if (pattern.hasMatch(message)) return true;
  }
  return false;
}

/// server-down を示すメッセージのパターン（A1 条件2のテキスト判定）。
final List<RegExp> _serverDownMessagePatterns = [
  RegExp(r'connection refused', caseSensitive: false),
  RegExp(r'econnrefused', caseSensitive: false),
  RegExp(r'failed to connect', caseSensitive: false),
  RegExp(r'(connect to|connecting to).*socket', caseSensitive: false),
  RegExp(r'socket.*(not found|does not exist|no such)', caseSensitive: false),
  RegExp(r'no such file or directory', caseSensitive: false),
  RegExp(
    r'server.*(not running|not started|stopped|unavailable)',
    caseSensitive: false,
  ),
];
