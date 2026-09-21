/// リサイズ結果（絶対 cols/rows）の不変値オブジェクト。
///
/// tmux / herdr のリサイズダイアログ共通の戻り値。UI 部品（プリセット等）とは
/// 分離してモデル単独の責務を持つ。
class ResizeResult {
  final int cols;
  final int rows;
  const ResizeResult({required this.cols, required this.rows});
}
