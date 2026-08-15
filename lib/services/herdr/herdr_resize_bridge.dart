import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ssh/ssh_client.dart';
import 'herdr_models.dart';
import 'herdr_snapshot_cache.dart';

/// herdr のターミナル全体 resize を実現する hidden TUI 常駐ブリッジ。
///
/// 方式:
/// - **lazy start**: 最初の Resize 操作時（[resize] / [ensureStarted]）に hidden
///   TUI を起動し、SSH 接続中のみ常駐させる（接続時には起動しない・Codex 方針。
///   他クライアントのサイズを勝手に上書きしない）。
/// - 起動: PTY 付き direct exec（[SshClient.startManagedPty]）で herdr App TUI を
///   起動する。Hello（= PTY サイズ）は「現在の daemon サイズ」に合わせて上書きを
///   回避する（ユーザー決定: **PTY 要求サイズ**で実装・herdr の表示設定は考慮しない）。
/// - resize: [ManagedPtyProcess.resize]（SSH window-change）→ SIGWINCH → TUI →
///   `ClientMessage::Resize` → fresh snapshot で収束を確認する。
/// - **収束判定**: デフォルト表示設定前提の実測変換式
///   （`area.width = cols - 26` / `area.height = rows - 1`・herdr 0.7.5/0.8.0 実測
///   確定・サイドバー 26 列・タブ行 1 行）。5 秒間 100ms 間隔で fresh snapshot を
///   ポーリングし、収束しなければ **fail closed**（resize 不可 + 通知）。
///   初回ポーリングは送信後〜30ms で旧サイズを観測し得るため即時 fail はしない
///   （daemon 適用遅延 30〜150ms・ユーザー決定）。
/// - TUI 単体終了: [ManagedPtyProcess.done] 検知 → 限定回数（**初回を除く 3 回**）
///   だけ再起動し、SSH 接続自体は維持する。[reset]（intentional close）は
///   再起動回数を消費しない。
/// - 二重 start / reset / restart / resize は single-flight + 世代管理で直列化
///   （Codex B3）。
///
/// 現在の PTY 要求サイズを保持する（ダイアログ初期値用・Codex B1 の自己縮小バグ
/// 回避: layout.area から毎回逆算しない）。未起動・未 resize のときのみ fresh
/// snapshot の現在 tab の area から変換式の逆算で推定する。
class HerdrResizeBridge {
  HerdrResizeBridge({
    required this.client,
    required this.cache,
    required this.executablePath,
    required this.tabIdProvider,
    Duration? convergeTimeout,
    Duration? convergePollInterval,
  }) : convergeTimeout = convergeTimeout ?? defaultConvergeTimeout,
       convergePollInterval =
           convergePollInterval ?? defaultConvergePollInterval;

  /// 実測確定の chrome サイズ（herdr デフォルト表示設定・0.7.5/0.8.0 共通）:
  /// サイドバー 26 列・タブ行 1 行。
  static const int chromeCols = 26;
  static const int chromeRows = 1;

  /// 初回起動を除く、意図しない終了の再起動上限。
  static const int maxRestarts = 3;

  /// 収束確認のタイムアウト / ポーリング間隔（プロダクション既定値）。
  ///
  /// herdr TUI の 100ms 周期 resize ポーリングと daemon 適用遅延（30〜150ms・
  /// 実測）を考慮し、5 秒間 100ms 間隔で収束を確認する（ユーザー決定）。
  static const Duration defaultConvergeTimeout = Duration(seconds: 5);
  static const Duration defaultConvergePollInterval = Duration(
    milliseconds: 100,
  );

  /// 収束確認のタイムアウト / ポーリング間隔（テストで短縮可能）。
  final Duration convergeTimeout;
  final Duration convergePollInterval;

  final SshClient client;
  final HerdrSnapshotCache cache;

  /// herdr 実行ファイルのパス（POSIX shell quote 済み・承認条件 7）。
  final String executablePath;

  /// 現在表示中の tab ID を返す（収束判定の layout 選択用）。
  final String? Function()? tabIdProvider;

  _BridgeState _state = _BridgeState.idle;
  ManagedPtyProcess? _process;
  StreamSubscription<void>? _doneSub;
  int _restartCount = 0;
  int _generation = 0;
  bool _starting = false;
  ({int cols, int rows})? _pendingResize;
  int? _currentPtyCols;
  int? _currentPtyRows;

  /// ブリッジの現在状態（テスト用・診断用）。
  @visibleForTesting
  String get stateForTesting => _state.name;

