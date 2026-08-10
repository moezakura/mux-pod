/// コマンド実行の結果。
///
/// トランスポートごとに出力の分離状態が異なるため、[CommandOutputSeparation]
/// で明示する（persistent shell は PTY のため stdout/stderr を分離できず
/// merged になる）。Codex 根本設計レビュー・バグ2 根本対応。
library;

/// 出力の分離状態。
enum CommandOutputSeparation {
  /// stdout と stderr が分離されている（ephemeral SSH exec）。
  separated,

  /// stdout と stderr が結合されている（persistent PTY）。
  merged,
}

/// 実際に使用されたトランスポート。
enum CommandTransport {
  ephemeral,
  persistent,
}

/// コマンド実行の結果。
final class CommandResult {
  /// 標準出力（[outputSeparation] が [CommandOutputSeparation.separated] のときのみ有効）。
  final String stdout;

  /// 標準エラー（[outputSeparation] が [CommandOutputSeparation.separated] のときのみ有効）。
  final String stderr;

  /// 結合出力（[outputSeparation] が [CommandOutputSeparation.merged] のときのみ有効）。
  ///
  /// PTY から得た結合出力。stdout/stderr のイベント順序は復元できないため、
  /// 「combined output」とは呼ばず merged として明示する。
  final String? mergedOutput;

  /// 終了コード（取得不能なら null）。
  final int? exitCode;

  /// 出力の分離状態。
  final CommandOutputSeparation outputSeparation;

  /// 実際に使用されたトランスポート。
  ///
  /// `persistentPreferred` は ephemeral フォールバックを許すため、結果の
  /// actual transport を見ないと性能低下や fallback を観測できない。
  final CommandTransport actualTransport;

  const CommandResult({
    this.stdout = '',
    this.stderr = '',
    this.mergedOutput,
    this.exitCode,
    required this.outputSeparation,
    required this.actualTransport,
  });

  /// 出力分離状態に応じた主出力（merged なら [mergedOutput]、separated なら [stdout]）。
  ///
  /// `combinedOutput` とはしない（separated stream の正しい相互順序を
  /// 復元できないため）。
  String get primaryOutput =>
      outputSeparation == CommandOutputSeparation.merged
          ? (mergedOutput ?? '')
          : stdout;

  /// separated の出力から (stdout, stderr) を返す。
  ///
  /// [outputSeparation] が merged の場合は stderr は空として扱う
  /// （呼び出し側は merged 出力からエラー分類を行う）。
  @override
  String toString() =>
      'CommandResult(${outputSeparation.name}, ${actualTransport.name}, '
      'exitCode=$exitCode, ${primaryOutput.length} chars)';
}
