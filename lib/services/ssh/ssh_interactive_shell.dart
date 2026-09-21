import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import '../connection_error.dart';
import 'ssh_models.dart';

/// インタラクティブシェル（startShell / write / writeBytes / resize）の担い手。
///
/// stream 購読からのイベント配信（onData / onError / onDone）は注入クロージャ
/// で broker / state controller へ届ける。session と購読自体の保存先は
/// [SshResourceManager]（attach / session クロージャ）。
class SshInteractiveShell {
  SshInteractiveShell({
    required this.l10n,
    required this.isConnected,
    required this.client,
    required this.session,
    required this.attachSession,
    required this.setLastError,
    required this.onData,
    required this.onError,
    required this.onDone,
  });

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// 接続中かどうか（現在値を返すクロージャ）。
  final bool Function() isConnected;

  /// SSH トランスポート本体（現在値を返すクロージャ）。
  final SSHClient? Function() client;

  /// 現在のインタラクティブシェルセッション（現在値を返すクロージャ）。
  final SSHSession? Function() session;

  /// session と stream 購読の登録先（resource manager）。
  final void Function(
    SSHSession session,
    StreamSubscription<Uint8List> stdoutSubscription,
    StreamSubscription<Uint8List> stderrSubscription,
  )
  attachSession;

  /// lastError の書込先（state controller）。
  final void Function(String?) setLastError;

  /// データ受信の配信先（event broker）。
  final void Function(Uint8List data) onData;

  /// エラーの配信先（event broker）。
  final void Function(Object error) onError;

  /// シェル完了の配信先（state controller + event broker を facade が配線）。
  final void Function() onDone;

  // inventory: SSH-037
  // inventory: LEGACY-0154
  /// インタラクティブシェルを開始する
  ///
  /// [options] シェルオプション
  Future<void> startShell([ShellOptions options = const ShellOptions()]) async {
    if (!isConnected() || client() == null) {
      throw SshConnectionError(l10n()?.sshNotConnected ?? 'Not connected');
    }

    try {
      final shellSession = await client()!.shell(
        pty: SSHPtyConfig(
          type: options.term,
          width: options.cols,
          height: options.rows,
        ),
      );

      // stdout/stderrのリスナーを設定
      final stdoutSubscription = shellSession.stdout.listen(
        // inventory: SSH-LIFE-013
        _handleData,
        // inventory: SSH-LIFE-014
        onError: _handleError,
        // inventory: SSH-LIFE-015
        onDone: _handleDone,
      );

      final stderrSubscription = shellSession.stderr.listen(
        _handleData,
        onError: _handleError,
      );

      attachSession(shellSession, stdoutSubscription, stderrSubscription);
    } catch (e) {
      throw SshConnectionError(
        l10n()?.sshStartShellFailed(e.toString()) ??
            'Failed to start shell: $e',
        e,
      );
    }
  }

  /// シェルにデータを書き込む
  ///
  /// [data] 送信データ（文字列）
  // inventory: SSH-038
  // inventory: LEGACY-0155
  void write(String data) {
    if (!isConnected() || session() == null) {
      throw SshConnectionError(
        l10n()?.sshNotConnectedOrShellNotStarted ??
            'Not connected or shell not started',
      );
    }
    session()!.write(utf8.encode(data));
  }

  // inventory: SSH-039
  // inventory: LEGACY-0156
  /// シェルにバイトデータを書き込む
  ///
  /// [data] 送信データ（バイト）
  void writeBytes(Uint8List data) {
    if (!isConnected() || session() == null) {
      throw SshConnectionError(
        l10n()?.sshNotConnectedOrShellNotStarted ??
            'Not connected or shell not started',
      );
    }
    session()!.write(data);
  }

  // inventory: SSH-040
  // inventory: LEGACY-0157
  /// ターミナルサイズを変更する
  ///
  /// [cols] カラム数
  /// [rows] 行数
  void resize(int cols, int rows) {
    if (session() == null) {
      return; // シェルが開始されていない場合は何もしない
    }

    try {
      session()!.resizeTerminal(cols, rows);
    } catch (e) {
      // リサイズエラーは警告のみ（致命的ではない）
      setLastError('Failed to resize: $e');
    }
  }

  /// データ受信ハンドラ
  void _handleData(Uint8List data) {
    onData(data);
  }

  /// エラーハンドラ
  void _handleError(Object error) {
    setLastError(error.toString());
    onError(error);
  }

  /// 完了ハンドラ
  void _handleDone() {
    onDone();
  }
}
