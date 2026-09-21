import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import '../tmux/tmux_backend.dart';
import 'pending_shell_command.dart';
import 'persistent_shell_error.dart';
import 'shell_marker_protocol.dart';
import 'shell_marker_scanner.dart';
import 'shell_output_parser.dart';

export 'pending_shell_command.dart';
export 'persistent_shell_error.dart';

// inventory: SHELL-001
/// 持続的シェルセッション
///
/// コマンドを書き込み、マーカーで出力終了を検知して結果を返す。
/// チャネル開閉のオーバーヘッドを排除し、1 RTT程度でコマンド実行可能。
///
/// 責務は「シェルセッションのライフサイクル（start/dispose/restart/sendNoWait）
/// とコマンド実行の調整（exec/execWithExitCode/timeout/poison、PENDING 管理）」。
/// マーカー構築は [ShellMarkerProtocol]（インスタンス毎 nonce・SHELL-002）、
/// バイト走査は [ShellMarkerScanner]、出力の意味解釈は [ShellOutputParser] に
/// 委譲し、ここではそれらを合成する。
class PersistentShell implements TmuxInputTransport {
  final SSHClient _sshClient;
  SSHSession? _session;

  /// ローカライズ文字列（null 時は英語フォールバック）。
  final AppLocalizations? _l10n;

  /// マーカーの構築（nonce はこのインスタンスごとに生成）。
  ///
  /// シングルトン・static 共有は禁止（共有するとユーザーのペイン内プログラム
  /// が END マーカーを予測してキャプチャ出力を偽装できてしまう）。
  final ShellMarkerProtocol _markerProtocol = ShellMarkerProtocol();

  /// マーカー間出力を O(n) で抽出するインクリメンタルスキャナ
  ///
  /// shell インスタンス単位で共有するのではなく、コマンド実行ごとに新しく
  /// 生成する（[PendingShellCommand.scanner]）。timeout 後に旧コマンドの
  /// 遅延フレームが届いても、新コマンドの scanner には影響しない（バグ2
  /// 根本対応: stale frame 混入防止）。
  late final ShellMarkerScanner _sharedScanner = ShellMarkerScanner(
    startMarker: utf8.encode(_markerProtocol.startMarker),
    endMarker: utf8.encode(_markerProtocol.endMarker),
  );

  /// 実行中のコマンド（per-command の状態）。
  ///
  /// 従来は shell 全体の可変フィールド（`_pendingCommand` / `_captureExitCode` /
  /// `_lastExitCode` / `_scanner`）で管理していたが、実行単位に集約する
  /// （Codex 根本設計レビュー）。timeout 時に [close] で shell を破棄するため、
  /// 旧コマンドの遅延フレームが新コマンドに混入しない。
  PendingShellCommand? _pendingCommand;

  // inventory: SHELL-005
  /// シェルが開始されているかどうか
  @override
  // inventory: LEGACY-0051
  bool get isStarted => _session != null;

  /// セッション切断検知用
  bool _isClosed = false;

  /// 実行中のコマンドが存在するか（再入検出用）。
  bool get hasPendingCommand =>
      _pendingCommand != null && !_pendingCommand!.isCompleted;

  /// stdoutサブスクリプション
  StreamSubscription<Uint8List>? _stdoutSubscription;

  // inventory: SHELL-006
  PersistentShell(this._sshClient, {AppLocalizations? l10n}) : _l10n = l10n;

  // inventory: SHELL-008
  // inventory: LEGACY-0052
  /// シェルセッションを開始
  Future<void> start() async {
    if (_session != null) {
      return; // すでに開始済み
    }

    _session = await _sshClient.shell(
      pty: SSHPtyConfig(
        type: 'dumb', // 最小限のPTY（エスケープシーケンスを抑制）
        width: 200,
        height: 50,
      ),
    );

    _isClosed = false;

    // stdout監視を開始
    _stdoutSubscription = _session!.stdout.listen(
      // inventory: SHELL-011
      _onData,
      // inventory: SHELL-012
      onDone: _onDone,
      // inventory: SHELL-013
      onError: _onError,
    );

    // シェル初期化を待つ（プロンプトが出力されるまで少し待機）
    await Future.delayed(const Duration(milliseconds: 100));

    // SSHログイン時にfishへ切り替える設定があっても、以降の制御文字を
    // BashのANSI-C quotingで送信できるよう、内部シェルをbashに固定する。
    // fishのWelcomeバナーなど、exec前に届いた初期出力は破棄する。
    _sharedScanner.reset();
    _session!.write(utf8.encode('exec bash --norc\n'));
    await Future.delayed(const Duration(milliseconds: 100));

    // Bashのヒストリー記録を無効化し、プロンプトを抑制する。
    // - export HISTFILE=... : スタートアップファイル後にも履歴を保存しない
    // - set +H : 入力中のリテラル`!`のヒストリー展開を無効化
    _session!.write(
      utf8.encode(
        'export HISTFILE=/dev/null HISTSIZE=0 HISTFILESIZE=0 SAVEHIST=0 2>/dev/null;'
        ' set +H 2>/dev/null;'
        ' export PS1="" PS2="" 2>/dev/null; stty -echo -onlcr -opost\n',
      ),
    );
    await Future.delayed(const Duration(milliseconds: 100));

    // バッファをクリア（bash起動・初期化コマンドのエコーを破棄）
    _sharedScanner.reset();
  }

