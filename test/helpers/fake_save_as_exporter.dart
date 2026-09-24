import 'package:flutter_muxpod/services/download/save_as_exporter.dart';

/// [SaveAsExporter] のテスト fake（providers / widgets 共通）。
///
/// - [result]（null は Save-As キャンセル）をそのまま返し、[error] を設定すると
///   `export()` が throw する。
/// - 呼び出し元ファイルパスを [calls] に記録する（tmp パスで呼ばれる検証用）。
class FakeSaveAsExporter implements SaveAsExporter {
  FakeSaveAsExporter({this.result, this.error});

  final String? result;
  final Object? error;
  final List<String> calls = [];

  @override
  Future<String?> export(String sourceFilePath) async {
    calls.add(sourceFilePath);
    if (error != null) throw error!;
    return result;
  }
}
