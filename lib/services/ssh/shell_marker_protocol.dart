import 'dart:math';

// inventory: SHELL-PROTO-001
/// マーカーの構築（送る側）を担う。
///
/// 責務は「コマンドを START/END/RC マーカーでラップした文字列の生成」のみ。
/// バイトストリームからのマーカー区間抽出（[ShellMarkerScanner]）や
/// 抽出結果の意味解釈（[ShellOutputParser]）は担当しない。
///
/// **nonce はインスタンスごとに生成する**（シングルトン・static 共有禁止）。
/// 静的な定数にすると、ユーザーの tmux ペイン内で動作するプログラムが
/// END マーカーを正確に出力し、キャプチャ出力を偽装・切り詰めできてしまう。
/// PersistentShell ごとに 1 インスタンスを生成し、セッションごとに予測不能な
/// nonce を発行することでこの偽装を防ぐ（SHELL-002）。
class ShellMarkerProtocol {
  // inventory: SHELL-002
  /// マーカーのコアテキスト（インスタンスごとにランダム生成する nonce）
  final String markerId = _generateMarkerId();

  // inventory: SHELL-003
  /// コマンド開始検知用マーカー（\x01プレフィックス/サフィックス付き）
  ///
  /// \x01（SOH制御文字）を含めることで、シェルのエコーバックテキスト内の
  /// リテラル文字列（`\x01`=4文字）と区別する。
  /// printfの実出力のみがバイト0x01を含むため、エコーバック内では一致しない。
  late final String startMarker = '\x01###START_$markerId###\x01';

  // inventory: SHELL-004
  /// コマンド終了検知用マーカー
  late final String endMarker = '\x01###END_$markerId###\x01';

  /// printf用のマーカー文字列（シェルコマンド内で使用）
  late final String printfStartMarker =
      r'\x01###START_'
      '$markerId'
      r'###\x01';
  late final String printfEndMarker =
      r'\x01###END_'
      '$markerId'
      r'###\x01';

  /// RC（終了コード）エコーのマーカー（printf用・文字列版）。
  ///
  /// `\x01###RC_<markerId>###:<code>\n` の形で出力される。マーカー内に
  /// ランダムな [markerId] を含めることで、コマンド出力に偶然現れる
  /// リテラル文字列との衝突を防ぐ（START/END マーカーと同じ方針）。
  late final String printfRcMarker =
      r'\x01###RC_'
      '$markerId'
      r'###:';

  /// RC エコーを出力から抽出するための文字列版マーカー。
  late final String rcMarker = '\x01###RC_$markerId###:';

  /// [command] を START/END マーカーでラップした送信文字列を構築する。
  ///
  /// [captureExitCode] が true のとき、コマンド直後に
  /// `; printf '\x01###RC_<markerId>###:%d\n' "$?"` を付与して終了コードを
  /// マーカー内に埋め込む（parser 側が出力から抽出する）。false のときは
  /// 従来の [exec] と同じラップ（RC エコーなし）を維持する。
  ///
  /// printfでマーカーを出力（\x01バイトを含む）
  /// echoではなくprintfを使用: シェルのエコーバック内ではリテラル'\x01'（4文字）が
  /// 表示されるが、printfの実出力はバイト0x01を含む。
  /// これによりエコーバック内のマーカーと実出力のマーカーを確実に区別できる。
  String buildCommand(String command, {required bool captureExitCode}) {
    final rcEcho = captureExitCode
        ? "; __muxpod_rc=\$?; printf '$printfRcMarker%d\\n' \"\$__muxpod_rc\""
        : '';
    return "printf '$printfStartMarker\\n'; $command$rcEcho;"
        " printf '$printfEndMarker\\n'\n";
  }

  // inventory: SHELL-007
  /// 予測不能なマーカーID（16進16文字 = 64bit）を生成する。
  ///
  /// Random.secureを使い、ユーザーのペイン内プログラムがマーカー文字列を
  /// 推測してキャプチャ出力を偽装することを防ぐ。
  static String _generateMarkerId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
