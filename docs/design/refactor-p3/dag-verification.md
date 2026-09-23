# P3 設計書の import グラフ / 循環参照 検証レポート

- 検証者: p3-dag-verifier（タスク#14・読み取り専用・書き込みは `/tmp/p3-design/` のみ）
- cwd: `/home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines`（branch `fix/refactor-many-lines`, HEAD `a86fbdd` = P2 完了）
- 対象: P3 設計書 5 本（`connections-screen.md` / `ansi-text-view.md` / `connection-form.md` / `browser-and-dashboard.md` / `shell-and-panes.md`）+ `BRIEF.md` / `critique.md`
- 前提資料の版: **全 5 設計書は v2（v3 は存在しない）**。`grep -c "v3" connections-screen.md shell-and-panes.md` = 0。タスク指示の「shell と connections は v3 改訂済みのものを読む」は満たせず、**v2 を対象に検証**した（v3 に期待された「static key の中立化」は未実施 → §4 の循環として顕在化）。

---

## 0. 判定（結論）

| 項目 | 判定 |
|---|---|
| (a) screens 配下の非自明 SCC（相互循環）ゼロ | **NG（1 件）** |
| (i) non-home → `home_screen`（シム）の逆辺ゼロ | **OK（案B適用が前提。§5 の条件付き）** |
| (ii) markdown の `body → screen` と `screen → body` の同時存在禁止 | **NG（同時存在）** |
| (iii) `connection_card ⇄ sessions_panel` 等の相互辺なし | **OK**（card → panel の一方向のみ） |
| (iv) ansi 協調オブジェクト → ファサードの逆向辺なし | **OK**（逆向辺ゼロ） |
| 除外: 既知の P3 対象外 `pane_content_reader ⇄ pane_frame_reader` | 除外（実測で相互 import を確認） |
| 除外: 生成物 `l10n/app_localizations*.dart` / `herdr_protocols.g.dart` | 除外（生成物） |

**検出した循環（唯一）: `markdown_preview/markdown_preview_screen.dart ⇄ markdown_preview/markdown_preview_body.dart`（SCC size=2）**

---

## 1. 手法と証跡

- 設計書の「目標構成」「依存グラフ」「移動マッピング」から、改修後の新規/存続ファイルを node、import/export を edge として辺リストを作成。
- 設計書に import 記載がない辺は、現行コード（`git show HEAD:<path>` 相当の作業ツリー実ファイル・`grep -n "^import"`）と移設マッピングから**推定**し、`inferred` と明記。
- Python（Tarjan 反復 SCC）で SCC>=2 を列挙。
- スクリプト:
  - 設計どおり（案B）: `/tmp/p3-design/dag_verify.py` → 実行結果 `dag_run_as_designed.txt`
  - static key 中立化の修正シミュレーション: `/tmp/p3-design/dag_verify_fix_sim.py` → `dag_run_fix_sim.txt`
  - 案A（シム経由）シミュレーション: `/tmp/p3-design/dag_verify_planA_sim.py` → `dag_run_planA_sim.txt`
  - 現行 HEAD ベースライン: `/tmp/p3-design/head_baseline.py` → `dag_run_head_baseline.txt`
