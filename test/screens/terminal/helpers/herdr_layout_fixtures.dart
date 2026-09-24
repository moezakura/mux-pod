// P5 helper: herdr snapshot JSON fixtures (H1a)  — 分割時に値不変で移動。

// 2 pane（w1:p1 / w1:p2・横並び）の layout 付き snapshot fixture。
// 各矩形は 幅>80 かつ 高さ>60（分割プレビューのインライン分割経路が入るサイズ）。
const kHerdrTwoPaneLayoutSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":100,"height":70}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":100,"y":0,"width":100,"height":70}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
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

// 3 pane（L 字: w1:p1 左上・w1:p2 右上・w1:p3 左下）の layout 付き snapshot
// fixture。w1:p1 は右隣（p2）と下隣（p3）の両方を持つため、Cols/Rows 両変更時の
// 「Cols→Rows 順の 2 回送信」（ユーザー決定6）の検証に使う。
const kHerdrThreePaneLayoutSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":100,"height":35}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":100,"y":0,"width":100,"height":35}},'
    '{"pane_id":"w1:p3","focused":false,'
    '"rect":{"x":0,"y":35,"width":100,"height":35}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":true,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/b","focused":false,'
    '"foreground_cwd":"/b","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_2","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/c","focused":false,'
    '"foreground_cwd":"/c","pane_id":"w1:p3","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_3","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":3,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":3,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// G4 実測のスナップショット fixture（workspace label は lab-ws1 / pane は w1:p1）。
/// 2 pane（w1:p1 / w1:p2）だが `layouts: []`（layout 未取得）の snapshot fixture。
/// 実機で接続直後に layout が届いていない状態を再現する（HIGH-2 の全 rect 0
/// ガードで indicator 非表示になる想定）。後続 poll で layout 付き snapshot に
/// 置き換わるシナリオ（#19）で使用する。
const kHerdrTwoPaneNoLayoutSnapshotFixture =
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

// 同名ラベル "tmp" の 2 workspace（w1/w2）fixture。
// herdr の実測と同じく label が重複するケース（tmp w3/w4）を模し、
// sessionId 優先（id 一致 → label 一致 → フォールバック）の解決を検証する。
// w1:p1（focused・cwd=/tmp）/ w2:p1（cwd=/var）。
const kHerdrSameLabelSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/var","focused":false,'
    '"foreground_cwd":"/var","pane_id":"w2:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w2:t1",'
    '"terminal_id":"term_2","workspace_id":"w2"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"tmp","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
    '{"active_tab_id":"w2:t1","agent_status":"unknown","focused":false,'
    '"label":"tmp","number":1,"pane_count":1,"tab_count":1,'
    '"workspace_id":"w2"}]},"type":"session_snapshot"}}';

// T10 セレクタ用: 2 workspace（w1/w2）の snapshot fixture。
// w1:p1（cwd=/tmp・focused）/ w2:p1（cwd=/var）を持ち、セレクタの
// workspace → tab → pane ドリルダウンと pane 表示名（A10: currentPath 優先）
// を検証できる。
const kHerdrTwoWorkspaceSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/var","focused":false,'
    '"foreground_cwd":"/var","pane_id":"w2:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w2:t1",'
    '"terminal_id":"term_2","workspace_id":"w2"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w2:t1","workspace_id":"w2"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"},'
    '{"active_tab_id":"w2:t1","agent_status":"unknown","focused":false,'
    '"label":"lab-ws2","number":1,"pane_count":1,"tab_count":1,'
    '"workspace_id":"w2"}]},"type":"session_snapshot"}}';

// M-4 検証用: tab に数字以外の実ラベル（"editor"）を持つ snapshot fixture。
// パンくずの tab セグメントが数字抽出（"1"）ではなく実ラベルを表示することを
// 検証する（T4）。
const kHerdrLabeledTabSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_6586edf6f766f1","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":true,"label":"editor","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t1",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":1,"tab_count":1,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';

