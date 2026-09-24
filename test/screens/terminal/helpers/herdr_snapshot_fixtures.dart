// P5 helper: herdr snapshot JSON fixtures (H1a)  — 分割時に値不変で移動。

// G4 実測の snapshot fixture（w1:p1 のみ・単一 tab / 単一 workspace）。
const kHerdrSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 再解決後（w1:p1 消滅・w1:p2 のみ）の snapshot fixture。
const kHerdrSnapshotPane2Fixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p2","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// 対象が存在しない（panes 空）snapshot fixture（終端判定用）。
const kHerdrEmptySnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],"panes":[],"protocol":17,"tabs":[],"version":"0.7.5",'
    '"workspaces":[]},"type":"session_snapshot"}}';

// G4 実測の snapshot fixture に layout rect（w1:p1 = 80x24）を追加した版。
// セレクタ / resize ダイアログの「現在サイズ（layout rect）」表示の検証に使う。
const kHerdrSnapshotWithLayoutFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// layout 付き snapshot fixture（バグ1 AutoFit 用）: pane w1:p1 の rect が
// 幅 120 x 高さ 24（文字セル単位・T0 実測⑥）。AutoFit がこの幅で計算される
// ことを検証する（従来は layout が空のため width/height=0 → 既定 80 のまま）。
const kHerdrLargeLayoutSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[{"area":{"height":24,"width":120,'
    '"x":0,"y":0},"focused_pane_id":"w1:p1","panes":[{"focused":true,'
    '"pane_id":"w1:p1","rect":{"height":24,"width":120,"x":0,"y":0}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// zoom 中 snapshot fixture（バグ1 AutoFit 用）: zoomed=true のとき pane 表示は
// タブ全面（layout.area）になる（T0 実測 6-b）。pane rect は非 zoom 値
// （width 40）のままでも、AutoFit は area の幅 120 を使うことを検証する。
const kHerdrSnapshotZoomedFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[{"area":{"height":24,"width":120,'
    '"x":0,"y":0},"focused_pane_id":"w1:p1","panes":[{"focused":true,'
    '"pane_id":"w1:p1","rect":{"height":24,"width":40,"x":0,"y":0}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":true}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// Phase 4 用: pane w1:p1 の rect が 幅120 x 高さ150 の layout 付き fixture。
// テスト実機では AnsiTextView のビューポートが pane（24 行相当）よりかなり
// 大きいため、paneHeight=150 かつ内容 300 行にすると「caret 中央寄せ」と
// 「末尾フォールバック（scrollToBottom）」のスクロール先が明確に区別できる。
// （paneHeight 24 では caret は常に下側へ clamp され末尾と同一になるため。）
const kHerdrTallLayoutSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[{"area":{"height":150,"width":120,'
    '"x":0,"y":0},"focused_pane_id":"w1:p1","panes":[{"focused":true,'
    '"pane_id":"w1:p1","rect":{"height":150,"width":120,"x":0,"y":0}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":149},"tab_id":"w1:t1",'
    '"terminal_id":"term_tall","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// hidden TUI resize 収束確認用: PTY 120x40 → 実測変換式で area 94x39 の fixture。
// （kHerdrSnapshotWithLayoutFixture の area / rect を 94x39 にした版）
const kHerdrResizedSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":26,"y":1,"width":94,"height":39},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":26,"y":1,"width":94,"height":39}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// resize 応答の `changed:false`（分割境界外・T0 実測 4-b）fixture。
const kHerdrResizeUnchangedFixture =
    '{"result":{"resize":{"changed":false,"reason":"unchanged",'
    '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}},'
    '"type":"pane_resize"}}';

// 構造化エラー JSON（target-not-found 分類用）。
const kPaneNotFoundErrorFixture =
    '{"error":{"code":"pane_not_found","message":"no pane"},'
    '"id":"cli:pane:close"}';

// T0 実測 5-b: focus の soft 失敗（no_neighbor・layout 込み）。
const kFocusNoNeighborFixture =
    '{"id":"cli:pane:focus","result":{"focus":{'
    '"changed":false,"focused_pane_id":"w1:p1",'
    '"layout":{"area":{"x":0,"y":0,"width":80,"height":24},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":80,"height":24}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false},'
    '"reason":"no_neighbor","source_pane_id":"w1:p1"},'
    '"type":"pane_focus_direction"}}';

// 2 pane（w1:p1 / w1:p2）・単一 tab の snapshot fixture（split 後・close 対象判定用）。
const kHerdrTwoPanesSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":true,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/b","focused":false,'
    '"foreground_cwd":"/b","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_2","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":2,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":2,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// focused 情報欠落（全 tab / pane が非フォーカス）の snapshot fixture。
// followBackendFocus では「フォーカス tab → フォーカス pane」が解決できないため
// sticky へフォールバックし、現在表示（w1:p1）を維持することを検証する
// （Codex 観点 4: focused 情報欠落 => 現在の tab を維持）。
const kHerdrSnapshotNoFocusInfoFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":null,"focused_tab_id":null,"focused_workspace_id":null,'
    '"layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":false,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":false,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';
