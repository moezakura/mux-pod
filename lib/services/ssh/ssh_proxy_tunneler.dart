import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../l10n/app_localizations.dart';
import 'ssh_models.dart';
import 'ssh_proxy_connection_error.dart';

/// hop 毎のソケットダイヤル（MR-6 注入点①・テスト用）。
///
/// hop 0 の踏み台への TCP 接続のみに使用する（hop 1 以降は前 hop の
/// `forwardLocal` 戻り値を socket として使う）。
typedef SshProxySocketDialer =
    Future<SSHSocket> Function(String host, int port, {Duration? timeout});

/// hop 毎の SSHClient 組立（MR-6 注入点②・テスト用）。
///
/// 本番実装は [buildHopClient]。テストは `authenticated` の完了制御と
/// `forwardLocal` の振る舞い（FakeSocket 返却 / throw / 完了しない）を
/// 持つ fake client を返せる。
typedef SshProxyHopClientFactory =
    Future<SSHClient> Function(
      SSHSocket socket,
      SshProxyHop hop, {
      required Duration? handshakeTimeout,
      required void Function() onAuthenticated,
      required Future<bool> Function(String type, Uint8List fingerprint)
      onVerifyHostKey,
    });

/// hop のホスト鍵検証（connector が hop 座標で配線する）。
typedef SshProxyHopVerifier =
    Future<bool> Function(SshProxyHop hop, String type, Uint8List fingerprint);

/// 本番の hop SSHClient 組立（MR-6 未注入時に使用）。
///
/// password 認証は [SshProxyHop.password]（解決済み平文）、鍵認証は
/// [SshProxyHop.privateKey]（解決済み PEM）から組み、[handshakeTimeout]
/// を dartssh2 に渡す（L4: ハンドシェイク沈黙点の防御）。ホスト鍵検証は
/// 呼び出し側が hop 座標を配線したコールバックへ委譲する。
Future<SSHClient> buildHopClient(
  SSHSocket socket,
  SshProxyHop hop, {
  required Duration? handshakeTimeout,
  required void Function() onAuthenticated,
  required Future<bool> Function(String type, Uint8List fingerprint)
  onVerifyHostKey,
}) async {
  final privateKey = hop.privateKey;
  if (privateKey != null) {
    return SSHClient(
      socket,
      username: hop.username,
      identities: SSHKeyPair.fromPem(privateKey, hop.passphrase),
      onAuthenticated: onAuthenticated,
      onVerifyHostKey: onVerifyHostKey,
      handshakeTimeout: handshakeTimeout,
    );
  }
  return SSHClient(
    socket,
    username: hop.username,
    onPasswordRequest: () => hop.password ?? '',
    onAuthenticated: onAuthenticated,
    onVerifyHostKey: onVerifyHostKey,
    handshakeTimeout: handshakeTimeout,
  );
}

/// ジャンプ経路（トンネル）確立の単一所有者。
///
/// hop ダイヤル → hop ハンドシェイク（per-hop タイムアウト MR-1 +
/// [SSHClient.handshakeTimeout] L4）→ `forwardLocal` チェーンを多段 loop で
/// 構築する。target の SSHClient 組立と `await authenticated` は
/// SshConnector の現行経路が担当する（tunneler は socket を渡すだけ）。
///
/// 責務分離（MR-2）: **失敗経路の掃除は tunneler**（attach 前の窓を自前で
/// 塞ぐ。facade の `disposeAll` は attach 済み資源しか閉じない）。失敗時は
/// 構築済み hop を後ろから close してから rethrow する。**成功経路の登録は
/// facade**（`attachConnection` + `attachJumpClients`）。
class SshProxyTunneler {
  SshProxyTunneler({
    required this.l10n,
    this.socketDialer = SSHSocket.connect,
    this.hopClientFactory = buildHopClient,
  });

  /// ローカライズ文字列プロバイダ（現在値を返すクロージャ）。
  final AppLocalizations? Function() l10n;

  /// MR-6 注入点①。
  final SshProxySocketDialer socketDialer;

  /// MR-6 注入点②。
  final SshProxyHopClientFactory hopClientFactory;

