
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../tmux/tmux_backend.dart';
import 'shell_marker_scanner.dart';

// inventory: SHELL-001
/// 持続的シェルセッション
///
/// コマンドを書き込み、マーカーで出力終了を検知して結果を返す。
/// チャネル開閉のオーバーヘッドを排除し、1 RTT程度でコマンド実行可能。
class PersistentShell implements TmuxInputTransport {
  final SSHClient _sshClient;
  SSHSession? _session;

  // inventory: SHELL-002
  /// マーカーのコアテキスト（インスタンスごとにランダム生成するnonce）
  ///
  /// 静的な定数にすると、ユーザーのtmuxペイン内で動作するプログラムが
  /// ENDマーカーを正確に出力し、キャプチャ出力を偽装・切り詰めできてしまう。
  /// セッションごとに予測不能なnonceを生成することでこの偽装を防ぐ。
  final String _markerId = _generateMarkerId();

  // inventory: SHELL-003
  /// コマンド開始検知用マーカー（\x01プレフィックス/サフィックス付き）
  ///
  /// \x01（SOH制御文字）を含めることで、シェルのエコーバックテキスト内の
  /// リテラル文字列（`\x01`=4文字）と区別する。
  /// printfの実出力のみがバイト0x01を含むため、エコーバック内では一致しない。
  late final String _startMarker = '\x01###START_$_markerId###\x01';

  // inventory: SHELL-004
  /// コマンド終了検知用マーカー
  late final String _endMarker = '\x01###END_$_markerId###\x01';

  /// printf用のマーカー文字列（シェルコマンド内で使用）
  late final String _printfStartMarker = r'\x01###START_' '$_markerId' r'###\x01';
  late final String _printfEndMarker = r'\x01###END_' '$_markerId' r'###\x01';

  /// RC（終了コード）エコーのマーカー（printf用・文字列版）。
  ///
  /// `\x01###RC_<markerId>###:<code>\n` の形で出力される。マーカー内に
  /// ランダムな [markerId] を含めることで、コマンド出力に偶然現れる
  /// リテラル文字列との衝突を防ぐ（START/END マーカーと同じ方針）。
  late final String _printfRcMarker = r'\x01###RC_' '$_markerId' r'###:';

  /// RC エコーを出力から抽出するための文字列版マーカー。
  late final String _rcMarker = '\x01###RC_$_markerId###:';

  /// マーカー間出力を O(n) で抽出するインクリメンタルスキャナ
  late final ShellMarkerScanner _scanner = ShellMarkerScanner(
    startMarker: utf8.encode(_startMarker),
    endMarker: utf8.encode(_endMarker),
  );

  /// コマンド実行中のCompleter
  Completer<String>? _pendingCommand;

  /// [execWithExitCode] 用: 最後に実行したコマンドの終了コード（未捕捉なら null）。
  int? _lastExitCode;

  /// [execWithExitCode] 用: 今回のコマンドで終了コードを捕捉するか。
  ///
  /// true のときコマンド末尾に RC エコー（`\x01###RC_<markerId>###:N`）を
  /// 付与し、[_onData] が出力から抽出して [_lastExitCode] に格納する。
  bool _captureExitCode = false;

  // inventory: SHELL-005
  /// シェルが開始されているかどうか
  @override
  // inventory: LEGACY-0051
  bool get isStarted => _session != null;

  /// セッション切断検知用
  bool _isClosed = false;

  /// stdoutサブスクリプション
  StreamSubscription<Uint8List>? _stdoutSubscription;

  // inventory: SHELL-006
  PersistentShell(this._sshClient);

  // inventory: SHELL-007
  /// 予測不能なマーカーID（16進16文字 = 64bit）を生成する。
  ///
  /// Random.secureを使い、ユーザーのペイン内プログラムがマーカー文字列を
  /// 推測してキャプチャ出力を偽装することを防ぐ。
  static String _generateMarkerId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

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

    // ヒストリー記録を無効化（Bash/Zsh/fish対応）し、プロンプトを抑制
    // - export HISTFILE=... : Bash/Zsh用（スタートアップファイル後に上書き）
    // - set +H : Bashのヒストリー展開を無効化（入力中のリテラル`!`が
    //   展開されて入力行全体が中断されるのを防ぐ）
    // - set fish_history ... : fish用（exportはfishで構文エラーになるため別途）
    // - 2>/dev/null で未対応シェルのエラーを抑制
    _session!.write(utf8.encode(
      'export HISTFILE=/dev/null HISTSIZE=0 HISTFILESIZE=0 SAVEHIST=0 2>/dev/null;'
      ' set +H 2>/dev/null;'
      ' set fish_history "" 2>/dev/null; true;'
      ' export PS1="" PS2="" 2>/dev/null; stty -echo\n',
    ));
    await Future.delayed(const Duration(milliseconds: 100));

