import 'dart:async';

import '../services/download/download_destination.dart';
import '../services/sftp/transfer_progress.dart';
import '../services/ssh/ssh_client.dart';
import 'download_state.dart';

/// バッチ世代・キャンセルトークン・アイテムリスト・予約名集合・保存先リソースの
/// 所有と解放を 1 箇所に管理する。
///
/// 不変条件（過去のバグ M1/M2/M4・レビュー HIGH#1 の再発防止）をここに集約する:
/// - 世代ガード付き items 更新（[updateItem]）: 旧バッチの在途コールバックが
///   新バッチの items へ書き込まない。
/// - 保存先の 1 回だけ dispose・クロスバッチ誤破棄防止（[disposeDestination]）:
///   dispose 済みバッチ集合（[_disposedBatches]）と「現在世代かつ同一オブジェクトの
///   場合のみフィールドクリア」で二重解放と誤破棄を防ぐ。
/// - 予約名集合（[reservedNames]）: バッチ内で採番済みの宛先名。衝突解決の
///   呼び出し側（[DownloadCollisionResolver]）は状態を持たず、ここから引数で受ける。
class DownloadBatchSession {
  DownloadBatchSession({this.onItemsPublished});

  /// items が公開（publish）されたときに呼ばれるコールバック（shell が
  /// [DownloadState] へ反映するための観測点）。
  final void Function(List<DownloadItemState> items)? onItemsPublished;

  /// バッチ無効化カウンタ。startDownloads で新バッチ開始、reset() で無効化し、
  /// 古いバッチの在途コールバック（進捗・完了・キュー後処理）を安全に abort させる
  /// （レビュー HIGH#1: 転送中 reset の RangeError/TypeError 防止）。
  int _generation = 0;

  TransferCancelToken? _token;
  StreamSubscription<SshConnectionState>? _connectionSub;
  List<DownloadItemState> _items = [];

  /// バッチ内で採番済み（予約済み）の宛先名集合（LOW#3）。所有者は本セッション。
  final Set<String> _reservedNames = {};

  /// 現在のバッチの保存先（startDownloads/startSingleTmpDownload が設定・キュー完了時に
  /// dispose する）。
  DownloadDestination? _destination;

  /// バッチ（世代）ごとの保存先 dispose 済みフラグ。
  ///
  /// キュー finally と reset() の二重 dispose を防ぐ。フィールド（[_destination]）では
  /// なく「世代」で管理することで、旧バッチの finally が新バッチの保存先（置換後の
  /// フィールド）を誤破棄しない（M1: クロスバッチ誤破棄の構造的排除）。
  final Set<int> _disposedBatches = {};

  /// 現在の世代。
  int get generation => _generation;

  /// 現在のバッチのキャンセルトークン（バッチ開始前は null）。
  TransferCancelToken? get token => _token;

  /// 現在のバッチのアイテムリスト。
  List<DownloadItemState> get items => _items;

  /// バッチ内で予約済みの宛先名集合（呼び出し側からは読み取り・追加のみ）。
  Set<String> get reservedNames => _reservedNames;

  /// 現在のバッチの保存先。
  DownloadDestination? get destination => _destination;

  /// 新バッチを開始する。
  ///
  /// 先頭で必ず新規 [TransferCancelToken] を生成（1 度キャンセル→次バッチ即キャンセルの
  /// 再入バグ防止）。旧バッチの在途コールバックを世代不一致で無効化する。
  void begin() {
    _generation++;
    _token = TransferCancelToken();
    _reservedNames.clear();
  }

  /// バッチを無効化して idle 相当へ戻す（reset() 用）。
  ///
  /// トークン cancel（在途 download を即中断・部分削除はサービス層）・切断購読解除・
  /// トークン破棄（次回 begin が新規生成）・items クリア・保存先参照の破棄を行う。
  /// 保存先リソース自体の解放は [disposeDestination] が担う（呼び出し側が旧バッチの
  /// 世代と保存先スナップショットを明示して呼ぶ）。
  void invalidate() {
    _generation++;
    _token?.cancel();
    _connectionSub?.cancel();
    _connectionSub = null;
    _token = null;
    _items = [];
    _destination = null;
    _reservedNames.clear();
  }

