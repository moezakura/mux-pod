/// herdr adapter テスト共用の実測 JSON fixture。
/// （元: herdr_adapter_test.dart のトップレベル const・値は完全に同一）
const kStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

const kStatusProtocol16 =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":16,"compatible":false,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

// 実測: server 非稼働時の `herdr status --json`（protocol が null）。
const kStatusNotRunning =
    '{"client":{"version":"0.7.5","channel":"stable","protocol":17,'
    '"binary":"/lab/herdr","session":null},"server":{"status":"not_running",'
    '"running":false,"version":null,"protocol":null,"capabilities":null,'
    '"compatible":null,"socket":"/home/lab/.config/herdr/herdr.sock",'
    '"session":null,"restart_needed":false},"update":{"restart_needed":false}}';

const kSnapshotOk =
    '{"id":"cli:api:snapshot","result":{"snapshot":{"protocol":17,'
    '"version":"0.7.5","focused_workspace_id":"w1","focused_tab_id":"w1:t1",'
    '"focused_pane_id":"w1:p1","workspaces":[{"workspace_id":"w1",'
    '"label":"lab-ws1","number":1,"focused":true,"agent_status":"unknown",'
    '"pane_count":1,"tab_count":1,"active_tab_id":"w1:t1"}],'
    '"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"1","number":1,'
    '"focused":true,"agent_status":"unknown","pane_count":1}],'
    '"panes":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1",'
    '"focused":true,"agent_status":"unknown","cwd":"/tmp",'
    '"foreground_cwd":"/tmp","revision":0,"terminal_id":"term_x"}]},'
    '"type":"session_snapshot"}}';

// T0 実測⑥の mutation 応答内 layout JSON（compact 版）。
const kMutationLayoutJson =
    '{"area":{"height":59,"width":78,"x":26,"y":1},'
    '"focused_pane_id":"w5:p1","panes":['
    '{"focused":true,"pane_id":"w5:p1",'
    '"rect":{"height":59,"width":39,"x":26,"y":1}}],'
    '"splits":[{"direction":"right","id":"split_0_root","ratio":0.5,'
    '"rect":{"height":59,"width":78,"x":26,"y":1}}],'
    '"tab_id":"w5:t1","workspace_id":"w5","zoomed":false}';

// T0 実測 4-c: resize 応答（layout 込み）。
const kResizeOk =
    '{"id":"cli:pane:resize","result":{"resize":{'
    '"changed":true,"focused_pane_id":"w5:p1","layout":$kMutationLayoutJson,'
    '"pane_id":"w5:p1"},"type":"pane_resize"}}';

// T0 実測 5-b: focus の soft 失敗（no_neighbor・layout 込み）。
const kFocusNoNeighbor =
    '{"id":"cli:pane:focus","result":{"focus":{'
    '"changed":false,"focused_pane_id":"w5:p1","layout":$kMutationLayoutJson,'
    '"reason":"no_neighbor","source_pane_id":"w5:p1"},'
    '"type":"pane_focus_direction"}}';

// T0 実測 5-a: edges 応答（layout 込み）。
const kEdgesOk =
    '{"id":"cli:pane:edges","result":{"edges":{'
    '"down":true,"layout":$kMutationLayoutJson,"left":true,'
    '"pane_id":"w5:p1","right":false,"up":true},"type":"pane_edges"}}';

// T0 実測 6-a: zoom 応答（zoom_changed）。
const kZoomOk =
    '{"id":"cli:pane:zoom","result":{"zoom":{'
    '"zoom_changed":true,"focus_changed":false,"zoomed":true},'
    '"type":"pane_zoom"}}';
