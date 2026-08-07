// inventory: HERDR-CMD-000
/// herdr CLI コマンド文字列の生成と preflight 検証。
///
/// 実装方式は CLI 先行方式（socket 直結は次の milestone）。コマンドは
/// [BackendAdapter.execWithExitCode] 経由で実行される。
library;

import 'herdr_models.dart';

// inventory: HERDR-CMD-PROTO-001
/// サポートする herdr protocol 番号。
///
/// G6 合意#2・#6: protocol 17 固定・最小対応版。
const int kHerdrSupportedProtocol = 17;

// inventory: HERDR-CMD-001
/// herdr CLI コマンド文字列を構築するヘルパー。
class HerdrCommands {
  HerdrCommands._();

  // inventory: HERDR-CMD-002
  /// 全階層（workspace/tab/pane/layout）のスナップショットを JSON で返す。
  static String snapshot() => 'herdr api snapshot';

  // inventory: HERDR-CMD-004
  /// protocol 確認用の status コマンド（JSON 出力）。
  static String preflightCommand() => 'herdr status --json';
}

// inventory: HERDR-ERR-001
/// herdr CLI 実行の失敗を表す例外。
///
/// コマンドが非 0 で終了した場合や、出力が期待した形式でない場合に投げる。
class HerdrCommandException implements Exception {
  /// エラーメッセージ。
  final String message;

  /// コマンドの終了コード（不明な場合は null）。
  final int? exitCode;

  /// 元の例外（任意）。
  final Object? cause;

  HerdrCommandException(this.message, {this.exitCode, this.cause});

  @override
  String toString() => 'HerdrCommandException: $message';
}

// inventory: HERDR-ERR-002
/// preflight で protocol が非対応（17 以外）の場合に投げる例外。
class HerdrProtocolMismatchException implements Exception {
  /// サポートする protocol 番号（17）。
  final int supported;

  /// 実測された protocol 番号。
  final int actual;

  HerdrProtocolMismatchException({
    required this.supported,
    required this.actual,
  });

  @override
  String toString() =>
      'HerdrProtocolMismatchException: protocol $actual is not supported '
      '(expected $supported)';
}

// inventory: HERDR-ERR-003
/// preflight で herdr server が稼働していない場合に投げる例外。
///
/// protocol 不整合（[HerdrProtocolMismatchException]）とは区別し、ユーザーに
/// 「サーバ未起動」であることを明示する。実測では未稼働時に
/// `server.protocol` が null となりパーサが 0 へ変換するため、protocol
/// 判定だけでは原因を誤報告する（`HerdrServerNotRunningException` で解決）。
///
/// 既存の `HerdrCommandException` を継承しない（接続画面の catch 順序で
/// 「herdr not found」と誤表示されるのを防ぐため）。
class HerdrServerNotRunningException implements Exception {
  /// ユーザー向けの案内文。
  final String message;

  HerdrServerNotRunningException()
      : message =
            "Herdr server is not running. Start it with 'herdr server' first.";

  @override
  String toString() => 'HerdrServerNotRunningException: $message';
}

// inventory: HERDR-PREFLIGHT-001
/// `herdr status --json` の結果から protocol 17 を検証する preflight。
///
/// コマンド実行は [HerdrAdapter.preflight] が行い、このクラスは検証のみを
/// 担当する。server 未稼働の場合は [HerdrServerNotRunningException]、
/// protocol が 17 以外の場合は [HerdrProtocolMismatchException] を投げる
/// （G6 合意#2・#6: protocol 17 固定・最小対応版）。
class HerdrPreflight {
  HerdrPreflight._();

  /// サポートする protocol 番号。
  static const int supportedProtocol = kHerdrSupportedProtocol;

  // inventory: HERDR-PREFLIGHT-002
  /// [status] の client/server protocol が 17 であることを検証する。
  ///
  /// 検証順序:
  /// 1. server 未稼働（[HerdrStatus.running] == false）なら
  ///    [HerdrServerNotRunningException] を投げる（protocol 判定より先）。
  /// 2. client/server protocol が 17 以外なら [HerdrProtocolMismatchException]。
  ///
  /// 検証に成功した場合は [status] をそのまま返す。
  static HerdrStatus validate(HerdrStatus status) {
    // server 未稼働は protocol 不整合より先に専用例外で報告する。
    // 実測では未稼働時に `server.protocol` が null となり `_asInt` が 0 へ
    // 変換されるため、protocol 判定だけでは「protocol 0 が非対応」と誤報告する。
    if (!status.running) {
      throw HerdrServerNotRunningException();
    }
    final client = status.clientProtocol;
    final server = status.serverProtocol;
    if (client != supportedProtocol || server != supportedProtocol) {
      // より具体的な方（server 優先）を actual として報告する。
      final actual = server != supportedProtocol ? server : client;
      throw HerdrProtocolMismatchException(
        supported: supportedProtocol,
        actual: actual,
      );
    }
    return status;
  }
}
