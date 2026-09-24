import '../../../helpers/fake_ssh_client.dart';

/// herdr adapter テスト共用の fake 派生クラス（元ファイルから verbatim 抽出
/// し、private→public に改名したもの）。
/// stderr を返す [FakeSshClient] のスタブ。
class FakeSshClientWithStderr extends FakeSshClient {
  final String stderr;
  FakeSshClientWithStderr(this.stderr);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: '', stderr: stderr, exitCode: 0);
  }
}

/// exitCode null・出力なしで戻す [FakeSshClient] のスタブ。
///
/// SSH exec チャネルが終了コードも出力も返さず閉じた（SSH 断・transport 層の
/// 異常）ケースを模す。実機では `herdr command failed (exit code: null)` として
/// 「No herdr pane found」に誤って swallow されていた経路（TERM-HERDR 診断）。
class FakeSshClientNullExit extends FakeSshClient {
  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: '', stderr: '', exitCode: null);
  }
}

/// exitCode null だが stdout は返す [FakeSshClient] のスタブ。
///
/// 出力は得られたが終了コードだけ欠落したケース（dartssh2 の exit-status
/// 欠落）を模し、stdout が成功扱いで返ることを検証する。
class FakeSshClientNullExitWithOutput extends FakeSshClient {
  final String output;
  FakeSshClientNullExitWithOutput(this.output);

  @override
  Future<({String stdout, String stderr, int? exitCode})> execWithExitCode(
    String command, {
    Duration? timeout,
  }) async {
    execCommands.add(command);
    return (stdout: output, stderr: '', exitCode: null);
  }
}
