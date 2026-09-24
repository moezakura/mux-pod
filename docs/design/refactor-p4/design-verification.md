# P4 設計 v2 独立検証レポート（読み取り専用）

- 検証者: p4-verifier（teammate #32）
- 対象入力: `/tmp/p4-design/{BRIEF,arbitration,critique,session-runtime,herdr,view-input,ui}.md`
- 対象コード: `lib/screens/terminal/terminal_screen.dart`（HEAD `bff0c136cc5cd506b39bbafb189a99a13a2cf1b7`・9,529 行）
- 判定: **条件付き OK（NG 1 件: 所有権マッピングの軽微な空白 3 メンバ）** — 詳細は §1 と §7
- スクリプト（本レポート同梱・`/tmp/p4-reports/`）: `extract_members.py` / `parse_claims.py` / `analyze_ownership.py` / `scc_verify.py` / `ownership_analysis.txt`

## 0. 検証系（実測インベントリ）

`_TerminalScreenState`（実測 L460-7878、BRIEF 記載 L7885 は閉括弧位置の誤差）から独自抽出した
全メンバは **292 個**（フィールド + メソッド + getter + static const + @visibleForTesting 転送フック含む。
BRIEF の「243 個（検出ベース）」とは検出方式の差：getter 10・static const 5・lifecycle 6・
@visibleForTesting 18 等の扱い違いと推定。以下、検証は 292 全件に対して実施）。
メンバ一覧 JSON: `members.json`。

---

## 1. 検証項目 1: 所有権の完全性（二重 claim ゼロ / 空白ゼロ）

### 1.1 二重 claim（所有権衝突）: 判定 **OK（ゼロ）**

4 設計書の §3 移動マッピング計 208 行（+ 各設計の §1.1/§1.2 所有権インベントリ）を機械突合した
（`parse_claims.py` → `analyze_ownership.py`）。複数設計が言及するメンバは以下のみで、
**いずれも調停済みパターン**（両設計が「同一の最終所有者」を指す）:

| メンバ | 設計 A | 設計 B | 整合性 |
|---|---|---|---|
| `_scrollToCaret`(C1) | session §3: 削除（view-input へ） | view-input §3.4: 移動 | ✓ 片方向委譲 |
| `_flushInputQueue`(C2) | session §3: 削除（view-input へ） | view-input §3.5: 移動 | ✓ |
| `_bufferedTargetIdentity`(C7) | herdr §3: 渡（view-input へ） | view-input §3.1: TerminalModeController | ✓ |
| `_hasInitialScrolled` | session §3/§1.2: session-runtime | view-input §3.4: 残置（明示的に session 側） | ✓ |
| `_applyBufferedUpdate`/`_applyUpdate` | session §3: session_poll | view-input §3.1/3.4: 残置（session 側） | ✓ |
| `_focusHerdrPaneDirection`/`_herdrNavigableDirections`/`_herdrHasAdjacentPane`/`_herdrVerticalOverlap`/`_herdrHorizontalOverlap` | herdr §3: herdr_navigation | view-input §3.7: 移設（他領域＝herdr） | ✓ |
| `_showHerdr{Workspace,Tab,Pane}Selector`(C3) | herdr §3: herdr_selectors | ui §3: 明渡し（herdr へ） | ✓ C3 の取り下げ反映 |
| `_showHerdrResizePaneChooser`(C4) | herdr §3: herdr_resize | ui §3: 明渡し（herdr へ） | ✓ |
| `_handleResizePane`/`_handleResizeWindow`(G1/G4) | session §3: session_resize | ui §3: 明渡し（session へ） | ✓ |
| G5/G6 転送系 5 メンバ | session §3: terminal_transfer_flow | ui §3: 明渡し（session へ） | ✓ |
| `_herdrToBreadcrumb`(C6) | herdr §3: 渡（ui へ） | ui §3: terminal_breadcrumb | ✓ |
| `_HerdrLabelInputDialog`+State(C5) | herdr §3: 渡（ui へ） | ui §3: herdr_label_input_dialog（唯一 public） | ✓ 両方 public 化なし |
| `_InputDialogContent`+State | view-input §3.6: 残置（ui） | ui §3: input_dialog_content | ✓ |
| `_pendingTargetIdentity`(C9) | herdr §3: root State フィールド（改） | session §1.2 / ui §2-2 / view-input §4.1: root | ✓ 表現統一 |