- 現行コードの import 実測（辺の根拠）:
  - `home_screen.dart` L19 `connections/connections_screen.dart` / L20 `dashboard/dashboard_screen.dart` / L21 `keys/keys_screen.dart` / L22 `notifications/notification_panes_screen.dart` / L23 `settings/settings_screen.dart` / L24 `terminal/terminal_screen.dart`
  - `connections_screen.dart` L10 `../home_screen.dart` / L25 `connection_form_screen.dart` / L26 `../terminal/terminal_screen.dart`
  - `file_browser_screen.dart` L20 `markdown_preview_screen.dart` / `terminal_screen.dart` L76 `file_browser_screen.dart` / L79 `widgets/ansi_text_view.dart` / L78 `settings_screen.dart` / L84 `custom_keys_screen.dart`
  - `notification_panes_screen.dart` L12 `../terminal/terminal_screen.dart` / `dashboard_screen.dart` L12 `connection_form_screen.dart` / L13 `terminal_screen.dart`
  - `keys_screen.dart` L9 `../home_screen.dart` / `settings_search_field.dart` L6 `../../home_screen.dart`
  - **sink 前提の実測**: `rg "screens/" lib/providers lib/services lib/widgets lib/theme lib/l10n` のヒットは `lib/widgets/dialogs/overwrite_confirm_dialog.dart:32` の**コメント内パス参照 1 件のみ**（import なし）→ providers/services/theme/l10n/widgets は screens を import しない（逆向き辺なし）ので sink として除外してよい。
- グラフ規模: **node 50 / edge 77**（設計どおり・案B版）。設計書に明記の辺は `design`、現行 import 維持の辺は `existing`、型受け取り等の推定は `inferred`。

### 実行結果（設計どおり・案B）

```
=== Tarjan SCC result ===
nodes=50, edges=77, SCCs(total)=49
trivial SCCs=48, non-trivial SCCs=1
SCC(size=2): md/body (presentation), md/screen (impl + static keys)

=== condition checks ===
(i)  non-home → home_screen(shim) 辺: なし (案B適用時) — 例外: main.dart は lib 直下(lib/main.dart→HOME_SIM)でscreens外
(ii) markdown body<->screen 両方向辺存在: True  →  違反: md/screen ⇄ md/body は SCC
(iii) conn card⇄panel 相互辺: [('CONN_CARD', 'CONN_PANEL', 'design: card → sessions panel')]
(iv) ansi 協調オブジェクト → ファサードの逆向辺: なし

=== VERDICT ===
non-trivial SCC 検出: ['マークダウン: md/body (presentation), md/screen (impl + static keys)']
```

---

## 2. 辺リスト（要約・全 77 辺）

同一パッケージ内の screens サブツリーのみを node 化（外部 provider/service/theme/l10n/widgets は sink として省略）。`*` は推定辺。

**connections（14）**
```
conn/shim        → conn/list (export)
conn/list        → conn/sort, conn/search, conn/card                    [design]
conn/list        → home/tab-provider                                    [design 案B]
conn/list        → form/root, terminal                                  [existing L25/L26]
conn/card        → conn/header, conn/panel, conn/ops, conn/new-session-dialog [design]
```
**form（10）**
```
form/root → form/{server-section, auth-section, components, values, tester, saver} [design]
form/server-section → form/components / form/auth-section → form/components        [design]
form/tester → form/values / form/saver → form/values                              [design]
```
**home（10）**
```
home/shim → home/root, home/tab-provider (export)   [design]
home/root → home/tab-provider, home/bottom-nav-bar  [design]
home/root → conn/shim, dashboard, keys, notif/shim, settings, terminal [existing L19-24]
```
**notifications（5）**
```
notif/shim → notif/view (export)                    [design]
notif/view → notif/card, notif/flag-style, terminal [design/existing L12]
notif/card → notif/flag-style                       [inferred]
```
**markdown（6）← 循環はここ**
```
md/shim → md/screen, md/code-block (export)         [design]
md/screen → md/body, md/code-block                  [design]
md/body → md/screen                                 [design v2: static key クラス静的参照]  ★PROBLEM
md/body → md/code-block                             [inferred]
```
**dashboard（3）**
```
dash/root → dash/session-history-card, form/root, terminal [design/existing]
```
**file_browser（6）**
```
fb/root → fb/{app-bar, body, download-flow, upload-flow, dialogs} [design]
fb/root → md/shim (遷移先)                                        [existing L20]
```
**ansi（21）**
```
ansi/facade → ansi/{terminal-model, display-model, scroll-driver, key-input-engine, gesture-engine, terminal-view, line-row} [design]
ansi/scroll-driver → ansi/display-model, ansi/terminal-model     [design]
ansi/key-input-engine → ansi/key-composer, ansi/terminal-model   [design]
ansi/key-composer → ansi/terminal-model                          [design]
ansi/gesture-engine → ansi/terminal-model, terminal_zoom(既存・import なし) [design]
ansi/terminal-view → ansi/overlays, ansi/line-row, ansi/display-model [design]
ansi/terminal-view → ansi/{terminal-model, scroll-driver, gesture-engine} [inferred: props の型参照]
ansi/line-row → ansi/display-model, ansi/terminal-model          [design]
```
**unchanged survivors（4）**
```
terminal(P4) → fb/root, ansi/facade, settings (L76/L79/L78)  [existing]
keys         → home/tab-provider (案B・import 1 行変更)      [design]
```

