/// パターンマッチオプション
class MatchOptions {
  /// 大文字小文字を区別する
  final bool caseSensitive;

  /// 単語全体にマッチ
  final bool wholeWord;

  /// マルチライン対応
  final bool multiLine;

  /// ドットが改行にもマッチ
  final bool dotAll;

  const MatchOptions({
    this.caseSensitive = false,
    this.wholeWord = false,
    this.multiLine = true,
    this.dotAll = false,
  });

  static const MatchOptions defaults = MatchOptions();
}

/// マッチ結果
class MatchResult {
  /// マッチした文字列
  final String matchedText;

  /// マッチした位置（開始）
  final int start;

  /// マッチした位置（終了）
  final int end;

  /// キャプチャグループ（正規表現の場合）
  final List<String?> groups;

  /// マッチした行番号（0始まり）
  final int lineNumber;

  /// マッチした行の内容
  final String lineContent;

  /// 前後のコンテキスト行
  final List<String> contextBefore;
  final List<String> contextAfter;

  const MatchResult({
    required this.matchedText,
    required this.start,
    required this.end,
    this.groups = const [],
    this.lineNumber = 0,
    this.lineContent = '',
    this.contextBefore = const [],
    this.contextAfter = const [],
  });

  @override
  String toString() => 'MatchResult(text: "$matchedText", line: $lineNumber)';
}

/// パターンマッチャー
///
/// 文字列パターンまたは正規表現によるマッチングを提供する。
class PatternMatcher {
  /// パターンにマッチするかチェック
  ///
  /// [pattern] マッチパターン
  /// [text] 検索対象テキスト
  /// [isRegex] 正規表現として処理するか
  /// [options] マッチオプション
  ///
  /// 戻り値: マッチした場合はマッチした文字列、しない場合はnull
  static String? match(
    String pattern,
    String text,
    bool isRegex, {
    MatchOptions options = MatchOptions.defaults,
  }) {
    final result = matchWithDetails(pattern, text, isRegex, options: options);
    return result?.matchedText;
  }

  /// 詳細なマッチ結果を取得
  static MatchResult? matchWithDetails(
    String pattern,
    String text,
    bool isRegex, {
    MatchOptions options = MatchOptions.defaults,
    int contextLines = 0,
  }) {
    if (pattern.isEmpty || text.isEmpty) return null;

    try {
      final regex = _buildRegex(pattern, isRegex, options);
      final regexMatch = regex.firstMatch(text);

      if (regexMatch == null) return null;

      // 行情報を計算
      final lines = text.split('\n');
      int lineNumber = 0;
      int currentPos = 0;

      for (int i = 0; i < lines.length; i++) {
        final lineEnd = currentPos + lines[i].length;
        if (regexMatch.start >= currentPos && regexMatch.start <= lineEnd) {
          lineNumber = i;
          break;
        }
        currentPos = lineEnd + 1; // +1 for newline
      }

      // コンテキスト行を収集
      final contextBefore = <String>[];
      final contextAfter = <String>[];

      if (contextLines > 0) {
        for (int i = lineNumber - contextLines; i < lineNumber; i++) {
          if (i >= 0 && i < lines.length) {
            contextBefore.add(lines[i]);
          }
        }
        for (int i = lineNumber + 1; i <= lineNumber + contextLines; i++) {
          if (i >= 0 && i < lines.length) {
            contextAfter.add(lines[i]);
          }
        }
      }

      // キャプチャグループを取得
      final groups = <String?>[];
      for (int i = 0; i <= regexMatch.groupCount; i++) {
        groups.add(regexMatch.group(i));
      }

      return MatchResult(
        matchedText: regexMatch.group(0) ?? '',
        start: regexMatch.start,
        end: regexMatch.end,
        groups: groups,
        lineNumber: lineNumber,
        lineContent: lineNumber < lines.length ? lines[lineNumber] : '',
        contextBefore: contextBefore,
        contextAfter: contextAfter,
      );
    } catch (e) {
      // 不正なパターンの場合はnull
      return null;
    }
  }