**二重 claim ゼロ**（最終所有者を 2 設計が同時に名指しするケースは存在しない）。

### 1.2 所有権空白: 判定 **NG（軽微）** — マッピング表に未記載 8 メンバ

§3 移動マッピング＋§1.1/§1.2 インベントリの**いずれにも明記されない**メンバ（292 件中）:

| メンバ | 行 | 設計書の言及 | 帰着先（文脈から一意） | 区分 |
|---|---|---|---|---|
| `_shouldFollowBottom` (getter) | 565 | view-input §1.1(D) L131 に列挙あり | view-input（`TerminalScrollFollowController`） | モノ申しなし → 実質カバー済み |
| `_getAuthOptions` | 3126 | session §4.3 API 表に `getAuthOptions` 記載 | session_connection | 契約表から帰着可 |
| `_selectSession` | 3995 | session §4.3 mutation コールバック＋ui §4-1 `onSessionSelected` | session_mutations | 同上 |
| `_selectWindow` | 4015 | 同上 `onWindowSelected` | session_mutations | 同上 |
| `_splitPane` | 5550 | herdr §1.4（`_splitPane`（session）L5578-5587）＋ui §4-1 `onSplitRequested` | session_mutations | 同上 |
| `_caretEquals` | 4331 | session §2 `session_models`「caret 値等価（caretEquals）」 | session_models | 目標構成から帰着可 |
| `_showRenameWindowDialog` | 6804 | **4 設計いずれにも言及なし** | session_mutations（tmux rename-window mutation・ui §4-1 に `onRenameWindow` のみ） | **真の空白** |
| `_renameWindow` | 6829 | **4 設計いずれにも言及なし** | session_mutations | **真の空白** |
| `_showErrorSnackBar` | 3150 | critique/herdr の H4 注記に名前のみ（所有権の記述なし） | session_runtime/connection（実測呼出は `_connectAndSetup` L1504/1512 のみ） | **真の空白** |

→ 「所有権空白ゼロ」を厳密には満たさない。ただし **8 件すべてが session-runtime 領域へ一意に帰属**でき、
設計意図と矛盾しない。**実装前修正必須（軽微）**：session-runtime v2 の §3 に 8 行を追記すること。

### 1.3 arbitration §1 C1-C9 / G1-G7 の 4 設計書への反映

| 項目 | session-runtime | herdr | view-input | ui | 判定 |
|---|---|---|---|---|---|
| C1 `_scrollToCaret` | §3 削除・§4.2 port 呼出 | —（無関係） | §3.4/§4.3 移設+guard 維持 | — | ✓ |
| C2 `_flushInputQueue` | §3 削除・§4.2 `input.flushInputQueue` | — | §3.5/§4.3 `flushInputQueue` | — | ✓ |
| C3 `_showHerdr*Selector` | §1.5 記載 | §3 herdr_selectors | — | §3 明渡し | ✓ |
| C4 `_showHerdrResizePaneChooser` | — | §3 herdr_resize | — | §3 明渡し | ✓ |
| C5 `_HerdrLabelInputDialog` | §1.5 記載 | §3 渡・§4.2 import 一方向 | — | §3 唯一 public | ✓ |
| C6 `_herdrToBreadcrumb` | §1.5 記載 | §3 渡 | — | §3 terminal_breadcrumb | ✓ |
| C7 選択バッファ 4 | §1.2/§4.2 capture/take | §3 `_bufferedTargetIdentity` 渡 | §3.1 TerminalModeController | — | ✓ 3 段契約 |
| C8 `_savedCommandInput` | §1.5 | — | §3.6/§4.1 | §4-4 撤回 | ✓ |
| C9 pendingTargetIdentity/Caret | §1.2 root・P7 | §3 root・P7 | §4.1 root 触らない | §2-2 root | ✓ |
| G1 `_executeAutoResize` | §3/§4.1 | — | §3.8（領域外） | §4-1（onResize 受領のみ） | ✓ |
| G2 `_restoreResizedWindows` | §3/§4.3 deactivate 経路 | — | — | §2-2（deactivate 委譲） | ✓ |
| G3 `_scheduleInitialAutoResize` | §3/§4.6 | — | — | — | ✓（呼出は接続フロー） |
| G4 `_handleResizeWindow` | §3 | — | — | §3 明渡し | ✓ |
| G5 転送系 | §3 terminal_transfer_flow・1 回登録 | — | §3.8 | §3 明渡し | ✓ |
| G6 `_ensureDownloadListener` | §3（ui 純関数 import） | — | — | §3 明渡し | ✓ session→ui 一方向 |
| G7 `_latencyNotifier` | §1.1/§4.1（poll 唯一書込・P8） | — | — | §1-2（read のみ） | ✓ |

