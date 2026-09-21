import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

// inventory: SSH-043
/// managed PTY process（hidden herdr TUI ホスト用・[ SshClient.startManagedPty] の成果物）。
///
/// - stdout: 明示的に discard（購読して破棄。SSH channel window の詰まり防止）
/// - stderr: 末尾 [maxStderrTail] バイトをリングバッファで保持（診断用）
/// - 終了検知: [done] が「exit / channel close のいずれか」で発火する
///   （`session.done` + `stdout.done` + `stderr.done` のすべてを監視・承認条件 10）
/// - exitCode: [SSHSession.exitCode] getter から取得（stream でなく）
/// - [resize]: 失敗時は throw（収束判定のため握り潰さない）
/// - [close]: SIGTERM 送信 → done 待ち → channel close（冪等）
class ManagedPtyProcess {
  ManagedPtyProcess(this._session, {int maxStderrTail = 8192}) {
    // stdout/stderr の監視と完了検知を開始（完了は [done] が通知する）。
    unawaited(_trackCompletion(maxStderrTail));
  }

  static const int _closeTimeoutMs = 500;

  final SSHSession _session;
  final List<int> _stderrTail = <int>[];
  final StreamController<void> _doneController =
      StreamController<void>.broadcast();
  bool _closed = false;

  /// プロセス終了（exit / channel close / [close] のいずれか）を通知する。
  Stream<void> get done => _doneController.stream;

  /// プロセス終了後の exit code（未終了または exit 非報告なら null）。
  int? get exitCode => _session.exitCode;

  /// 終了コードの代わりにシグナルで終了した場合のシグナル名（無ければ null）。
  String? get exitSignalName => _session.exitSignal?.signalName;

  /// stderr の末尾（最大 8KB・診断用）。
  String get stderrTail => utf8.decode(_stderrTail, allowMalformed: true);

  /// PTY のウィンドウサイズを変更する（SSH window-change → SIGWINCH）。
  ///
  /// 失敗は throw（成功判定のため握り潰さない）。終了後の呼び出しも拒否する。
  void resize(int cols, int rows) {
    if (_closed) {
      throw StateError('Managed PTY is already closed');
    }
    _session.resizeTerminal(cols, rows);
  }

  /// プロセスを終了する（SIGTERM → done 待ち → channel close・冪等）。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _session.kill(SSHSignal.TERM);
    } catch (_) {
      // シグナル非対応のサーバでは channel close で代替する。
    }
    try {
      await _session.done.timeout(
        const Duration(milliseconds: _closeTimeoutMs),
      );
    } catch (_) {
      // タイムアウトしても channel close で強制終了する。
    }
    try {
      _session.close();
    } catch (_) {}
  }

  /// stdout / stderr の監視設置と完了検知（承認条件 10・11）。
  ///
  /// - stdout: データを破棄（discard）しながら done を監視
  /// - stderr: 末尾 [maxStderrTail] バイトを保持しながら done を監視
  /// - 3 つの完了（session.done / stdout.done / stderr.done）を待って [done] を発火
  Future<void> _trackCompletion(int maxStderrTail) async {
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    // stdout: 明示 discard（channel window 詰まり防止）。
    _session.stdout.listen(
      (_) {},
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      onError: (Object _) {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );
    // stderr: 末尾保持 + done 監視。
    _session.stderr.listen(
      (data) {
        _stderrTail.addAll(data);
        if (_stderrTail.length > maxStderrTail) {
          _stderrTail.removeRange(0, _stderrTail.length - maxStderrTail);
        }
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onError: (Object _) {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );
    await Future.wait([
      _session.done.catchError((Object _) {}),
      stdoutDone.future,
      stderrDone.future,
    ]);
    if (!_doneController.isClosed) {
      _doneController.add(null);
    }
  }
}
