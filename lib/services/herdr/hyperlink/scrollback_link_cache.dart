// inventory: HERDR-SCROLLBACK-LINK-CACHE-000
/// スクロールモードのリンクキャッシュ。
///
/// 保持する状態は4つ:
/// - スナップショットの identity（[identity] と [generation]。
///   `TerminalScrollFollowController.onViewportSettled` の
///   `snapshotIdentity` と同じ形。[identity] は `==`（値の等価性）で比較
///   するオブジェクト、[generation] はその世代を表す整数。generation だけを
///   比較すると、controller の作り直しや再接続の後に番号が偶然一致して
///   衝突する余地が残るため、両方を保持する）。
///   [identity] の実体（`HerdrTargetIdentity`。`herdr_types.dart`）は
///   `({HerdrSnapshotCache cache, int epoch, String? paneId})` の record
///   で、`HerdrController.captureIdentity()` は呼び出しのたびに新しい
///   record インスタンスを作る（内容が同じでも `identical` は `false`）。
///   `identical` で比較すると本番では常に不一致になり、キャッシュが毎回
///   破棄されて世代ガードも常に不一致になる
///   （`HerdrController.isCurrentIdentity` と同じ「値の等価性」基準に揃える）。
/// - スナップショット行番号 → リンク範囲の対応（[linksByBodyLine]）
/// - 取得済みの窓（[hasFetched]。`offsetFromBottom` の集合。
///   取得済みの範囲は再取得しない）
/// - 直近に採用した整列の差 k（[lastK]。次回の窓計算の見積りに使う）
/// - 直近の helper 結果が実際に使った frame の行数（[lastFrameRows]。
///   helper が実 pty サイズを優先するようになったため、次回の
///   窓タイリング（`HerdrScrollbackLinkReader._computeOffsets` の R）の
///   最有力の見積りに使う）
///
/// `TerminalViewData` ではなく画面の状態として持つ（永続化しない）。
/// スナップショット差し替え（[identity] または [generation] の変化）と
/// スクロールモード終了（[clear]）で内容を破棄する。
///
/// [revision]: 内容が実際に変わるたびに増分する内部カウンタ。
/// `applyWindowResult` は [generation] を変えずに [linksByBodyLine] だけを
/// 書き換える設計のため、表示側（`AnsiTextView`）が
/// 「generation だけ」をメモ化キーにすると、同一 generation 内で新しく
/// 取得したリンクが表示へ反映されない。表示側は `(identity, generation,
/// revision)` をメモ化キーに使うこと。同じ結果の再適用や、変化の無い
/// resetIfNeeded/clear の呼び出しでは増分しない（不要な再計算を避ける）。
///
/// throw しない（読み取り・書き込みとも例外を投げない）。
library;

import 'herdr_hyperlink_alignment.dart' show HerdrHyperlinkRange;

final class ScrollbackLinkCache {
  Object? _identity;
  int? _generation;
  final Map<int, List<HerdrHyperlinkRange>> _linksByBodyLine = {};
  final Set<int> _fetchedOffsets = {};
  int? _lastK;
  int? _lastFrameRows;
  int _revision = 0;

  /// 現在保持しているスナップショットの identity（未保持なら `null`）。
  /// `==`（値の等価性）で比較する（表示側の世代ガードと同じ）。
  Object? get identity => _identity;

  /// 現在保持しているスナップショットの generation（未保持なら `null`）。
  int? get generation => _generation;

  /// 本文行番号 → リンク範囲の対応（[overlayHerdrHyperlinks] の
  /// `linksByLine` へそのまま渡せる形。unmodifiable view）。
  Map<int, List<HerdrHyperlinkRange>> get linksByBodyLine =>
      Map.unmodifiable(_linksByBodyLine);

  /// 直近に採用した整列の差 k（未取得なら `null`）。
  int? get lastK => _lastK;

  /// 直近の helper 結果が実際に使った frame の行数（未取得なら `null`。
  /// helper が実 pty サイズを優先するため、次回の窓タイリングの
  /// 最有力の見積りに使う）。
  int? get lastFrameRows => _lastFrameRows;

  /// 内容が実際に変わるたびに増分するカウンタ（表示側のメモ化キー）。
  /// `resetIfNeeded`（実際に切り替わったとき）・`applyWindowResult`（実際に
  /// 適用したとき）・`clear`（実際に内容があったとき）でのみ増分する。
  int get revision => _revision;

  /// [identity] と [generation] のスナップショットが現在保持中のものと
  /// 異なれば、内容を破棄して切り替える（両方一致すれば何もしない・冪等）。
  void resetIfNeeded({required Object? identity, required int generation}) {
    if (_identity == identity && _generation == generation) return;
    _identity = identity;
    _generation = generation;
    _linksByBodyLine.clear();
    _fetchedOffsets.clear();
    _lastK = null;
    _lastFrameRows = null;
    _revision++;
  }

  /// [offsetFromBottom] の窓を取得済みか（取得済みの範囲は
  /// 再取得しない、の判定に使う）。
  bool hasFetched(int offsetFromBottom) =>
      _fetchedOffsets.contains(offsetFromBottom);

  /// [generation] の窓の取得結果をマージする。
  ///
  /// 呼び出し時点の [generation] が現在保持中のものと異なる場合は、
  /// スナップショットが差し替わった後に届いた結果とみなして無視する
  /// （破棄済み世代の結果を取り込まない。呼び出し側の reader が
  /// identity 照合と合わせて使う想定）。
  ///
  /// [revision] は内容が実際に変わったときだけ増分する（同じ offset・
  /// 同じ内容の再適用では増やさない）。
  ///
  /// [frameRows] は窓取得時に helper が実際に使った frame の行数
  /// （[lastFrameRows]。正の値のときだけ更新する。0 以下・`null` は
  /// 「今回は分からなかった」として前回の値を保持する）。
  ///
  /// [truncated] が true の窓は取得済み（[hasFetched]）にしない。
  void applyWindowResult({
    required int generation,
    required int offsetFromBottom,
    required Map<int, List<HerdrHyperlinkRange>> linksByBodyLine,
    int? k,
    int? frameRows,
    bool truncated = false,
  }) {
    if (_generation != generation) return;

    // truncated の窓（helper が描画内容を拒否した窓、または出力量の上限で
    // 入りきらなかった窓）は取得済みにしない。次に止まったときに再取得の
    // 対象に残す（頻度は reader の開始間隔の制限に従う）。
    var changed = truncated ? false : _fetchedOffsets.add(offsetFromBottom);

    linksByBodyLine.forEach((line, ranges) {
      final existing = _linksByBodyLine[line];
      if (existing == null || !_rangesEqual(existing, ranges)) {
        _linksByBodyLine[line] = ranges;
        changed = true;
      }
    });

    if (k != null && k != _lastK) {
      _lastK = k;
      changed = true;
    }

    if (frameRows != null && frameRows > 0 && frameRows != _lastFrameRows) {
      _lastFrameRows = frameRows;
      changed = true;
    }

    if (changed) _revision++;
  }

  /// 全内容を破棄する（スクロールモード終了時）。
  void clear() {
    final hadState =
        _identity != null ||
        _generation != null ||
        _linksByBodyLine.isNotEmpty ||
        _lastK != null ||
        _lastFrameRows != null;
    _identity = null;
    _generation = null;
    _linksByBodyLine.clear();
    _fetchedOffsets.clear();
    _lastK = null;
    _lastFrameRows = null;
    if (hadState) _revision++;
  }

  static bool _rangesEqual(
    List<HerdrHyperlinkRange> a,
    List<HerdrHyperlinkRange> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
