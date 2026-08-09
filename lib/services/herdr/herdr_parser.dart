// inventory: HERDR-PARSER-000
/// herdr CLI の JSON 出力を DTO へパースする。
///
/// 出力形式は G4 実測の証跡
/// （`/tmp/herdr-lab/work/evidence/read/12_api_snapshot.json` 等）に基づく。
/// 欠損フィールドは許容し、構造が不正な場合は [FormatException] を投げる。
library;

import 'dart:convert';

import 'herdr_models.dart';

// inventory: HERDR-PARSER-STATUS-001
/// `herdr status --json` のパーサ。
class HerdrStatusParser {
  HerdrStatusParser._();

  /// 出力形式:
  /// `{"client":{"version":..,"protocol":17,..},"server":{"status":..,"protocol":17,..},"update":{..}}`
  static HerdrStatus parse(String json) {
    final decoded = _decodeObject(json);
    final client = decoded['client'];
    final server = decoded['server'];
    return HerdrStatus(
      clientVersion: _asString(client, 'version'),
      clientProtocol: _asInt(client, 'protocol'),
      serverVersion: _asString(server, 'version'),
      serverProtocol: _asInt(server, 'protocol'),
      serverStatus: _asString(server, 'status'),
      running: _asBool(server, 'running'),
      compatible: _asBool(server, 'compatible'),
      socket: _asString(server, 'socket'),
    );
  }
}

// inventory: HERDR-PARSER-SNAPSHOT-001
/// `herdr api snapshot` のパーサ。
class HerdrSnapshotParser {
  HerdrSnapshotParser._();

  /// 出力形式:
  /// `{"id":"cli:api:snapshot","result":{"snapshot":{..},"type":"session_snapshot"}}`
  static HerdrSnapshot parse(String json) {
    final decoded = _decodeObject(json);
    final result = decoded['result'];
    final snapshot = _asMap(result, 'snapshot');

    final workspaces = _asList(snapshot, 'workspaces')
        .map(_parseWorkspace)
        .toList();
    final tabs =
        _asList(snapshot, 'tabs').map((raw) => _parseTab(raw)).toList();
    final panes =
        _asList(snapshot, 'panes').map((raw) => _parsePane(raw)).toList();

    return HerdrSnapshot(
      protocol: _asInt(snapshot, 'protocol'),
      version: _asString(snapshot, 'version') ?? '',
      focusedWorkspaceId: _asString(snapshot, 'focused_workspace_id'),
      focusedTabId: _asString(snapshot, 'focused_tab_id'),
      focusedPaneId: _asString(snapshot, 'focused_pane_id'),
      workspaces: workspaces,
      tabs: tabs,
      panes: panes,
      layouts: _parseLayouts(snapshot),
    );
  }

  // inventory: HERDR-PARSER-LAYOUT-001
  /// mutation 応答内の `layout` オブジェクトを単体でパースする。
  ///
  /// resize/zoom/focus/edges の応答 `result.<op>.layout`（T0 実測⑥）に使う。
  static HerdrLayout parseLayoutMap(Map<String, dynamic> map) =>
      _parseLayout(map);
}

// inventory: HERDR-PARSER-LAYOUT-002
/// `layouts[]` をパースする（空・欠損許容）。
///
/// キー自体が無い / 空配列の場合は空リストを返す（欠損許容）。
List<HerdrLayout> _parseLayouts(dynamic parent) {
  return _asListOrEmpty(parent, 'layouts').map(_parseLayout).toList();
}

// inventory: HERDR-PARSER-LAYOUT-003
/// layout オブジェクトをパースする（フィールド欠損はデフォルト値で補完）。
HerdrLayout _parseLayout(dynamic raw) {
  final map = _requireMap(raw, 'layout');
  final area = _asMapOrNull(map, 'area');
  return HerdrLayout(
    area: area == null ? const HerdrRect() : _parseRect(area),
    focusedPaneId: _asString(map, 'focused_pane_id'),
    panes: _asListOrEmpty(map, 'panes').map(_parseLayoutPane).toList(),
    splits: _asListOrEmpty(map, 'splits').map(_parseLayoutSplit).toList(),
    tabId: _asString(map, 'tab_id'),
    workspaceId: _asString(map, 'workspace_id'),
    zoomed: _asBool(map, 'zoomed'),
  );
}

// inventory: HERDR-PARSER-LAYOUT-004
/// rect オブジェクトをパースする（欠損フィールドは 0）。
HerdrRect _parseRect(Map<String, dynamic> map) {
  return HerdrRect(
    x: _asInt(map, 'x'),
    y: _asInt(map, 'y'),
    width: _asInt(map, 'width'),
    height: _asInt(map, 'height'),
  );
}

HerdrLayoutPane _parseLayoutPane(dynamic raw) {
  final map = _requireMap(raw, 'layout pane');
  final rect = _asMapOrNull(map, 'rect');
  return HerdrLayoutPane(
    paneId: _requireString(map, 'pane_id'),
    focused: _asBool(map, 'focused'),
    rect: rect == null ? const HerdrRect() : _parseRect(rect),
  );
}

