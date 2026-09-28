// inventory: SSH-001
/// ジャンプホスト経由接続のトランスポートエラー（hop 座標付き）。
library;

import '../connection_error.dart';

/// ジャンプホスト経由接続で失敗したことを表す例外。
///
/// [SshConnectionError] を継承する。**[SshAuthenticationError] は継承しない**
/// （SshAuthenticationError 派生にすると facade の既存 catch 経路で
/// connPrivateKeyUnreadable 系のメッセージに誤上書きされる実証済み経路を
/// 回避する・design-v2 §2(f)）。facade はこの型を既存 catch より前に受け、
/// wrap 前の（l10n 済み）メッセージを lastError へ書いて rethrow する。
class SshProxyConnectionError extends SshConnectionError {
  /// 失敗した hop の 0 始まり座標（resolver 等の hop 処理前の失敗では null）。
  final int? hopIndex;

  /// 失敗した hop のホスト（同上・null 可）。
  final String? hopHost;

  /// 失敗した hop のポート（同上・null 可）。
  final int? hopPort;

  SshProxyConnectionError(
    super.message, [
    super.cause,
    this.hopIndex,
    this.hopHost,
    this.hopPort,
  ]);

  @override
  String toString() => 'SshProxyConnectionError: $message';
}
