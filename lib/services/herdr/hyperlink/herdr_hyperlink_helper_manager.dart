// inventory: HERDR-HYPERLINK-MANAGER-000
/// SSH先への herdr-caret-helper `hyperlinks` サブコマンドの実行と、出力
/// JSON の検証（型・寸法・範囲の境界・上限）を担う manager。
///
/// 処理フロー（herdr OSC 8 ハイパーリンク実験機能）:
/// 1. HerdrStatus.serverProtocol が allow-list（[isHerdrHyperlinkProtocolSupported]。
///    現在の対応 protocol は 17/20/22）に含まれなければ実行しない（unsupportedProtocol）。
/// 2. HerdrStatus.socket を caret と同じ規則で `*-client.sock` へ導出
///    （null なら unsupported）。
/// 3. paneId / frame size の形式検証（不正は invalidOutput）。
/// 4. installer に helper 配置を依頼（caret と共有する場合は呼び出し側が
///    既存 installer を注入する）。
/// 5. executor に `hyperlinks` サブコマンドで 1 回実行させ、stdout
///    （最大 64KB で打ち切り）を得る。
/// 6. stdout を手書きで型・寸法・範囲検証し、domain 型
///    [PaneHyperlinks] へ変換する（[HerdrCaretSnapshot] のような herdr
///    固有の中間型は作らない。[PaneHyperlinks] には paneId/protocolVersion
///    が元々無く、中間型が持つ追加情報が無いため）。
///
/// caret の manager/snapshot 層と異なり、本 manager は「helper 管理」と
/// 「JSON 検証」を1つの公開契約にまとめる。[run] は失敗を必ず [HerdrCaretHelperException]
/// 1種類で throw する（内部の JSON 検証で出る [FormatException] は
/// [invalidOutput] へ変換して再 throw し、外へ漏らさない）。呼び出し側
/// （reader）はこの1種類だけを catch すればよい。
///
/// セキュリティ規則: socket path・pane 本文・helper 出力の未検証内容を
/// 例外メッセージ・ログへ残さない。失敗分類だけを伝える。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../backend/domain/pane_frame_reader.dart';
import '../../sftp/sftp_service.dart';
import '../../ssh/ssh_client.dart';
import '../herdr_models.dart';
import '../herdr_version.dart';
import '../caret/herdr_caret_helper_executor.dart';
import '../caret/herdr_caret_helper_installer.dart';
import '../caret/herdr_caret_helper_manifest.dart';
import '../caret/herdr_caret_helper_types.dart';
import '../caret/herdr_caret_shell_args.dart';
import '../caret/herdr_caret_ssh.dart';
import 'herdr_hyperlink_json.dart';

/// helper `hyperlinks` 実行の抽象（reader が注入・fake する対象。
/// [HerdrCaretHelperRunner] と同型）。
abstract interface class HerdrHyperlinkHelperRunner {
  /// [status] の protocol / socket に基づき、[paneId] の viewport リンクを
  /// helper 1 回実行で取得する。
  ///
  /// 失敗は [HerdrCaretHelperException] を投げる（[FormatException] は
  /// 外に漏れない）。
  Future<PaneHyperlinks> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    Duration? timeout,
  });
}

/// SSH/SFTP 経由で `hyperlinks` を配置・実行・検証する manager。
class HerdrHyperlinkHelperManager implements HerdrHyperlinkHelperRunner {
  /// 既定の helper 実行タイムアウト（通常表示。caret と同じ値）。
  static const Duration defaultRunTimeout = Duration(milliseconds: 1000);

  /// 既定の `--max-output-bytes`。
  static const int defaultMaxOutputBytes = 60000;

  late final HerdrCaretSshRunner _sshRunner;
  late final HerdrCaretInstaller _installer;
  late final HerdrCaretHelperExecutor _executor;

  /// [installer] が非 null ならそれを使う（caret と共有し、配置確認の SSH
  /// 実行を機能ごとに重複させない）。null（既定）なら内部生成。
  HerdrHyperlinkHelperManager({
    required SshClient ssh,
    required HerdrCaretHelperManifest manifest,
    HerdrCaretBinaryLoader? binaryLoader,
    SftpService? sftpService,
    HerdrCaretInstaller? installer,
  }) {
    _sshRunner = HerdrCaretSshRunner(ssh);
    _installer =
        installer ??
        HerdrCaretInstaller(
          ssh: ssh,
          manifest: manifest,
          sshRunner: _sshRunner,
          binaryLoader: binaryLoader ?? HerdrCaretInstaller.rootBundleLoad,
          sftpService: sftpService ?? SftpService(),
        );
    _executor = HerdrCaretHelperExecutor(
      sshRunner: _sshRunner,
      manifest: manifest,
    );
  }