`TERM → custom_keys_screen`（terminal L84）は P3 サブツリー外（`screens/custom_keys/`）の sink として省略。循環に寄与しない。

---

## 3. 条件別の検証結果

### (i) non-home → `home_screen`（シム）逆辺ゼロ: **OK（案B前提）**

- 設計どおり（案B: `conn/list → home/home_tab_provider.dart` 直接 import）では、screens サブツリー内に `→ home_screen.dart`（シム）の辺は**ゼロ**。
- 例外は `lib/main.dart`（`lib/screens/` 外）→ `home_screen.dart` のみで、これは現行どおりの正式な入口。
- **条件付き**: 案Bは `keys_screen.dart`（L9）と `settings/widgets/settings_search_field.dart`（L6）の **import 1 行を `home/home_tab_provider.dart` へ変更**することを前提にする。これら 2 ファイルは **P3 の 8 対象外**であり、P3 実装時に「対象外ファイルの import 1 行変更」が発生する点をリーダーは明示的に管理する必要がある（BRIEF の「対象ファイル以外は触らない」との整合を要確認）。
- **案A（シム経由維持）を選ぶと循環が発生する（重要）**: シミュレーション結果
  ```
  === 案A（シム経由・循環維持案） ===
  non-trivial SCCs=1
  SCC(size=4): home/root (IndexedStack), home/shim (re-export), conn/list (shell), conn/shim (thin re-export)
  ```
  つまり `home/shim → home/root → conn/shim → conn/list → home/shim` の 4 ファイル SCC。**markdown を直しても、案A では循環が残る**。シェル設計書の既定は案B であり、**案B の採用が循環回避の必要条件**。
- 参考（現行 HEAD ベースライン）: `SCC(size=2): conn, home`（`home_screen.dart ⇄ connections_screen.dart` の既知循環）。案B はこの循環を現行より 1 段浅くする（シムの相互参照を解消）。

### (ii) markdown `body ⇄ screen` 同時存在: **違反（NG）**

`shell-and-panes.md` §2.3 の依存記述は**自己矛盾**している:
- 同節は「`markdown_preview_screen.dart` → `markdown_preview/markdown_preview_screen.dart` → `markdown_preview_body.dart`」（screen impl が body を import）と明記。
- 続けて「この `body → 実装クラスの import` で循環は生じない（**screen 実装は body を import しない**。シムが双方を export）」と主張。
- しかし前者の矢印が示すとおり screen impl は body を import する（State の build を body へ委譲）。したがって `md/screen → md/body` と `md/body → md/screen` が同時に存在し、**SCC size=2** になる。タスク条件 (ii) の禁止事項そのもの。

`body → screen` が必要な理由（設計書どおり）: `markdown_preview_body.dart` が `MarkdownPreviewScreen.rawScrollKey` / `renderedScrollKey` を**クラス静的参照**するため。テストも同 static を参照する（実測）:
```
test/screens/file_browser/markdown_preview_screen_test.dart:246/251  find.byKey(MarkdownPreviewScreen.renderedScrollKey)
test/screens/file_browser/markdown_preview_screen_test.dart:270      find.byKey(MarkdownPreviewScreen.rawScrollKey)
lib/screens/file_browser/markdown_preview_screen.dart:40-41  static const Key rawScrollKey / renderedScrollKey（定義）
```

