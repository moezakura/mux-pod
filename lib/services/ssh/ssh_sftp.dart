import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import '../connection_error.dart';

/// SFTP クライアントのキャッシュ管理（openSftp）。
///
/// 初回呼び出し時にSFTPセッションを開始し、以降はキャッシュを返す。
/// dartssh2の SftpClient.close() はSSHチャネルを解放しないため、
/// SSH接続のライフサイクルで1つのSftpClientを使い回す（資源は
/// [SshResourceManager] が保持し、本クラスは入出力のみ）。
class SshSftpAccess {
  SshSftpAccess({
    required this.l10n,
    required this.isConnected,
    required this.client,
    required this.cachedSftp,
    required this.setCachedSftp,
  });

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// 接続中かどうか（現在値を返すクロージャ）。
  final bool Function() isConnected;

  /// SSH トランスポート本体（現在値を返すクロージャ）。
  final SSHClient? Function() client;

  /// 現在の SFTP キャッシュ（現在値を返すクロージャ）。
  final SftpClient? Function() cachedSftp;

  /// SFTP キャッシュの登録先（resource manager）。
  final void Function(SftpClient?) setCachedSftp;

  // inventory: SSH-025
  // inventory: LEGACY-0149
  /// SFTPクライアントを取得（キャッシュ付き）
  ///
  /// 呼び出し側で close() を呼んではならない。
  Future<SftpClient> openSftp() async {
    if (!isConnected() || client() == null) {
      throw SshConnectionError(
        l10n()?.sshSftpRequiresConnection ??
            'SFTP requires an active SSH connection',
      );
    }
    if (cachedSftp() != null) {
      debugPrint('[SshClient] openSftp: returning cached SftpClient');
      return cachedSftp()!;
    }
    debugPrint('[SshClient] openSftp: creating new SftpClient');
    final sftp = await client()!.sftp();
    setCachedSftp(sftp);
    return sftp;
  }
}
