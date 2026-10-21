/// SSH先への herdr-caret-helper `scrollback-links` サブコマンドの実行と、
/// 出力 JSON の検証を担う manager（herdr OSC 8 ハイパーリンク実験機能）。
///
/// 処理フロー:
/// 1. HerdrStatus.serverProtocol が allow-list（[isHerdrScrollbackLinkProtocolSupported]。
///    現在の対応 protocol は 17/20/22）に含まれなければ実行しない（unsupportedProtocol）。
/// 2. [offsetsFromBottom] は 1..3 個（`--window` の上限）。範囲外は
///    実行前に invalidOutput。
/// 3. socket 導出・paneId/cols の検証は [HerdrHyperlinkHelperManager] と同じ
///    規則。
/// 4. installer に helper 配置を依頼（caret・hyperlinks と共有する場合は
///    呼び出し側が既存 installer を注入する）。
/// 5. executor に `scrollback-links` サブコマンドで 1 回実行させる。helper
///    用 timeout（既定 1500ms）と SSH 実行 timeout（既定 3200ms）を分けて
///    渡す。
/// 6. stdout を手書きで検証し、[ScrollbackLinksResult] へ変換する。窓ごとの
///    `frameWidth`/`frameHeight`/`truncated`/`links`/`rowHashes` の検証は
///    [HerdrHyperlinkHelperManager] と共通（`herdr_hyperlink_json.dart`）。
///
/// [run] は失敗を必ず [HerdrCaretHelperException] で throw する（null を
/// 返さない。`HerdrHyperlinkHelperManager` と同じ規約）。
/// `HerdrScrollbackLinkReader.fetch` がこれを catch して best-effort（null）
/// に変換する。`busy`（ロック取得失敗）は
/// [HerdrCaretHelperException.helperErrorKind] で判別できる
/// （executor 側で共通対応済み）。
///
/// セキュリティ規則: socket path・pane 本文・helper 出力の未検証内容を
/// 例外メッセージ・ログへ残さない。失敗分類だけを伝える。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

/// `scrollback-links` の `restore` フィールド。
///
/// MuxPod は debug ログの分類にだけ使う（表示・入力の分岐には使わない）。
enum ScrollbackLinkRestore {
  /// 元が最下部で、最下部へ戻したことを確認した。
  exact,

  /// best-effort で戻した。
  approximate,

  /// 往復中に PC 側の入力等で最下部へ戻っていたため動かさなかった。
  skippedReset,

  /// 戻す操作が失敗・時間切れ。
  failed;

  static ScrollbackLinkRestore? fromWireName(String name) => switch (name) {
    'exact' => ScrollbackLinkRestore.exact,
    'approximate' => ScrollbackLinkRestore.approximate,
    'skipped_reset' => ScrollbackLinkRestore.skippedReset,
    'failed' => ScrollbackLinkRestore.failed,
    _ => null,
  };
}

/// `scrollback-links` の窓1つ分の結果。
final class ScrollbackLinkWindow {
  /// 要求した offset from bottom（`--window` の値）。
  final int requestedOffset;

  /// 実際に観測した offset from bottom（`pane.get` 由来。0 以上）。
  final int actualOffset;

  /// 窓の中身（frameWidth/frameHeight/links/rowFingerprints/truncated）。
  /// `hyperlinks` の出力と同一構造のため、検証済みの [PaneHyperlinks] を
  /// そのまま入れ子にする。
  final PaneHyperlinks hyperlinks;

  const ScrollbackLinkWindow({
    required this.requestedOffset,
    required this.actualOffset,
    required this.hyperlinks,
  });

  @override
  String toString() =>
      'ScrollbackLinkWindow(requested=$requestedOffset, '
      'actual=$actualOffset, $hyperlinks)';
}

/// `scrollback-links` 1回実行の結果。
final class ScrollbackLinksResult {
  final List<ScrollbackLinkWindow> windows;
  final ScrollbackLinkRestore restore;

  const ScrollbackLinksResult({required this.windows, required this.restore});

  @override
  String toString() =>
      'ScrollbackLinksResult(${windows.length} windows, '
      'restore=${restore.name})';
}

/// helper `scrollback-links` 実行の抽象（`HerdrScrollbackLinkReader` が
/// 注入・fake する対象）。
abstract interface class HerdrScrollbackLinkHelperRunner {
  /// [status] の protocol / socket に基づき、[paneId] のスクロールバック窓
  /// （[offsetsFromBottom]、1..3個）のリンクを helper 1 回実行で取得する。
  ///
  /// 失敗は [HerdrCaretHelperException] を投げる（null を返さない）。
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  });
}

