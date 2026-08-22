import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/custom_keys/custom_key_button.dart';

/// State of the custom key buttons and their row layouts.
class CustomKeysState {
  const CustomKeysState({required this.buttons, required this.rows});

  final List<CustomKeyButton> buttons;

  /// Token rows, top to bottom. Length 0..[CustomKeyRows.maxRows].
  final List<List<String>> rows;

  CustomKeyButton? buttonById(String id) {
    for (final b in buttons) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Buttons no row references.
  List<CustomKeyButton> unplacedButtons() {
    final placed = _placedTokens();
    return buttons
        .where((b) => !placed.contains('ck:${b.id.substring(3)}'))
        .toList();
  }

  /// Tokens no row holds, in canonical order: [CustomKeyRows.allLayoutTokens]
  /// first, then custom `ck:` tokens in [buttons] order.
  List<String> unusedTokens() {
    final placed = _placedTokens();
    final unused = <String>[
      for (final token in CustomKeyRows.allLayoutTokens)
        if (!placed.contains(token)) token,
    ];
    for (final b in buttons) {
      final token = 'ck:${b.id.substring(3)}';
      if (!placed.contains(token)) unused.add(token);
    }
    return unused;
  }

  Set<String> _placedTokens() => {for (final row in rows) ...row};
}

/// Manages custom key buttons and their row layouts, persisting to shared_preferences.
class CustomKeysNotifier extends Notifier<CustomKeysState> {
  static const String buttonsKey = 'custom_key_buttons_v1';

  /// 行レイアウト全体（`List<List<String>>` の JSON）。
  static const String rowsKey = 'custom_key_rows_v1';

  /// 旧形式（行が3本固定だった時代）のキー。移行時にのみ読み、移行後は削除する。
  static const String legacyRow0Key = 'custom_key_row0_v1';
  static const String legacyRow1Key = 'custom_key_row1_v1';
  static const String legacyRow2Key = 'custom_key_row2_v1';

  static const String shelfMigrationKey = 'custom_keys_shelf_v1';

  @override
  CustomKeysState build() {
    _load();
    return const CustomKeysState(buttons: [], rows: CustomKeyRows.defaultRows);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final buttons = _loadButtons(prefs);
    final rows = prefs.getString(rowsKey) != null
        ? _loadRows(prefs)
        : await _migrateLegacyRows(prefs);
    if (!ref.mounted) return;
    state = CustomKeysState(buttons: buttons, rows: rows);
    await _persist();
  }

  List<CustomKeyButton> _loadButtons(SharedPreferences prefs) {
    final raw = prefs.getString(buttonsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final buttons = <CustomKeyButton>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final button = CustomKeyButton.fromJson(item);
        if (button == null) continue;
        buttons.add(button);
      }
      return buttons;
    } catch (_) {
      return [];
    }
  }