    // バッファをクリア（初期化出力を破棄）
    _scanner.reset();
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
  /// [captureExitCode] が true のとき、コマンド直後に
  /// `; printf '\x01###RC_<markerId>###:%d\n' "$?"` を付与して終了コードを
  /// マーカー内に埋め込み、[_onData] が出力から抽出する。false のときは
  /// 従来の [exec] と同じラップ（RC エコーなし）を維持する（tmux の
  /// 既存 [exec] 利用者に影響を与えない）。
  Future<({String output, int? exitCode})> _execFramed(
    String command, {
    Duration? timeout,
    required bool captureExitCode,
  }) async {
    if (_session == null) {
      throw PersistentShellError('Shell not started');
    }

    if (_isClosed) {
      throw PersistentShellError('Shell session is closed');
    }

    if (_pendingCommand != null && !_pendingCommand!.isCompleted) {
      throw PersistentShellError('Another command is already running');
    }

    _pendingCommand = Completer<String>();
    _scanner.reset();
    _captureExitCode = captureExitCode;
    _lastExitCode = null;

    // printfでマーカーを出力（\x01バイトを含む）
    // echoではなくprintfを使用: シェルのエコーバック内ではリテラル'\x01'（4文字）が
    // 表示されるが、printfの実出力はバイト0x01を含む。
    // これによりエコーバック内のマーカーと実出力のマーカーを確実に区別できる。
    final rcEcho = captureExitCode
        ? "; __muxpod_rc=\$?; printf '$_printfRcMarker%d\\n' \"\$__muxpod_rc\""
        : '';
    final commandWithMarkers =
        "printf '$_printfStartMarker\\n'; $command$rcEcho; printf '$_printfEndMarker\\n'\n";
    _session!.write(utf8.encode(commandWithMarkers));

    // タイムアウト付きで結果を待機
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    try {
      final output = await _pendingCommand!.future.timeout(effectiveTimeout);
      _captureExitCode = false;
      return (output: output, exitCode: _lastExitCode);
    } on TimeoutException {
      _pendingCommand = null;
      _captureExitCode = false;
      throw PersistentShellError('Command execution timed out');
    }
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
      throw TmuxTransportException('Shell not started');
    }
    if (_isClosed) {
      throw TmuxTransportException('Shell session is closed');
    }
    try {
      session.write(utf8.encode('$command\n'));
    } catch (e) {
      throw TmuxTransportException('Failed to send to shell', e);
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
    assert(() {
      final chunkDecoded = utf8.decode(data, allowMalformed: true);
      if (chunkDecoded.contains('\uFFFD')) {
        final lastBytes = data.length > 6
            ? data.sublist(data.length - 6)
            : data;
        debugPrint(
          '[PersistentShell] UTF-8 boundary split detected!'
          ' chunk_size=${data.length}'
          ' last_bytes=${lastBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}'
        );
      }
      return true;
    }());

    // マーカー間の出力をインクリメンタルに抽出（O(n)スキャン）
    final between = _scanner.feed(data);
    if (between == null) {
      return;
    }

    // マーカー間バイト列をUTF-8デコード（マルチバイト境界分割を防止）
    var result = utf8.decode(between, allowMalformed: true);

    // PTYの出力変換で\r\nや\rが使われる場合があるため正規化
    // 事実: macOS PTYではnewlines=0, CRs=19（\nが\rに変換されている）
    result = result.replaceAll(RegExp(r'\r\n?'), '\n');

    // execWithExitCode 用: 末尾の RC エコー（\x01###RC_<id>###:<code>\x01\n）を抽出する。
    // エコーは必ずコマンド出力の最後に付くため、最後の出現位置から終了コードを
    // 取り出して出力から除去する（コードは次の \x01 または改行まで）。
    if (_captureExitCode) {
      final rcIndex = result.lastIndexOf(_rcMarker);
      if (rcIndex >= 0) {
        final codeText = result.substring(rcIndex + _rcMarker.length);
        final terminator = codeText.indexOf('\x01');
        final codeEnd = terminator >= 0 ? terminator : codeText.indexOf('\n');
        final code = codeEnd >= 0 ? codeText.substring(0, codeEnd) : codeText;
        _lastExitCode = int.tryParse(code.trim());
        // RC エコー行を除去（\x01 終端と直前の改行も含める）
        result = result.substring(0, rcIndex);
        if (result.endsWith('\n')) {
          result = result.substring(0, result.length - 1);
        }
      }
    }

    // 先頭と末尾の改行を削除
    if (result.startsWith('\n')) {
      result = result.substring(1);
    }
    if (result.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
    }

    // Completerを先にnullにしてから完了（再入防止）
    _pendingCommand = null;
    pending.complete(result);
  }

  /// セッション終了時の処理
  void _onDone() {
    _isClosed = true;
    _captureExitCode = false;
    if (_pendingCommand != null && !_pendingCommand!.isCompleted) {
      _pendingCommand!.completeError(PersistentShellError('Shell session closed'));
    }
  }

  /// エラー発生時の処理
  void _onError(Object error) {
    _isClosed = true;
    _captureExitCode = false;
    if (_pendingCommand != null && !_pendingCommand!.isCompleted) {
      _pendingCommand!.completeError(PersistentShellError('Shell error: $error'));
    }
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
    _captureExitCode = false;

    if (_pendingCommand != null && !_pendingCommand!.isCompleted) {
      _pendingCommand!.completeError(PersistentShellError('Shell disposed'));
    }
    _pendingCommand = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    _session?.close();
    _session = null;

    _scanner.reset();
  }
}

// inventory: SHELL-016
/// PersistentShellのエラー
class PersistentShellError implements Exception {
  // inventory: LEGACY-0057
  final String message;

  PersistentShellError(this.message);

  @override
  // inventory: LEGACY-0058
  String toString() => 'PersistentShellError: $message';
}
