/// SSH Service Contract
///
/// SSH接続管理のサービス層インターフェース。
/// dartssh2の実装詳細を隠蔽し、テスタビリティを確保する。

import 'dart:async';
import 'dart:typed_data';

import '../models/connection.dart';
import '../models/ssh_key.dart';

/// SSH接続状態
enum ConnectionStatus {
  disconnected,
  connecting,
  authenticating,
  connected,
  error,
}

/// SSH接続状態の変更イベント
class ConnectionStateEvent {
  final String connectionId;
  final ConnectionStatus status;
  final String? error;
  final int? latencyMs;

  const ConnectionStateEvent({
    required this.connectionId,
    required this.status,
    this.error,
    this.latencyMs,
  });
}

/// SSHシェルセッション
abstract class SshShellSession {
  /// シェル出力ストリーム
  Stream<Uint8List> get stdout;

  /// シェルエラー出力ストリーム
  Stream<Uint8List> get stderr;

  /// シェル終了Future
  Future<void> get done;

  /// データ送信
  void write(Uint8List data);

  /// 文字列送信（UTF-8エンコード）
  void writeString(String data);

  /// PTYサイズ変更
  Future<void> resize(int width, int height);

  /// シェルクローズ
  Future<void> close();
}

/// SSHサービスインターフェース
abstract class SshService {
  /// 接続状態ストリーム
  Stream<ConnectionStateEvent> get connectionState;

  /// SSH接続（パスワード認証）
  Future<void> connectWithPassword({
    required Connection connection,
    required String password,
  });

  /// SSH接続（鍵認証）
  Future<void> connectWithKey({
    required Connection connection,
    required SSHKey key,
    String? passphrase,
  });

  /// 接続状態取得
  ConnectionStatus getStatus(String connectionId);

  /// シェルセッション開始
  Future<SshShellSession> startShell({
    required String connectionId,
    int? width,
    int? height,
    String term = 'xterm-256color',
  });

  /// コマンド実行（単発）
  Future<SshExecResult> exec({
    required String connectionId,
    required String command,
  });

  /// 切断
  Future<void> disconnect(String connectionId);

  /// 全接続切断
  Future<void> disconnectAll();

  /// キープアライブ送信
  Future<void> ping(String connectionId);
}

/// コマンド実行結果
class SshExecResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  const SshExecResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  bool get success => exitCode == 0;
}
