import 'dart:typed_data';

import '../backend/multiplexer_config.dart';

// inventory: SSH-003
/// SSH接続オプション
class SshConnectOptions {
  // inventory: SSH-004
  // inventory: LEGACY-0128
  /// パスワード認証時のパスワード
  final String? password;

  // inventory: SSH-005
  // inventory: LEGACY-0129
  /// 鍵認証時の秘密鍵（PEM形式）
  final String? privateKey;

  // inventory: SSH-006
  // inventory: LEGACY-0130
  /// 秘密鍵のパスフレーズ
  final String? passphrase;

  // inventory: SSH-007
  /// マルチプレクサ設定（nullなら自動検出）
  final MultiplexerConfig? multiplexer;

  // inventory: SSH-008
  // inventory: LEGACY-0132
  /// 接続タイムアウト（秒）
  final int timeout;

  // inventory: SSH-043
  /// 未知のホスト鍵を自動受け入れする（TOFU）。
  /// false の場合、未保存ホストは拒否する。
  final bool acceptNewHostKeys;

  /// ジャンプホスト経由接続の runtime 形（null なら直接接続・現行動作完全維持）。
  ///
  /// persisted 形（`ProxyConfig`）から認証情報を解決した解決済み値のみを
  /// 載せる（M3: forwardHost/forwardPort は解決済み非 null）。
  final SshProxyOptions? proxy;

  /// keepalive プローブタイムアウトの上書き値（秒・null = 自動）。
  ///
  /// UI 側が「接続個別 > 全体設定」を解決した値を載せる。null の場合は
  /// transport 側（[SshKeepAlive.resolveKeepAliveTimeoutSeconds]）が自動式
  /// （proxy あり: 10 + hops × 5 / なし: 10）を適用する（🤝3 責務分離:
  /// UI = 設定解決・transport = 式適用）。
  final int? keepAliveTimeoutSeconds;

  SshConnectOptions({
    this.password,
    this.privateKey,
    this.passphrase,
    this.multiplexer,
    this.timeout = 30,
    this.acceptNewHostKeys = true,
    this.proxy,
    this.keepAliveTimeoutSeconds,
  });
}

/// 実行時に解決済みのジャンプホスト 1 ホップ（runtime 形）。
///
/// persisted 形（`ProxyHop`）の keyId をストレージで解決した平文認証情報を
/// 保持する。transport 層にストレージ命名規約を漏らさないための runtime 形
/// （M3・design-v2 §2(e)）。
class SshProxyHop {
  /// 踏み台ホスト。
  final String host;

  /// 踏み台ポート。
  final int port;

  /// 踏み台のユーザー名。
  final String username;

  /// 解決済みパスワード（password 認証時）。
  final String? password;

  /// 解決済み秘密鍵 PEM（鍵認証時）。
  final String? privateKey;

  /// 秘密鍵のパスフレーズ。
  final String? passphrase;

  const SshProxyHop({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshProxyHop &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          password == other.password &&
          privateKey == other.privateKey &&
          passphrase == other.passphrase;

  @override
  int get hashCode =>
      Object.hash(host, port, username, password, privateKey, passphrase);

  @override
  String toString() => 'SshProxyHop(host: $host, port: $port, '
      'username: $username)';
}

/// 実行時に解決済みのジャンプ経路（runtime 形・L2）。
///
/// [forwardHost] / [forwardPort] は resolver が接続先座標で埋めた解決済み
/// 非 null 値（M3）。
class SshProxyOptions {
  /// 踏み台チェーン（チェーン順・hop 0 が最初にダイヤルされる）。
  final List<SshProxyHop> hops;

  /// 転送先ホスト（解決済み非 null）。
  final String forwardHost;

  /// 転送先ポート（解決済み非 null）。
  final int forwardPort;

  const SshProxyOptions({
    required this.hops,
    required this.forwardHost,
    required this.forwardPort,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshProxyOptions &&
          runtimeType == other.runtimeType &&
          forwardHost == other.forwardHost &&
          forwardPort == other.forwardPort &&
          _hopsEqual(other);

  /// hops を要素ごとに deep 比較する。
  bool _hopsEqual(SshProxyOptions other) {
    if (hops.length != other.hops.length) return false;
    for (var i = 0; i < hops.length; i++) {
      if (hops[i] != other.hops[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(hops), forwardHost, forwardPort);

  @override
  String toString() => 'SshProxyOptions(hops: $hops, '
      'forwardHost: $forwardHost, forwardPort: $forwardPort)';
}

// inventory: SSH-009
/// シェルオプション
class ShellOptions {
  // inventory: SSH-010
  // inventory: LEGACY-0133
  /// ターミナルタイプ
  final String term;

  // inventory: SSH-011
  // inventory: LEGACY-0134
  /// カラム数
  final int cols;

  // inventory: SSH-012
  // inventory: LEGACY-0135
  /// 行数
  final int rows;

  const ShellOptions({
    this.term = 'xterm-256color',
    this.cols = 80,
    this.rows = 24,
  });
}

// inventory: SSH-013
/// SSH接続イベント
class SshEvents {
  // inventory: SSH-014
  // inventory: LEGACY-0136
  /// データ受信時
  final void Function(Uint8List data)? onData;

  // inventory: SSH-015
  /// 接続クローズ時
  final void Function()? onClose;

  // inventory: SSH-016
  /// エラー発生時
  final void Function(Object error)? onError;

  const SshEvents({this.onData, this.onClose, this.onError});

  // inventory: SSH-017
  // inventory: LEGACY-0137
  SshEvents copyWith({
    void Function(Uint8List data)? onData,
    void Function()? onClose,
    void Function(Object error)? onError,
  }) {
    return SshEvents(
      onData: onData ?? this.onData,
      onClose: onClose ?? this.onClose,
      onError: onError ?? this.onError,
    );
  }
}