  /// 現在の PTY 要求サイズ（ダイアログ初期値用）。
  ///
  /// resize 成功後は最後に要求したサイズを維持する（Codex B1 の自己縮小バグ回避）。
  /// 未起動・未 resize の場合は fresh snapshot の現在 tab の area から
  /// 変換式の逆算で推定する（初回のみ・推定不能なら 80x24）。
  Future<({int cols, int rows})> currentPtySize() async {
    if (_currentPtyCols != null && _currentPtyRows != null) {
      return (cols: _currentPtyCols!, rows: _currentPtyRows!);
    }
    try {
      final snapshot = await cache.get(force: true);
      final area = _areaForTab(snapshot);
      if (area != null && area.width > 0 && area.height > 0) {
        return (cols: area.width + chromeCols, rows: area.height + chromeRows);
      }
    } catch (_) {}
    return (cols: 80, rows: 24);
  }

  /// hidden TUI を起動済みにする（lazy start・single-flight）。
  ///
  /// 成功 = session 生成 + 両 stream 監視設置完了（プロセス終了は待たない）。
  /// 起動失敗（executablePath 不正・接続断等）は false（state は failed）。
  Future<bool> ensureStarted() async {
    if (_state == _BridgeState.ready && _process != null) return true;
    if (_starting) return false;
    _starting = true;
    try {
      final current = await currentPtySize();
      final process = await client.startManagedPty(
        executablePath,
        cols: current.cols,
        rows: current.rows,
      );
      _process = process;
      _doneSub = process.done.listen((_) => _onProcessDone());
      _generation++;
      _state = _BridgeState.ready;
      _currentPtyCols = current.cols;
      _currentPtyRows = current.rows;
      return true;
    } catch (_) {
      _state = _BridgeState.failed;
      return false;
    } finally {
      _starting = false;
    }
  }

  /// PTY 要求サイズを [cols] x [rows] に変更し、fresh snapshot で収束を確認する。
  ///
  /// 収束確認はデフォルト表示設定前提の実測変換式（[chromeCols] / [chromeRows]）
  /// に基づく期待値との width/height 明示比較。[convergeTimeout] の間
  /// [convergePollInterval] 間隔でポーリングし、収束しなければ false（resize 不可）。
  /// 0 列 0 行・chrome 差引後 0 以下も拒否する。
  Future<bool> resize(int cols, int rows) async {
    if (cols <= chromeCols || rows <= chromeRows) return false;
    _pendingResize = (cols: cols, rows: rows);
    final ok = await ensureStarted();
    if (!ok || _process == null) return false;
    final gen = _generation;
    try {
      _process!.resize(cols, rows);
      _currentPtyCols = cols;
      _currentPtyRows = rows;
    } catch (_) {
      return false;
    }
    return _waitForConvergence(cols, rows, gen);
  }

  /// ブリッジをリセットする（再接続時・intentional close）。
  ///
  /// hidden TUI を終了し、state を idle に戻す。再起動回数は消費しない
  /// （承認条件 5）。世代を進めるため、古い done callback は無視される。
  Future<void> reset() async {
    _generation++;
    _state = _BridgeState.stopping;
    _pendingResize = null;
    final process = _process;
    _process = null;
    final doneSub = _doneSub;
    _doneSub = null;
    await doneSub?.cancel();
    if (process != null) {
      await process.close();
    }
    _restartCount = 0;
    _state = _BridgeState.idle;
  }

  /// TUI 単体終了の検知（承認条件 10 の done 監視からのコールバック）。
  ///
  /// - intentional close（[reset] 中）は無視（再起動回数を消費しない）
  /// - 世代不一致（reset 後の旧 callback）は無視
  /// - 限定回数（初回を除く 3 回）内なら idle に戻して再起動を許可し、
  ///   再起動後に最新要求サイズを一度だけ再適用する（承認条件 6）
  /// - 超過時は failed（resize 不可・SSH 接続は維持）
  void _onProcessDone() {
    final expectedGen = _generation;
    // 世代チェック: reset 後の旧 done callback は無視（承認条件: reset と旧
    // done callback の競合を generation で排除）。
    if (_state == _BridgeState.stopping) return;
    _process = null;
    final doneSub = _doneSub;
    _doneSub = null;
    unawaited(doneSub?.cancel());
    if (_restartCount < maxRestarts) {
      _restartCount++;
      _state = _BridgeState.idle;
      final pending = _pendingResize;
      if (pending != null) {
        unawaited(_restartAndReapply(pending, expectedGen));
      }
    } else {
      _state = _BridgeState.failed;
    }
  }