### (iii) `connection_card ⇄ sessions_panel` 相互辺: **OK**

辺は `conn/card → conn/panel` の一方向のみ（panel → card の辺なし）。設計書の状態所有権表でも panel は「表示部品（props 受領）」で card State が唯一の所有者。

### (iv) ansi 協調オブジェクト → ファサード逆向辺: **OK**

`ANSI_*`（協調オブジェクト 9 種）から `ansi/facade`（`ansi_text_view.dart`）への辺はゼロ。`ansi/facade` から各協調への一方向のみ。なお `TERM → ANSI_FACADE`（`terminal_screen.dart` L79）は P4 の既存辺（terminal_screen は協調オブジェクトではなくファサードの利用者）で、循環には寄与しない。

---

## 4. 検出した循環と推定修正案

### 循環 1（唯一・要修正）: markdown `screen impl ⇄ body`

- 対象設計書: `shell-and-panes.md`（v2）§2.3 markdown
- 辺: `markdown_preview/markdown_preview_screen.dart → markdown_preview_body.dart`（build 委譲）＋ `markdown_preview_body.dart → markdown_preview_screen.dart`（static key 参照）
- **推定修正案（static key の中立化 / task 指示どおり）**:
  1. 新規 `screens/file_browser/markdown_preview/markdown_preview_keys.dart` に中立トークンを置く（例: `abstract final class MarkdownPreviewKeys { static const Key raw = Key('mdScrollRaw'); static const Key rendered = Key('mdScrollRendered'); }`）。
  2. `body` は `markdown_preview_keys.dart` のみを import（`body → keys`）。
  3. `md/screen` の `MarkdownPreviewScreen.rawScrollKey` / `renderedScrollKey` は**同値を forwarder として維持**（`static const Key rawScrollKey = MarkdownPreviewKeys.raw;` 等）し、`screen → keys` を持つ。**テストの `MarkdownPreviewScreen.rawScrollKey` 参照は不変**（既存テスト差分ゼロ維持）。
  4. これで `screen → body → keys` / `screen → keys` となり、`body → screen` の逆辺が消える。
- **修正シミュレーション証跡**（`dag_verify_fix_sim.py` / `dag_run_fix_sim.txt`）:
  ```
  nodes=51, edges=78
  trivial SCCs=51, non-trivial SCCs=0
  VERDICT: non-trivial SCC 検出: なし
  ```
  すなわち上記の 3 手（中立ファイル新設・body は中立のみ参照・screen は forwarder 維持）で**循環は完全に解消**し、他に新たな循環は生じない。

### 循環 2（回避策の選択で顕在化・要確認事項）: home/conn シム 4 ファイル SCC（案A のみ）

§3(i) のとおり。既定の案B を採用すれば発生しない。**設計書の既定が案B であること、および案A を選ぶと SCC が出ることを実装時に厳守**すること。

---

## 5. 除外した循環（指示どおり）

- `lib/services/backend/domain/pane_content_reader.dart ⇄ pane_frame_reader.dart`（実測: 相互 import）。P3 対象外の services のため除外。ただし `ansi_display_model` が `pane_frame_reader` を import する設計であり、この既知循環に接続する。P3 の分割自体は循環を増やさない（新規逆向辺なし）が、**将来 ansi 側から pane 系を見直す際の注意点**として記録。
- `lib/l10n/app_localizations*.dart`（gen-l10n 生成物）・`lib/services/herdr/herdr_protocols.g.dart`（生成物）は node から除外。

---

## 6. 実装フェーズへの申し送り（要点）