  // inventory: SHELL-009
  // inventory: LEGACY-0053
  /// コマンドを実行して結果を取得
  ///
  /// [command] 実行するコマンド
  /// [timeout] タイムアウト（デフォルト: 5秒）
  /// 戻り値: コマンドの標準出力
  Future<String> exec(String command, {Duration? timeout}) async {
    final result = await _execFramed(
      command,
      timeout: timeout,
      captureExitCode: false,
    );
    return result.output;
  }

  /// コマンドを実行し、終了コードも取得する。
  ///
  /// [exec] と同じマーカー方式で、コマンド末尾に終了コードの RC エコーを
  /// 付与して捕捉する。herdr は [BackendAdapter.execWithExitCode] の代替として
  /// exit code と stderr でエラー分類（target-not-found / server-down）を
  /// 行うため、persistent shell 経由でも終了コードを失わない必要がある
  /// （バグ2: 描画遅延の修正。チャネル再利用 + エラー分類の両立）。
  ///
  /// 戻り値: マーカー間の標準出力（RC エコーは除去済み）と終了コード。
  /// stderr は persistent shell（PTY）では stdout に混ざるため分離せず、
  /// 呼び出し側（[SshClient.execPersistentWithExitCode]）が分類を担う。
  Future<({String output, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    return _execFramed(command, timeout: timeout, captureExitCode: true);
  }

  /// [exec] / [execWithExitCode] の共通実装。
  ///
  /// [captureExitCode] が true のとき、コマンド直後に RC エコーを付与して
  /// 終了コードをマーカー内に埋め込み、[ShellOutputParser] が出力から抽出する。
  /// false のときは従来の [exec] と同じラップ（RC エコーなし）を維持する
  /// （tmux の既存 [exec] 利用者に影響を与えない）。
  ///
  /// **timeout 時は shell を破棄・再起動する**（stale frame 混入防止）:
  /// 遅延して届いた旧コマンドの START/END フレームが、次のコマンド結果として
  /// 扱われるのを防ぐため、timeout したコマンドの自動再実行はしない
  /// （実行結果が不明のため・mutation の二重適用防止）。
  Future<({String output, int? exitCode})> _execFramed(
    String command, {
    Duration? timeout,
    required bool captureExitCode,
  }) async {
    if (_session == null) {
      throw PersistentShellError(
        _l10n?.sshShellNotStarted ?? 'Shell not started',
      );
    }

    if (_isClosed) {
      throw PersistentShellError(
        _l10n?.sshShellSessionIsClosed ?? 'Shell session is closed',
      );
    }

    if (hasPendingCommand) {
      throw PersistentShellError(
        _l10n?.sshAnotherCommandRunning ?? 'Another command is already running',
      );
    }

    final pending = PendingShellCommand(
      captureExitCode: captureExitCode,
      scannerFactory: () => ShellMarkerScanner(
        startMarker: utf8.encode(_markerProtocol.startMarker),
        endMarker: utf8.encode(_markerProtocol.endMarker),
      ),
    );
    _pendingCommand = pending;

    // マーカーでラップしたコマンド文字列を構築して送信（構築は
    // ShellMarkerProtocol が担う。printfでマーカーを出力（\x01バイトを含む））
    _session!.write(
      utf8.encode(
        _markerProtocol.buildCommand(command, captureExitCode: captureExitCode),
      ),
    );

    // タイムアウト付きで結果を待機
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    try {
      final output = await pending.completer.future.timeout(effectiveTimeout);
      _pendingCommand = null;
      return (output: output, exitCode: pending.exitCode);
    } on TimeoutException {
      // timeout 後は shell を破棄して再起動する（stale frame 混入防止）。
      // 破棄のため pending はエラーで完了し、次回 exec は再起動後に受付ける。
      await _poisonAfterTimeout();
      throw PersistentShellError(
        _l10n?.sshCommandTimedOut ?? 'Command execution timed out',
      );
    }
  }

  /// timeout 発生時の shell 破棄処理。
  ///
  /// pending をエラーで完了し、stdout 購読を解除して session を閉じ、
  /// 再起動可能な状態にする。旧 session の遅延フレームが新 session に
  /// 届くことはない（subscription 解除 + session close で物理的に遮断）。
  /// timeout したコマンドの自動再実行はしない。
  Future<void> _poisonAfterTimeout() async {
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending.completer.completeError(
        PersistentShellError(
          _l10n?.sshCommandTimedOut ?? 'Command execution timed out',
        ),
      );
    }
    _pendingCommand = null;
    _isClosed = true;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    _session?.close();
    _session = null;

    _sharedScanner.reset();
  }