/// SSH/SFTP 経由で `scrollback-links` を配置・実行・検証する manager。
class HerdrScrollbackLinkHelperManager
    implements HerdrScrollbackLinkHelperRunner {
  /// 既定の SSH 実行タイムアウト（helper の取得 1500ms + 復元 700ms より
  /// 長くする）。
  static const Duration defaultRunTimeout = Duration(milliseconds: 3200);

  /// 既定の helper `--timeout-ms`（取得専用）。
  static const Duration defaultHelperTimeout = Duration(milliseconds: 1500);

  /// 既定の `--restore-budget-ms`（復元専用の追加時間）。
  static const int defaultRestoreBudgetMs = 700;

  /// 既定の `--max-output-bytes`。
  static const int defaultMaxOutputBytes = 60000;

  /// `--window` の最大個数。
  static const int maxWindowCount = 3;

  late final HerdrCaretSshRunner _sshRunner;
  late final HerdrCaretInstaller _installer;
  late final HerdrCaretHelperExecutor _executor;

  /// [installer] が非 null ならそれを使う（caret・hyperlinks と共有し、
  /// 配置確認の SSH 実行を機能ごとに重複させない）。null（既定）なら内部生成。
  HerdrScrollbackLinkHelperManager({
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

  /// 構築済み installer（他の manager と共有するために公開する）。
  HerdrCaretInstaller get installer => _installer;

  @override
  Future<ScrollbackLinksResult> run({
    required HerdrStatus status,
    required String paneId,
    required int cols,
    required List<int> offsetsFromBottom,
    Duration? timeout,
  }) async {
    final execTimeout = timeout ?? defaultRunTimeout;

    if (!isHerdrScrollbackLinkProtocolSupported(status.serverProtocol)) {
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
    if (cols < 0 || cols > 0xFFFF) {
      _fail(HerdrCaretHelperFailure.invalidOutput, 'Invalid frame size');
    }
    if (offsetsFromBottom.isEmpty ||
        offsetsFromBottom.length > maxWindowCount) {
      // --window は 1..3 個に限る。実行前に拒否する。
      _fail(
        HerdrCaretHelperFailure.invalidOutput,
        'offsetsFromBottom must have 1..$maxWindowCount entries',
      );
    }
    for (final offset in offsetsFromBottom) {
      if (offset < 0) {
        _fail(
          HerdrCaretHelperFailure.invalidOutput,
          'offsetsFromBottom entries must be >= 0',
        );
      }
    }

    final clientSocket = HerdrCaretShellArgs.deriveClientSocket(apiSocket);
    final installation = await _installer.ensureInstalled(execTimeout);
    // lock-dir は sha256 ディレクトリの親
    // （`${XDG_CACHE_HOME:-$HOME/.cache}/mux-pod/herdr-caret/locks/`）を使う。
    // remotePath は `<herdr-caret ルート>/<sha256>/herdr-caret-helper` なので、
    // dirname を2回たどって sha256 ディレクトリの親（herdr-caret ルート）を
    // 得る。バージョン（sha256）が異なる MuxPod 端末でも同じ --lock-dir が
    // 渡り、同じ pane への排他が効く。
    final herdrCaretRoot = p.posix.dirname(
      p.posix.dirname(installation.remotePath),
    );
    final lockDir = p.posix.join(herdrCaretRoot, 'locks');

    final stdout = await _executor.runHelper(
      installation,
      subcommand: HerdrCaretHelperSubcommand.scrollbackLinks,
      apiSocket: apiSocket,
      clientSocket: clientSocket,
      paneId: paneId,
      cols: cols,
      protocol: status.serverProtocol,
      timeout: execTimeout,
      helperTimeout: defaultHelperTimeout,
      preTimeoutArgs: [
        for (final offset in offsetsFromBottom) ('--window', offset.toString()),
      ],
      postTimeoutArgs: [
        ('--restore-budget-ms', defaultRestoreBudgetMs.toString()),
        ('--max-output-bytes', defaultMaxOutputBytes.toString()),
        ('--lock-dir', lockDir),
      ],
    );

    try {
      return _parseScrollbackLinksJson(
        stdout,
        expectedPaneId: paneId,
        expectedProtocol: status.serverProtocol,
        expectedOffsets: offsetsFromBottom,
      );
    } on FormatException catch (e) {
      _fail(HerdrCaretHelperFailure.invalidOutput, e.message, e);
    }
  }

  ScrollbackLinksResult _parseScrollbackLinksJson(
    String json, {
    required String expectedPaneId,
    required int expectedProtocol,
    required List<int> expectedOffsets,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
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

    final protocolVersion = decoded['protocolVersion'];
    if (protocolVersion is! int || protocolVersion != expectedProtocol) {
      throw const FormatException('protocolVersion mismatch in helper output');
    }

    final restoreRaw = decoded['restore'];
    final restore = restoreRaw is String
        ? ScrollbackLinkRestore.fromWireName(restoreRaw)
        : null;
    if (restore == null) {
      throw const FormatException('Invalid restore in helper output');
    }

    final windowsRaw = decoded['windows'];
    if (windowsRaw is! List) {
      throw const FormatException('windows must be an array');
    }
    if (windowsRaw.length != expectedOffsets.length) {
      // 要求した窓数と応答の窓数が不一致。
      throw const FormatException('windows count mismatch');
    }

    final windows = List<ScrollbackLinkWindow>.unmodifiable(
      List.generate(
        windowsRaw.length,
        (i) => _parseWindow(windowsRaw[i], expectedOffsets[i]),
      ),
    );

    return ScrollbackLinksResult(windows: windows, restore: restore);
  }

  ScrollbackLinkWindow _parseWindow(Object? entry, int expectedOffset) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('windows entry must be an object');
    }
    final requestedOffset = entry['requestedOffset'];
    if (requestedOffset is! int || requestedOffset != expectedOffset) {
      // 要求した順序・値と一致しない。
      throw const FormatException('requestedOffset mismatch');
    }
    final actualOffset = entry['actualOffset'];
    if (actualOffset is! int || actualOffset < 0) {
      throw const FormatException('actualOffset must be >= 0');
    }
    final hyperlinks = parseHyperlinkFields(entry);
    return ScrollbackLinkWindow(
      requestedOffset: requestedOffset,
      actualOffset: actualOffset,
      hyperlinks: hyperlinks,
    );
  }

  Never _fail(
    HerdrCaretHelperFailure failure,
    String message, [
    Object? cause,
  ]) {
    if (kDebugMode) {
      debugPrint('[herdr-scrollback-link] ${failure.name}: $message');
    }
    throw HerdrCaretHelperException(failure, message, cause);
  }
}