→ 全 C/G が設計書へ反映済み（C1/C2/C3/C4/C5/C6/C7/C8/C9・G1-G7 すべて一致）。

---

## 2. 検証項目 2: 500 行制約 — 判定 **OK**

### 2.1 各設計の新設/変更ファイル推定行数（§2 目標構成・数値根拠どおりのまま集計）

| 設計 | ファイル数 | 合計 | 最大 | ≥500 | 450 超（分割先未記載） |
|---|---|---|---|---|---|
| session-runtime | 13 | 2,970 | **430**（session_runtime） | なし | なし（session_runtime の分割スロット #5 session_view_pipeline を**事前定義**） |
| herdr | 12 | 3,175 | **450**（herdr_controller） | なし | herdr_controller ≤450（480 見積→ **herdr_setup.dart へ必須分割** §5）・herdr_selectors ≤450（460 見積→ **herdr_selectors_commit.dart へ必須分割** §5） |
| view-input | 9 | 1,770 | **340**（terminal_key_sender） | なし | なし |
| ui | 14 | 3,630 | **450**（shim） | なし | shim ≈450（450 超時フォールバック: `terminal_root_bindings.dart`/`terminal_test_hooks.dart` を**事前定義** ui §2-2） |

→ **500 行以上のファイル: ゼロ**。450 行超（等）ファイルはすべて分割先を事前記載済み
（arbitration §5 の条件付き分割禁止に準拠）。ui `pane_layout_visualizer` の必須 2 分割
（`pane_layout_painter.dart` + `pane_layout_visualizer.dart`）も §2-1 に記載 ✓。

### 2.2 root State（terminal_screen.dart シム）残置合計の検算: **500 未満**

ui §2-2 の内訳合計を検算: 25+80+30+20+50+15+70+45+90+25 = **450 行 < 500**。
独立再計算（arbitration §2 の限定スコープ × 実測行数）: TerminalScreen widget L379-458（80）+
State 残置フィールド（keys 4・`_isDisposed`・C9 2 値・subscription 4・`_terminalScrollController` ≈11）+
initState(20)/deactivate(19)/dispose(57=P0-P9 統括)/build 縮小(≈90)/テストフック転送 18 本(≈45)+
imports/exports(≈25) ≈ **347 行 < 500**（いずれの計算法でも余裕あり）。

---

## 3. 検証項目 3: 循環（SCC>=2）— 判定 **OK**

新設ファイル間グラフを 4 設計書の「依存先」列から構築し Tarjan SCC を実行
（`scc_verify.py`・グラフ `graph.json`）。

```
=== SCC 検出 ===
num SCCs: 49, cycles (size>=2): 0        ← 循環なし
```

個別確認:
- **(a) 新ファイル → terminal_screen.dart（シム）の逆 import: 0 件**（全設計の依存先にシムなし）
- **(b) herdr → session の import: 0 件**（`herdr_*` は `session/` を一切 import しない。
  herdr §4.5 の「*_env.dart 相互 import 禁止」「session は import しない」と一致。
  session → herdr は一方向: session_poll/session_connection → herdr_controller）
- **(c) herdr_crud → ui(HerdrLabelInputDialog): 一方向**（`herdr_crud -> [herdr_controller, herdr_messages, ui/HerdrLabelInputDialog]`。
  ui → herdr_crud/controller の逆 import **0 件**。ui が import する herdr 系はリーフ `herdr_types` のみ = C6 §4.5 で明示許可）
- **(d) session → ui: `terminal_transfer_flow → download_snackbar_display` のみの一方向**
  （他 session ファイルから ui への import 0 件。ui → session controller の逆 import 0 件:
  root のコールバック結線のみ）