1. **必須**: markdown の static key を中立ファイル化し、`body → screen` を消す（§4 循環 1）。`shell-and-panes.md` を v3 として改訂し、依存グラフを `screen → body` / `screen → keys` / `body → keys` に修正。§2.3 の「screen 実装は body を import しない」という矛盾記述も訂正。
2. **必須**: home 側は **案B**（`home/home_tab_provider.dart` 直接 import）を採用。案A は 4 ファイル SCC を生む（§3(i) のシミュレーション）。connections 設計 v2（§6-6）と shell 設計 v2（§2.1）は既に案B で整合済み。
3. **注意**: 案B は P3 対象外の `keys_screen.dart` / `settings/widgets/settings_search_field.dart` の import 1 行変更を伴う。対象外ファイルへの最小変更として実装計画に明記すること（変更しない場合は non-home → home シムの逆辺が残る）。
4. **注意**: 設計書の `terminal_zoom` 依存は `lib/screens/terminal/widgets/terminal_zoom.dart`（実在・import なしの葉）を指す。`services/terminal/` には存在しない（設計書の所在表記は不正確）。循環には影響しない。
5. 参考: ansi の協調オブジェクト→ファサード逆向辺ゼロ、card→panel 一方向、providers/services→screens 逆向辺ゼロ（sink 前提）は実測で確認済み。**markdown 以外に循環はない**。

---

## 7. 限界（事実と推定の区別）

- **事実**: SCC の算出結果、現行コードの import（行番号付き）、sink 前提（`rg` 実測）、テストの static key 参照、pane 系の相互 import、`terminal_zoom.dart` の実在と import ゼロ。
- **推定（要実装時確認）**: 設計書に import 明記のない辺（`notif/card → notif/flag-style`、`md/body → md/code-block`、`ansi/terminal-view → scroll-driver/gesture-engine` の型参照）は、移設マッピングと props 契約から推定した。これらは循環の成否に影響しない（いずれも末端方向の辺）。実装時に `flutter analyze` と本スクリプトの再実行で確定すること。
- 設計書の版が v2 のため、タスク指示が想定した v3（static key 中立化済み）での再検証は未実施。v3 が作成された場合は本スクリプトに v3 の辺を反映して再実行すれば、同じ手順で判定できる。

---

# v3 再検証（タスク#15・循環参照 再検証）

> **前回（タスク#14・v2 時点）の判定: NG（markdown screen⇄body の 1 件）→ `connections-screen.md`（v3）と `shell-and-panes.md`（v3）が改訂済み。全 5 設計書を改めて検証。**
> 本節は v2 検証の結果（上記 §0〜§7）を残したまま追記する。

## v3-0. 判定（結論）

| 項目 | 判定 | 証跡 |
|---|---|---|
| (c) screens 配下の非自明 SCC >= 2 ゼロ | **OK（循環ゼロ）** | curated: 52 node / 79 edge → SCC 0 件。独立全実グラフ: 316 node / 830 edge → screens SCC 0 件 |
| (a) non-home → `home_screen`（シム）逆辺ゼロ | **OK** | `home_screen.dart` への inbound は `main.dart`（screens 外）のみ。3 逆辺は中立モジュールへ再ターゲット済み |
| (b) markdown `body ⇄ screen` 解消・`body → 中立 keys` のみ | **OK** | `markdown_preview_body.dart → markdown_scroll_keys.dart` のみ。`body → screen` の辺は存在しない |
| (d) ansi / form / browser（+connections/home/notification/markdown）に逆向辺なし | **OK** | グループ別 grep で逆辺ゼロ（エビデンス §v3-4） |
| 対象外 SCC（l10n 生成物・services/pane） | 除外 | 理由は §v3-5 |

**結論: P3 の 5 設計書（v3 反映）の改修後 import グラフは screens 配下で相互循環なし（DAG）。** 前回の NG 項目（markdown）は解消されている。

## v3-1. v3 で検証した変更（2 設計書）

