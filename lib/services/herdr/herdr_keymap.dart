// inventory: HERDR-KEYMAP-000
/// tmux キー名 → herdr 送信経路の変換表（T0 実測ベース・Q-07）。
///
/// herdr 0.7.5 の `send-keys` は F キー・基本キー・矢印・C-c の最小語彙のみ
/// （T0 実測 1-a: 21 種）。Home/End/PgUp/PgDn/Delete/Insert・S-/C-/M- 修飾
/// キーは全て `invalid_key` で拒否されるため、**拒否キーは `send-text` で
/// エスケープシーケンス / 制御文字を送る**（`send-text` はバイナリ素通し・
/// G4 実測）。これにより「送信できないキー」は存在しない（Q-07）。
///
/// 送信経路の 3 分類:
/// 1. **`send-keys` 受理キー**（F1-F12 / Enter / Tab / Space / Backspace /
///    BS / Escape / 矢印 / C-c）→ [HerdrKeyRoute.sendKeys]
/// 2. **`send-keys` 拒否キー**（Home/End/PgUp/PgDn/Delete/Insert・修飾キー）
///    → [HerdrKeyRoute.sendTextEscape]（xterm エスケープシーケンス）
/// 3. **制御文字**（`C-<letter>`・C-@ 等）→ [HerdrKeyRoute.sendTextControl]
library;

import '../backend/domain/pane_writer.dart';

// inventory: HERDR-KEYMAP-001
/// tmux キー名を herdr 送信経路へ変換する O(1) テーブル + 修飾キー合成。
class PaneKeyMap {
  const PaneKeyMap._();

  /// `send-keys` で受理されるキー名（T0 実測 1-a: 21 種 + 小文字エイリアス）。
  ///
  /// `BSpace` は tmux 側のキー名で、herdr の受理名 `Backspace` に正規化して
  /// から送る（mapSpecialKey 内で変換）。
  static const Set<String> _sendKeysAccepted = {
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'Enter',
    'Tab',
    'Space',
    'Backspace',
    'BS',
    'BSpace',
    'Escape',
    'Up',
    'Down',
    'Left',
    'Right',
    'C-c',
    'c-c',
  };

  /// 無修飾の拒否キー → send-text エスケープシーケンス（T0 実測②）。
  static const Map<String, String> _escapeSequences = {
    'Home': '\x1b[H',
    'End': '\x1b[F',
    'PPage': '\x1b[5~',
    'NPage': '\x1b[6~',
    'DC': '\x1b[3~',
    'Insert': '\x1b[2~',
    'BTab': '\x1b[Z',
  };

  /// 修飾キーの xterm CSI パラメータ番号（S=2 / M=3 / C=5 / 合成は加算対応）。
  static const Map<String, int> _modifierCodes = {
    'S': 2,
    'M': 3,
    'S-M': 4,
    'C': 5,
    'S-C': 6,
    'C-M': 7,
    'S-C-M': 8,
  };

  /// 矢印キーの CSI 最終文字。
  static const Map<String, String> _arrowFinal = {
    'Up': 'A',
    'Down': 'B',
    'Right': 'C',
    'Left': 'D',
  };

  /// 編集系キーの CSI パラメータ。
  static const Map<String, int> _navParams = {
    'PPage': 5,
    'NPage': 6,
    'DC': 3,
    'Insert': 2,
  };

  /// F1-F4 の SS3/CSI 最終文字。
  static const Map<String, String> _functionLetters = {
    'F1': 'P',
    'F2': 'Q',
    'F3': 'R',
    'F4': 'S',
  };

  /// F5-F12 の CSI パラメータ。
  static const Map<String, int> _functionParams = {
    'F5': 15,
    'F6': 17,
    'F7': 18,
    'F8': 19,
    'F9': 20,
    'F10': 21,
    'F11': 23,
    'F12': 24,
  };

  /// C-<特殊文字> の制御バイト（T0 実測③: C-d=0x04 / C-x=0x18 等と同系）。
  static const Map<String, int> _specialControlBytes = {
    '@': 0x00,
    'Space': 0x00, // C-Space = NUL = C-@
    '[': 0x1b,
    r'\': 0x1c,
    ']': 0x1d,
    '^': 0x1e,
    '_': 0x1f,
    '?': 0x7f,
  };

  /// 拒否キーの代替スペル（T0 実測 1-b: `PgUp PgDn Prior Next Del Ins` 等も
  /// 全て拒否される）をアプリの tmux 名へ正規化する。
  static const Map<String, String> _aliasBase = {
    'PageUp': 'PPage',
    'PageDown': 'NPage',
    'PgUp': 'PPage',
    'PgDn': 'NPage',
    'Prior': 'PPage',
    'Next': 'NPage',
    'Delete': 'DC',
    'Del': 'DC',
    'Ins': 'Insert',
  };

