import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xterm/xterm.dart';

import '../ssh/ssh_client.dart';

/// ターミナルコントローラー
///
/// xterm.dartのTerminalとSSHシェルセッションを接続する。
class SshTerminalController {
  SshTerminalController({
    required String connectionId,
    required SshClient sshClient,
    int? maxLines,
  })  : _connectionId = connectionId,
        _sshClient = sshClient,
        terminal = Terminal(maxLines: maxLines ?? 2000);

  final String _connectionId;
  final SshClient _sshClient;
  final Terminal terminal;

  SshShellSession? _session;
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;

  bool _isConnected = false;

  /// 接続状態
  bool get isConnected => _isConnected;

  /// シェルセッション開始
  Future<void> startShell({
    int width = 80,
    int height = 24,
    String term = 'xterm-256color',
  }) async {
    if (_session != null) {
      throw StateError('Shell already started');
    }

    _session = await _sshClient.startShell(
      connectionId: _connectionId,
      width: width,
      height: height,
      term: term,
    );

    _isConnected = true;

    // SSH出力をTerminalに流す
    _stdoutSubscription = _session!.stdout.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });

    _stderrSubscription = _session!.stderr.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });

    // Terminalからの入力をSSHに送る
    terminal.onOutput = (data) {
      _session?.writeString(data);
    };

    // シェル終了時の処理
    _session!.done.then((_) {
      _isConnected = false;
      terminal.write('\r\n[Connection closed]\r\n');
    });
  }

  /// PTYサイズ変更
  Future<void> resize(int width, int height) async {
    if (_session == null) return;

    await _session!.resize(width, height);
    terminal.resize(width, height);
  }

  /// 文字列入力
  void write(String text) {
    _session?.writeString(text);
  }

  /// キー入力（特殊キー）
  void sendKey(TerminalKey key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
  }) {
    final sequence = _encodeKey(key, ctrl: ctrl, alt: alt, shift: shift);
    if (sequence != null) {
      _session?.writeString(sequence);
    }
  }

  /// 特殊キーのエスケープシーケンス変換
  String? _encodeKey(
    TerminalKey key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
  }) {
    // 基本的な特殊キーのエスケープシーケンス
    switch (key) {
      case TerminalKey.escape:
        return '\x1b';
      case TerminalKey.enter:
        return '\r';
      case TerminalKey.backspace:
        return ctrl ? '\x08' : '\x7f';
      case TerminalKey.tab:
        return shift ? '\x1b[Z' : '\t';
      case TerminalKey.arrowUp:
        return '\x1b[A';
      case TerminalKey.arrowDown:
        return '\x1b[B';
      case TerminalKey.arrowRight:
        return '\x1b[C';
      case TerminalKey.arrowLeft:
        return '\x1b[D';
      case TerminalKey.home:
        return '\x1b[H';
      case TerminalKey.end:
        return '\x1b[F';
      case TerminalKey.insert:
        return '\x1b[2~';
      case TerminalKey.delete:
        return '\x1b[3~';
      case TerminalKey.pageUp:
        return '\x1b[5~';
      case TerminalKey.pageDown:
        return '\x1b[6~';
      case TerminalKey.f1:
        return '\x1bOP';
      case TerminalKey.f2:
        return '\x1bOQ';
      case TerminalKey.f3:
        return '\x1bOR';
      case TerminalKey.f4:
        return '\x1bOS';
      case TerminalKey.f5:
        return '\x1b[15~';
      case TerminalKey.f6:
        return '\x1b[17~';
      case TerminalKey.f7:
        return '\x1b[18~';
      case TerminalKey.f8:
        return '\x1b[19~';
      case TerminalKey.f9:
        return '\x1b[20~';
      case TerminalKey.f10:
        return '\x1b[21~';
      case TerminalKey.f11:
        return '\x1b[23~';
      case TerminalKey.f12:
        return '\x1b[24~';
      default:
        return null;
    }
  }

  /// リソース解放
  Future<void> dispose() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _session?.close();
    _session = null;
    _isConnected = false;
  }
}