- **connections-screen.md（v3）・必須A〜C**:
  - A: `currentTabProvider` の参照先を **中立モジュール `lib/navigation/current_tab_provider.dart`（新設）への直接 import** に変更（home シム経由禁止）。connections 配下の全ファイルは `home_screen.dart` を import しない。
  - B: 実装順序（中立モジュール新設 → connections 改修）を強制し、常に SCC 消滅状態で進める。
  - C: §2.4 に connections サブツリーの import 辺リスト全 16 本を新設（card⇄panel の型依存なし等を明示）。
- **shell-and-panes.md（v3）・項目 A〜C**:
  - A: `CurrentTabNotifier`/`currentTabProvider` を `lib/navigation/current_tab_provider.dart`（中立・screens 非依存）へ抽出。home_screen.dart シムは中立を re-export（main.dart 不変）。
  - B: markdown の static ScrollKey を **中立 `markdown_preview/markdown_scroll_keys.dart` へ抽出**。`MarkdownPreviewScreen.rawScrollKey/renderedScrollKey` は中立 const への**静的 getter** として残し、テストのクラス静的参照を維持（const 正準化で identity 一致）。
  - C: 改修後 import グラフ全辺リストと Python/Tarjan 検証（`scc_verify_v3.py`）を §0b に添付。

## v3-2. 検証方法（独立 3 系統）

1. **キュレーション版**（v2 検証のグラフを v3 へ更新）: `/tmp/p3-design/dag_verify_v3.py`（52 node / 79 edge、設計書の依存記述 + 現行 import 実測）。
2. **独立・全実グラフ版**: `/tmp/p3-design/scc_fullscreen_v3.py` — 作業ツリー `lib/**/*.dart` の import を自作パーサで抽出し、v3 の仮想変換（①3 逆辺の除去＋中立再ターゲット ②home シム/実装/ナビ への分割 ③markdown 3 ファイル化）を適用して Tarjan SCC を計算。配布スクリプト `scc_verify_v3.py` は**参照せずに独立実装**。
3. **配布スクリプト（突合）**: `python3 scc_verify_v3.py`（shell 設計者作成物）→ 出力 `/tmp/p3-design/scc_v3_output_recheck.txt`。結果は 2 と一致。

**PRE ベースライン（作業ツリー実測・未改修）**: スクリプト 2 は現行の **screens size=10 SCC**（connections/dashboard/home/keys/notifications/settings×3/terminal）と、除外対象 2 件（l10n size=3・pane size=2）を再現。ユーザー指摘「相互循環参照」の実体（home への逆辺 3 本による 10 ファイル SCC）を**検証者の独立スキャナでも再現**してから POST を計算している（スキャナ妥当性の担保）。

## v3-3. 実行結果（証跡・要約）

### PRE（未改修・実測）

```
size=10 [screens]: screens/connections/connections_screen.dart, screens/dashboard/dashboard_screen.dart,
        screens/home_screen.dart, screens/keys/keys_screen.dart, screens/notifications/notification_panes_screen.dart,
        screens/settings/category_list_view.dart, screens/settings/master_detail_view.dart,
        screens/settings/settings_screen.dart, screens/settings/widgets/settings_search_field.dart,
        screens/terminal/terminal_screen.dart
size=3 [out-of-screens]: l10n/app_localizations*.dart            （生成物）
size=2 [out-of-screens]: services/backend/domain/pane_content_reader.dart ⇄ pane_frame_reader.dart
```

### POST（v3 仮想グラフ・独立スキャナ）

```
nodes=316 edges=830
non-trivial SCCs = 2
  size=3 [out-of-screens]: l10n/app_localizations*.dart
  size=2 [out-of-screens]: services/backend/domain/pane_content_reader.dart ⇄ pane_frame_reader.dart
RESULT: screens 配下 SCC>=2: NONE (=DAG)
```

### curated（設計書ベース）

```
nodes=52 edges=79
trivial SCCs=52, non-trivial SCCs=0
VERDICT: non-trivial SCC 検出: なし
```

