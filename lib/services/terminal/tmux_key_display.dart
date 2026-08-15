/// キーオーバーレイのカテゴリ
enum KeyOverlayCategory {
  /// 修飾キー組み合わせ: Ctrl+x, Alt+x, Shift+x
  modifier,

  /// 単独特殊キー: ESC, TAB, ENTER, S-Enter, BSpace, BTab
  special,

  /// 矢印キー: Up, Down, Left, Right
  arrow,

  /// ショートカットキー: /, -, 1, 2, 3, 4
  shortcut,
}

/// キーオーバーレイの表示位置
enum KeyOverlayPosition {
  /// キーボード（SpecialKeysBar）の真上
  aboveKeyboard,

  /// ターミナル領域の中央
  center,

  /// ブレッドクラムヘッダーの直下
  belowHeader,
}

/// tmux send-keys 形式のキー名を人間可読表示に変換するユーティリティ
class TmuxKeyDisplay {
  static const _specialKeys = {
    'Escape',
    'Tab',
    'Enter',
    'BSpace',
    'BTab',
    'S-Enter',
  };

  static const _arrowKeys = {'Up', 'Down', 'Left', 'Right'};

  static const _shortcutKeys = {'/', '-', '1', '2', '3', '4'};

  static const _displayMap = {
    'Escape': 'ESC',
    'Tab': 'TAB',
    'Enter': 'ENTER',
    'S-Enter': 'Shift+Enter',
    'BSpace': 'BS',
    'BTab': 'Shift+TAB',
    'Up': '↑',
    'Down': '↓',
    'Left': '←',
    'Right': '→',
  };

  static final _modifierPattern = RegExp(r'^([CMS]-)+');

  /// tmuxキー名からオーバーレイカテゴリを判定
  ///
  /// 該当しない場合は null を返す
  static KeyOverlayCategory? categoryOf(String tmuxKey) {
    if (_specialKeys.contains(tmuxKey)) return KeyOverlayCategory.special;
    if (_arrowKeys.contains(tmuxKey)) return KeyOverlayCategory.arrow;
    if (_shortcutKeys.contains(tmuxKey)) return KeyOverlayCategory.shortcut;
    if (_modifierPattern.hasMatch(tmuxKey)) return KeyOverlayCategory.modifier;
    return null;
  }

  /// リテラルキーがショートカットキーに該当するか判定
  static bool isShortcutKey(String key) => _shortcutKeys.contains(key);

  /// tmux形式のキー名を人間可読テキストに変換
  static String displayText(String tmuxKey) {
    // 固定マッピング
    final mapped = _displayMap[tmuxKey];
    if (mapped != null) return mapped;

    // 修飾キーパターン: C-c → Ctrl+C, M-x → Alt+X, S-a → Shift+A
    final match = _modifierPattern.firstMatch(tmuxKey);
    if (match != null) {
      final prefix = match.group(0)!;
      final baseKey = tmuxKey.substring(prefix.length);
      final parts = <String>[];
      if (prefix.contains('C-')) parts.add('Ctrl');
      if (prefix.contains('M-')) parts.add('Alt');
      if (prefix.contains('S-')) parts.add('Shift');
      final displayBase = _displayMap[baseKey] ?? baseKey.toUpperCase();
      parts.add(displayBase);
      return parts.join('+');
    }

    // そのまま返す（/, -, 1-4 等のリテラルキー）
    return tmuxKey;
  }
}
