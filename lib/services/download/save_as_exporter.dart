import 'package:flutter_file_dialog/flutter_file_dialog.dart';

/// 「名前を付けて保存」ダイアログによるエクスポートの抽象。
///
/// 既に端末ローカルに保存済みのファイルを、ユーザーが選択する保存先（Android の
/// ACTION_CREATE_DOCUMENT / iOS の export モード）へコピーして保存する。
abstract class SaveAsExporter {
  /// [sourceFilePath] をユーザー選択先へコピーし、**保存先を示す表示用パス断片**を返す。
  ///
  /// - キャンセル時は `null` を返す。
  /// - 戻り値は **content URI の path 部の断片であって実パスではない**（Android の
  ///   `saveFile` は `destinationFileUri.path` を返す。例: DownloadsProvider では
  ///   `/document/msf%3A...`・ExternalStorage では
  ///   `/document/primary%3ADownload%2Fsample.txt` のような識別子）。ファイル名そのもの
  ///   でもないため、保存先の表示用途（SnackBar 等）でのみ使うこと。
  /// - 失敗（例外）はそのまま伝播する（呼び出し側でエラー報告する）。
  Future<String?> export(String sourceFilePath);
}

/// [flutter_file_dialog] による [SaveAsExporter] 実装。
class FfdSaveAsExporter implements SaveAsExporter {
  const FfdSaveAsExporter();

  @override
  Future<String?> export(String sourceFilePath) async {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: sourceFilePath),
    );
  }
}