（実行ログ: `dag_run_v3_fullscreen.txt` / `dag_run_v3.txt` / `v3_conditions_evidence.txt`）

## v3-4. 重点確認（a）(b)（d）の実グラフ証跡

### (a) non-home → home_screen（シム）逆辺ゼロ

```
home_screen.dart への全 inbound: main.dart -> screens/home_screen.dart   （screens 外・アプリ入口のみ）
screens 配下 → home_screen.dart: （なし）

中立モジュールへの inbound（v3）:
  connection_list_screen.dart -> navigation/current_tab_provider.dart
  home/home_screen.dart        -> navigation/current_tab_provider.dart
  home_screen.dart             -> navigation/current_tab_provider.dart （シム re-export）
  keys_screen.dart             -> navigation/current_tab_provider.dart
  settings/widgets/settings_search_field.dart -> navigation/current_tab_provider.dart
```

→ connections / keys / settings_search_field の 3 逆辺が**中立モジュールへ再ターゲット**され、`home_screen.dart` への screens 内逆辺はゼロ。`main.dart` の `import screens/home_screen.dart`（HomeScreen エントリ）は正当（screens 外）で、v3 のシム re-export により**不変**。

### (b) markdown の screen⇄body 解消

```
markdown_preview_screen.dart(シム) -> markdown_preview/markdown_preview_screen.dart        （export）
markdown_preview_screen.dart(シム) -> markdown_preview/markdown_code_block.dart            （export）
markdown_preview/screen.dart(impl) -> markdown_preview_body.dart / code_block / scroll_keys
markdown_preview/body.dart         -> markdown_preview_code_block.dart / markdown_scroll_keys.dart
                                   （→ impl screen への辺は存在しない = 2-cycle 解消）
```

→ **`body → scroll_keys`（中立）のみ**。`body → screen` は存在しない。タスク条件「static key の中立化後は body→中立のみ」を満たす。

### (d) グループ内逆向辺（サブ → entry）ゼロ

```
connections サブ → connections_screen.dart       OK（なし）
form サブ → connection_form_screen.dart          OK（なし）
file_browser サブ → file_browser_screen.dart     OK（なし）
ansi 協調 9 → ansi_text_view.dart                OK（なし）
home/… → home_screen.dart                        OK（なし）
notifications/panes/… → notification_panes_screen.dart  OK（なし）
markdown_preview/… → markdown_preview_screen.dart        OK（なし）
```

curated 版のグループ別チェック（`dag_verify_v3.py`）も「内部逆向辺: なし（全グループ）」。ansi/form/browser/connections/home/notification/markdown の各グループで逆向き辺がないことは設計書の依存矢印と実グラフの両方で確認できた。

## v3-5. 除外対象（理由）

| 除外 | 理由 |
|---|---|
| `l10n/app_localizations.dart ⇄ app_localizations_{en,ja}.dart`（size=3） | gen-l10n（`.arb` から生成）の自動生成物。手編集禁止・P3 対象外。相互 import は生成器の特性。POST/ PRE とも同一で **P3 の変更では増減しない**ことを確認 |
| `services/backend/domain/pane_content_reader.dart ⇄ pane_frame_reader.dart`（size=2） | P3 対象外（P3 = `lib/screens`）。`ansi_display_model` が `pane_frame_reader` を import する設計は**逆向辺を新設しない**ため、この既知循環への追加はない。将来 pane 系を見直す際の注意点として §v3-6 に記録 |

これら以外に非自明 SCC は**存在しない**ことを 2 系統のスキャナで確認（curated ではそもそも非 screens を node 化しないため、実グラフ系でのみ検出・除外判定）。

## v3-6. 実装フェーズへの申し送り（v3 反映）

