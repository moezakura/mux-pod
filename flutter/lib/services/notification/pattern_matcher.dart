import '../../models/notification_rule.dart';

/// パターンマッチング結果
class PatternMatchResult {
  /// マッチしたか
  final bool matched;

  /// マッチした部分のテキスト
  final String? matchedText;

  /// マッチした開始位置
  final int? startIndex;

  /// マッチした終了位置
  final int? endIndex;

  const PatternMatchResult({
    required this.matched,
    this.matchedText,
    this.startIndex,
    this.endIndex,
  });

  /// マッチなし
  static const PatternMatchResult noMatch = PatternMatchResult(matched: false);

  /// マッチ結果を作成
  factory PatternMatchResult.match({
    required String matchedText,
    required int startIndex,
    required int endIndex,
  }) {
    return PatternMatchResult(
      matched: true,
      matchedText: matchedText,
      startIndex: startIndex,
      endIndex: endIndex,
    );
  }
}

/// パターンマッチングサービス
///
/// テキストに対してNotificationConditionのパターンをマッチングする。
class PatternMatcher {
  /// コンパイル済みの正規表現キャッシュ
  final Map<String, RegExp> _regexCache = {};

  /// 単一の条件をテキストにマッチング
  PatternMatchResult matchCondition(
    NotificationCondition condition,
    String text,
  ) {
    final pattern = condition.pattern;
    final caseSensitive = condition.caseSensitive;

    PatternMatchResult result;

    switch (condition.patternType) {
      case PatternType.text:
        result = _matchText(pattern, text, caseSensitive);
      case PatternType.regex:
        result = _matchRegex(pattern, text, caseSensitive);
      case PatternType.wildcard:
        result = _matchWildcard(pattern, text, caseSensitive);
    }

    // 否定条件の場合は結果を反転
    if (condition.negate) {
      if (result.matched) {
        return PatternMatchResult.noMatch;
      } else {
        // 否定でマッチした場合、マッチしたテキストは元のテキスト全体
        return PatternMatchResult.match(
          matchedText: text,
          startIndex: 0,
          endIndex: text.length,
        );
      }
    }

    return result;
  }

  /// 複数条件をテキストにマッチング（AND条件）
  PatternMatchResult matchConditions(
    List<NotificationCondition> conditions,
    String text,
  ) {
    if (conditions.isEmpty) {
      return PatternMatchResult.noMatch;
    }

    String? firstMatchedText;
    int? firstStartIndex;
    int? firstEndIndex;

    for (final condition in conditions) {
      final result = matchCondition(condition, text);
      if (!result.matched) {
        return PatternMatchResult.noMatch;
      }

      // 最初のマッチを記録
      if (firstMatchedText == null && result.matchedText != null) {
        firstMatchedText = result.matchedText;
        firstStartIndex = result.startIndex;
        firstEndIndex = result.endIndex;
      }
    }

    return PatternMatchResult.match(
      matchedText: firstMatchedText ?? text,
      startIndex: firstStartIndex ?? 0,
      endIndex: firstEndIndex ?? text.length,
    );
  }

  /// ルール全体をテキストにマッチング
  PatternMatchResult matchRule(NotificationRule rule, String text) {
    if (!rule.enabled) {
      return PatternMatchResult.noMatch;
    }

    return matchConditions(rule.conditions, text);
  }

  /// テキスト完全一致/部分一致
  PatternMatchResult _matchText(
    String pattern,
    String text,
    bool caseSensitive,
  ) {
    final searchPattern = caseSensitive ? pattern : pattern.toLowerCase();
    final searchText = caseSensitive ? text : text.toLowerCase();

    final index = searchText.indexOf(searchPattern);
    if (index == -1) {
      return PatternMatchResult.noMatch;
    }

    return PatternMatchResult.match(
      matchedText: text.substring(index, index + pattern.length),
      startIndex: index,
      endIndex: index + pattern.length,
    );
  }

  /// 正規表現マッチング
  PatternMatchResult _matchRegex(
    String pattern,
    String text,
    bool caseSensitive,
  ) {
    try {
      final cacheKey = '$pattern:$caseSensitive';
      final regex = _regexCache.putIfAbsent(
        cacheKey,
        () => RegExp(pattern, caseSensitive: caseSensitive),
      );

      final match = regex.firstMatch(text);
      if (match == null) {
        return PatternMatchResult.noMatch;
      }

      return PatternMatchResult.match(
        matchedText: match.group(0) ?? '',
        startIndex: match.start,
        endIndex: match.end,
      );
    } catch (e) {
      // 無効な正規表現
      return PatternMatchResult.noMatch;
    }
  }

  /// ワイルドカードマッチング（*, ?）
  PatternMatchResult _matchWildcard(
    String pattern,
    String text,
    bool caseSensitive,
  ) {
    // ワイルドカードを正規表現に変換
    final regexPattern = _wildcardToRegex(pattern);
    return _matchRegex(regexPattern, text, caseSensitive);
  }

  /// ワイルドカードパターンを正規表現に変換
  String _wildcardToRegex(String wildcard) {
    final buffer = StringBuffer();

    for (var i = 0; i < wildcard.length; i++) {
      final char = wildcard[i];
      switch (char) {
        case '*':
          buffer.write('.*');
        case '?':
          buffer.write('.');
        case '.':
        case '^':
        case r'$':
        case '+':
        case '{':
        case '}':
        case '[':
        case ']':
        case '|':
        case '(':
        case ')':
        case r'\':
          buffer.write(r'\');
          buffer.write(char);
        default:
          buffer.write(char);
      }
    }

    return buffer.toString();
  }

  /// キャッシュをクリア
  void clearCache() {
    _regexCache.clear();
  }

  /// パターンが有効かどうかを検証
  bool validatePattern(String pattern, PatternType type) {
    switch (type) {
      case PatternType.text:
        return pattern.isNotEmpty;
      case PatternType.regex:
        try {
          RegExp(pattern);
          return true;
        } catch (e) {
          return false;
        }
      case PatternType.wildcard:
        return pattern.isNotEmpty;
    }
  }

  /// パターンの説明を取得
  String describePattern(NotificationCondition condition) {
    final typeStr = switch (condition.patternType) {
      PatternType.text => 'contains',
      PatternType.regex => 'matches regex',
      PatternType.wildcard => 'matches pattern',
    };

    final caseStr = condition.caseSensitive ? '(case sensitive)' : '';
    final negateStr = condition.negate ? 'NOT ' : '';

    return '$negateStr$typeStr "${condition.pattern}" $caseStr'.trim();
  }
}
