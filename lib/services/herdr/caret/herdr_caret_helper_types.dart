// inventory: HERDR-CARET-TYPES-000
/// herdr-caret-helper の型群。
///
/// failure enum / exception / run result / installation / binary loader
/// typedef / runner interface を定義する。実装（installer / executor /
/// ssh runner）と interface を分離し、snapshot reader 層はこの interface
/// にのみ依存する。
library;

import 'dart:typed_data';

import '../herdr_models.dart';

/// helper バイナリの読み込み（asset → バイト列）。
typedef HerdrCaretBinaryLoader = Future<Uint8List> Function(String assetPath);

/// 失敗分類。
enum HerdrCaretHelperFailure {
  /// 非対応環境（非 Linux・未知 arch・API socket 無し）。
  unsupported,

  /// Herdr serverProtocol が 17/20 以外。
  unsupportedProtocol,

  /// SSH 実行そのものが失敗（切断・基本コマンド不能など）。
  connectFailed,

  /// SFTP の open / mkdir / upload / rename が失敗。
  uploadFailed,

  /// helper バイナリの sha256/size が不一致（bundle 内・upload 後とも）。
  hashMismatch,

  /// helper / chmod が非ゼロ終了。
  execFailed,

  /// helper 実行がタイムアウト。
  timeout,

  /// helper 出力が単一 JSON 行でない・引数値が不正。
  invalidOutput,
}

/// helper が stderr の `{"error":"<kind>"}`（helper 共通の失敗分類）で
/// 返す種別（herdr OSC 8 ハイパーリンク実験機能）。
///
/// [HerdrCaretHelperFailure]（Dart 側の粗い分類。非0終了は引き続き
/// [HerdrCaretHelperFailure.execFailed] のまま変えない）とは別に、
/// [HerdrCaretHelperException.helperErrorKind] として並行して持たせる。
/// `scrollback-links` の `busy`（再試行判定）のように、呼び出し側が
/// より細かい種別を必要とする場合にだけ使う。
enum HerdrHelperErrorKind {
  usageError,
  connectFailed,
  ioError,
  timeout,
  welcomeRejected,
  protocolError,
  decodeError,
  renderRejected,
  attachRejected,
  busy,
  unsupportedScroll,

  /// `--api-socket` 経由で実 pty サイズ（winsize）を読めなかった。
  ///
  /// この kind が出るのは **scrollback-links の protocol 17/20 のみ**
  /// （helper 側 `resolve_size_fail_closed`・fail-closed。
  /// attach する前に推測サイズで進めない）。この場合 helper は
  /// `--cols`/`--rows` へフォールバックせず、attach せずに実行全体を
  /// 中断する（Rust 側: `scrollback.rs` の
  /// `resolve_size_fail_closed`）。
  ///
  /// hyperlinks（全 protocol）と scrollback-links の protocol 22 は
  /// fail-open（`resolve_dimensions` / `resolve_size_fail_open`）のため、
  /// 読めなければこの kind を出さず、黙って `--cols`/`--rows` へ
  /// フォールバックして継続する（呼び出し側からはエラーに見えない）。
  winsizeUnavailable;

  /// helper の stderr JSON `error` フィールドの文字列表現。
  String get wireName => switch (this) {
    HerdrHelperErrorKind.usageError => 'usage_error',
    HerdrHelperErrorKind.connectFailed => 'connect_failed',
    HerdrHelperErrorKind.ioError => 'io_error',
    HerdrHelperErrorKind.timeout => 'timeout',
    HerdrHelperErrorKind.welcomeRejected => 'welcome_rejected',
    HerdrHelperErrorKind.protocolError => 'protocol_error',
    HerdrHelperErrorKind.decodeError => 'decode_error',
    HerdrHelperErrorKind.renderRejected => 'render_rejected',
    HerdrHelperErrorKind.attachRejected => 'attach_rejected',
    HerdrHelperErrorKind.busy => 'busy',
    HerdrHelperErrorKind.unsupportedScroll => 'unsupported_scroll',
    HerdrHelperErrorKind.winsizeUnavailable => 'winsize_unavailable',
  };

  /// [wireName] から逆引きする。未知の文字列は null（採用しない）。
  static HerdrHelperErrorKind? fromWireName(String name) {
    for (final kind in HerdrHelperErrorKind.values) {
      if (kind.wireName == name) return kind;
    }
    return null;
  }
}

/// helper 実行の失敗。
class HerdrCaretHelperException implements Exception {
  final HerdrCaretHelperFailure failure;
  final String message;

  /// 元の例外（任意。機密情報を含めないこと）。
  final Object? cause;

  /// helper の stderr JSON から抽出した種別（抽出できた場合のみ非 null。
  /// stderr 本文そのものは保持しない）。
  final HerdrHelperErrorKind? helperErrorKind;

  const HerdrCaretHelperException(
    this.failure,
    this.message, [
    this.cause,
    this.helperErrorKind,
  ]);

  @override
  String toString() => 'HerdrCaretHelperException(${failure.name}): $message';
}

/// helper 1 回実行の結果。
class HerdrCaretHelperRunResult {
  /// helper が stdout へ書いた単一 JSON 行（最大 64KB）。
  final String stdout;

  /// 配置先のリモート絶対パス。
  final String remotePath;

  const HerdrCaretHelperRunResult({
    required this.stdout,
    required this.remotePath,
  });

  @override
  String toString() =>
      'HerdrCaretHelperRunResult(remotePath=$remotePath, '
      'stdout=${stdout.length} chars)';
}

/// 配置済み helper の情報。
class HerdrCaretInstallation {
  final String remotePath;
  final String sha256;

  const HerdrCaretInstallation({
    required this.remotePath,
    required this.sha256,
  });
}

/// snapshot reader（Phase 4）から注入される helper 実行抽象。
///
/// テストではこの interface を fake する。
abstract interface class HerdrCaretHelperRunner {
  /// [status] の protocol / socket に基づき、[paneId] のカーソル snapshot
  /// を helper 1 回実行で取得する。
  ///
  /// 失敗は [HerdrCaretHelperException] を投げる。
  Future<HerdrCaretHelperRunResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    Duration? timeout,
  });
}
