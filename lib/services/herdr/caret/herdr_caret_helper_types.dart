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

/// helper 実行の失敗。
class HerdrCaretHelperException implements Exception {
  final HerdrCaretHelperFailure failure;
  final String message;

  /// 元の例外（任意。機密情報を含めないこと）。
  final Object? cause;

  const HerdrCaretHelperException(this.failure, this.message, [this.cause]);

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