  /// 構築済み installer（外部注入時はそのまま、未指定時は内部生成した
  /// もの）。他の manager（caret・scrollback-links）と共有するために公開する。
  HerdrCaretInstaller get installer => _installer;

  @override
  Future<PaneHyperlinks> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required int rows,
    Duration? timeout,
  }) async {
    final execTimeout = timeout ?? defaultRunTimeout;

    // protocol は helper 実行前に判定（allow-list 外は配置・実行しない）。
    if (!isHerdrHyperlinkProtocolSupported(status.serverProtocol)) {
      _fail(
        HerdrCaretHelperFailure.unsupportedProtocol,
        'Server protocol ${status.serverProtocol} is not supported',
      );
    }

    final apiSocket = status.socket;
    if (apiSocket == null || apiSocket.trim().isEmpty) {
      _fail(
        HerdrCaretHelperFailure.unsupported,
        'Herdr API socket is unavailable',
      );
    }

    if (!HerdrCaretShellArgs.isValidPaneId(paneId)) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid pane id format');
    }
    if (cols < 0 || cols > 0xFFFF || rows < 0 || rows > 0xFFFF) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid frame size');
    }

    final clientSocket = HerdrCaretShellArgs.deriveClientSocket(apiSocket);
    final installation = await _installer.ensureInstalled(execTimeout);
    final stdout = await _executor.runHelper(
      installation,
      subcommand: HerdrCaretHelperSubcommand.hyperlinks,
      // --api-socket を渡すと helper が実 pty サイズでレンダリングし、
      // 読めない場合は --cols/--rows へフォールバックする。
      // apiSocket は上の null/空チェック済みで常に非null。
      apiSocket: apiSocket,
      clientSocket: clientSocket,
      paneId: paneId,
      cols: cols,
      rows: rows,
      protocol: status.serverProtocol,
      timeout: execTimeout,
      postTimeoutArgs: [
        ('--max-output-bytes', defaultMaxOutputBytes.toString()),
      ],
    );

    try {
      return _parseHyperlinksJson(
        stdout,
        expectedPaneId: paneId,
        expectedProtocol: status.serverProtocol,
      );
    } on FormatException catch (e) {
      _fail(HerdrCaretHelperFailure.invalidOutput, e.message, e);
    }
  }

  /// helper の単一 JSON 行を手書きで検証し、[PaneHyperlinks] へ変換する。
  ///
  /// 検証失敗（破損 JSON・範囲外座標・不正 protocol・pane 不一致・
  /// フィンガープリント書式不正）は [FormatException] を投げる（clamp
  /// しない。[run] がこれを捕捉し [HerdrCaretHelperException] へ変換する）。
  ///
  /// [expectedProtocol] は要求した `status.serverProtocol`。応答の
  /// `protocolVersion` は allow-list 内であることに加え、これと一致すること
  /// も確認する（stale な応答・別 herdr からの応答の拒否）。
  PaneHyperlinks _parseHyperlinksJson(
    String json, {
    required String expectedPaneId,
    required int expectedProtocol,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      // jsonDecode の FormatException.message は入力の断片（stdout 本文）を
      // 含み得るため、そのまま伝播させない。
      throw const FormatException('Helper output is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Helper output is not a JSON object');
    }

    final paneId = decoded['paneId'];
    if (paneId is! String || !HerdrCaretShellArgs.isValidPaneId(paneId)) {
      throw const FormatException('Invalid paneId in helper output');
    }
    if (paneId != expectedPaneId) {
      throw const FormatException('Pane id mismatch in helper output');
    }

    // [expectedProtocol]（= 要求した status.serverProtocol）は run() の
    // 冒頭で allow-list 済みのため、一致確認だけで「allow-list 内かつ要求と
    // 一致」の両方を満たす。
    final protocolVersion = decoded['protocolVersion'];
    if (protocolVersion is! int || protocolVersion != expectedProtocol) {
      throw const FormatException('protocolVersion mismatch in helper output');
    }

    // frameWidth/frameHeight/truncated/links/rowHashes の検証は
    // hyperlinks/scrollback-links 共通（herdr_hyperlink_json.dart）。
    return parseHyperlinkFields(decoded);
  }

  Never _fail(
    HerdrCaretHelperFailure failure,
    String message, [
    Object? cause,
  ]) {
    if (kDebugMode) {
      debugPrint('[herdr-hyperlink] ${failure.name}: $message');
    }
    throw HerdrCaretHelperException(failure, message, cause);
  }
}
