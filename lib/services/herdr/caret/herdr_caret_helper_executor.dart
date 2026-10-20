// inventory: HERDR-CARET-EXEC-000
/// 配置済み herdr-caret-helper の 1 回実行（snapshot 取得）を担う。
///
/// 処理フロー（Phase 3 契約・run 部分）:
/// shellQuote 済み引数でコマンドを構築 → ephemeral SSH で実行 → 出力検証
/// （JSON 単一行・64KB 打ち切り・exit code）。helper 実行は呼び出し毎に
/// 行い、実行頻度の制御（TTL・pane 単位 single-flight・epoch 照合）は
/// reader 側（[HerdrCaretHelperSnapshotReader]）が担うため、ここでは
/// single-flight しない。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'herdr_caret_helper_manifest.dart';
import 'herdr_caret_helper_types.dart';
import 'herdr_caret_shell_args.dart';
import 'herdr_caret_ssh.dart';

/// helper サブコマンドの allow-list（herdr OSC 8 ハイパーリンク実験機能）。
/// caret（既存）はサブコマンド省略（[runHelper] の
/// [HerdrCaretHelperExecutor.runHelper] で `subcommand: null`）のため、
/// この enum には含めない。
enum HerdrCaretHelperSubcommand {
  hyperlinks,
  scrollbackLinks;

  /// CLI 上のサブコマンド文字列。
  String get cliName => switch (this) {
    HerdrCaretHelperSubcommand.hyperlinks => 'hyperlinks',
    HerdrCaretHelperSubcommand.scrollbackLinks => 'scrollback-links',
  };
}

/// [HerdrCaretHelperExecutor.runHelper] の `preTimeoutArgs` /
/// `postTimeoutArgs` に渡す1個の追加フラグ（フラグ名・生の値）。
/// 値は executor が [HerdrCaretShellArgs.shellQuote] で quote する
/// （呼び出し側で quote 済みの文字列を渡してはいけない）。
typedef HerdrCaretHelperExtraArg = (String flag, String value);

/// 配置済み helper の実行を担う executor。
class HerdrCaretHelperExecutor {
  /// helper stdout の最大長（これを超えた分は打ち切り）。
  static const int maxStdoutBytes = 64 * 1024;

  /// 追加フラグ名の書式（`--` + 小文字英字始まり + 小文字英数字・ハイフン）。
  static final RegExp _flagPattern = RegExp(r'^--[a-z][a-z0-9-]*$');

  final HerdrCaretSshRunner _sshRunner;
  final HerdrCaretHelperManifest _manifest;

  HerdrCaretHelperExecutor({
    required HerdrCaretSshRunner sshRunner,
    required HerdrCaretHelperManifest manifest,
  }) : _sshRunner = sshRunner,
       _manifest = manifest;

  /// helper を 1 回実行する。
  ///
  /// manager 側では実行を single-flight しない（呼び出し毎に実行する）。
  /// 理由:
  /// - single-flight の契約は「同一 connection / pane / epoch」であり、
  ///   connection 単位で合流すると異なる pane の要求が混ざり、paneId 不一致の
  ///   stdout が返る（reader 側で stale として破棄されるだけで無駄になる）。
  /// - 実行頻度の制御（TTL・pane 単位 single-flight・epoch 照合・pane 切替時の
  ///   stale 破棄）は [HerdrCaretHelperSnapshotReader] が担う層にあり、
  ///   manager が connection 単位で合流すると reader の契約と重複・干渉する。
  /// - manager の memoize は install のみを対象とする。
  ///
  /// [subcommand] が null なら既存 caret 呼び出し（サブコマンド省略）と同じ
  /// コマンド形になる（herdr OSC 8 ハイパーリンク実験機能の
  /// 互換要件）。`hyperlinks`/`scrollback-links`は非 null を渡す。
  /// 生文字列ではなく [HerdrCaretHelperSubcommand]（allow-list）で受け取る。
  ///
  /// 引数は caret・hyperlinks・scrollback-links の3つのコマンド形に合わせて次の順で組み立てる:
  /// ```
  /// remotePath [subcommand] [--api-socket apiSocket] --socket clientSocket
  ///   --pane paneId --protocol protocol --cols cols [--rows rows]
  ///   [preTimeoutArgs...] --timeout-ms (helperTimeout ?? timeout)
  ///   [postTimeoutArgs...]
  /// ```
  ///
  /// - [apiSocket] は null なら `--api-socket` を出さない（caret は常に null。
  ///   hyperlinks/scrollback-links は常に非null を渡す）。
  ///   `--api-socket` 指定時の helper の挙動は protocol/サブコマンドで
  ///   異なる: hyperlinks（全 protocol）と
  ///   scrollback-links の protocol 22 は fail-open（読めなければ
  ///   `--cols`/`--rows` へ黙ってフォールバック）。scrollback-links の
  ///   protocol 17/20 は fail-closed（読めなければ `winsize_unavailable`
  ///   で中断し、フォールバックしない。[HerdrHelperErrorKind.winsizeUnavailable]
  ///   参照）。
  /// - [rows] は null なら `--rows` を出さない（scrollback-links は pane の
  ///   幅だけを渡す）。
  /// - [helperTimeout] は null なら [timeout]（SSH 実行の timeout）と同値に
  ///   なる（既存 caret 呼び出しはこの経路で不変）。
  /// - [preTimeoutArgs] / [postTimeoutArgs] は `(flag, value)` の組
  ///   （[HerdrCaretHelperExtraArg]）のリスト（例: `('--window', '120')`）。
  ///   呼び出し側は quote 済みの文字列を渡してはいけない。executor がフラグ名
  ///   を allow-list（`^--[a-z][a-z0-9-]*$`）で検証し、値を
  ///   [HerdrCaretShellArgs.shellQuote] で quote してから連結する
  ///   （呼び出し側に quote を委ねない。同じフラグを複数回渡せる。
  ///   例: `--window` を最大3回）。
  Future<String> runHelper(
    HerdrCaretInstallation installation, {
    HerdrCaretHelperSubcommand? subcommand,
    String? apiSocket,
    required String clientSocket,
    required String paneId,
    required int cols,
    int? rows,
    List<HerdrCaretHelperExtraArg> preTimeoutArgs = const [],
    required int protocol,
    required Duration timeout,
    Duration? helperTimeout,
    List<HerdrCaretHelperExtraArg> postTimeoutArgs = const [],
  }) {
    return _doRunHelper(
      installation,
      subcommand: subcommand,
      apiSocket: apiSocket,
      clientSocket: clientSocket,
      paneId: paneId,
      cols: cols,
      rows: rows,
      preTimeoutArgs: preTimeoutArgs,
      protocol: protocol,
      timeout: timeout,
      helperTimeout: helperTimeout,
      postTimeoutArgs: postTimeoutArgs,
    );
  }