  /// ジャンプチェーンを構築し、target への転送済み socket と
  /// 構築済み hop clients（チェーン順）を返す。
  ///
  /// [onVerifyHostKey] には hop 座標付きの検証コールバックを渡す
  /// （connector が storage 検証へ配線する・ホスト鍵キーは hop 座標基準）。
  ///
  /// 失敗時は構築済み hop を後ろから close した上で
  /// [SshProxyConnectionError]（hop 座標付き・メッセージは l10n 済み）を
  /// throw する。
  Future<({SSHSocket socket, List<SSHClient> jumpClients})> tunnel({
    required SshProxyOptions proxy,
    required SshConnectOptions options,
    required SshProxyHopVerifier onVerifyHostKey,
  }) async {
    final hops = proxy.hops;
    final timeout = Duration(seconds: options.timeout);
    final built = <({SSHSocket socket, SSHClient client})>[];
    try {
      SSHSocket? nextSocket;
      for (var i = 0; i < hops.length; i++) {
        final hop = hops[i];

        // 1. hop ソケットの取得（hop 0 は直接ダイヤル・他は前 hop の転送先）
        final SSHSocket socket;
        if (i == 0) {
          try {
            socket = await socketDialer(hop.host, hop.port, timeout: timeout);
          } catch (e) {
            throw _error(
              l10n()?.connProxyDialFailed(hop.host, hop.port, e.toString()) ??
                  'Failed to connect to jump host '
                      '${hop.host}:${hop.port}: $e',
              e,
              i,
              hop,
            );
          }
        } else {
          socket = nextSocket!;
        }

        // 2. hop ハンドシェイク用クライアントの組立
        final SSHClient client;
        var hostKeyRejected = false;
        try {
          client = await hopClientFactory(
            socket,
            hop,
            handshakeTimeout: timeout,
            onAuthenticated: () {},
            onVerifyHostKey: (type, fingerprint) async {
              final ok = await onVerifyHostKey(hop, type, fingerprint);
              if (!ok) hostKeyRejected = true;
              return ok;
            },
          );
        } catch (e) {
          // socket は未登録（built 未追加）のためここで閉じる
          socket.close();
          rethrow;
        }
        built.add((socket: socket, client: client));

        // 3. hop 認証完了を待機（MR-1: per-hop タイムアウト）
        try {
          await client.authenticated.timeout(timeout);
        } on TimeoutException catch (e) {
          throw _error(_timeoutMessage(hop), e, i, hop);
        } on SSHAuthAbortError catch (e) {
          if (hostKeyRejected) {
            // H1: ホスト鍵拒否を hop 座標付きエラーへ変換する
            throw _error(
              l10n()?.connProxyHostKeyRejected(hop.host, hop.port) ??
                  'Host key verification for jump host '
                      '${hop.host}:${hop.port} failed',
              e,
              i,
              hop,
            );
          }
          rethrow;
        } on SSHAuthFailError catch (e) {
          throw _error(
            l10n()?.connProxyAuthFailed(hop.host, hop.port) ??
                'Authentication to jump host ${hop.host}:${hop.port} failed',
            e,
            i,
            hop,
          );
        }

        // 4. 転送チャネルの確立（MR-1: per-hop タイムアウト）
        final forwardTarget = i + 1 < hops.length
            ? (host: hops[i + 1].host, port: hops[i + 1].port)
            : (host: proxy.forwardHost, port: proxy.forwardPort);
        try {
          nextSocket = await client
              .forwardLocal(forwardTarget.host, forwardTarget.port)
              .timeout(timeout);
        } on TimeoutException catch (e) {
          throw SshProxyConnectionError(
            _timeoutMessage(hop),
            e,
            i,
            hop.host,
            hop.port,
          );
        } catch (e) {
          // AllowTcpForwarding 無効環境などはここに帰着する
          throw SshProxyConnectionError(
            l10n()?.connProxyForwardFailed(
                  forwardTarget.host,
                  forwardTarget.port,
                ) ??
                'Could not reach ${forwardTarget.host}:'
                    '${forwardTarget.port} via the jump host',
            e,
            i,
            hop.host,
            hop.port,
          );
        }
      }
      return (
        socket: nextSocket!,
        jumpClients: built.map((entry) => entry.client).toList(),
      );
    } catch (e) {
      // MR-2: 構築済み hop を後ろから close してから rethrow する。
      // hop client の close は dartssh2 上で transport close → 全チャネル
      // （間の forward channel 含む）も閉じる。
      for (final entry in built.reversed) {
        entry.client.close();
        entry.socket.close();
      }
      if (e is SshProxyConnectionError) rethrow;
      throw SshProxyConnectionError(e.toString(), e);
    }
  }

  /// hop 座標付きエラーを生成する。
  SshProxyConnectionError _error(
    String message,
    Object cause,
    int hopIndex,
    SshProxyHop hop,
  ) {
    return SshProxyConnectionError(
      message,
      cause,
      hopIndex,
      hop.host,
      hop.port,
    );
  }

  String _timeoutMessage(SshProxyHop hop) {
    return l10n()?.connProxyTimeout(hop.host, hop.port) ??
        'Timed out connecting to jump host ${hop.host}:${hop.port}';
  }
}