HerdrLayoutSplit _parseLayoutSplit(dynamic raw) {
  final map = _requireMap(raw, 'layout split');
  final rect = _asMapOrNull(map, 'rect');
  return HerdrLayoutSplit(
    direction: _asString(map, 'direction') ?? '',
    id: _asString(map, 'id') ?? '',
    ratio: _asDouble(map, 'ratio'),
    rect: rect == null ? const HerdrRect() : _parseRect(rect),
  );
}

// inventory: HERDR-PARSER-PANE-CONTENT-001
/// `herdr pane read` のパーサ。
///
/// 出力はプレーンテキストまたは ANSI 付き（`--raw`）のいずれでもよく、
/// 生文字列のまま保持して [HerdrPaneContent] を作る。末尾の改行は除去し、
/// 行分割する。`--raw` で取得した場合は [ansi] を true にする。内容自体に
/// ANSI エスケープが含まれる場合も検出して [HerdrPaneContent.hasAnsi] を
/// 補完する（両対応）。
class HerdrPaneContentParser {
  HerdrPaneContentParser._();

  /// ANSI CSI（`ESC [`）で始まるエスケープシーケンスの簡易検出用。
  static final RegExp _ansiEscape = RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]');

  /// 出力を [HerdrPaneContent] に変換する。
  static HerdrPaneContent parse(String output, {bool ansi = false}) {
    final processed = output.endsWith('\n')
        ? output.substring(0, output.length - 1)
        : output;
    final lines = processed.isEmpty ? const <String>[] : processed.split('\n');
    return HerdrPaneContent(
      lines: lines,
      rawText: processed,
      hasAnsi: ansi || _ansiEscape.hasMatch(processed),
    );
  }
}

// ===== shared helpers =====

HerdrWorkspace _parseWorkspace(dynamic raw) {
  final map = _requireMap(raw, 'workspace');
  return HerdrWorkspace(
    id: _requireString(map, 'workspace_id'),
    label: _asString(map, 'label') ?? '',
    number: _asInt(map, 'number'),
    focused: _asBool(map, 'focused'),
    agentStatus: _asString(map, 'agent_status') ?? 'unknown',
    paneCount: _asInt(map, 'pane_count'),
    tabCount: _asInt(map, 'tab_count'),
    activeTabId: _asString(map, 'active_tab_id'),
  );
}

HerdrTab _parseTab(dynamic raw) {
  final map = _requireMap(raw, 'tab');
  return HerdrTab(
    id: _requireString(map, 'tab_id'),
    workspaceId: _requireString(map, 'workspace_id'),
    label: _asString(map, 'label'),
    number: _asInt(map, 'number'),
    focused: _asBool(map, 'focused'),
    agentStatus: _asString(map, 'agent_status') ?? 'unknown',
    paneCount: _asInt(map, 'pane_count'),
  );
}

HerdrPane _parsePane(dynamic raw) {
  final map = _requireMap(raw, 'pane');
  return HerdrPane(
    id: _requireString(map, 'pane_id'),
    workspaceId: _requireString(map, 'workspace_id'),
    tabId: _requireString(map, 'tab_id'),
    focused: _asBool(map, 'focused'),
    agentStatus: _asString(map, 'agent_status') ?? 'unknown',
    cwd: _asString(map, 'cwd'),
    foregroundCwd: _asString(map, 'foreground_cwd'),
    revision: _asInt(map, 'revision'),
    terminalId: _asString(map, 'terminal_id'),
  );
}

Map<String, dynamic> _decodeObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object');
  }
  return decoded;
}

Map<String, dynamic> _requireMap(dynamic value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected $label to be a JSON object');
  }
  return value;
}

Map<String, dynamic> _asMap(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected "$key" to be a JSON object');
  }
  return value;
}

List<dynamic> _asList(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value is! List) {
    throw FormatException('Expected "$key" to be a JSON array');
  }
  return value;
}

/// 欠損・null・空を許容する配列取得（layouts / layout.panes / layout.splits）。
List<dynamic> _asListOrEmpty(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value == null) return const [];
  if (value is List) return value;
  throw FormatException('Expected "$key" to be a JSON array');
}

/// 欠損・null を許容するオブジェクト取得（無ければ null）。
Map<String, dynamic>? _asMapOrNull(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Expected "$key" to be a JSON object');
}

String? _asString(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string');
}

int _asInt(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Expected "$key" to be an integer');
}

double _asDouble(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  throw FormatException('Expected "$key" to be a number');
}

bool _asBool(dynamic parent, String key) {
  final value = (parent is Map<String, dynamic>) ? parent[key] : null;
  if (value == null) return false;
  if (value is bool) return value;
  throw FormatException('Expected "$key" to be a boolean');
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string');
}
