import 'dart:convert';

import '../ssh/ssh_client.dart';

/// Safe remote editing of AI agent config files (`settings.json`,
/// `config.toml`) over an SSH connection.
///
/// All parsing/serialization is pure Dart string processing (no new pub
/// dependencies). Remote writes are atomic: the new content goes to a
/// temporary file which is then `mv`-ed over the target, and the original
/// file is preserved once as `<path>.muxpod-bak` before the first
/// overwrite.
///
/// Shell-safety: file content travels base64-encoded (same pattern as
/// [TmuxCommands.loadBufferAndPaste]) so no user-controlled byte is ever
/// interpolated into a shell command. Paths passed to this service are
/// compile-time constants defined by the adapters, never raw user input;
/// they may contain `$HOME`, which the remote shell expands inside double
/// quotes.
class AgentConfigService {
  AgentConfigService._();

  /// Suffix of the one-time backup created before the first overwrite.
  static const String backupSuffix = '.muxpod-bak';

  /// Suffix of the temporary file used for atomic writes.
  static const String tempSuffix = '.muxpod-tmp';

  // ===== Remote file operations =====

  /// Reads a remote text file via `cat`. Returns null when the file does
  /// not exist or cannot be read.
  static Future<String?> readRemoteFile(SshClient ssh, String path) async {
    final result = await ssh.execWithExitCode('cat -- "$path"');
    if (result.exitCode != 0) return null;
    return result.stdout;
  }

  /// Atomically writes [content] to the remote file at [path].
  ///
  /// Sequence: create the parent directory, copy the current file to
  /// `<path>.muxpod-bak` (only if no backup exists yet), write the new
  /// content to `<path>.muxpod-tmp` via base64, then `mv` it over [path].
  ///
  /// Throws [StateError] when the remote command fails.
  static Future<void> writeRemoteFileAtomic(
    SshClient ssh,
    String path,
    String content,
  ) async {
    final dir = path.substring(0, path.lastIndexOf('/'));
    final backupPath = '$path$backupSuffix';
    final tempPath = '$path$tempSuffix';
    // base64 contains only [A-Za-z0-9+/=], so single-quoting is safe.
    final encoded = base64.encode(utf8.encode(content));
    final command = 'mkdir -p -- "$dir" && '
        '( [ -f "$backupPath" ] || [ ! -f "$path" ] || cp -- "$path" "$backupPath" ) && '
        "printf '%s' '$encoded' | base64 -d > \"$tempPath\" && "
        'mv -f -- "$tempPath" "$path"';
    final result = await ssh.execWithExitCode(command);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to write $path (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  // ===== TOML (simple top-level `key = "value"` lines) =====

  /// Returns the string value of a top-level [key] in TOML [content], or
  /// null when the key is absent.
  ///
  /// Only top-level keys are considered: the scan stops at the first
  /// `[table]` header so a key inside a table is never matched. Quoted
  /// values are unquoted; bare values are returned with trailing comments
  /// stripped.
  static String? tomlGetString(String content, String key) {
    final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*=\\s*(.*)\$');
    for (final line in content.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('[')) break; // top-level keys only
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      return _parseTomlValue(match[1]!.trim());
    }
    return null;
  }

  /// Sets a top-level string [key] to [value] in TOML [content].
  ///
  /// An existing top-level `key = ...` line is replaced in place; all
  /// unrelated lines (comments, tables, other keys) are preserved. When
  /// the key is missing, the line is inserted before the first `[table]`
  /// header so it stays top-level, or appended when the file has no
  /// tables.
  static String tomlSetString(String content, String key, String value) {
    // Control characters would break out of the single-line `key = "..."`
    // form and inject extra TOML keys into the user's real config file
    // (model entry is free text, and paste can carry newlines).
    if (value.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError.value(
        value,
        'value',
        'TOML basic string values must not contain newlines',
      );
    }
    final newLine = '$key = "${_escapeTomlBasicString(value)}"';
    final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*=');
    final lines = content.split('\n');
    var firstTableIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('[')) {
        firstTableIndex = i;
        break;
      }
      if (trimmed.startsWith('#')) continue;
      if (pattern.hasMatch(lines[i])) {
        lines[i] = newLine;
        return lines.join('\n');
      }
    }
    if (firstTableIndex >= 0) {
      lines.insert(firstTableIndex, newLine);
      return lines.join('\n');
    }
    // No table anywhere: append at the end, keeping exactly one trailing
    // newline.
    final trimmedEnd = content.trimRight();
    if (trimmedEnd.isEmpty) return '$newLine\n';
    return '$trimmedEnd\n$newLine\n';
  }

  /// Parses a TOML value literal into a plain string.
  ///
  /// Handles double-quoted basic strings (with `\"` and `\\` unescaped),
  /// single-quoted literal strings, and bare values (numbers/booleans,
  /// returned as their literal text).
  static String? _parseTomlValue(String raw) {
    if (raw.startsWith('"')) {
      final buffer = StringBuffer();
      var i = 1;
      while (i < raw.length) {
        final ch = raw[i];
        if (ch == r'\') {
          if (i + 1 >= raw.length) return null;
          final escaped = raw[i + 1];
          if (escaped != '"' && escaped != r'\') return null;
          buffer.write(escaped);
          i += 2;
          continue;
        }
        if (ch == '"') return buffer.toString();
        buffer.write(ch);
        i++;
      }
      return null;
    }
    if (raw.startsWith("'")) {
      final end = raw.indexOf("'", 1);
      return end > 0 ? raw.substring(1, end) : null;
    }
    final commentIndex = raw.indexOf('#');
    final value = (commentIndex >= 0 ? raw.substring(0, commentIndex) : raw)
        .trim();
    return value.isEmpty ? null : value;
  }

  /// Escapes a value for a TOML basic string (`"..."`).
  static String _escapeTomlBasicString(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  // ===== JSON (dotted keys) =====

  /// Returns the value at [dottedKey] (e.g. `permissions.defaultMode`) in
  /// JSON [content], or null when any segment is missing.
  ///
  /// Malformed JSON (hand-edited config, truncated write) degrades to
  /// null — "value unknown" — instead of throwing, so the Remote UI keeps
  /// working when a settings file is temporarily broken.
  static Object? jsonGetDotted(String content, String dottedKey) {
    if (content.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return null;
    }
    Object? current = decoded;
    for (final key in dottedKey.split('.')) {
      if (current is Map<String, Object?> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Sets the value at [dottedKey] in JSON [content] and returns the
  /// updated document encoded with a 2-space indent and a trailing
  /// newline.
  ///
  /// Intermediate objects are created as needed. Empty [content] starts
  /// from an empty object. Throws [FormatException] when [content] is not
  /// a JSON object or a path segment collides with a non-object value.
  static String jsonSetDotted(String content, String dottedKey, Object? value) {
    final Map<String, Object?> root;
    if (content.trim().isEmpty) {
      root = <String, Object?>{};
    } else {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected a JSON object at the top level');
      }
      root = decoded;
    }
    final keys = dottedKey.split('.');
    var current = root;
    for (var i = 0; i < keys.length - 1; i++) {
      final next = current[keys[i]];
      if (next == null) {
        final created = <String, Object?>{};
        current[keys[i]] = created;
        current = created;
      } else if (next is Map<String, Object?>) {
        current = next;
      } else {
        throw FormatException(
          'Cannot set "$dottedKey": "${keys[i]}" is not an object',
        );
      }
    }
    current[keys.last] = value;
    return '${const JsonEncoder.withIndent('  ').convert(root)}\n';
  }
}