  // inventory: SHELL-010
  /// コマンドを書き込むが出力は待たない（fire-and-forget）。
  ///
  /// tmux send-keys のような出力を持たない・待つ必要のないコマンド専用。
  /// 効果はポーリングで観測されるため結果を待つ必要がなく、チャネル開閉・
  /// execロック・往復待ちをすべて排除して高遅延回線でも即座に送信できる。
  ///
  /// マーカーを付与しないため、このシェルでは決して [exec] を併用しないこと
  /// （併用すると入力バイトが混線する）。専用チャネルでのみ使用する。
  @override
  // inventory: LEGACY-0054
  void sendNoWait(String command) {
    final session = _session;
    if (session == null) {
      throw TmuxTransportException(
        _l10n?.sshShellNotStarted ?? 'Shell not started',
      );
    }
    if (_isClosed) {
      throw TmuxTransportException(
        _l10n?.sshShellSessionIsClosed ?? 'Shell session is closed',
      );
    }
    try {
      session.write(utf8.encode('$command\n'));
    } catch (e) {
      throw TmuxTransportException(
        _l10n?.sshSendToShellFailed ?? 'Failed to send to shell',
        e,
      );
    }
  }

  /// stdout受信時の処理
  void _onData(Uint8List data) {
    // 待機中のコマンドがない、または完了済みの場合は無視
    final pending = _pendingCommand;
    if (pending == null || pending.isCompleted) {
      return;
    }

    // デバッグ: UTF-8境界分割の検出（debugビルドのみ）
    // （parser の責務外・診断用途のため本体に残す）
    assert(() {
      final chunkDecoded = utf8.decode(data, allowMalformed: true);
      if (chunkDecoded.contains('\uFFFD')) {
        final lastBytes = data.length > 6
            ? data.sublist(data.length - 6)
            : data;
        debugPrint(
          '[PersistentShell] UTF-8 boundary split detected!'
          ' chunk_size=${data.length}'
          ' last_bytes=${lastBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
        );
      }
      return true;
    }());

    // マーカー間の出力をインクリメンタルに抽出（O(n)スキャン）
    final between = pending.scanner.feed(data);
    if (between == null) {
      return;
    }

    // 抽出結果の意味解釈（UTF8デコード・CR正規化・RCエコー抽出・trim）
    final parsed = ShellOutputParser.parse(
      between,
      rcMarker: _markerProtocol.rcMarker,
      captureExitCode: pending.captureExitCode,
    );
    pending.exitCode = parsed.exitCode;

    // Completerを先にnullにしてから完了（再入防止）
    _pendingCommand = null;
    pending.completer.complete(parsed.output);
  }

  /// セッション終了時の処理
  void _onDone() {
    _isClosed = true;
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending.completer.completeError(
        PersistentShellError(
          _l10n?.sshShellSessionClosed ?? 'Shell session closed',
        ),
      );
    }
    _pendingCommand = null;
  }

  /// エラー発生時の処理
  void _onError(Object error) {
    _isClosed = true;
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending.completer.completeError(
        PersistentShellError('Shell error: $error'),
      );
    }
    _pendingCommand = null;
  }

  // inventory: SHELL-014
  // inventory: LEGACY-0055
  /// シェルセッションを再起動
  ///
  /// セッションが切断された場合に呼び出す
  Future<void> restart() async {
    // inventory: SHELL-015
    // inventory: LEGACY-0056
    await dispose();
    await start();
  }

  /// リソースを解放
  Future<void> dispose() async {
    _isClosed = true;

    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending.completer.completeError(PersistentShellError('Shell disposed'));
    }
    _pendingCommand = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    _session?.close();
    _session = null;

    _sharedScanner.reset();
  }
}
