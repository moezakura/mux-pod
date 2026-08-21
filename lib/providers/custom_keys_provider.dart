import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/custom_keys/custom_key_button.dart';

/// State of the custom key buttons and their row layouts.
class CustomKeysState {
  const CustomKeysState({
    required this.buttons,
    required this.row0,
    required this.row1,
    required this.row2,
  });

  final List<CustomKeyButton> buttons;
  final List<String> row0;
  final List<String> row1;
  final List<String> row2;

  CustomKeyButton? buttonById(String id) {
    for (final b in buttons) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Buttons not referenced by row0, row1 or row2.
  List<CustomKeyButton> unplacedButtons() {
    final placed = <String>{
      for (final token in [...row0, ...row1, ...row2])
        if (CustomKeyRows.isCustomToken(token)) token,
    };
    return buttons
        .where((b) => !placed.contains('ck:${b.id.substring(3)}'))
        .toList();
  }

  /// Tokens not present in row0, row1 or row2, in canonical order:
  /// [CustomKeyRows.allLayoutTokens] first, then custom `ck:` tokens in
  /// [buttons] order.
  List<String> unusedTokens() {
    final placed = <String>{...row0, ...row1, ...row2};
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
}

/// Manages custom key buttons and their row layouts, persisting to shared_preferences.
class CustomKeysNotifier extends Notifier<CustomKeysState> {
  static const String buttonsKey = 'custom_key_buttons_v1';
  static const String row0Key = 'custom_key_row0_v1';
  static const String row1Key = 'custom_key_row1_v1';
  static const String row2Key = 'custom_key_row2_v1';

  static const String shelfMigrationKey = 'custom_keys_shelf_v1';

  @override
  CustomKeysState build() {
    _load();
    return const CustomKeysState(
      buttons: [],
      row0: CustomKeyRows.standardRow0,
      row1: CustomKeyRows.standardRow1,
      row2: CustomKeyRows.standardRow2,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final buttons = _loadButtons(prefs);
    var row0 = _loadRow(prefs, row0Key, CustomKeyRows.standardRow0);
    var row1 = _loadRow(prefs, row1Key, CustomKeyRows.standardRow1);
    var row2 = _loadRow(prefs, row2Key, CustomKeyRows.standardRow2);
    // 専用のカスタム行が導入される前のレイアウトを一度だけ移行する:
    // row1/row2 に混在していたカスタムトークンを row0 へ集約する。
    if (prefs.getString(row0Key) == null) {
      row0 = [
        ...row1.where(CustomKeyRows.isCustomToken),
        ...row2.where(CustomKeyRows.isCustomToken),
      ];
      row1 = row1.where((t) => !CustomKeyRows.isCustomToken(t)).toList();
      row2 = row2.where((t) => !CustomKeyRows.isCustomToken(t)).toList();
    }
    // 一度だけ: row2 が既定と異なる（ユーザーが並べ替えた）うえに直接入力の
    // 数字キーを持たない場合のみ、描画時の自動付与に代えて num1..num4 を明示
    // 的に追記する。既定の row2 は旧来の直接入力レイアウトで数字を描くため、
    // ここで触ると既定レイアウトが壊れる（キーの存在有無では判定できない:
    // _persist() が毎回すべての行キーを書くため）。
    if (!(prefs.getBool(shelfMigrationKey) ?? false) &&
        !listEquals(row2, CustomKeyRows.standardRow2) &&
        !row2.any(CustomKeyRows.directInputExtras.contains)) {
      row2 = [...row2, ...CustomKeyRows.directInputExtras];
    }
    state = CustomKeysState(
      buttons: buttons,
      row0: row0,
      row1: row1,
      row2: row2,
    );
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

  List<String> _loadRow(
    SharedPreferences prefs,
    String key,
    List<String> fallback,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return fallback;
      final row = <String>[];
      for (final item in decoded) {
        if (item is! String) return fallback;
        row.add(item);
      }
      return row;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _persist() async {
    final buttonsJson = jsonEncode(
      state.buttons.map((b) => b.toJson()).toList(),
    );
    final row0Json = jsonEncode(state.row0);
    final row1Json = jsonEncode(state.row1);
    final row2Json = jsonEncode(state.row2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(buttonsKey, buttonsJson);
    await prefs.setString(row0Key, row0Json);
    await prefs.setString(row1Key, row1Json);
    await prefs.setString(row2Key, row2Json);
    await prefs.setBool(shelfMigrationKey, true);
  }

  CustomKeyButton addButton(String label, List<CustomKeyStep> steps) {
    final b = CustomKeyButton(
      id: CustomKeyButton.newId(),
      label: label.trim(),
      steps: List.of(steps),
    );
    state = CustomKeysState(
      buttons: [...state.buttons, b],
      row0: state.row0,
      row1: state.row1,
      row2: state.row2,
    );
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
    state = CustomKeysState(
      buttons: buttons,
      row0: state.row0,
      row1: state.row1,
      row2: state.row2,
    );
    _persist();
  }

  void deleteButton(String id) {
    final token = 'ck:${id.substring(3)}';
    state = CustomKeysState(
      buttons: state.buttons.where((b) => b.id != id).toList(),
      row0: state.row0.where((t) => t != token).toList(),
      row1: state.row1.where((t) => t != token).toList(),
      row2: state.row2.where((t) => t != token).toList(),
    );
    _persist();
  }

  void setRowTokens(int row, List<String> tokens) {
    final customIds = state.buttons
        .map((b) => 'ck:${b.id.substring(3)}')
        .toSet();
    final seen = <String>{};
    final clean = tokens
        .where((t) => CustomKeyRows.isKnownToken(t, customIds) && seen.add(t))
        .toList();
    state = CustomKeysState(
      buttons: state.buttons,
      row0: row == 0 ? clean : state.row0,
      row1: row == 1 ? clean : state.row1,
      row2: row == 2 ? clean : state.row2,
    );
    _persist();
  }

  /// Moves [token] to [toRow] (0,1,2) at slot [toIndex], or to the shelf when
  /// [toRow] == [CustomKeyRows.shelfRow].
  ///
  /// The token is first stripped from every row. When [toRow] is a real row the
  /// slot index is interpreted against that row's pre-move token list, so a
  /// same-row move from a lower index lands at [toIndex] - 1. Unknown tokens
  /// (not standard and not an existing custom button) are a no-op.
  void placeToken(String token, {required int toRow, required int toIndex}) {
    final customIds = state.buttons
        .map((b) => 'ck:${b.id.substring(3)}')
        .toSet();
    if (!CustomKeyRows.isKnownToken(token, customIds)) return;

    final row0 = state.row0.where((t) => t != token).toList();
    final row1 = state.row1.where((t) => t != token).toList();
    final row2 = state.row2.where((t) => t != token).toList();

    if (toRow == 0 || toRow == 1 || toRow == 2) {
      final preMove = switch (toRow) {
        0 => state.row0,
        1 => state.row1,
        _ => state.row2,
      };
      final target = switch (toRow) {
        0 => row0,
        1 => row1,
        _ => row2,
      };
      final oldIndex = preMove.indexOf(token);
      var index = toIndex;
      if (oldIndex >= 0 && oldIndex < toIndex) {
        index = toIndex - 1;
      }
      final insertAt = index < 0
          ? 0
          : index > target.length
          ? target.length
          : index;
      target.insert(insertAt, token);
    }

    state = CustomKeysState(
      buttons: state.buttons,
      row0: row0,
      row1: row1,
      row2: row2,
    );
    _persist();
  }
}

final customKeysProvider =
    NotifierProvider<CustomKeysNotifier, CustomKeysState>(
      CustomKeysNotifier.new,
    );