依存の向き `ui ← session-runtime → ports ← view-input` および `herdr → ports / ui(純関数) / herdr 内部` を満たす。

---

## 4. 検証項目 4: 公開 API 維持 — 判定 **OK**

| 公開シンボル | 実測（HEAD） | 設計の維持策 |
|---|---|---|
| `TerminalScreen` コンストラクタ | 実測 12 引数: `key`/`connectionId`(required)/`sessionName`/`sessionId`/`lastWindowIndex`/`lastPaneId`/`deepLinkWindowName`/`deepLinkPaneIndex`/`paneContentReader`/`initialPaneId`/`herdrCacheClock`/`herdrCaretReader` | シム本体に存続・シグネチャ不変（4 設計書 §5 全て一致）。lib 呼出元 4（main/connection_list/dashboard/notification_panes）+ test 21 ファイルがシム import を継続 |
| `enum ScrollModeSource` | 値順: `none, manual, tmux`（TERM-ENUM-001） | view-input `terminal_input_mode.dart` が**唯一の定義**・シム export 1 経路（他設計で再定義禁止） |
| `enum HerdrSyncTargetPolicy` | 値順: `preserveCurrent, followBackendFocus`（TERM-ENUM-002） | herdr_types が**唯一の定義**・シム export 1 経路 |
| `DownloadSnackBarDisplay` / `downloadSnackBarDisplay` | L9472/9487（外部参照ゼロ・内部使用） | ui `download_snackbar_display.dart` へ移動・シム export 1 経路（session §2 も明記） |
| State テストフック | 実測 18 本（@visibleForTesting）: 4 scroll/mode + 10 herdr + 4（loadHistory/can/paneCapabilities/sendSpecialKey） | 全設計: root State フォワード維持（herdr 10・view-input 6・session 2・ui 0）。※ 設計書の「16 本」表記は実測 18 本と 2 本差（`canForTesting`/`paneCapabilitiesForTesting` が未計上）— 見積行数のみの誤差で API 維持には影響なし |
| `_PaneLayoutPainter` runtimeType `'_PaneLayoutPainter'` | herdr test 7+ 箇所が固定 | ui §5: 新ファイル内 **private のまま**定義・typedef 禁止（arbitration §3） |

→ シムからの export 経路は 4 公開シンボル（＋ 補助）で **1 本化**（仲裁 §7 統制）。

---

## 5. 検証項目 5: dispose フェーズ表の整合 — 判定 **OK**

HEAD dispose 実測（L3292-3348）: `_isDisposed=true` → bridge.reset → removeObserver/Wakelock →
subscription 4+2 close → poll/tree cancel → scrollSend/keyOverlay(P5) → autoResize/background(P6) →
herdr cache + C9 + buffer null + ring clear(P7) → notifier view→herdrDisplay→herdrPaneIndicator→latency(P8) →
scrollController.removeListener+dispose → super(P9)。**4 設計書の枠組み（P0-P9）と完全一致**:

| フェーズ | arbitration §4 | session-runtime §4.5 | herdr §4.4 | view-input §4.4 | ui §4-3 | 判定 |
|---|---|---|---|---|---|---|
| P0 | `_isDisposed=true` | root | root | root | root | ✓ |
| P1 | herdr bridge.reset（先頭） | herdr | `disposeBridge()`（単独） | herdr | `herdr.disposeBridge()` | ✓ |
| P2 | removeObserver/Wakelock | root+`session_lifecycle.detach()` | root | root | root | ✓ |
| P3 | subscription 4 + transfer 2 | root: `transferFlow.disposeSubscriptions()`+4 close | root | root | `session.closeSubscriptions()` | ✓ |
| P4 | poll/tree 停止 | `sessionRuntime.cancelPollTimers()` | session | session | `session.disposePollers()` | ✓ |
| P5 | scrollSend/keyOverlay | view-input | view-input | `input.disposeTimers()`（scrollSend+keySender+keyOverlayState） | `view.disposeTimers()` | ✓ |
| P6 | autoResize/background | `sessionResize.cancelResizeTimers()` | session（+G2 deactivate 経路） | session | `session.disposeResizeTimers()` | ✓ |
| P7 | herdr cache/identity/resolved null 化 | herdr `disposeCaches()`+root C9 null | 同 | 同 | `herdr.clearResolved()` | ✓ |
| P8 | notifier: view→herdrDisplay→herdrPaneIndicator→latency | P8a→P8b→P8c | 順序厳守 | 順序厳守 | 順序厳守 | ✓ |
| P9 | ScrollController dispose → super | root | root | `scrollFollow.detach()`→root | root | ✓ |

