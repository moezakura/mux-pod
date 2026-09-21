import 'dart:convert';
import 'dart:typed_data';

// inventory: SHELL-PARSE-001
/// スキャナ抽出結果の意味解釈（受ける側）を担う純関数群。
///
/// 責務は「マーカー間バイト列の UTF8 デコード・CR 正規化・RC エコー抽出・
/// 前後改行の除去」のみ。マーカー文字列の構築（[ShellMarkerProtocol]）や
/// バイト走査（[ShellMarkerScanner]）は担当しない。状態を持たない。
class ShellOutputParser {
  /// マーカー間バイト列 [between] を出力文字列へ解釈する。
  ///
  /// [captureExitCode] が true のとき、末尾の RC エコー
  /// （`\x01###RC_<id>###:<code>\n`）を [rcMarker] で抽出し、出力から除去して
  /// 終了コードを返す。
  static ({String output, int? exitCode}) parse(
    Uint8List between, {
    required String rcMarker,
    required bool captureExitCode,
  }) {
    // マーカー間バイト列をUTF-8デコード（マルチバイト境界分割を防止）
    var result = utf8.decode(between, allowMalformed: true);

    // PTYの出力変換で\r\nや\rが使われる場合があるため正規化
    // 事実: macOS PTYではnewlines=0, CRs=19（\nが\rに変換されている）
    result = result.replaceAll(RegExp(r'\r\n?'), '\n');

    // execWithExitCode 用: 末尾の RC エコー（\x01###RC_<id>###:<code>\x01\n）を抽出する。
    // エコーは必ずコマンド出力の最後に付くため、最後の出現位置から終了コードを
    // 取り出して出力から除去する（コードは次の \x01 または改行まで）。
    int? exitCode;
    if (captureExitCode) {
      final rcIndex = result.lastIndexOf(rcMarker);
      if (rcIndex >= 0) {
        final codeText = result.substring(rcIndex + rcMarker.length);
        final terminator = codeText.indexOf('\x01');
        final codeEnd = terminator >= 0 ? terminator : codeText.indexOf('\n');
        final code = codeEnd >= 0 ? codeText.substring(0, codeEnd) : codeText;
        exitCode = int.tryParse(code.trim());
        // RC エコー行を除去（\x01 終端と直前の改行も含める）
        result = result.substring(0, rcIndex);
        if (result.endsWith('\n')) {
          result = result.substring(0, result.length - 1);
        }
      }
    }

    // 先頭と末尾の改行を削除
    if (result.startsWith('\n')) {
      result = result.substring(1);
    }
    if (result.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
    }

    return (output: result, exitCode: exitCode);
  }
}
