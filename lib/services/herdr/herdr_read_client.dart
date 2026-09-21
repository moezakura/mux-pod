// inventory: HERDR-READ-000
/// read 操作（preflight / status / snapshot / paneRead）を提供する。
///
/// 実行は [HerdrCommandExecutor.execChecked] へ、stdout の検証・解析は
/// [HerdrStatusParser] / [HerdrSnapshotParser] / [HerdrPaneContentParser] /
/// [HerdrPreflight] へ委譲する。
library;

import 'herdr_command_executor.dart';
import 'herdr_commands.dart';
import 'herdr_models.dart';
import 'herdr_parser.dart';

/// read 操作（preflight / status / snapshot / paneRead）のクライアント。
///
/// exec 基盤（[HerdrCommandExecutor]）へ実行を委譲し、stdout をパーサで
/// 検証する。ローカライズ文字列は executor の遅延解決
/// （[HerdrCommandExecutor.strings]）を使う。
class HerdrReadClient {
  final HerdrCommandExecutor _exec;

  HerdrReadClient(this._exec);

  // inventory: HERDR-ADAPTER-002
  /// preflight: `herdr status --json` を実行し protocol（最小 17）を検証する。
  ///
  /// server 未稼働の場合は [HerdrServerNotRunningException]、
  /// protocol が 17 未満の場合は [HerdrProtocolMismatchException] を投げる。
  Future<HerdrStatus> preflight({Duration? timeout}) async {
    final stdout = await _exec.execChecked(
      HerdrCommands.preflightCommand(),
      timeout: timeout,
    );
    final HerdrStatus status;
    try {
      status = HerdrStatusParser.parse(stdout);
    } on FormatException catch (e) {
      throw HerdrCommandException(
        _exec.strings.connHerdrParseStatusFailed(e.message),
      );
    }
    return HerdrPreflight.validate(status, l10n: _exec.strings);
  }

  // inventory: HERDR-ADAPTER-034
  /// `herdr status --json` の生結果を返す（protocol 検証なし）。
  ///
  /// [preflight] は client/server の最小対応 protocol と稼働状態を検証する。
  /// caret helper は server protocol を専用の対応一覧で判定するため、
  /// このメソッドで検証前の [HerdrStatus] を取得する。
  /// protocol 判定・socket 導出は呼び出し側が行う。
  Future<HerdrStatus> status({Duration? timeout}) async {
    final stdout = await _exec.execChecked(
      HerdrCommands.preflightCommand(),
      timeout: timeout,
    );
    try {
      return HerdrStatusParser.parse(stdout);
    } on FormatException catch (e) {
      throw HerdrCommandException(
        _exec.strings.connHerdrParseStatusFailed(e.message),
      );
    }
  }

  // inventory: HERDR-ADAPTER-003
  /// 全階層スナップショット（workspace/tab/pane）を取得する。
  Future<HerdrSnapshot> snapshot({Duration? timeout}) async {
    final stdout = await _exec.execChecked(
      HerdrCommands.snapshot(),
      timeout: timeout,
    );
    try {
      return HerdrSnapshotParser.parse(stdout);
    } on FormatException catch (e) {
      throw HerdrCommandException(
        _exec.strings.connHerdrParseSnapshotFailed(e.message),
      );
    }
  }

  // inventory: HERDR-ADAPTER-004
  /// pane の内容を読み取る。
  ///
  /// [source]: `'visible'`（可視領域）または `'recent'`（履歴含む）。
  /// [lines]: 読み取る行数（null なら全量）。
  /// [ansi]: true なら `--raw` で ANSI エスケープ付きの出力を取得する。
  /// [viaPersistent]: true なら持続的シェル経由（[execPersistentWithExitCode]）
  /// で実行し、チャネル開閉と exec ロック直列化を回避する（バグ2: 描画遅延の
  /// 修正。tmux の `execPersistent` 経由ポーリングと対称）。デフォルト false
  /// （従来の [execWithExitCode]）で、深い履歴など低頻度・大量出力の取得は
  /// exec チャネルのままにする（tmux の `capturePane` 対比）。
  Future<HerdrPaneContent> paneRead(
    String paneId, {
    String source = 'recent',
    int? lines,
    bool ansi = false,
    bool viaPersistent = false,
    Duration? timeout,
  }) async {
    final stdout = await _exec.execChecked(
      HerdrCommands.paneRead(paneId, source: source, lines: lines, ansi: ansi),
      timeout: timeout,
      viaPersistent: viaPersistent,
    );
    return HerdrPaneContentParser.parse(stdout, ansi: ansi);
  }
}
