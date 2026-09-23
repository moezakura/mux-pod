/// キーイベントからエスケープシーケンス / tmux キー名を合成する純粋関数群
/// （P3-2）。
///
/// すべて static でインスタンス状態を持たない。修飾子状態は呼び出し側
/// （[.AnsiKeyInputEngine]）が引数で渡し、**消費**（`_getModifiedTmuxKey` の
/// リセット）はエンジン側で再現する。
class AnsiKeyComposer {
  /// 単一の ASCII 印字可能文字 (0x20-0x7E) かどうか
  static bool isAsciiPrintable(String s) {
    if (s.length != 1) return false;
    final c = s.codeUnitAt(0);
    return c >= 0x20 && c <= 0x7e;
  }

  /// event.character が非 ASCII（OS 合成文字）の場合に logicalKey から
  /// ASCII 文字を導出する。
  ///
  /// Flutter 3.44.9 の keyLabel は標準印字キーで
  /// `String.fromCharCode(keyId).toUpperCase()`（keyboard_key.g.dart:111-115,
  /// keyId < 2^32）。keyO=0x6f→'O' / comma=0x2c→',' / digit1=0x31→'1' が保証される。
  /// 例外（'Intl Yen' 等の複数文字名・空・非 ASCII ラベルキー'Ù' 等）は
  /// 導出不能として null を返し、呼び出し元は従来動作（character 使用）を維持する (R3)。
  ///
  /// [keyLabel] は `event.logicalKey.keyLabel`。[shiftPressed] は呼び出し側の
  /// Shift 状態（テスト注入可能）。英字 (A-Z) かつ Shift なしの場合のみ
  /// 小文字化する (R1: M-o と M-O を区別)。
  static String? deriveBaseChar(String keyLabel, {bool shiftPressed = false}) {
    if (!isAsciiPrintable(keyLabel)) {
      return null; // length==1 かつ ASCII 印字のみ
    }
    var code = keyLabel.codeUnitAt(0);
    // keyLabel は常に大文字。Shift なしの英字のみ小文字化する (R1: M-o と M-O を区別)
    if (!shiftPressed && code >= 0x41 && code <= 0x5a) {
      code += 0x20;
    }
    return String.fromCharCode(code);
  }

  /// 矢印キーのシーケンスを取得
  static String arrowSequence(
    String code, {
    required bool shiftPressed,
    required bool ctrlPressed,
    required bool altPressed,
  }) {
    if (shiftPressed) {
      return '\x1b[1;2$code';
    } else if (ctrlPressed) {
      return '\x1b[1;5$code';
    } else if (altPressed) {
      return '\x1b[1;3$code';
    }
    return '\x1b[$code';
  }

  /// 矢印キーのtmux形式キー名を取得
  static String arrowTmuxKey(
    String direction, {
    required bool shiftPressed,
    required bool ctrlPressed,
    required bool altPressed,
  }) {
    if (shiftPressed) {
      return 'S-$direction';
    } else if (ctrlPressed) {
      return 'C-$direction';
    } else if (altPressed) {
      return 'M-$direction';
    }
    return direction;
  }

  /// 修飾子付きtmuxキー名を取得（汎用: Home/End/PPage/NPage/DC等）。
  ///
  /// 戻り値の `name` に修飾子を前置したキー名を返す。旧実装の「修飾子フラグを
  /// 消費（リセット）する」セマンティクスは、返り値の `modifierUsed` を基に
  /// 呼び出し側（エンジン）が該当フラグを false にする（Consume 順を再現）。
  static ({String name, String modifierUsed}) modifiedTmuxKey(
    String baseKey, {
    required bool shiftPressed,
    required bool ctrlPressed,
    required bool altPressed,
  }) {
    if (shiftPressed) {
      return (name: 'S-$baseKey', modifierUsed: 'shift');
    } else if (ctrlPressed) {
      return (name: 'C-$baseKey', modifierUsed: 'ctrl');
    } else if (altPressed) {
      return (name: 'M-$baseKey', modifierUsed: 'alt');
    }
    return (name: baseKey, modifierUsed: '');
  }

  /// 修飾子付きCSIシーケンス: 最終文字型（Home: \x1b[H, End: \x1b[F）
  /// 修飾子あり: \x1b[1;{mod}{finalChar}
  static String finalCharSequence(
    String finalChar, {
    required bool shiftPressed,
    required bool ctrlPressed,
    required bool altPressed,
  }) {
    final mod = shiftPressed
        ? 2
        : ctrlPressed
        ? 5
        : altPressed
        ? 3
        : 0;
    if (mod == 0) return '\x1b[$finalChar';
    return '\x1b[1;$mod$finalChar';
  }

  /// 修飾子付きCSIシーケンス: パラメータ型（PageUp: \x1b[5~, Delete: \x1b[3~）
  /// 修飾子あり: \x1b[{param};{mod}~
  static String paramSequence(
    int param,
    String suffix, {
    required bool shiftPressed,
    required bool ctrlPressed,
    required bool altPressed,
  }) {
    final mod = shiftPressed
        ? 2
        : ctrlPressed
        ? 5
        : altPressed
        ? 3
        : 0;
    if (mod == 0) return '\x1b[$param$suffix';
    return '\x1b[$param;$mod$suffix';
  }

  /// F1-F4用シーケンス（SS3形式、修飾子ありならCSI形式に変換）
  /// F1=P, F2=Q, F3=R, F4=S
  /// 修飾子なし: \x1bO{code}, 修飾子あり: \x1b[1;{mod}{code}
  static String fKeySequence(
    String code, {
    required bool shiftPressed,
    required bool ctrlPressed,
    required bool altPressed,
  }) {
    final mod = shiftPressed
        ? 2
        : ctrlPressed
        ? 5
        : altPressed
        ? 3
        : 0;
    if (mod == 0) return '\x1bO$code';
    return '\x1b[1;$mod$code';
  }
}