  // inventory: HERDR-KEYMAP-002
  /// tmux キー名を送信経路へ変換する。
  ///
  /// **全キーで送信経路が返る**（「送信できないキー」なし・Q-07）。未知の
  /// キー名はベストエフォートで `send-keys` に流し、万一 `invalid_key` が
  /// 返った場合のみ UI が防御的に通知する（R9）。
  static HerdrKeyRoute mapSpecialKey(String tmuxKey) {
    // ① 受理キー → send-keys（BSpace は herdr の受理名 Backspace へ正規化）。
    if (_sendKeysAccepted.contains(tmuxKey)) {
      final keyName = tmuxKey == 'BSpace' ? 'Backspace' : tmuxKey;
      return HerdrKeyRoute.sendKeys(keyName);
    }

    // 修飾子を分離（アプリは S → C → M の順で生成する）。
    final modMatch = RegExp(r'^(S-)?(C-)?(M-)?(.*)$').firstMatch(tmuxKey);
    final s = modMatch!.group(1) != null;
    final c = modMatch.group(2) != null;
    final m = modMatch.group(3) != null;
    final rawBase = modMatch.group(4)!;
    final base = _aliasBase[rawBase] ?? rawBase;

    // ③ 制御文字: C-<letter>（C-c は①で処理済みのためここには来ない）。
    if (c && !m && !s && _isLetter(base)) {
      final byte = base.toLowerCase().codeUnitAt(0) & 0x1f;
      return HerdrKeyRoute.sendTextControl(byte);
    }

    // ③ 制御文字: C-@ / C-Space / C-[ / C-\ / C-] / C-^ / C-_ / C-?。
    if (c && !m && !s) {
      final special = _specialControlBytes[base];
      if (special != null) {
        return HerdrKeyRoute.sendTextControl(special);
      }
    }

    // ② 修飾キー → send-text エスケープ（xterm `;mod` 合成）。
    if (s || c || m) {
      return HerdrKeyRoute.sendTextEscape(_modifiedSequence(base, s, c, m));
    }

    // ② 無修飾の拒否キー → send-text エスケープ。
    final escape = _escapeSequences[base];
    if (escape != null) {
      return HerdrKeyRoute.sendTextEscape(escape);
    }

    // 未知キーのベストエフォート（防御的 invalid_key 経路・通常は到達しない）。
    return HerdrKeyRoute.sendKeys(tmuxKey);
  }

  /// 修飾付きキーの xterm エスケープシーケンスを合成する。
  static String _modifiedSequence(String base, bool s, bool c, bool m) {
    final mod = _modifierCodes[_modifierKey(s, c, m)] ?? 1;

    // 矢印: `\x1b[1;<mod>A` 等。
    final arrow = _arrowFinal[base];
    if (arrow != null) {
      return '\x1b[1;$mod$arrow';
    }

    // Home / End。
    if (base == 'Home') {
      return '\x1b[1;$mod'
          'H';
    }
    if (base == 'End') {
      return '\x1b[1;$mod'
          'F';
    }

    // PgUp / PgDn / Delete / Insert: `\x1b[<param>;<mod>~`。
    final navParam = _navParams[base];
    if (navParam != null) {
      return '\x1b[$navParam;$mod~';
    }

    // ファンクションキー。
    if (base.startsWith('F')) {
      final letter = _functionLetters[base];
      if (letter != null) return '\x1b[1;$mod$letter';
      final param = _functionParams[base];
      if (param != null) return '\x1b[$param;$mod~';
    }

    // S-Tab は CSI Z（後方タブ・広く解釈される形式）。
    if (base == 'Tab' && s && !c && !m) {
      return '\x1b[Z';
    }

    // Enter / Tab / Space / Backspace: xterm `\x1b[27;<mod>;<char>~`。
    final xtermParam = {
      'Enter': 13,
      'Tab': 9,
      'Space': 32,
      'Backspace': 8,
      'BSpace': 8,
      'BS': 8,
    }[base];
    if (xtermParam != null) {
      return '\x1b[27;$mod;$xtermParam~';
    }

    // 文字キー: S- は大文字化 / C- は制御文字化 / M- は ESC 前置。
    if (base.length == 1) {
      var ch = base;
      if (s) ch = ch.toUpperCase();
      if (c) ch = String.fromCharCode(ch.codeUnitAt(0) & 0x1f);
      return m ? '\x1b$ch' : ch;
    }

    // 未知ベースのベストエフォート（通常は到達しない）。
    return _escapeSequences[base] ?? '\x1b[$base';
  }

  /// 修飾子の合成キー（"S-C-M" 等）。
  static String _modifierKey(bool s, bool c, bool m) {
    final parts = <String>[];
    if (s) parts.add('S');
    if (c) parts.add('C');
    if (m) parts.add('M');
    return parts.join('-');
  }

  static bool _isLetter(String value) => RegExp(r'^[A-Za-z]$').hasMatch(value);
}