  Future<String> _doRunHelper(
    HerdrCaretInstallation installation, {
    HerdrCaretHelperSubcommand? subcommand,
    String? apiSocket,
    required String clientSocket,
    required String paneId,
    required int cols,
    int? rows,
    List<HerdrCaretHelperExtraArg> preTimeoutArgs = const [],
    required int protocol,
    required Duration timeout,
    Duration? helperTimeout,
    List<HerdrCaretHelperExtraArg> postTimeoutArgs = const [],
  }) async {
    final buffer = StringBuffer(
      HerdrCaretShellArgs.shellQuote(installation.remotePath),
    );
    if (subcommand != null) buffer.write(' ${subcommand.cliName}');
    if (apiSocket != null) {
      buffer.write(
        ' --api-socket ${HerdrCaretShellArgs.shellQuote(apiSocket)}',
      );
    }
    buffer.write(' --socket ${HerdrCaretShellArgs.shellQuote(clientSocket)}');
    buffer.write(' --pane ${HerdrCaretShellArgs.shellQuote(paneId)}');
    buffer.write(' --protocol $protocol');
    buffer.write(' --cols $cols');
    if (rows != null) buffer.write(' --rows $rows');
    for (final arg in preTimeoutArgs) {
      _writeExtraArg(buffer, arg);
    }
    buffer.write(' --timeout-ms ${(helperTimeout ?? timeout).inMilliseconds}');
    for (final arg in postTimeoutArgs) {
      _writeExtraArg(buffer, arg);
    }
    final command = buffer.toString();
    final result = await _sshRunner.exec(command, timeout: timeout);

    if (result.exitCode != null && result.exitCode != 0) {
      _fail(
        HerdrCaretHelperFailure.execFailed,
        'Helper exited with ${result.exitCode}',
        null,
        _extractHelperErrorKind(result.stderr),
      );
    }

    var stdout = result.stdout.trim();
    if (stdout.length > maxStdoutBytes) {
      stdout = stdout.substring(0, maxStdoutBytes);
      _log('${_manifest.helperName}: stdout truncated');
    }
    if (stdout.isEmpty && result.exitCode == null) {
      _fail(HerdrCaretHelperFailure.connectFailed, 'Helper produced no output');
    }
    if (!stdout.startsWith('{') || !stdout.endsWith('}')) {
      _fail(
        HerdrCaretHelperFailure.invalidOutput,
        'Helper output is not a single JSON line',
      );
    }
    return stdout;
  }

  /// 追加フラグ（[preTimeoutArgs] / [postTimeoutArgs]）を1個分書き出す。
  ///
  /// フラグ名は allow-list（[_flagPattern]）で検証し、値は
  /// [HerdrCaretShellArgs.shellQuote] で quote する（呼び出し側で quote
  /// 済みの文字列を渡す旧契約は廃止）。
  void _writeExtraArg(StringBuffer buffer, HerdrCaretHelperExtraArg arg) {
    final (flag, value) = arg;
    if (!_flagPattern.hasMatch(flag)) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid flag name: $flag');
    }
    buffer.write(' $flag ${HerdrCaretShellArgs.shellQuote(value)}');
  }

  Never _fail(
    HerdrCaretHelperFailure failure,
    String message, [
    Object? cause,
    HerdrHelperErrorKind? helperErrorKind,
  ]) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] ${failure.name}: $message');
    }
    throw HerdrCaretHelperException(failure, message, cause, helperErrorKind);
  }

  /// helper の stderr から [HerdrHelperErrorKind] を抽出する。
  ///
  /// stderr の trim 後が 256 バイト以下、かつ `{"error":"<kind>"}` という
  /// **他のキーを含まない** JSON オブジェクトで、`<kind>` が既知の allow-list
  /// にある場合だけ非 null を返す。それ以外（非 JSON・長すぎる・未知の
  /// kind・余分なキー）はすべて null（stderr 本文はここでも例外・ログへ
  /// 渡さない。main.rs:11 の方針と同じ）。
  HerdrHelperErrorKind? _extractHelperErrorKind(String stderr) {
    final trimmed = stderr.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > 256) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded.length != 1 || !decoded.containsKey('error')) return null;
    final kind = decoded['error'];
    if (kind is! String) return null;
    return HerdrHelperErrorKind.fromWireName(kind);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[herdr-caret] $message');
    }
  }
}