  /// すべてのマッチを取得
  static List<MatchResult> matchAllWithDetails(
    String pattern,
    String text,
    bool isRegex, {
    MatchOptions options = MatchOptions.defaults,
    int contextLines = 0,
    int maxMatches = 100,
  }) {
    if (pattern.isEmpty || text.isEmpty) return [];

    try {
      final regex = _buildRegex(pattern, isRegex, options);
      final matches = regex.allMatches(text);
      final results = <MatchResult>[];
      final lines = text.split('\n');

      // 各行の開始位置を事前計算
      final lineStarts = <int>[0];
      for (int i = 0; i < lines.length - 1; i++) {
        lineStarts.add(lineStarts.last + lines[i].length + 1);
      }

      for (final regexMatch in matches) {
        if (results.length >= maxMatches) break;

        // バイナリサーチで行番号を特定
        int lineNumber = _findLineNumber(lineStarts, regexMatch.start);

        // コンテキスト行を収集
        final contextBefore = <String>[];
        final contextAfter = <String>[];

        if (contextLines > 0) {
          for (int i = lineNumber - contextLines; i < lineNumber; i++) {
            if (i >= 0 && i < lines.length) {
              contextBefore.add(lines[i]);
            }
          }
          for (int i = lineNumber + 1; i <= lineNumber + contextLines; i++) {
            if (i >= 0 && i < lines.length) {
              contextAfter.add(lines[i]);
            }
          }
        }

        // キャプチャグループを取得
        final groups = <String?>[];
        for (int i = 0; i <= regexMatch.groupCount; i++) {
          groups.add(regexMatch.group(i));
        }

        results.add(MatchResult(
          matchedText: regexMatch.group(0) ?? '',
          start: regexMatch.start,
          end: regexMatch.end,
          groups: groups,
          lineNumber: lineNumber,
          lineContent: lineNumber < lines.length ? lines[lineNumber] : '',
          contextBefore: contextBefore,
          contextAfter: contextAfter,
        ));
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// 複数のパターンにマッチするかチェック
  static List<String> matchAll(
    List<String> patterns,
    String text,
    bool isRegex, {
    MatchOptions options = MatchOptions.defaults,
  }) {
    final matches = <String>[];
    for (final pattern in patterns) {
      final result = match(pattern, text, isRegex, options: options);
      if (result != null) {
        matches.add(result);
      }
    }
    return matches;
  }

  /// パターンが有効かテスト
  static bool isValidPattern(String pattern, bool isRegex) {
    if (pattern.isEmpty) return false;

    if (!isRegex) return true;

    try {
      RegExp(pattern);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// パターンのエラーメッセージを取得
  static String? getPatternError(String pattern, bool isRegex) {
    if (pattern.isEmpty) return 'パターンが空です';

    if (!isRegex) return null;

    try {
      RegExp(pattern);
      return null;
    } on FormatException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// 正規表現をビルド
  static RegExp _buildRegex(
    String pattern,
    bool isRegex,
    MatchOptions options,
  ) {
    String regexPattern = pattern;

    if (!isRegex) {
      // 特殊文字をエスケープ
      regexPattern = RegExp.escape(pattern);
    }

    if (options.wholeWord) {
      regexPattern = r'\b' + regexPattern + r'\b';
    }

    return RegExp(
      regexPattern,
      caseSensitive: options.caseSensitive,
      multiLine: options.multiLine,
      dotAll: options.dotAll,
    );
  }

  /// 行番号をバイナリサーチで特定
  static int _findLineNumber(List<int> lineStarts, int position) {
    int low = 0;
    int high = lineStarts.length - 1;

    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (lineStarts[mid] <= position) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return low;
  }

  /// テキストをハイライト（HTMLタグ付与）
  static String highlightMatches(
    String pattern,
    String text,
    bool isRegex, {
    MatchOptions options = MatchOptions.defaults,
    String startTag = '<mark>',
    String endTag = '</mark>',
  }) {
    if (pattern.isEmpty || text.isEmpty) return text;

    try {
      final regex = _buildRegex(pattern, isRegex, options);
      return text.replaceAllMapped(regex, (match) {
        return '$startTag${match.group(0)}$endTag';
      });
    } catch (e) {
      return text;
    }
  }

  /// ANSI エスケープコードを除去してからマッチ
  static MatchResult? matchWithoutAnsi(
    String pattern,
    String text,
    bool isRegex, {
    MatchOptions options = MatchOptions.defaults,
    int contextLines = 0,
  }) {
    final plainText = stripAnsiCodes(text);
    return matchWithDetails(
      pattern,
      plainText,
      isRegex,
      options: options,
      contextLines: contextLines,
    );
  }

  /// ANSIエスケープコードを除去
  static String stripAnsiCodes(String text) {
    // ANSI エスケープシーケンスのパターン
    final ansiPattern = RegExp(
      r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])',
    );
    return text.replaceAll(ansiPattern, '');
  }
}

/// パターンビルダー（よく使うパターンのファクトリ）
class PatternBuilder {
  PatternBuilder._();

  /// エラーパターン
  static String error() => r'error|fail|exception|fatal';

  /// 警告パターン
  static String warning() => r'warn|caution|alert';

  /// 成功パターン
  static String success() => r'success|complete|done|pass';

  /// ビルド完了パターン
  static String buildComplete() => r'build\s+(successful|finished|complete)';

  /// テスト完了パターン
  static String testComplete() => r'(\d+)\s+tests?\s+(passed|failed)';

  /// SSHプロンプトパターン
  static String shellPrompt() => r'[\$#>]\s*$';

  /// メンション（@username）パターン
  static String mention(String username) {
    return '@${RegExp.escape(username)}';
  }

  /// 時刻パターン（HH:MM:SS）
  static String timestamp() => r'\d{2}:\d{2}:\d{2}';

  /// IPアドレスパターン
  static String ipAddress() =>
      r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b';

  /// URLパターン
  static String url() =>
      r'https?://[^\s<>"]+|www\.[^\s<>"]+';

  /// ファイルパスパターン（Unix）
  static String unixPath() => r'/[\w./\-]+';

  /// 数値パターン（整数または小数）
  static String number() => r'-?\d+(?:\.\d+)?';

  /// コンテナID（Docker）
  static String dockerContainerId() => r'[a-f0-9]{12}|[a-f0-9]{64}';

  /// Git コミットハッシュ
  static String gitCommitHash() => r'[a-f0-9]{7,40}';
}
