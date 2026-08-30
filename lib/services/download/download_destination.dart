import 'dart:typed_data';

/// ダウンロード先へ 1 ファイル分を書き込むためのストリーム（契約）。
///
/// 端末固有の保存実装（ローカルファイル・SAF・iOS スコープ）を隠蔽する。
/// 呼び出し側（転送タスク層）は [add] をチャンク単位で呼び、完了時に [close] を、
/// キャンセル/失敗時は [deletePartial] を呼ぶ。
///
/// 契約:
/// - [add] はチャンク境界ごとに呼ぶ（実装は逐次 flush し、メモリに残さない）。
/// - [close] は正常終了時の flush 兼 close。以後の [add] は呼ばない。
/// - [deletePartial] はベストエフォート。**throw しない**（cleanup 失敗は握りつぶす）。
abstract class DownloadSink {
  /// [bytes] を追加で書き込む。
  ///
  /// 実装によっては各呼び出しで flush する（メモリ使用量を一定に保つ）。
  Future<void> add(Uint8List bytes);

  /// flush して閉じる。
  Future<void> close();

  /// 部分ファイルを削除する（ベストエフォート・throw しない）。
  ///
  /// キャンセル/失敗時に呼び出す。実装はまだ閉じていなければ flush を試行し、
  /// その後削除を試行する。いずれも失敗は握りつぶす。
  Future<void> deletePartial();
}

/// ダウンロード先ディレクトリの抽象。
///
/// プラットフォーム別の保存先（ローカルディレクトリ / Android SAF tree /
/// iOS security-scoped フォルダ）を共通化する。バッチダウンロードは 1 つの
/// [DownloadDestination] に複数ファイルを [open] する。
///
/// 契約:
/// - [exists] は同名ファイルの存在確認（上書き衝突の事前スキャン用）。
/// - [open] は保存名 [name] で書込ストリームを開く。`overwrite:true` は既存を
///   切り詰めて上書き、`false` は**新規作成**（保存先実装により採番される場合あり）。
/// - [dispose] は保存先のリソース解放。iOS スコープ解除用で、他プラットフォーム
///   （Android SAF・ローカル）は no-op。複数ファイルの書込後に 1 回だけ呼ぶ。
abstract class DownloadDestination {
  /// [name] のファイルが保存先に存在するか。
  Future<bool> exists(String name);

  /// [name] で書込ストリームを開く。
  ///
  /// - [overwrite]: `true` で既存ファイルを切り詰めて再利用、`false` で新規作成
  ///   （SAF は自動採番、ローカルは呼び出し側が [exists] で非存在を保証済みであること）。
  Future<DownloadSink> open(String name, {required bool overwrite});

  /// 保存先のリソースを解放する（iOS スコープ解除用。他は no-op）。
  Future<void> dispose();
}
