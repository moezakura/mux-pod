import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'persistent_shell.dart';
import 'ssh_managed_pty.dart';

/// 資源ライフサイクルの単一所有者。
///
/// SSHClient / SSHSocket / SSHSession / SftpClient / ManagedPty / stream 購読 /
/// 持続的シェル2本の attach・取得・cleanup・dispose を一括実行する。
/// コラボレータ（connector / shell_manager 等）は生成した資源を
/// [attachConnection] 等でここへ登録し、[disposeAll] がライフサイクルを
/// 終了する（HEAD `SshClient._cleanup` 相当。keep-alive 停止は facade 側）。
class SshResourceManager {
  SSHClient? _client;
  SSHSocket? _socket;
  SSHSession? _session;
  SftpClient? _cachedSftp;
  ManagedPtyProcess? _managedPty;
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  PersistentShell? _persistentShell;
  PersistentShell? _inputShell;
  final List<SSHClient> _jumpClients = <SSHClient>[];

  /// SSH トランスポート本体。
  SSHClient? get client => _client;

  /// 接続ソケット。
  SSHSocket? get socket => _socket;

  /// インタラクティブシェルセッション。
  SSHSession? get session => _session;

  /// SFTP キャッシュ。
  SftpClient? get cachedSftp => _cachedSftp;

  /// ポーリング用の持続的シェル。
  PersistentShell? get persistentShell => _persistentShell;

  /// 入力専用の持続的シェル。
  PersistentShell? get inputShell => _inputShell;

  /// 接続資源（socket / client）を登録する。
  void attachConnection({
    required SSHSocket socket,
    required SSHClient client,
  }) {
    _socket = socket;
    _client = client;
  }

  /// ジャンプホストの SSHClient 群（チェーン順）を登録する。
  ///
  /// facade は attachConnection と同一位置（target 認証待ちの前・M5）で
  /// 呼ぶ。これにより target 認証失敗時も [disposeAll] が jump を
  /// 閉じられる（全 disconnect 経路が通る唯一の掃除点）。
  void attachJumpClients(List<SSHClient> clients) {
    _jumpClients
      ..clear()
      ..addAll(clients);
  }

  /// 登録済みジャンプホスト SSHClient 群（チェーン順・防御コピー）。
  List<SSHClient> get jumpClients => List.unmodifiable(_jumpClients);

  /// インタラクティブシェルセッションと stream 購読を登録する。
  void attachSession(
    SSHSession session,
    StreamSubscription<Uint8List> stdoutSubscription,
    StreamSubscription<Uint8List> stderrSubscription,
  ) {
    _session = session;
    _stdoutSubscription = stdoutSubscription;
    _stderrSubscription = stderrSubscription;
  }

  /// ポーリング用の持続的シェルを登録する。
  void attachPollingShell(PersistentShell? shell) {
    _persistentShell = shell;
  }

  /// 入力専用の持続的シェルを登録する。
  void attachInputShell(PersistentShell? shell) {
    _inputShell = shell;
  }

  /// SFTP キャッシュを登録する（null で無効化）。
  void attachCachedSftp(SftpClient? client) {
    _cachedSftp = client;
  }

  /// managed PTY を登録する。
  void attachManagedPty(ManagedPtyProcess process) {
    _managedPty = process;
  }

  /// managed PTY を取り出して null にする（二重 start 時の close 用）。
  ManagedPtyProcess? takeManagedPty() {
    final process = _managedPty;
    _managedPty = null;
    return process;
  }

  /// 全資源をクリーンアップする（HEAD `SshClient._cleanup` 相当）。
  Future<void> disposeAll() async {
    // SFTPキャッシュを無効化
    _cachedSftp?.close();
    _cachedSftp = null;

    // 持続的シェルを解放
    await _persistentShell?.dispose();
    _persistentShell = null;
    await _inputShell?.dispose();
    _inputShell = null;

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    _session?.close();
    _session = null;

    // managed PTY（hidden herdr TUI）も確実に終了させる（承認条件 9）。
    final managedPty = _managedPty;
    _managedPty = null;
    if (managedPty != null) {
      await managedPty.close();
    }

    _client?.close();
    _client = null;

    _socket?.close();
    _socket = null;

    // ジャンプホストを後ろから close（target close 後・MR-2/M5）。
    // jump client の close は dartssh2 上で transport close → 間の
    // forward channel も閉じる。
    for (final jump in _jumpClients.reversed) {
      jump.close();
    }
    _jumpClients.clear();
  }
}
