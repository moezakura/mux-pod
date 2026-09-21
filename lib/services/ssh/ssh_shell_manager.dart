import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import 'persistent_shell.dart';

/// 持続的シェル2本（ポーリング用・入力用）の生成・起動・再起動の所有者。
///
/// 生成・再起動したシェルは attach クロージャ経由で [SshResourceManager] へ
/// 登録する（破棄は resource manager の disposeAll が担う）。再起動通知
/// （onInputShellRebooted）は facade の可変フィールドの現在値をクロージャで
/// 参照するため、設定変更後も追随する。
class SshShellManager {
  SshShellManager({
    required this.client,
    required this.isConnected,
    required this.pollingShell,
    required this.inputShell,
    required this.persistentShellFactory,
    required this.l10n,
    required this.attachPollingShell,
    required this.attachInputShell,
    required this.onInputShellRebooted,
  });

  /// SSH トランスポート本体（現在値を返すクロージャ）。
  final SSHClient? Function() client;

  /// 接続中かどうか（現在値を返すクロージャ）。
  final bool Function() isConnected;

  /// 現在のポーリング用シェル（現在値を返すクロージャ）。
  final PersistentShell? Function() pollingShell;

  /// 現在の入力専用シェル（現在値を返すクロージャ）。
  final PersistentShell? Function() inputShell;

  /// 持続的シェル生成の注入（テスト用）。
  final Future<PersistentShell?> Function(SSHClient client)?
  persistentShellFactory;

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// ポーリング用シェルの登録先。
  final void Function(PersistentShell?) attachPollingShell;

  /// 入力専用シェルの登録先。
  final void Function(PersistentShell?) attachInputShell;

  /// 入力シェル再起動の通知先（現在値を返すクロージャ）。
  final void Function()? Function() onInputShellRebooted;

  /// 持続的シェルを開始（HEAD `SshClient._startPersistentShell` 相当）。
  ///
  /// ポーリング用と入力用の2チャネルを並列で起動（接続時間を増やさない）。
  /// どちらの起動失敗も接続自体は継続し、該当機能はexec()にフォールバックする。
  Future<void> startShells() async {
    if (client() == null) return;

    final shells = await Future.wait([_tryStartShell(), _tryStartShell()]);
    attachPollingShell(shells[0]);
    attachInputShell(shells[1]);
    // 入力シェルが復活したら Tmux 側に通知（restore trap 再設定等）
    // inventory: SSH-LIFE-004
    onInputShellRebooted()?.call();
  }

  // inventory: SSH-LIFE-002
  /// 持続的シェルを1つ起動する。失敗時はnullを返す（例外を投げない）。
  Future<PersistentShell?> _tryStartShell() async {
    final sshClient = client();
    if (sshClient == null) return null;
    try {
      final factory = persistentShellFactory;
      if (factory != null) return await factory(sshClient);
      final shell = PersistentShell(sshClient, l10n: l10n());
      await shell.start();
      return shell;
    } catch (_) {
      return null;
    }
  }

  // inventory: SSH-028
  // inventory: LEGACY-0152
  /// 持続的シェルを再起動（HEAD `SshClient.restartPersistentShell` 相当）。
  Future<void> restartPolling() async {
    if (client() == null || !isConnected()) return;
    try {
      await pollingShell()?.dispose();
    } catch (_) {
      // dispose失敗は無視して再作成を試みる
    }
    attachPollingShell(await _tryStartShell());
  }

  // inventory: SSH-LIFE-003
  // inventory: LEGACY-0153
  /// 入力専用シェルを再起動する（送信失敗時の自己回復用・HEAD
  /// `SshClient.restartInputShell` 相当）。
  Future<void> restartInput() async {
    if (client() == null || !isConnected()) return;
    try {
      await inputShell()?.dispose();
    } catch (_) {
      // dispose失敗は無視して再作成を試みる
    }
    attachInputShell(await _tryStartShell());
    // 入力シェルが復活したら Tmux 側に通知
    onInputShellRebooted()?.call();
  }
}
