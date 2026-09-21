// inventory: TMUX-COMMAND-RUNNER-000
/// tmux コマンド実行と結果検証
///
/// l10n エラーメッセージ生成（connTmuxCommandFailed / connTmuxOutputUnparsable）の
/// 所有者。ops 層は常にこのクラス経由で例外・文言を得る。
library;

import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_lookup.dart';
import '../../command/command_request.dart';
import '../parsers/output_validator.dart';
import '../tmux_command_executor.dart';
import '../tmux_contract.dart';

/// tmux コマンドの実行と出力の健全性判定。
class TmuxCommandRunner {
  TmuxCommandRunner({AppLocalizations? l10n}) : _l10n = l10n;

  final AppLocalizations? _l10n;

  // inventory: TMUX-FACADE-CHECK-001
  /// [CommandExecutor.execute] を使ってコマンドを実行し、
  /// 終了コード/標準エラーがあれば [TmuxCommandException] を投げる。
  ///
  /// ephemeral + separatedOutput を要求する（stderr 分離が必要な tmux
  /// mutation / チェック系コマンド。Codex 根本設計レビュー・バグ2 根本対応）。
  Future<String> run(TmuxCommandExecutor executor, String command) async {
    final result = await executor.execute(
      CommandRequest(
        command: command,
        transport: CommandTransportPreference.ephemeralOnly,
        output: CommandOutputRequirement.separatedOutput,
      ),
    );
    if (result.exitCode != 0 || result.stderr.isNotEmpty) {
      throw TmuxCommandException(
        result.stderr.isNotEmpty
            ? result.stderr.trim()
            : (_l10n ?? lookupL10n()).connTmuxCommandFailed(
                '${result.exitCode}',
              ),
      );
    }
    return result.stdout;
  }

  /// tmux が出力を返したのに 1 レコードも解析できなかった場合は投げる。
  ///
  /// 区切り文字が往路で失われた出力は終了コード 0 のまま空リストになり、
  /// 「セッションが無い」と見分けが付かないため、成功として返さない。
  List<T> requireRecords<T>(String output, List<T> records) {
    if (records.isEmpty && TmuxOutputValidator.hasRecordContent(output)) {
      throw TmuxOutputParseException(
        (_l10n ?? lookupL10n()).connTmuxOutputUnparsable,
      );
    }
    return records;
  }
}
