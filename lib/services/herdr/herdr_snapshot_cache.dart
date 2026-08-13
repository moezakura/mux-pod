// inventory: HERDR-CACHE-000
/// herdr snapshot のキャッシュ（決定層・純 Dart・エポック内在化）。
///
/// snapshot 読み取りの**唯一の chokepoint** が `get()` であることを構造的に
/// 保証する（A5 / A3 改 / L0-b-05）。TTL 5s + single-flight + forceFresh に加え、
/// adapter 差し替え（再接続・SSH client 再生成）を `identical` で検出し
/// 自動再取得＋エポック++ する。
///
/// - **エポック増分（自動・cache 内在）**:
///   1. `get()` で `identical(_adapterProvider(), _snapshotAdapter)` が
///      false（adapter 差し替え）→ 自動再取得＋エポック++
///   2. `get(force: true)`（A2 エスカレーション経路）→ 強制再取得＋エポック++
///   ※ TTL 切れの通常再取得はエポックを増やさない（ターゲットは不変）。
/// - 画面側ヘルパー（世代カウンタ）は作らない（呼び忘れ・バンプ漏れを
///   構造的に排除）。
/// - 画面側（A3改・エポック照合）は公開された [epoch] と表示対象 pane ID
///   （`_TargetSource.currentPaneId`）を照合に使う。バンプは cache 内在のため
///   画面側はバンプしない。
library;

import 'herdr_adapter.dart';
import 'herdr_models.dart';

// inventory: HERDR-CACHE-001
/// herdr snapshot キャッシュ。
///
/// [adapterProvider] は「現在の adapter を返す関数」。再接続で
/// [HerdrAdapter] インスタンスが作り直されたとき、`identical` 比較が
/// false になり自動再取得が走る。TTL と時刻源は注入可能（テスト用）。
class HerdrSnapshotCache {
  final HerdrAdapter Function() _adapterProvider;
  final Duration _ttl;
  final DateTime Function() _clock;

  HerdrSnapshot? _snapshot;
  HerdrAdapter? _snapshotAdapter;
  DateTime? _snapshotAt;
  int _epoch = 0;
  Future<HerdrSnapshot>? _inFlight;

  /// [adapterProvider]: 現在の [HerdrAdapter] を返す関数。
  /// [ttl]: キャッシュ有効期間（既定 5 秒）。
  /// [clock]: 時刻源（既定 [DateTime.now]。テストで注入可能）。
  HerdrSnapshotCache(
    this._adapterProvider, {
    Duration ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _ttl = ttl,
        _clock = clock ?? DateTime.now;

  /// snapshot の世代（adapter 差し替え / force 再取得で増える）。
  ///
  /// read only。バンプは [get] 内部（force / adapter 差し替え）でのみ行われ、
  /// 画面側はバンプしない（A3改・エポック照合の照合キーとして使う）。
  int get epoch => _epoch;

  /// snapshot を保持しているかどうか。
  bool get hasSnapshot => _snapshot != null;

  /// 現在キャッシュしている snapshot（無ければ null）。
  ///
  /// read chokepoint は [get] のみ。この getter は TTL/epoch に関与しない
  /// 診断用の参照であり、表示ロジックからは使わないこと。
  HerdrSnapshot? get cachedSnapshot => _snapshot;

  /// 現在キャッシュしている snapshot を取得した adapter。
  ///
  /// 診断用（adapter 差し替え検出の `identical` 比較は [get] 内部で行う）。
  HerdrAdapter? get cachedAdapter => _snapshotAdapter;

  /// snapshot を取得する（唯一の read chokepoint）。
  ///
  /// - TTL 内かつ force でなければキャッシュを返す（エポック不変）。
  /// - [force] が true なら強制再取得しエポック++ する（A2 再解決経路）。
  /// - adapter が差し替わっていれば自動再取得しエポック++ する。
  /// - TTL 切れの通常再取得はエポックを増やさない（表示対象は不変）。
  /// - 同時に呼ばれた場合は single-flight で 1 回の CLI 実行にまとめる。
  ///   [joinInflight] が false のときは進行中の fetch に**合流せず**、その完了を
  ///   待ってから必ず新規 fetch する（Codex B2: window-change 送信後に開始された
  ///   snapshot を保証するための同期契約。hidden TUI resize の収束判定用）。
  ///
  /// 失敗時は throw（[HerdrAdapter.snapshot] の例外をそのまま伝播）。
  Future<HerdrSnapshot> get({
    bool force = false,
    bool joinInflight = true,
  }) async {
    final adapter = _adapterProvider();

    // adapter 差し替え検出（再接続・SSH client 再生成）→ キャッシュ無効化。
    // エポック++ は fetch 側で force / adapter 差し替えのときのみ行う。
    final adapterChanged =
        _snapshot != null && !identical(adapter, _snapshotAdapter);
    if (adapterChanged) {
      _snapshot = null;
      _snapshotAdapter = null;
      _snapshotAt = null;
    }

    // TTL 内ならキャッシュ返却（force は TTL を無視して再取得）。
    if (!force && _snapshot != null && _snapshotAt != null) {
      final age = _clock().difference(_snapshotAt!);
      if (age < _ttl) return _snapshot!;
    }

    // single-flight: 進行中の fetch があれば共有（joinInflight: false では合流しない）。
    final inFlight = _inFlight;
    if (inFlight != null && joinInflight) return inFlight;
    if (inFlight != null) {
      // 進行中の fetch の完了を待ってから新規 fetch する（古い取得結果を返さない）。
      try {
        await inFlight;
      } catch (_) {
        // 前回 fetch の失敗は無視して新規 fetch する。
      }
    }

    final bumpEpoch = force || adapterChanged;
    final future = _fetch(adapter, bumpEpoch: bumpEpoch);
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  /// キャッシュを失効させる（server-down 時など。A2）。
  ///
  /// 次の [get] で再取得される。エポックは増やさない（失効は表示対象の
  /// 切替ではないため）。接続・切替経路は [get] 側の force / adapter 検出で
  /// エポック++ される。
  void invalidate() {
    _snapshot = null;
    _snapshotAdapter = null;
    _snapshotAt = null;
  }

  Future<HerdrSnapshot> _fetch(
    HerdrAdapter adapter, {
    required bool bumpEpoch,
  }) async {
    final snapshot = await adapter.snapshot();
    _snapshot = snapshot;
    _snapshotAdapter = adapter;
    _snapshotAt = _clock();
    if (bumpEpoch) _epoch++;
    return snapshot;
  }
}