  /// 新形式の行レイアウトを読む。壊れていれば既定レイアウトに戻す。
  List<List<String>> _loadRows(SharedPreferences prefs) {
    final raw = prefs.getString(rowsKey);
    if (raw == null) return _copyRows(CustomKeyRows.defaultRows);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return _copyRows(CustomKeyRows.defaultRows);
      final rows = <List<String>>[];
      for (final row in decoded) {
        if (row is! List) return _copyRows(CustomKeyRows.defaultRows);
        final tokens = <String>[];
        for (final token in row) {
          if (token is! String) return _copyRows(CustomKeyRows.defaultRows);
          tokens.add(token);
        }
        rows.add(tokens);
      }
      if (rows.length > CustomKeyRows.maxRows) {
        return rows.sublist(0, CustomKeyRows.maxRows);
      }
      return rows;
    } catch (_) {
      return _copyRows(CustomKeyRows.defaultRows);
    }
  }

  /// 行が3本固定だった旧レイアウトを新形式へ一度だけ移行する。
  ///
  /// 旧来の 2 つの移行（カスタムトークンの行0への集約、並べ替え済み行2への
  /// num1..num4 追記）をここで適用したうえで `[row0, row1, row2]` を返し、
  /// 旧キーは削除する。
  Future<List<List<String>>> _migrateLegacyRows(SharedPreferences prefs) async {
    var row0 = _loadLegacyRow(prefs, legacyRow0Key, const <String>[]);
    var row1 = _loadLegacyRow(prefs, legacyRow1Key, CustomKeyRows.standardRow1);
    var row2 = _loadLegacyRow(prefs, legacyRow2Key, CustomKeyRows.standardRow2);
    // 専用のカスタム行が導入される前のレイアウト: row1/row2 に混在していた
    // カスタムトークンを row0 へ集約する。
    if (prefs.getString(legacyRow0Key) == null) {
      row0 = [
        ...row1.where(CustomKeyRows.isCustomToken),
        ...row2.where(CustomKeyRows.isCustomToken),
      ];
      row1 = row1.where((t) => !CustomKeyRows.isCustomToken(t)).toList();
      row2 = row2.where((t) => !CustomKeyRows.isCustomToken(t)).toList();
    }
    // row2 が既定と異なる（ユーザーが並べ替えた）うえに直接入力の数字キーを
    // 持たない場合のみ、描画時の自動付与に代えて num1..num4 を明示的に追記
    // する。既定の row2 は旧来の直接入力レイアウトで数字を描くため、ここで
    // 触ると既定レイアウトが壊れる（キーの存在有無では判定できない: 旧版の
    // 保存処理が毎回すべての行キーを書いていたため）。
    if (!(prefs.getBool(shelfMigrationKey) ?? false) &&
        !listEquals(row2, CustomKeyRows.standardRow2) &&
        !row2.any(CustomKeyRows.directInputExtras.contains)) {
      row2 = [...row2, ...CustomKeyRows.directInputExtras];
    }
    await prefs.remove(legacyRow0Key);
    await prefs.remove(legacyRow1Key);
    await prefs.remove(legacyRow2Key);
    return [row0, row1, row2];
  }

  List<String> _loadLegacyRow(
    SharedPreferences prefs,
    String key,
    List<String> fallback,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return List.of(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List.of(fallback);
      final row = <String>[];
      for (final item in decoded) {
        if (item is! String) return List.of(fallback);
        row.add(item);
      }
      return row;
    } catch (_) {
      return List.of(fallback);
    }
  }

  Future<void> _persist() async {
    final buttonsJson = jsonEncode(
      state.buttons.map((b) => b.toJson()).toList(),
    );
    final rowsJson = jsonEncode(state.rows);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(buttonsKey, buttonsJson);
    await prefs.setString(rowsKey, rowsJson);
    await prefs.setBool(shelfMigrationKey, true);
  }

  CustomKeyButton addButton(String label, List<CustomKeyStep> steps) {
    final b = CustomKeyButton(
      id: CustomKeyButton.newId(),
      label: label.trim(),
      steps: List.of(steps),
    );
    state = CustomKeysState(buttons: [...state.buttons, b], rows: state.rows);
    _persist();
    return b;
  }

  void updateButton(
    String id, {
    required String label,
    required List<CustomKeyStep> steps,
  }) {
    final buttons = state.buttons
        .map(
          (b) => b.id == id
              ? CustomKeyButton(
                  id: b.id,
                  label: label.trim(),
                  steps: List.of(steps),
                )
              : b,
        )
        .toList();
    state = CustomKeysState(buttons: buttons, rows: state.rows);
    _persist();
  }

  void deleteButton(String id) {
    final token = 'ck:${id.substring(3)}';
    state = CustomKeysState(
      buttons: state.buttons.where((b) => b.id != id).toList(),
      rows: [
        for (final row in state.rows) row.where((t) => t != token).toList(),
      ],
    );
    _persist();
  }

  void setRowTokens(int row, List<String> tokens) {
    if (row < 0 || row >= state.rows.length) return;
    final customIds = _customTokens();
    final seen = <String>{};
    final clean = tokens
        .where((t) => CustomKeyRows.isKnownToken(t, customIds) && seen.add(t))
        .toList();
    final rows = _copyRows(state.rows);
    rows[row] = clean;
    state = CustomKeysState(buttons: state.buttons, rows: rows);
    _persist();
  }

  /// 空の行を最下段に追加する。[CustomKeyRows.maxRows] に達していれば何もしない。
  void addRow() {
    if (state.rows.length >= CustomKeyRows.maxRows) return;
    state = CustomKeysState(
      buttons: state.buttons,
      rows: [..._copyRows(state.rows), <String>[]],
    );
    _persist();
  }

  /// 行を削除する。載っていたトークンは未使用（Unused）へ戻るだけで失われない。
  void removeRow(int row) {
    if (row < 0 || row >= state.rows.length) return;
    final rows = _copyRows(state.rows)..removeAt(row);
    state = CustomKeysState(buttons: state.buttons, rows: rows);
    _persist();
  }

  /// Moves [token] to [toRow] at slot [toIndex], or to the shelf when [toRow]
  /// is [CustomKeyRows.shelfRow].
  ///
  /// The token is first stripped from every row. When [toRow] is a real row the
  /// slot index is interpreted against that row's pre-move token list, so a
  /// same-row move from a lower index lands at [toIndex] - 1. Unknown tokens
  /// (not standard and not an existing custom button) are a no-op.
  void placeToken(String token, {required int toRow, required int toIndex}) {
    if (!CustomKeyRows.isKnownToken(token, _customTokens())) return;

    final rows = [
      for (final row in state.rows) row.where((t) => t != token).toList(),
    ];

    if (toRow >= 0 && toRow < rows.length) {
      final oldIndex = state.rows[toRow].indexOf(token);
      var index = toIndex;
      if (oldIndex >= 0 && oldIndex < toIndex) {
        index = toIndex - 1;
      }
      final target = rows[toRow];
      final insertAt = index < 0
          ? 0
          : index > target.length
          ? target.length
          : index;
      target.insert(insertAt, token);
    }

    state = CustomKeysState(buttons: state.buttons, rows: rows);
    _persist();
  }

  Set<String> _customTokens() =>
      state.buttons.map((b) => 'ck:${b.id.substring(3)}').toSet();

  static List<List<String>> _copyRows(List<List<String>> rows) => [
    for (final row in rows) List.of(row),
  ];
}

final customKeysProvider =
    NotifierProvider<CustomKeysNotifier, CustomKeysState>(
      CustomKeysNotifier.new,
    );