- bridge.reset（P1）と herdr notifier（P8）の分離: herdr §4.4 に明記（`HerdrController.dispose()` 1 本化しない）✓
- G2 deactivate 経路: session §4.3（`unawaited(restoreResizedWindows().then(...))` L3282-3289 同型）・ui §2-2 に契約記載 ✓
- P8 で latency が末尾（G7）: 3 設計とも「view → herdrDisplay → herdrPaneIndicator → latency」順 ✓

---

## 6. 所見・軽微な不整合（重大でないもの）

1. **所有権空白 3 メンバのマッピング追記（必須・軽微）**: `_showRenameWindowDialog`/`_renameWindow`/
   `_showErrorSnackBar` + 契約表由来 5 メンバ（`_getAuthOptions`/`_selectSession`/`_selectWindow`/`_splitPane`/`_caretEquals`）を session-runtime v2 §3 へ明記。8 件の最終帰属先は一意（session 領域）で設計競合なし。
2. **テストフック数の表記**: 設計書「16 本」vs 実測 18 本（`canForTesting`/`paneCapabilitiesForTesting` 未計上）。API 維持・フォワード方針に影響なし。
3. **BRIEF/arbitration の行番号ズレ**: class 終端 7885→実測 7878・`didUpdateWidget` は HEAD に存在しない（設定リスナー配線は `_setupListeners` 内）。設計内容への影響なし。
4. **ui 提供 API の命名ギャップ（軽微）**: herdr §2/§4.2 は ui 所有の `MultiplexerSheetHost`/`PaneChooserLauncher` を Env 経由で受けると明記するが、ui.md §2-1 のファイル一覧・§4-2 の提供 API にこの 2 型への明示的な言及がない（機能上は `selector_launch` の `showMultiplexerSheet`/`showResizePaneChooser` 相当が対応）。herdr 側と ui 側でホスト型名を揃える追記を推奨（依存方向には影響なし: herdr → ui 一方向・SCC=0）。
4. **記載どおりの前提**: `_ensureDownloadListener`（session §3 行）の帰属は session（ui 純関数 import）で一意。6 種 SnackBar 多重抑止なし・既定タイマー値（200ms/300ms/1500ms/2000ms/50ms/100ms）は全設計で不変と明記。

## 7. 総合判定

| 項目 | 判定 |
|---|---|
| 1. 所有権（二重 claim ゼロ） | **OK** |
| 1. 所有権（空白ゼロ） | **NG（軽微）** — 8 メンバ未記載（3 は真の空白、5 は契約表から帰着可）。すべて session 領域へ一意帰属 |
| 2. 500 行制約（全ファイル <500・root 残置 <500・450 超の分割先記載） | **OK** |
| 3. SCC>=2（新設グラフ・シム逆辺 0・herdr→session 0・herdr_crud→ui 一方向・session→ui 一方向） | **OK** |
| 4. 公開 API 維持（12 引数・enum 順・DownloadSnackBar・フック・シム export 1 経路） | **OK** |
| 5. dispose P0-P9（bridge reset=P1 / notifier=P8 順序・session P4/P6・view-input P5・G2 deactivate） | **OK** |

**全体: NG 1 件（軽微・追記で解消）— 実装着手可（session-runtime v2 §3 へ 8 メンバの追記を先行推奨）**

## 8. 成果物・実行方法

```
/tmp/p4-reports/verify.md               … 本レポート
/tmp/p4-reports/extract_members.py      … メンバ抽出（python3 extract_members.py → members.json）
/tmp/p4-reports/parse_claims.py         … 設計書マッピング claim 抽出（→ claims.json）
/tmp/p4-reports/analyze_ownership.py    … 二重 claim / 空白判定（→ ownership_analysis.txt）
/tmp/p4-reports/scc_verify.py           … Tarjan SCC 検証（サイクル 0・逆辺 0 を出力）
/tmp/p4-reports/members.json / claims.json / ownership.json / graph.json / ownership_analysis.txt
```