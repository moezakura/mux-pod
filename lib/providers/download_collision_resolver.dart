import 'dart:io';

import '../services/sftp/overwrite_choice.dart';
import 'download_state.dart';

/// 決定適用の結果（cancel はバッチ中断を意味する）。
class CollisionResolveResult {
  const CollisionResolveResult({required this.items, required this.cancelled});

  /// 決定適用後のアイテムリスト（cancel 時は空）。
  final List<DownloadItemState> items;

  /// 上書き確認で「キャンセル」決定されたか（バッチ中断）。
  final bool cancelled;
}

/// 同名衝突の事前スキャン・`_1` 採番・上書き/リネーム/スキップ決定の名前解決を行う。
///
/// **予約名集合は状態として保持しない**（所有者は [DownloadBatchSession]）。呼び出し
/// 側が [DownloadBatchSession.reservedNames] を引数で渡す。名前解決は純粋関数であり、
/// state / 通知 / 保存先の解放には触れない（フロー制御は shell が行う）。
class DownloadCollisionResolver {
  const DownloadCollisionResolver();

  /// 保存先に同名ファイルが存在するアイテムを事前スキャンする（転送開始前に一括確認・
  /// 転送中のダイアログ排除）。存在確認の失敗（iOS スコープ未開始等）は「非衝突」。
  Future<List<DownloadItemState>> preScan(
    List<DownloadItemState> items, {
    required Future<bool> Function(String name) existsIn,
  }) async {
    final colliding = <DownloadItemState>[];
    for (final item in items) {
      if (await existsIn(item.name)) colliding.add(item);
    }
    return colliding;
  }

  /// `name.ext` → `name_1.ext` → `name_2.ext`…の順で保存先に存在せず、[reserved] にも
  /// 含まれない空き名を採番する（`destination.exists` ベース・Sync API 禁止）。
  Future<String> firstAvailableName(
    String name, {
    Set<String>? reserved,
    required Future<bool> Function(String name) existsIn,
  }) async {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '${base}_1$ext';
    for (
      var n = 2;
      await existsIn(candidate) || (reserved?.contains(candidate) ?? false);
      n++
    ) {
      candidate = '${base}_$n$ext';
    }
    return candidate;
  }

  /// `name.ext` → `name_1.ext` → `name_2.ext`…の順で空き名を採番する。
  ///
  /// **最初の候補は常に `name_1.ext`** であり、`name.ext` そのものは存在検査しない
  /// （実装は常に `_1` から採番する仕様・一括の [firstAvailableName] と同様）。例:
  /// `data.bin` が未存在でも `data_1.bin` を返す（衝突回避は `_1` 採番で常に成立）。
  /// ファイル実パスベース（単一 tmp ダウンロード用）。[reserved] は同一バッチ内で既に
  /// 割当済みの宛先集合（バッチ内重複の自動リネームでも使用・LOW#3）。
  String firstAvailablePath(String localPath, {Set<String>? reserved}) {
    final dot = localPath.lastIndexOf('.');
    final base = dot > 0 ? localPath.substring(0, dot) : localPath;
    final ext = dot > 0 ? localPath.substring(dot) : '';
    var candidate = '${base}_1$ext';
    for (
      var n = 2;
      File(candidate).existsSync() || (reserved?.contains(candidate) ?? false);
      n++
    ) {
      candidate = '${base}_$n$ext';
    }
    return candidate;
  }

  /// 上書き確認の決定（`Map<name, OverwriteChoice>`・applyToAll 展開済み）を適用する。
  ///
  /// - `overwrite`: [DownloadItemState.overwrite]=true で保存先の同名を切り詰めて再利用。
  /// - `rename`: `_1` 接尾辞で空き名を採番（`destination.exists` + [reserved]・LOW#3）して
  ///   overwrite=true（決定した名前を SAF 側の自動採番で壊さない）。
  /// - `skip`: キューから除外（isSkipped=true）。
  /// - `cancel`: [CollisionResolveResult.cancelled]=true でバッチ中断を報告する
  ///   （#40 batch モードでは不使用の値。安全側にバッチ中断）。
  Future<CollisionResolveResult> resolveDecisions({
    required Map<String, OverwriteChoice> decisions,
    required List<DownloadItemState> items,
    required Set<String> reserved,
    required Future<bool> Function(String name) existsIn,
  }) async {
    final updated = <DownloadItemState>[];
    for (final item in items) {
      switch (decisions[item.name]) {
        case null:
          // 衝突なし（または決定なし）アイテムはそのまま（overwrite=false）。
          updated.add(item);
        case OverwriteChoice.overwrite:
          // ユーザー明示の上書き: 保存先の同名を切り詰めて再利用する。
          updated.add(item.copyWith(overwrite: true));
        case OverwriteChoice.rename:
          // バッチ内の他アイテム宛先も予約済みとして採番し、重複上書きを防ぐ（LOW#3）。
          final newName = await firstAvailableName(
            item.name,
            reserved: reserved,
            existsIn: existsIn,
          );
          updated.add(
            item.copyWith(name: newName, localPath: newName, overwrite: true),
          );
        case OverwriteChoice.skip:
          updated.add(item.copyWith(isSkipped: true));
        case OverwriteChoice.cancel:
          // #40 batch モードでは不使用の値。安全側にバッチ中断（idle・転送開始しない）。
          return const CollisionResolveResult(items: [], cancelled: true);
      }
    }
    return CollisionResolveResult(items: updated, cancelled: false);
  }
}
