/// コマンド実行の共通契約（transport・出力要件・タイムアウト）。
///
/// 従来 `BackendAdapter` の `exec` / `execPersistent` / `execWithExitCode` /
/// `execPersistentWithExitCode` という直積で表現していた実行方式と出力要件を、
/// リクエスト型に明示化する（Codex 根本設計レビュー・バグ2 根本対応）。
library;

/// コマンド実行のトランスポート方式とフォールバック方針。
enum CommandTransportPreference {
  /// 毎回独立チャネル（ephemeral SSH exec）。stdout/stderr 分離が必要な場合にも使用。
  ephemeralOnly,

  /// persistent を優先し、利用不能（shell 未起動・競合・shell error）なら
  /// ephemeral へフォールバックする。既存 `execPersistent*` に相当。
  persistentPreferred,

  /// persistent 以外を許可しない。利用不能なら例外。
  persistentOnly,
}

/// 呼び出し側が必要とする出力能力。
enum CommandOutputRequirement {
  /// 出力だけ必要。終了コード欠落を許容。
  outputOnly,

  /// 終了コードが必要。stderr 分離は要求しない。
  exitCode,

  /// stdout / stderr の分離が必要。
  separatedOutput,
}

/// コマンド実行のリクエスト。
final class CommandRequest {
  /// 実行するコマンド文字列。
  final String command;

  /// トランスポート方式とフォールバック方針。
  final CommandTransportPreference transport;

  /// 必要とする出力能力。
  final CommandOutputRequirement output;

  /// 実行全体のデッドライン（null なら transport 固有の既定値）。
  ///
  /// timeout は「コマンドを transport に書き込んだ後、結果が完成するまでの
  /// 上限」。fallback / retry を含む `execute()` 全体の deadline とし、
  /// retry 時は残時間を引き継ぐ。timeout 後に別 transport でコマンドを
  /// 自動再実行しない（実行結果が不明なため・mutation の二重適用防止）。
  final Duration? timeout;

  const CommandRequest({
    required this.command,
    this.transport = CommandTransportPreference.ephemeralOnly,
    this.output = CommandOutputRequirement.outputOnly,
    this.timeout,
  });

  /// 実行方式と出力要件の組み合わせを検証する。
  ///
  /// - `persistentOnly + separatedOutput`: persistent shell（PTY）では
  ///   stdout / stderr を分離できないため拒否。
  /// - `persistentPreferred + separatedOutput`: 最初から ephemeral に
  ///   ルーティングする（persistent を試してから fallback する必要は無い）。
  bool get isValid =>
      !(transport == CommandTransportPreference.persistentOnly &&
          output == CommandOutputRequirement.separatedOutput);

  @override
  String toString() =>
      'CommandRequest($command, transport=$transport, output=$output'
      '${timeout != null ? ', timeout=$timeout' : ''})';
}