1. **ゲート（connections）**: connections サブツリー配下に `home_screen.dart` の import が存在しないこと（`rg "home_screen" lib/screens/connections/` = 0）を実装時に grep で確認。
2. **ゲート（中立モジュール）**: `lib/navigation/current_tab_provider.dart` は **screens を一切 import しない**（依存ゼロを維持。import が追加されると SCC が再発する可能性）。
3. **markdown 実装の要点**: `markdown_scroll_keys.dart` の値は **const Key** に保つ。`MarkdownPreviewScreen.rawScrollKey` 等は getter（`static Key get rawScrollKey => MarkdownScrollKeys.rawScrollKey;`）。const 正準化により `find.byKey(MarkdownPreviewScreen.rawScrollKey)`（テスト 3 箇所）は変更ゼロで通る。getter を非 const の生成値に変えると identity が崩れテストが落ちるため、**const 維持を実装レビューで確認**。
4. **対象外ファイルの import 1 行変更**: `keys_screen.dart`（L9）と `settings/widgets/settings_search_field.dart`（L6）の `import` を中立モジュールへ差し替える（P3 の 8 対象外への最小変更として実装計画に明記）。
5. **検証コマンド（既定どおり）**: `dart format --output=none --set-exit-if-changed .` / `flutter analyze` / `flutter test --exclude-tags=repro` / `git diff HEAD -- test/` 空 / `dart tool/generate_herdr_protocols.dart --check` / 本検証スクリプト再実行。
6. 実装後に本スクリプト（`scc_fullscreen_v3.py`）を実リポジトリに対して**変換なしで**実行し、screens SCC ゼロを最終確認するとよい（実装後は仮想変換が不要になる）。

## v3-7. 検証者自身のスキャナの自己修正（透明性）

独立スキャナ `scc_fullscreen_v3.py` の初版に 2 つの誤りがあり、修正した（いずれも結果を変える前に発見）。
- **誤り 1**: `connections/x.dart` のような「`./` 付きでない兄弟相対 import」を外部パッケージ扱いで落としていた → PRE の size=10 が検出できなくなっていた。スキーム（`dart:` / `package:` / `http:` 等）を持つものだけを外部扱いにするよう `resolve` を修正 → PRE size=10 を再現。
- **誤り 2**: POST 構築で「home_shim への全 inbound 除去」を行っていた（`main.dart → home_screen.dart` の正当な辺まで消した）→ `main.dart` 以外の source のみを対象に除去するよう修正。
修正後の PRE size=10（ユーザー指摘の実体）と POST screens SCC ゼロは、**配布スクリプト `scc_verify_v3.py` の出力と一致**（相互確認）。

## v3-8. 限界

- POST グラフは設計書の仮想変換を元にした**静的検証**。実際の実装内容（新ファイルの import が設計どおりか）は実装後の `flutter analyze` とスクリプト再実行で確定する（特に `ansi_terminal_view → scroll_driver / gesture_engine`、`notif/card → flag_style`、`md/body → code_block` の推定辺）。
- ansi / form / browser の 3 設計書は v2 のまま（v3 対象 2 書のみ改訂）。この 3 書に**逆向辺が新設されていない**ことは実グラフの grep で確認済み（§v3-4 (d)）。
- 配布スクリプトの PRE/POST の node 化方式（`part` の扱い等）は本検証と完全に同一ではない可能性があるが、**結論（screens SCC ゼロ / 除外 2 件）は両系統で一致**。

### 証跡ファイル一覧（`/tmp/p3-design/`）
- `dag_verify_v3.py` / `dag_run_v3.txt`（curated・設計書ベース）
- `scc_fullscreen_v3.py` / `dag_run_v3_fullscreen.txt` / `v3_post_edges.txt`（独立・実グラフベース全 830 辺）
- `v3_conditions_evidence.txt`（重点確認 (a)〜(d) の実グラフ証跡）
- `scc_verify_v3.py` / `scc_v3_output_recheck.txt`（配布スクリプト・突合）
- `head_baseline.py` / `dag_run_head_baseline.txt`（v2 時の最小ベースライン）
