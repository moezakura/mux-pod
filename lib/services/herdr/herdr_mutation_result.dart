// inventory: HERDR-RESULT-000
/// mutation 応答の値型 [HerdrMutationResult] と、応答 stdout から値を抽出する
/// 静的パーサ（[HerdrMutationResult.parse]）を提供する。無依存の最下層。
library;

import 'dart:convert';

import 'herdr_models.dart';
import 'herdr_parser.dart';

// inventory: HERDR-ADAPTER-020
/// mutation 実行結果。
///
/// `changed:false`（分割境界外 resize / 隣接なし focus 等）は失敗ではなく
/// **soft 失敗**（情報通知）を表す（S4 分類）。
class HerdrMutationResult {
  /// 状態が変化したかどうか。
  ///
  /// `changed:false`（resize の `reason:"unchanged"` / focus の
  /// `reason:"no_neighbor"` 等）で false。stdout が空の成功
  /// （send-text / send-keys / close / split / rename）は true。
  final bool changed;

  /// 応答の `reason`（`no_neighbor` / `unchanged` 等・無ければ null）。
  final String? reason;

  /// 応答に含まれるレイアウト（resize/zoom/focus/edges。無ければ null）。
  final HerdrLayout? layout;

  const HerdrMutationResult({this.changed = true, this.reason, this.layout});

  /// 隣接 pane が無い（soft 失敗・情報通知）。
  bool get isNoNeighbor => reason == 'no_neighbor';

  /// 分割境界のため変更なし（soft 失敗・情報通知）。
  bool get isUnchanged => !changed;

  @override
  String toString() =>
      'HerdrMutationResult(changed: $changed, reason: $reason, '
      'layout: ${layout == null ? 'null' : 'present'})';

  /// mutation 応答の stdout から [HerdrMutationResult] を抽出する。
  ///
  /// - stdout 空 → `changed:true` の素の成功（R7）。
  /// - JSON でない / 想定構造でない stdout → rc=0 を尊重し素の成功。
  /// - 応答形式（T0 実測 4-c/5-a/5-b/6-a）:
  ///   `{"result":{"resize":{"changed":..,"reason":..,"layout":{..}},"type":..}}`
  ///   操作サブオブジェクトは `changed` / `zoom_changed` / `layout` のいずれか
  ///   を持つものを探す（resize / focus / zoom / edges 共通）。
  static HerdrMutationResult parse(String stdout) {
    if (stdout.trim().isEmpty) return const HerdrMutationResult();
    final Object? decoded;
    try {
      decoded = jsonDecode(stdout);
    } catch (_) {
      return const HerdrMutationResult();
    }
    if (decoded is! Map<String, dynamic>) return const HerdrMutationResult();
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) return const HerdrMutationResult();

    Map<String, dynamic>? op;
    for (final entry in result.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic> &&
          (value.containsKey('changed') ||
              value.containsKey('zoom_changed') ||
              value.containsKey('layout'))) {
        op = value;
        break;
      }
    }
    if (op == null) return const HerdrMutationResult();

    final changedRaw = op['changed'] ?? op['zoom_changed'];
    final changed = changedRaw is bool ? changedRaw : true;
    final reasonRaw = op['reason'];
    HerdrLayout? layout;
    final layoutRaw = op['layout'];
    if (layoutRaw is Map<String, dynamic>) {
      try {
        layout = HerdrSnapshotParser.parseLayoutMap(layoutRaw);
      } on FormatException {
        // 応答 layout の欠損は許容（rc=0 を優先・R7）。
        layout = null;
      }
    }
    return HerdrMutationResult(
      changed: changed,
      reason: reasonRaw is String ? reasonRaw : null,
      layout: layout,
    );
  }
}
