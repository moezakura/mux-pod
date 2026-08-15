/// SSH/Terminal統合機能のインターフェース契約
///
/// このファイルは実装の契約を定義するものであり、
/// 実際の実装は lib/ 以下の既存ファイルで行う。
library;

import 'dart:async';
import 'dart:typed_data';

// ============================================================
// TerminalScreen に追加すべきメソッド
// ============================================================

/// TerminalScreenが実装すべき統合インターフェース
abstract interface class ITerminalIntegration {
  /// SSH接続してtmuxにアタッチする
  ///
  /// 実装要件:
  /// 1. connectionIdから接続情報を取得
  /// 2. 認証情報をセキュアストレージから取得
  /// 3. SshProvider経由でSSH接続
  /// 4. tmuxセッション一覧を取得
  /// 5. 存在すればアタッチ、なければ新規作成
  /// 6. SSHイベントハンドラをTerminalに接続
  ///
  /// エラー時:
  /// - 接続エラー: SnackBarでエラー表示
  /// - 認証エラー: SnackBarでエラー表示
  /// - tmuxなし: メッセージ表示
  Future<void> connectAndAttach();

  /// キーをSSH経由で送信する
  ///
  /// 実装要件:
  /// 1. SshProvider.isConnectedを確認
  /// 2. SshProvider.write()でデータ送信
  ///
  /// [key] 送信するキーデータ（ESC、CTRL+C等の特殊キー含む）
  void sendKey(String key);

  /// ターミナルリサイズ時の処理
  ///
  /// 実装要件:
  /// 1. SshProvider.resize()でPTYリサイズ
  ///
  /// [cols] カラム数
  /// [rows] 行数
  void onTerminalResize(int cols, int rows);

  /// クリーンアップ処理
  ///
  /// 実装要件:
  /// 1. SSHストリームのサブスクリプション解除
  /// 2. SshProvider.disconnect()
  Future<void> cleanup();
}

// ============================================================
// SshProvider に追加すべきメソッド
// ============================================================

/// SshProviderが実装すべき追加インターフェース
abstract interface class ISshProviderExtensions {
  /// tmuxセッション一覧を取得
  ///
  /// 実装:
  /// ```dart
  /// final output = await client.exec(TmuxCommands.listSessions());
  /// return TmuxParser.parseSessions(output);
  /// ```
  Future<List<TmuxSessionInfo>> listTmuxSessions();

  /// tmuxセッションにアタッチ
  ///
  /// 実装:
  /// ```dart
  /// final cmd = TmuxCommands.attachSession(sessionName);
  /// client.write('$cmd\n');
  /// ```
  void attachTmuxSession(String sessionName);

  /// 新規tmuxセッションを作成
  ///
  /// 実装:
  /// ```dart
  /// final cmd = TmuxCommands.newSession(name: sessionName, detached: false);
  /// client.write('$cmd\n');
  /// ```
  void createTmuxSession(String sessionName);
}

// ============================================================
// イベントハンドラ契約
// ============================================================

/// SSHデータ受信ハンドラ
///
/// [data] 受信したバイトデータ
typedef SshDataHandler = void Function(Uint8List data);

/// SSH切断ハンドラ
typedef SshCloseHandler = void Function();

/// SSHエラーハンドラ
///
/// [error] 発生したエラー
typedef SshErrorHandler = void Function(Object error);

// ============================================================
// 状態遷移契約
// ============================================================

/// TerminalScreen状態遷移
///
/// ```
/// State: idle
///   ↓ initState()
/// State: connecting
///   ↓ connectAndAttach() success
/// State: connected
///   ↓ error / disconnect
/// State: error / idle
/// ```
enum TerminalConnectionState {
  /// 初期状態
  idle,

  /// SSH接続中
  connecting,

  /// 接続完了（tmuxアタッチ済み）
  connected,

  /// エラー状態
  error,

  /// 切断済み
  disconnected,
}

// ============================================================
// エラー型
// ============================================================

/// ターミナル統合エラー
sealed class TerminalIntegrationError implements Exception {
  String get message;
}

/// 接続設定が見つからない
class ConnectionNotFoundError implements TerminalIntegrationError {
  final String connectionId;
  ConnectionNotFoundError(this.connectionId);

  @override
  String get message => 'Connection not found: $connectionId';
}

/// 認証情報が見つからない
class AuthenticationDataNotFoundError implements TerminalIntegrationError {
  final String connectionId;
  AuthenticationDataNotFoundError(this.connectionId);

  @override
  String get message =>
      'Authentication data not found for connection: $connectionId';
}

/// tmuxが利用不可
class TmuxNotAvailableError implements TerminalIntegrationError {
  @override
  String get message =>
      'tmux is not installed or not available on the remote server';
}

// ============================================================
// 型エイリアス（既存型との互換性）
// ============================================================

/// TmuxSessionの型エイリアス
typedef TmuxSessionInfo = ({
  String name,
  String? id,
  bool attached,
  int windowCount,
});

// ============================================================
// テスト用モック契約
// ============================================================

/// テスト用モックSshClient
///
/// 統合テストで使用するモックの契約
abstract interface class IMockSshClient {
  /// 接続をシミュレート
  Future<void> mockConnect({required bool shouldSucceed, Duration delay});

  /// データ受信をシミュレート
  void mockReceiveData(Uint8List data);

  /// エラーをシミュレート
  void mockError(Object error);

  /// 切断をシミュレート
  void mockDisconnect();
}