// Phase 3 (#18) min 正規化検証用: 非 0 起点 rect（x:26 / y:1 ベース・
// `kHerdrResizedSnapshotFixture` 相当）の 2 pane 新規 fixture。
// 0 起点 fixture では min 正規化を検証できないため新規追加する（HIGH-1/LOW-2）。
const kHerdrMinNormalizeSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":26,"y":1,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":26,"y":1,"width":100,"height":70}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":126,"y":1,"width":100,"height":70}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
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

// Phase 3 (#11) zoom 検証用: 2 pane + zoomed:true の新規 fixture（既存
// `kHerdrSnapshotZoomedFixture` は書き換えない・HIGH-1）。pane rect は非 zoom 値の
// まま（下地レイアウトをそのまま描画する設計の検証）。
const kHerdrZoomedTwoPaneSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":100,"height":70}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":100,"y":0,"width":100,"height":70}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":true}],'
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

// Phase 3 (#12/#13) mutation 後更新（同一 id・rect 変化=resize）検証用: 初期
// `kHerdrTwoPaneLayoutSnapshotFixture`（w1:p1 100x70 / w1:p2 100x70）に対して、
// 同一 pane id のまま rect のみ変化させた 2 pane 新規 fixture。
// MultiplexerPane.== は id のみ比較のため shouldRepaint の rect 明示比較が効く。
const kHerdrIndicatorResizeSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p1","focused_tab_id":"w1:t1",'
    '"focused_workspace_id":"w1",'
    '"layouts":[{"area":{"x":0,"y":0,"width":200,"height":70},'
    '"focused_pane_id":"w1:p1",'
    '"panes":[{"pane_id":"w1:p1","focused":true,'
    '"rect":{"x":0,"y":0,"width":130,"height":70}},'
    '{"pane_id":"w1:p2","focused":false,'
    '"rect":{"x":130,"y":0,"width":70,"height":70}}],'
    '"splits":[],"tab_id":"w1:t1","workspace_id":"w1","zoomed":false}],'
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

// S0 実測形状: create --focus 後の snapshot（旧 tab は残存しつつ新タブが focused）。
// 旧 tab w1:t1（w1:p1）が残っていても、focused_tab_id / focused_pane_id /
// active_tab_id の 3 点で新タブ w1:t8（w1:p2）を指す。New Tab ダイアログの
// 「作成後の表示切替」検証に使う（旧 pane 残存でも followBackendFocus が新 pane
// を優先することを UI 経由で確認）。
const kHerdrNewTabActiveSnapshotFixture =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"agents":[],'
    '"focused_pane_id":"w1:p2","focused_tab_id":"w1:t8",'
    '"focused_workspace_id":"w1","layouts":[],'
    '"panes":[{"agent_status":"unknown","cwd":"/a","focused":false,'
    '"foreground_cwd":"/a","pane_id":"w1:p1","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t1",'
    '"terminal_id":"term_1","workspace_id":"w1"},'
    '{"agent_status":"unknown","cwd":"/tmp","focused":true,'
    '"foreground_cwd":"/tmp","pane_id":"w1:p2","revision":0,'
    '"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,'
    '"viewport_rows":23},"tab_id":"w1:t8",'
    '"terminal_id":"term_2","workspace_id":"w1"}],"protocol":17,'
    '"tabs":[{"agent_status":"unknown","focused":false,"label":"1","number":1,'
    '"pane_count":1,"tab_id":"w1:t1","workspace_id":"w1"},'
    '{"agent_status":"unknown","focused":true,"label":"2","number":2,'
    '"pane_count":1,"tab_id":"w1:t8","workspace_id":"w1"}],'
    '"version":"0.7.5","workspaces":[{"active_tab_id":"w1:t8",'
    '"agent_status":"unknown","focused":true,"label":"lab-ws1","number":1,'
    '"pane_count":2,"tab_count":2,"workspace_id":"w1"}]},'
    '"type":"session_snapshot"}}';