  /// [batch] が現在のバッチか（世代一致）。
  bool isCurrent(int batch) => batch == _generation;

  /// [batch] が保存先 dispose 済みか。
  bool isDisposed(int batch) => _disposedBatches.contains(batch);

  /// アイテムリストを置き換える（バッチ開始時・決定適用後の新リスト確定）。
  void setItems(List<DownloadItemState> items) {
    _items = items;
  }

  /// 保存先を設定する（バッチ開始時）。
  void setDestination(DownloadDestination destination) {
    _destination = destination;
  }

  /// 切断監視の購読を登録する（キュー実行時）。
  void setConnectionSub(StreamSubscription<SshConnectionState> sub) {
    _connectionSub = sub;
  }

  /// 自分が登録した購読のみ解除する（旧バッチの finally が新バッチの購読を触らない）。
  void clearConnectionSub(StreamSubscription<SshConnectionState> sub) {
    if (identical(_connectionSub, sub)) _connectionSub = null;
  }

  /// 切断監視の購読を解除する（reset・provider dispose 時）。
  void cancelConnectionSub() {
    _connectionSub?.cancel();
  }

  /// アイテムを 1 件更新する（世代ガード付き）。
  ///
  /// [batch] が現在世代と一致しない場合は何もせず false を返す
  /// （古いバッチ（reset 後）には書き込まない・HIGH#1）。[publish] 時は
  /// [onItemsPublished] を発火する（shell が [DownloadState.items] へ反映）。
  bool updateItem(
    int index,
    DownloadItemState Function(DownloadItemState) change, {
    required bool publish,
    required int batch,
  }) {
    if (batch != _generation) return false; // 古いバッチ（reset 後）には書き込まない（HIGH#1）。
    final items = List<DownloadItemState>.of(_items);
    items[index] = change(items[index]);
    _items = items;
    if (publish) {
      onItemsPublished?.call(items);
    }
    return true;
  }

  /// 保存先のリソースを解放する（バッチ単位・1 回だけ・クロスバッチ誤破棄防止 M1）。
  ///
  /// キュー実行側（[DownloadQueueRunner]）は自分が保持するスナップショット
  /// （batch + destination）を明示して呼ぶ。reset()・エラー return 等はバッチ/保存先を
  /// 省略し、現在のフィールドを対象にする（既定は現在世代）。
  ///
  /// - 同一バッチ（世代）の二重 dispose は [_disposedBatches] で抑止（キュー finally と
  ///   reset() の両立）。
  /// - フィールド（[_destination]）のクリアは「現在世代かつ同一オブジェクト」の場合のみ
  ///   行うため、旧バッチの finally は新バッチのフィールド（置換済みの保存先）を
  ///   null 化しない。
  /// - 失敗はベストエフォート（握りつぶし）。
  Future<void> disposeDestination({
    int? batch,
    DownloadDestination? destination,
  }) async {
    final b = batch ?? _generation;
    if (_disposedBatches.contains(b)) return; // このバッチは dispose 済み。
    final target = destination ?? _destination;
    if (target == null) return;
    _disposedBatches.add(b);
    try {
      await target.dispose();
    } catch (_) {
      // スコープ解放失敗はベストエフォート（転送結果に影響させない）。
    }
    if (b == _generation && identical(_destination, target)) {
      _destination = null;
    }
  }

  /// バッチに採用されなかった保存先（再入ガード等）を解放する（ベストエフォート）。
  Future<void> disposeOrphan(DownloadDestination destination) async {
    try {
      await destination.dispose();
    } catch (_) {
      // 採用されない保存先の解放失敗は握りつぶし（転送結果に影響させない）。
    }
  }

  /// 保存先に [name] のファイルが存在するか（ベストエフォート・失敗は false 扱い）。
  ///
  /// 存在確認の失敗（iOS スコープ未開始等）は「非衝突」として扱い、実際の `open()`
  /// 失敗としてアイテム単位で顕在化させる。
  Future<bool> existsInDestination(String name) async {
    final destination = _destination;
    if (destination == null) return false;
    try {
      return await destination.exists(name);
    } catch (_) {
      return false;
    }
  }
}