  /// 再起動後に最新要求サイズを一度だけ再適用する（承認条件 6）。
  ///
  /// [gen] は [_onProcessDone] 時点の世代。再起動（[ensureStarted]）が 1 世代
  /// 進めるため、`gen + 1` が現在の世代と一致するときのみ再適用する。
  /// それ以外（他の再起動 / [reset] が割り込んだ）は破棄する。
  Future<void> _restartAndReapply(
    ({int cols, int rows}) pending,
    int gen,
  ) async {
    final ok = await ensureStarted();
    if (!ok || _process == null) return;
    if (gen + 1 != _generation) return;
    try {
      _process!.resize(pending.cols, pending.rows);
      _currentPtyCols = pending.cols;
      _currentPtyRows = pending.rows;
      await _waitForConvergence(pending.cols, pending.rows, gen + 1);
    } catch (_) {}
  }

  /// fresh snapshot（force + joinInflight:false = window-change 送信後に開始された
  /// fetch を保証・Codex B2）で、現在 tab の layout.area が期待値に収束するかを
  /// [convergePollInterval] 間隔でポーリングし、[convergeTimeout] までに収束しな
  /// ければ false を返す。
  ///
  /// 初回ポーリングは window-change 送信後〜30ms で旧サイズの snapshot を観測し
  /// 得るため（herdr daemon の適用遅延 30〜150ms・実測）、即時 fail はしない。
  /// 5 秒間ポーリングし続け、収束すれば true・しなければ false（fail closed）。
  Future<bool> _waitForConvergence(int cols, int rows, int gen) async {
    final deadline = DateTime.now().add(convergeTimeout);
    var pollCount = 0;
    HerdrRect? lastArea;
    while (DateTime.now().isBefore(deadline)) {
      if (gen != _generation) {
        // reset / 世代進行の割り込み: タイムアウトを待たず即座に失敗（安全弁）。
        return false;
      }
      try {
        final snapshot = await cache.get(force: true, joinInflight: false);
        final area = _areaForTab(snapshot);
        if (area != null) {
          lastArea = area;
          if (_matchesRequestedArea(area, cols, rows)) return true;
        }
      } catch (_) {}
      pollCount++;
      await Future<void>.delayed(convergePollInterval);
    }
    // タイムアウト原因の判別: generation 不一致はループ内で即時 return 済み。
    // ここに到達するのは「convergeTimeout の間ポーリングしても期待値に収束
    // しなかった」場合（非デフォルト表示設定 or snapshot 不達）。
    debugPrint(
      '[ResizeDebug] waitForConvergence: TIMEOUT after '
      '${convergeTimeout.inMilliseconds}ms (polls=$pollCount '
      'lastArea=${lastArea == null ? 'null' : '${lastArea.width}x${lastArea.height}'}) '
      '-> false',
    );
    return false;
  }

  /// 実測変換式（デフォルト表示設定前提・herdr 0.7.5/0.8.0 実測確定）に基づく
  /// 収束判定。width / height を個別に明示比較する（HerdrRect の == は未実装）。
  @visibleForTesting
  bool matchesRequestedArea(HerdrRect area, int cols, int rows) =>
      _matchesRequestedArea(area, cols, rows);

  bool _matchesRequestedArea(HerdrRect area, int cols, int rows) {
    final expectedWidth = cols - chromeCols;
    final expectedHeight = rows - chromeRows;
    return area.width == expectedWidth && area.height == expectedHeight;
  }

  /// snapshot の現在 tab（[tabIdProvider]）の layout.area を返す。
  ///
  /// 現在 tab の layout が無い場合は先頭 layout の area（同一 PTY のため全 tab 同値）。
  /// 全 layout 欠損（空）なら null。
  HerdrRect? _areaForTab(HerdrSnapshot snapshot) {
    if (snapshot.layouts.isEmpty) return null;
    final tabId = tabIdProvider?.call();
    if (tabId != null) {
      for (final layout in snapshot.layouts) {
        if (layout.tabId == tabId) return layout.area;
      }
    }
    return snapshot.layouts.first.area;
  }
}

/// ブリッジのライフサイクル状態。
enum _BridgeState {
  /// 未起動（lazy start 前 or [reset] 後）。
  idle,

  /// hidden TUI 起動済み（resize 可能）。
  ready,

  /// 起動失敗 or 再起動回数超過（resize 不可・SSH 接続は維持）。
  failed,

  /// [reset] 中の intentional close。
  stopping,
}
