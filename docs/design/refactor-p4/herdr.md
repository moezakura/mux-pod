# P4 設計書 v2: herdr 領域（`lib/screens/terminal/terminal_screen.dart` 分割）

- 対象ブランチ: `fix/refactor-many-lines` / HEAD: `bff0c13`（P3 完了状態）
- 対象ファイル: `lib/screens/terminal/terminal_screen.dart`（9,529 行 / import 80 本）
- 担当: **herdr**（BRIEF 領域表の 74 メンバ / 約 2,291 行）
- 本文の行番号はすべて `lib/screens/terminal/terminal_screen.dart` の実測値（`grep -n` ベース、メソッド先頭行）。
- **v2 の正**: 調停書 `/tmp/p4-design/arbitration.md`（§1 C3-C6・§3・§4・§5・§6・§7）と critique §1.1/§4/§5/§10 に従う。v1 と矛盾する記載は v2 が優先。

---

## v2 改訂サマリ（対応表）

| # | 指示 | v2 での対応 |
|---|---|---|
| 1 | C3 `_showHerdr{Workspace,Tab,Pane}Selector` / C4 `_showHerdrResizePaneChooser` を**自領域に一本化**（ui は残置取下げ） | §2/§3: herdr_selectors / herdr_resize に確保持。ui から受ける**起動 API 契約**を §4.2 に新設（`MultiplexerSheetHost`＝シート基盤＋`closeSelectorThen` 200ms・`mux-sel-*` Key・文言不変、`PaneChooserLauncher`＝ui アダプタ経由、起動コールバックは root 配線）。セレクタ本体は ui のシート基盤とは分離して自領域に置く |
| 2 | C5 `_HerdrLabelInputDialog` は **ui の独立 Dialog（public・ui 所有）** に一本化 | §2/§3: `lib/screens/terminal/ui/herdr_label_input_dialog.dart`（public `HerdrLabelInputDialog`）を ui 所有に移動。herdr_crud は **ui を import（一方向）** して使用。**両方 public 化禁止**・シムは export しない（元 private・テストは文言経由）→ §5・§6 に明記 |
| 3 | C6 `_herdrToBreadcrumb` は ui へ明渡し、自領域は `HerdrDisplayData` 提供のみ | §2/§3/§4: herdr 側の `toBreadcrumb` 廃止。変換は ui `terminal_breadcrumb.dart` の `buildHerdrBreadcrumb`（`HerdrDisplayData`＋`sessionName`＋l10n＋起動コールバック 3 本を引数）。herdr は型・notifier・純関数 `herdrPaneSegmentLabel` の提供のみ |
| 4 | dispose を arbitration §4 のフェーズ表（P0-P9）に落とし、bridge.reset（P1）と notifier.dispose（P8）を**別フェーズ**として区別 | §4.4: `HerdrController` の dispose を **3 メソッド分割**（`disposeBridge()`＝P1 / `disposeCaches()`＝P7 / `disposeNotifiers()`＝P8）して root State が各フェーズで呼ぶ表に変更。P8 の順序厳守（view → herdrDisplay → herdrPaneIndicator → latency） |
| 5 | 検証計画に SCC>=2 検証を追加 | §7: `/tmp/p3-design/scc_verify_v3.py`（同等）を新設ファイル全間＋シム逆 import 禁止対象に適用するステップを追加 |
| 6 | SnackBar 多重抑止は**追加しない**旨を明記（H4） | §1 / §6: herdr_messages と §6 に「HEAD と同一（多重抑止なし・文言/回数テスト保護）」を明記 |
| 7 | env 相互 import 禁止（herdr は session を import しない）を依存先列に明記 | §2 各ファイルの「依存先」列と §4.5 に明記（`HerdrEnv` は session-runtime を一切 import しない。session 側から herdr controller への一方向のみ） |
| 8 | 見積り 450 行超のファイルは分割先を事前記載 | §2: `herdr_controller.dart`（480 見積り）→ **`herdr_setup.dart` へ必須分割**。`herdr_selectors.dart`（460 見積り）→ **`herdr_selectors_commit.dart` へ必須分割**。分割先の責務・行内訳を事前記載 |

併せて対応: critique §10 herdr 推奨（H1 mutation 中 reconnect の安全記述 / H2 バッファ破棄 3 段契約）→ §6・§4.3 へ追加。arbitration §7（シム 1 経路 export）→ §5 へ反映。

---

## 1. 現状分析（事実）

### 1.1 トップレベル・herdr 型（クラス外）

| シンボル | 行 | 内容 |
|---|---|---|
| `enum HerdrSyncTargetPolicy` | L107-126 | `preserveCurrent` / `followBackendFocus`（TERM-ENUM-002・**公開必須**、テストが import、シム 1 経路 export ・arbitration §7） |
| `abstract interface class _TargetSource` | L163-176 | `String? get currentPaneId`。tmux 遅延委譲と herdr 固定 pane を抽象化（A9） |
| `_TmuxTargetSource` | L178-192 | tmux 実装（**session-runtime 側**） |
| `_HerdrTargetSource` | L194-207 | herdr 実装。`setPaneId` で切替コミット時に差し替え |
| `typedef _HerdrTargetIdentity` | L216-222 | record `({HerdrSnapshotCache cache, int epoch, String? paneId})`。A3改 エポック照合キー |
| `class _HerdrDisplayData` | L229-265 | workspaceLabel/workspaceId/tabId/tabLabel/paneId（不変・A9）。ブレッドクラム入力（**ui の変換関数が入力に使う**） |
| `class _HerdrPaneIndicatorData` | L271-281 | `(panes, activePaneId)`。右上ミニマップ描画データ |
| `class _HerdrResolvedTarget` | L287-311 | snapshot 解決結果 `(paneId, workspaceId, tabId, tabLabel)`（L-1 実値） |
| `_herdrTabIdFromPaneId` | L314-322 | pane ID から tab ID を best-effort 導出 |
| `_herdrPaneSegmentLabel` | L325-331 | ブレッドクラム用 'Pane N'（**ui の buildHerdrBreadcrumb が使用**・純関数） |
| `_herdrPaneLabel` | L336-343 | A10: セレクタ用表示名（cwd 優先 → 'Pane N'） |
| `_BreadcrumbData` | L348-377 | tmux / herdr 共通ブレッドクラム中間データ（**ui 所有**・C6） |

### 1.2 `_TerminalScreenState` 内 herdr フィールド（状態所有権インベントリ）

| フィールド | 行 | 型 | v2 での所有者 / 破棄 |
|---|---|---|---|
| `_herdrDisplayNotifier` | L481 | `ValueNotifier<_HerdrDisplayData?>` | herdr_controller / P8 `disposeNotifiers()` |
| `_herdrPaneIndicatorNotifier` | L486-489 | `ValueNotifier<_HerdrPaneIndicatorData?>` | herdr_controller / P8（display の次） |
| `_pendingTargetIdentity` | L511 | `_HerdrTargetIdentity?` | **root State フィールド（C9）**。値生成は herdr API。P7 で root が null 化 |
| `_bufferedTargetIdentity` | L536 | `_HerdrTargetIdentity?` | **view-input（C7）**。P7 で view-input が関与 |
| `_targetSource` | L661 | `_TargetSource?` | root/session がフィールド保持、**値生成・変更は herdr controller のみ**（arbitration §1.3） |
| `_herdrSnapshotCache` | L665 | `HerdrSnapshotCache?` | herdr_controller / P7 `disposeCaches()` |
| `_herdrFrameAdapter` | L671 | `HerdrAdapter?` | herdr_controller / P7 |
| `_herdrCaretReader` | L675 | `HerdrCaretSnapshotReader?` | herdr_controller / P7 |
| `_herdrCaretStatus` | L680 | `HerdrStatus?` | herdr_controller / P7 |
| `_herdrResizeBridge` | L688 | `HerdrResizeBridge?` | herdr_controller / **P1 `disposeBridge()`（先頭・単独フェーズ）** |
| `_backendKind` | L694 | `MultiplexerBackendKind` | session 所有（herdr は read-only） |
| `_herdrSwitchEventBufferSize` | L743 | `static const int`（64） | — |
| `_herdrSwitchEvents` | L744 | `List<String>`（リングバッファ） | herdr_controller / P7 で clear |

herdr 用テスト注入（`TerminalScreen` コンストラクタ、L414-451）: `initialPaneId`/`paneContentReader`/`herdrCacheClock`/`herdrCaretReader`。

### 1.3 メソッド一覧（行番号付き・責務別）

**A. エポック照合 / 監視（最小・A3改 / A8）**
- `_recordHerdrSwitchEvent` L752-761（呼出 38 箇所）
- `_captureHerdrTarget` L767-779 / `_isCurrentHerdrTarget` L784-793

**B. セッション確立・初回解決**
- `_setupHerdrSession` L1782-1836 / `_resolveHerdrPaneId` L1846-1906 / `_resolveHerdrPaneIdFromSnapshot` L1907-1957

**C. ポーリング例外・再解決・再接続**
- `_handleHerdrPollError` L2414-2440 / `_handleHerdrTargetNotFound` L2441-2478 / `_reResolveHerdrTargetAfterReconnect` L2491-2528（123 行）/ `_fetchHerdrSessions` L2541-2582

**D. mutation 後同期・ターゲット再解決（TERM-MUT-SYNC-001）**
- `_syncAfterHerdrMutation` L2614-2667 / `_resolveHerdrTargetFromSessions` L2678-2757 / `_findHerdrPane` L2758-2776 / `_herdrResolvedTargetOf` L2777-2802

**E. server-down / 終端 / SnackBar / mutation 失敗分類**
- `_handleHerdrServerDown` L2804-2816 / `_notifyHerdrTargetLost` L2817-2824 / `_suspendPollingAfterError` L2826-2832 / `_resumePollingAfterError` L2833-2839
- SnackBar 群 L2842-2903 / `_handleHerdrMutationError` L2904-2951

**F. 切替コミット・テストフック**
- `_switchHerdrTarget` L4080-4141（TERM-NAV-008・単一入口）
- `@visibleForTesting` フック 10 種: L4142 / L4148 / L4157 / L4163 / L4169 / L4176 / L4186 / L4193 / L4200 / L4206（**root State にフォワード維持**）

**G. ブレッドクラム変換 / セレクタ（C3・C6 の調停反映）**
- `_herdrToBreadcrumb` L4632-4648 → **ui へ明渡し（C6）**
- `_showHerdrWorkspaceSelector` L4664-4715 / `_showHerdrTabSelector` L4731-4807 / `_showHerdrPaneSelector` L4818-4926 → **自領域（C3）**
- `_herdrSelectorContext` L4931-4942 / `_herdrSelectWorkspace` L4943-4959 / `_herdrResolveWorkspaceTarget` L4963-4988 / `_resolveFocusedPaneFromSessions` L5001-5015 / `_herdrSelectTab` L5017-5036 / `_herdrSelectPane` L5039-5055 / `_herdrFindWorkspace` L5058-5070 / `_herdrFindWindow` L5073-5084
- `_setHerdrPaneIndicatorData` L5097-5120（CRITICAL-1）/ `_refreshHerdrPaneIndicatorFromCache` L5126-5141

**H. resize（C4・タスク①）**
- `_showHerdrResizePaneChooser` L5716-5751（**C4: 自領域**・ui アダプタ経由）/ `_handleHerdrResizePane` L5955-6027 / `_herdrContainerCells` L6030-6053 / `_herdrResizeOneAxis` L6054-6098 / `_herdrAdjacentPane` L6101-6138 / `_herdrOppositeDirection` L6139-6149 / `_handleHerdrResizeTerminal` L6167-6229

**I. pane/tab CRUD と label**
- `_confirmAndKillHerdrPane` L6917-6984 / `_killHerdrPane` L6994-7019 / `_renameHerdrPane` L7026-7039 / `_handleHerdrZoomPane` L7046-7059
- `_showHerdrRenameTabDialog` L7065-7088 / `_showHerdrCreateTabDialog` L7097-7115 / `_renameHerdrTab` L7120-7133 / `_createHerdrTab` L7145-7167 / `_confirmAndCloseHerdrTab` L7175-7236 / `_closeHerdrTab` L7244-7261
- `_HerdrLabelInputDialog`+State L8692-8824 → **ui 独立 Dialog（C5・自領域は import のみ）**

**J. 方向フォーカス / ナビゲーション判定（T18）**
- `_focusHerdrPaneDirection` L3808-3844 / `_herdrNavigableDirections` L3891-3917 / `_herdrHasAdjacentPane` L3918-3953 / `_herdrVerticalOverlap` L3954-3956 / `_herdrHorizontalOverlap` L3957-3959

**K. caret（Phase 4）・フレーム合成**
- `_resolveInjectedHerdrCaretReader` L1591-1599 / `_buildHerdrFrameReader` L1604-1614 / `_isHerdrCaretEnabled` L1616-1619 / `_readHerdrStatus` L1626-1627 / `_logCaretState` L1629-1637 / `_refreshHerdrStatus` L1639-1648 / `_setupProductionHerdrCaretReader` L1657-1707 / `_reconfigureHerdrCaretForSettings` L1709-1742 / `_herdrExecutablePath` L1744-1751

### 1.4 呼出元 / 呼出先（領域内外・実測・C3-C6 調停反映）

**領域外 → herdr（一方向・これがインターフェース契約の入力）**
- `_pollPaneContent`（session）L2228 `_captureHerdrTarget` / L2249 `_isCurrentHerdrTarget` / L2256 `_refreshHerdrPaneIndicatorFromCache` / L2391 `_handleHerdrPollError`
- `_onReconnectSuccess`（session）L1214-1230: `_recreatePaneReader` → `_reResolveHerdrTargetAfterReconnect` → 成功時 `_startPolling`
- `_recreatePaneReader`（session）L1538-1584: herdr キャッシュ/adapter/caretReader/bridge 再生成・`_frameReader = _buildHerdrFrameReader()`
- `_connectAndSetup`（session）L1301-1303: `_setupHerdrSession(client)`
- `_splitPane`（session）L5578-5587: herdr 分岐で `_syncAfterHerdrMutation` / `_handleHerdrMutationError`
- view-input: `_flushScrollSend` L2149/2152・`_sendScrollKey`/`_sendScrollText` L3739/3756（`_recordHerdrSwitchEvent`）・`_sendSpecialKey`/`_sendKeyData` L7479/7541（`isHerdrInvalidKey` → `_showHerdrInvalidKeySnackBar`）・`_loadHistoryForScroll` L2980（`_captureHerdrTarget`）・copy-mode 遷移 L2369（`_recordHerdrSwitchEvent`）
- ui: build L3370-3372（`_herdrDisplayNotifier`）・L3480-3482（`_herdrPaneIndicatorNotifier`）・L3490（indicator onTap → `_showHerdrPaneSelector` の起動を root 配線）・L3374（`_herdrToBreadcrumb`→**ui の `buildHerdrBreadcrumb` が受ける**）
- `didUpdateWidget`/設定リスナー: `_reconfigureHerdrCaretForSettings`（L981-1000）

**herdr → 領域外**
- `_switchHerdrTarget` → `_viewNotifier.copyWith` / `_hasInitialScrolled` / `_resetTerminalMode` / `_boostPolling`（root が Env コールバックとして注入）
- `_setupHerdrSession` → `ref.read(tmuxProvider.notifier).clear()` / `_recreatePaneReader()` / `_viewNotifier` / `_startPolling`（same）
- 全 mutation → `_can(...)`（`_paneWriter.capabilities`・session が Env 提供）
- セレクタ（C3） → ui のシート基盤（`MultiplexerSheetHost`・Env 注入）/ `mux-*` タイル（widgets/multiplexer_tiles.dart・P2 既存）/ `MultiplexerSheet` の起動後 `_scrollToBottomKey` 表示
- resize（C4） → ui の `PaneChooserLauncher`（アダプタ）
- label（C5） → **ui の `HerdrLabelInputDialog` を import**
- SnackBar Retry → `_resumePollingAfterError`（session が Env 提供・H4 多重抑止なし）

### 1.5 担当領域に固定挙動を課すテスト（実測・C 調停連動）

| テストファイル | 行数 | 検証内容（herdr 固定点） |
|---|---|---|
| `terminal_screen_herdr_test.dart` | 2785 | ① backend flow（tmux setup なし表示 / execPersistent ライブポーリング / 深い履歴チャネル / snapshot fetch 失敗の `[HerdrSwitch]` 記録 / 注入 reader / 同ターゲット切替 no-op（L-3））② **C3 セレクタ**（3 段の表示・即閉じ・mutation コマンド非発行 / T10 ハイライト FontWeight.bold＋`mux-sel-*` Key / H-1 同名ラベル ID 一致判定）③ T13 mutation UI 有効（SpecialKeysBar・`Not connected — viewing only` 非表示）④ Q-07 PaneKeyMap 受容/拒否キー ⑤ bug1 AutoFit ⑥ bug3 セレクタ再タップガード ⑦ bug4 scrollbackLines クランプ ⑧ indicator Phase 3（#8-#18: 2 pane 描画 / タップで Select Pane / 単一 pane 非表示 / zoom 中 rect / mutation 後同期反映 / 再接続更新 / layout なし非表示 / 非 0 起点 rect 正規化 / セレクタ切替更新）⑨ caret Phase 4 5 件 |
| `terminal_screen_herdr_cc_close_test.dart` | 315 | T17: C-c 確認なし即送信（`sendSpecialKeyForTesting('C-c')` → `herdr pane send-keys w1:p1 C-c`）/ 連鎖 close 確認（`Close Pane?` / `termClosePaneHerdrLast` / `termClosePaneHerdrLastBoth` 文言 / 再解決で終端通知） |
| `terminal_screen_herdr_epoch_test.dart` | 315 | A3改 3 件（in-flight 照合破棄 / スクロール中バッファ破棄（エポック++） / 深い履歴照合破棄）。2500ms pump 発火前提・`re-resolve succeeded` 確認 |
| `terminal_screen_herdr_mutation_sync_test.dart` | 1188 | T18 単一経路（force 再取得→ターゲット変化で切替 / 同一ならコミットなし / split・focus・rename・zoom・create tab・followBackendFocus フォールバック・rename tab・close tab・close 連鎖）+ T19 分類通知（`pane_not_found` →「Target pane disappeared. Re-synced.」+ 再同期 / `no_neighbor` →「No pane in that direction」/ server-down / 再同期不能の終端）。fixture 6 種 |
| `terminal_screen_herdr_mutation_ui_test.dart` | 1516 | T14 resize 2 段階（**C4**: 選択モーダル常表示・`Selected: /tmp (80x24)`・`terminal-resize-pane-w1:p1` Key・旧 UI 非表示・絶対値→相対換算 4/200 ・縮小は隣接成長・changed:false NoOp）/ T15 paste・画像・copy-mode 代替 / Q-02 split 配線 / N-T プレビュー（0.7 固定・オフセット rect）/ Q-05 tab CRUD（**C5**: New Tab 空欄・ラベル付き `--focus`・キャンセル・Rename・Close 連鎖）/ タスク① ターミナル全体 resize（`termResizeFailedHerdr`） |
| `terminal_screen_contract_test.dart` | — | TERM-ENUM-001 `ScrollModeSource.values` 順序 / TERM-SCREEN-002..003 復元入力 / 表示到達（HerdrSyncTargetPolicy は直接検証しないが mutation_sync L644 が import 必須） |
| `terminal_screen_follow_scroll_test.dart` / `terminal_screen_scroll_send_test.dart` | — | `switchHerdrTargetForTesting` / `herdrSwitchEventsForTesting` を root State 経由で使用 |

**テストが固定するリテラル**: ブレッドクラム `'Pane 1'`/`'lab-ws1'`/`'1: 1'`、cwd `/a` `/b` `/tmp` `/var`、シート `'Select Session/Window/Pane'`、`ValueKey('mux-sel-<kind>-<id>')`、ダイアログ `'Resize Pane'`/`'Estimated'`/`'Cols'`/`'Rows'`/`'80x24 (Standard)'`/`'Close Pane?'`/`'Close Tab?'`、SnackBar 英文。タイミング: シート +300ms・`_closeSelectorThen` 200ms・key overlay 1500ms・`_scrollToCaret` 100ms・適応型上限 2000ms・boost 50ms（**不変**）。

---

## 2. 目標構成

原則: `_TerminalScreenState` が合成ルートで `HerdrController`（コンポジション・has-a）を 1 個持ち、controller が herdr 領域の state を独占所有。依存方向は `root → herdr_controller →（herdr サブコーディネータ / herdr_types → services・ui 純関数・ports）` の一方向（循環 import 禁止・SCC=0）。private 型は素の public 化（principle 3）。

**env 相互 import 禁止（arbitration §6）**: `HerdrEnv` は session-runtime のファイルを**一切 import しない**。session 側 → herdr controller への一方向のみ許容。herdr は `ui（表示・純関数）/ ports / herdr 内部` のみ import（`session_runtime.dart`・`terminal_screen.dart` シムへの逆 import 禁止）。

| 新規ファイル | 責務（1 文） | 目安行数 | 公開シンボル | 依存先 |
|---|---|---|---|---|
| `lib/screens/terminal/target_source.dart` | 表示対象 pane ID 取得抽象（共有リーフ） | 25 | `abstract interface class TargetSource` | services |
| `lib/screens/terminal/herdr/herdr_types.dart` | herdr の純データ型・policy enum・表示名ヘルパー（**リーフ・4 領域から参照可**） | 250 | `HerdrSyncTargetPolicy` / `HerdrTargetSource` / `HerdrTargetIdentity` / `HerdrDisplayData` / `HerdrPaneIndicatorData` / `HerdrResolvedTarget` / `herdrTabIdFromPaneId` / `herdrPaneSegmentLabel` / `herdrPaneLabel` | target_source / multiplexer 系 / l10n（**ui の breadcrumb もここを参照**） |
| `lib/screens/terminal/herdr/herdr_messages.dart` | herdr 通知 SnackBar の仕様（文言・Retry 動作）と mutation 失敗分類。**多重抑止なし（HEAD 同等・H4）** | 120 | `herdrShowError` / `herdrShowMutation` / `herdrShowTargetNotFound` / `herdrShowInvalidKey` / `herdrShowNoop` / `class HerdrMutationErrorClassifier` | l10n / services（controller 非依存・Retry はコールバック引数） |
| `lib/screens/terminal/herdr/herdr_controller.dart` | herdr state の単一所有（notifier×2 / リングバッファ / cache / bridge）と切替・エポック照合・監視の窓口 | **≤450（480 見積り → §分割: `herdr_setup.dart` へ必須分割）** | `class HerdrController` / `class HerdrEnv` | herdr_types / herdr_messages / services / Riverpod / ui の `MultiplexerSheetHost`・`PaneChooserLauncher` を Env 経由（**session は import しない**） |
| `lib/screens/terminal/herdr/herdr_setup.dart` | セッション確立・初回解決・backend 再生成（`setupSession`/`resolvePaneId`/`resolvePaneIdFromSnapshot`/`rebuildAfterClient`） | 220 | `class HerdrSetupFlow`（controller の内部協調） | herdr_controller / herdr_types / herdr_caret |
| `lib/screens/terminal/herdr/herdr_sync.dart` | H5/T18 単一経路（mutation 後同期 / 再接続再解決 / target-not-found / server-down / fetch 共有）とターゲット再解決 | 420 | `class HerdrSyncFlow` | herdr_controller / herdr_types / herdr_messages |
| `lib/screens/terminal/herdr/herdr_selectors.dart` | workspace/tab/pane セレクタのシート内容構築（**C3 自領域**）。表示は ui の `MultiplexerSheetHost` へ委譲 | **≤450（460 見積り → §分割: `herdr_selectors_commit.dart` へ必須分割）** | `class HerdrSelectorPresenter` | herdr_controller / herdr_types / ui（シート基盤のみ Env） |
| `lib/screens/terminal/herdr/herdr_selectors_commit.dart` | 選択コミット（select workspace/tab/pane とターゲット解決）＋ `_setHerdrPaneIndicatorData` / `_refreshHerdrPaneIndicatorFromCache` | 160 | `class HerdrSelectorCommitter` | herdr_controller / herdr_types |
| `lib/screens/terminal/herdr/herdr_resize.dart` | pane 選択モーダル（**C4 自領域**）＋ 絶対値→相対換算 resize ＋ ターミナル全体 resize（hidden TUI bridge） | 330 | `class HerdrResizeFlow` | herdr_controller / PaneResizeMath / **ui の `PaneChooserLauncher`（アダプタ）** / HerdrResizePaneDialog・HerdrResizeTerminalDialog（P2 既存） |
| `lib/screens/terminal/herdr/herdr_crud.dart` | pane/tab の CRUD（close/rename/zoom/create/close tab）と確認ダイアログ | 400 | `class HerdrCrudFlow` | herdr_controller / herdr_messages / **ui の `HerdrLabelInputDialog`（import・C5）** |
| `lib/screens/terminal/herdr/herdr_navigation.dart` | 2 本指スワイプ方向フォーカスと layout 隣接判定（純関数） | 150 | `herdrNavigableDirections` / `herdrHasAdjacentPane` / `herdrOppositeDirection` | services/herdr_models |
| `lib/screens/terminal/herdr/herdr_caret.dart` | caret reader / frame reader / status / executablePath の合成ファクトリ | 200 | `class HerdrCaretComposer` | services/herdr（caret・frame reader） |

**ui 側に新設される受注ファイル（自領域は依存側のみ）**: `lib/screens/terminal/ui/herdr_label_input_dialog.dart`（public `HerdrLabelInputDialog`・**C5 の唯一の定義**・ui 所有）、`lib/screens/terminal/ui/terminal_breadcrumb.dart` 内 `buildHerdrBreadcrumb`（**C6**）、`MultiplexerSheetHost`（シート基盤＋`_closeSelectorThen` 200ms）、`PaneChooserLauncher`（C4 用アダプタ）。

**シム化**: `terminal_screen.dart` はロジックゼロの thin re-export シム（root State は §4.4 の dispose フェーズ統括・テストフックフォワード・build 合成のみ）。`export 'herdr/herdr_types.dart' show HerdrSyncTargetPolicy;` は**シムの唯一の export 経路**（arbitration §7・他設計で再定義しない）。import パス不変（24 test + 4 lib）。

**450 行超の事前分割（arbitration §5）**:
- `herdr_controller.dart`（自己計測 ≈ 480: B 165 + F 61 + A 21 + 監視 9 + dispose 3 メソッド + ヘッダ）。**必須分割**: 「B セッション確立・初回解決・backend 再生成」を `herdr_setup.dart`（≈220）へ。残り ≈260。
- `herdr_selectors.dart`（自己計測 ≈ 460: 3 セレクタ 51+75+108 + context 11 + commit 系 16+19+16 + resolve 25+14 + find 12+11 + indicator 23+15）。**必須分割**: 「選択コミット・ターゲット解決・indicator setter/refresh」を `herdr_selectors_commit.dart`（≈160）へ。残り ≈300。
- 実装時 `wc -l` で 450 超過を再検証（§7・commit 時）。

---

## 3. 移動マッピング

凡例: 【移】= 移動のみ（public 化） / 【改】= 移動 + interface 適応 / 【渡】= 他領域へ明渡し（自領域の所有取下げ）

| 行範囲 | メンバ | 移動先 | 区分 |
|---|---|---|---|
| L107-126 | `HerdrSyncTargetPolicy` | herdr_types（シム 1 経路 export） | 移 |
| L163-176 | `_TargetSource`→`TargetSource` | target_source（共有リーフ） | 移 |
| L178-192 | `_TmuxTargetSource` | session-runtime | 渡 |
| L194-207 | `_HerdrTargetSource`→`HerdrTargetSource` | herdr_types | 移 |
| L216-222 / L229-265 / L271-281 / L287-311 | `_HerdrTargetIdentity`/`_HerdrDisplayData`/`_HerdrPaneIndicatorData`/`_HerdrResolvedTarget` | herdr_types | 移 |
| L314-343 | `_herdrTabIdFromPaneId`/`_herdrPaneSegmentLabel`/`_herdrPaneLabel` | herdr_types（**ui の breadcrumb が `herdrPaneSegmentLabel` を参照**・C6） | 移 |
| L478-489 | `_herdrDisplayNotifier`/`_herdrPaneIndicatorNotifier` | herdr_controller | 移 |
| L511 | `_pendingTargetIdentity` | **root State フィールド（C9）・値生成は herdr API** | 改 |
| L536 | `_bufferedTargetIdentity` | view-input（C7） | 渡 |
| L665-693 | cache/adapter/caretReader/caretStatus/bridge | herdr_controller（`HerdrResizeBridge` の reset は P1） | 移 |
| L743-744 / L752-793 | リングバッファ / `_recordHerdrSwitchEvent` / `_captureHerdrTarget` / `_isCurrentHerdrTarget` | herdr_controller（`recordSwitchEvent`/`captureIdentity`/`isCurrentIdentity`） | 移 |
| L1782-1957 | `_setupHerdrSession`/`_resolveHerdrPaneId`/`_resolveHerdrPaneIdFromSnapshot` | herdr_controller →（450 超分割）**herdr_setup** | 改 |
| L2414-2528 | `_handleHerdrPollError`/`_handleHerdrTargetNotFound`/`_reResolveHerdrTargetAfterReconnect` | herdr_sync | 改 |
| L2541-2582 | `_fetchHerdrSessions` | herdr_sync | 移 |
| L2614-2667 | `_syncAfterHerdrMutation` | herdr_sync（`syncAfterMutation`） | 移 |
| L2678-2802 | `_resolveHerdrTargetFromSessions`/`_findHerdrPane`/`_herdrResolvedTargetOf` | herdr_sync（**全呼出元が herdr 専用のため本領域・v1 で根拠済み**） | 移 |
| L2804-2839 | server-down / 終端 / suspend / resume | herdr_sync（polling 制御は Env.suspend/resumePolling） | 改 |
| L2842-2903 | SnackBar 群 | herdr_messages | 移 |
| L2904-2951 | `_handleHerdrMutationError` | herdr_messages（`classifier`・後続は戻り値/コールバック） | 改 |
| L4080-4141 | `_switchHerdrTarget` | herdr_controller（`switchTarget`・`onLiveReset`/`boostPolling` を Env 化） | 改 |
| L4142-4208 | `@visibleForTesting` フック 10 種 | **root State にフォワード維持** | 改 |
| L4632-4648 | `_herdrToBreadcrumb` | **ui `terminal_breadcrumb.dart` `buildHerdrBreadcrumb`（C6・【渡】）**。自領域は `HerdrDisplayData`・`herdrPaneSegmentLabel` 提供のみ。起動コールバック 3 本は引数で受ける | 渡 |
| L4664-4926 | `_showHerdrWorkspaceSelector`/`Tab`/`Pane` | **herdr_selectors（C3 自領域・ui 残置取下げ）**。シート表示は ui の `MultiplexerSheetHost` を Env 注入 | 改 |
| L4931-5084 | `_herdrSelectorContext`/select/resolve/find | herdr_selectors + herdr_selectors_commit | 移 |
| L5097-5141 | `_setHerdrPaneIndicatorData`/`_refreshHerdrPaneIndicatorFromCache` | herdr_selectors_commit | 移 |
| L5716-5751 | `_showHerdrResizePaneChooser` | **herdr_resize（C4 自領域）**。`PaneChooserDialog` へは ui の `PaneChooserLauncher` 経由 | 改 |
| L5955-6229 | `_handleHerdrResizePane` 他 resize 5 + `_handleHerdrResizeTerminal` | herdr_resize | 改 |
| L6917-7261 | CRUD 10 メンバ | herdr_crud | 移 |
| L8692-8824 | `_HerdrLabelInputDialog`+State | **ui `herdr_label_input_dialog.dart`（C5・public 唯一・【渡】）**。herdr_crud から import。**両方 public 化禁止・シム export しない** | 渡 |
| L3808-3959 | `_focusHerdrPaneDirection` 他 nav 5 | herdr_navigation | 移 |
| L1591-1751 | caret / executablePath ファクトリ | herdr_caret（`_recreatePaneReader` が `composer.buildFrameReader(...)` を呼ぶ） | 移 |

**BRIEF 境界の修正（根拠付き・v1 継続）**: ① `_resolveHerdrTargetFromSessions`/`_findHerdrPane`/`_herdrResolvedTargetOf` は全呼出元が herdr 専用のため本領域へ移動。② `_captureHerdrTarget`/`_isCurrentHerdrTarget`/`_recordHerdrSwitchEvent` は poll・view・send パスから呼ばれるため controller の公開 API として screen が呼ぶ。③ `_suspendPollingAfterError`/`_resumePollingAfterError` は `_pollingSuspended`/`_pollTimer` が root/session にあるため **Env コールバックで提供**。

---

## 4. インターフェース契約（最重要）

### 4.1 自領域が所有する state（単一所有・二重所有なし）

| state | 所有者 | 破棄フェーズ | 備考 |
|---|---|---|---|
| `HerdrTargetSource`（paneId） | herdr_controller | P7（`disposeCaches()` で参照解除・screen の `_targetSource=null` は root） | 値の変更は `switchTarget` のみ |
| `ValueNotifier<HerdrDisplayData?>` | herdr_controller | **P8（`disposeNotifiers()`・display 先）** | ui は root 経由で value を購読 |
| `ValueNotifier<HerdrPaneIndicatorData?>` | herdr_controller | **P8（display の次）** | 同上 |
| `HerdrSnapshotCache` / `frameAdapter` / `caretReader` / `caretStatus` | herdr_controller | **P7（`disposeCaches()`）** | 再生成は `HerdrSetupFlow.rebuildAfterClient` |
| `HerdrResizeBridge?` | herdr_controller | **P1（`disposeBridge()`・先頭かつ単独）** | lazy start・managed PTY close |
| リングバッファ（64 件） | herdr_controller | **P7** | `disposeCaches()` で clear（現 L3337 相当） |
| _pendingTargetIdentity / _pendingCaret | **root State（C9・調停済み）** | P7（root が null 化） | **値生成・照合は herdr API** |
| _bufferedTargetIdentity（C7） | view-input | P7（view-input） | 破棄判定 `isCurrentIdentity` は herdr API（H2） |

### 4.2 他領域から受ける props / コールバック

| 入力 | 提供元 | herdr での用途 |
|---|---|---|
| `WidgetRef ref` | root（コンストラクタ注入） | settings / tmuxProvider.clear / ssh client / terminalDisplay |
| `String? Function() sessionId/sessionName/initialPaneId/lastPaneId` | root（widget props） | 初回解決・決定順 |
| `VoidCallback recreateReaders / resetTerminalMode / boostPolling / startPolling` | root/session | setup・switch・sync 末尾 |
| `VoidCallback suspendPolling / resumePolling` | root/session | server-down / 終端 / SnackBar Retry（**H4: 多重抑止なし**） |
| `VoidCallback onLiveReset` | root/session | view クリア＋`_hasInitialScrolled=false`（現 `_switchHerdrTarget`/`_setupHerdrSession` の副作用を集約・衝突回避） |
| `bool isMounted / isDisposed` | root | 全 async ガード（HEAD と等価） |
| **C3 起動 API**: `MultiplexerSheetHost`（ui 所有・abstract。`show(...)`＝現 `_showMultiplexerSheet`＋`SelectorContent`。**`_closeSelectorThen` の 200ms はこの Host の実装が保持**） | **ui** | herdr 3 セレクタは Env 経由で起動（`mux-sel-*` Key・文言は呼出側のタイル/引数で不変） |
| **C4 起動 API**: `PaneChooserLauncher`（ui 所有アダプタ・`PaneChooserDialog` の showDialog をラップ） | **ui** | `_showHerdrResizePaneChooser` は Env/import 経由で使用 |
| **C5 Dialog**: `HerdrLabelInputDialog`（ui 所有・public） | **ui** | herdr_crud が import（一方向・両方 public 化禁止） |
| **C6 変換入力**: `buildHerdrBreadcrumb` が `HerdrDisplayData`＋`herdrPaneSegmentLabel`＋起動コールバック 3 本を受ける | ← ui から root 配線 | herdr は型・純関数提供のみ。**ui → herdr controller の import は発生しない**（起動は root がコールバック接続） |

### 4.3 他領域へ提供する API（公開・ルート/他領域が呼ぶ）

| API | 提供先 | 用途 |
|---|---|---|
| `Future<void> setupSession(SshClient client)` | root `_connectAndSetup` | 初回確立 |
| `Future<bool> reResolveAfterReconnect()` | root `_onReconnectSuccess` | true なら root が `_startPolling` |
| `void handlePollError(Object e)` | root `_pollPaneContent` catch | 種別分岐 |
| `HerdrTargetIdentity? captureIdentity()` / `bool isCurrentIdentity(id?)` | root poll・view update・**view-input（C7 バッファ破棄判定）** | **H2 3 段契約: 「view-input が呼ぶ・herdr API が判定・session が破棄」** |
| `Future<void> refreshPaneIndicatorFromCache()` | root poll | 現 `_refreshHerdrPaneIndicatorFromCache` |
| `PaneFrameReader? rebuildAfterClient(SshClient)` | root `_recreatePaneReader` | cache/adapter/caret/bridge 再生成（herdr_setup） |
| `void recordSwitchEvent(String)` | root poll・view-input（scrollSend/copy-mode） | 現 `_recordHerdrSwitchEvent` |
| `Future<bool> syncAfterMutation({eventLabel, policy})` | root `_splitPane` 分岐・herdr_crud/resize/navigation | 現 `_syncAfterHerdrMutation` |
| `void switchTarget(paneId, {...})` | herdr 内部 + root（セレクタ起動のコールバック先） | 現 `_switchHerdrTarget`（表示変更の副作用は Env 経由） |
| `showWorkspaceSelector()/showTabSelector()/showPaneSelector()` | **root → ui 配線**（breadcrumb onXxxTap / indicator onTap / menu） | C3 の起動点は ui にあるが**本体は self 領域**・root がコールバックで接続 |
| `showResizePaneChooser(sessions, window)` | root/ui（pane セレクタヘッダー・タイル⋮からの起動） | C4・ui の起動導線から Env 経由 |
| `HerdrDisplayData? get display` / `HerdrPaneIndicatorData? get indicator` | root→ui（ValueListenableBuilder） | notifier の value |
| `@visibleForTesting` フック 10 種 | test（`tester.state(...)`） | **root State フォワード** |

### 4.4 dispose フェーズ表（arbitration §4 準拠・root State が統括）

| フェーズ | root State の動作 | **herdr controller の対応メソッド** |
|---|---|---|
| P0 | `_isDisposed = true` | — |
| **P1** | `herdr.disposeBridge()`（**先頭・単独**） | `disposeBridge()`: `unawaited(_herdrResizeBridge?.reset()); _herdrResizeBridge = null;`（現 L3298-3299） |
| P2 | removeObserver / Wakelock 解除 | — |
| P3 | ProviderSubscription 4+transfer 2 | — |
| P4 | poll/tree タイマー停止 | — |
| P5 | scrollSend / keyOverlay タイマー | — |
| P6 | autoResize / background タイマー・`_restoreResizedWindows`（deactivate 経路含む） | — |
| **P7** | `herdr.disposeCaches()` ＋ root が `_pendingTargetIdentity` を null ＋ view-input がバッファ null | `disposeCaches()`: `_herdrSnapshotCache=null; _herdrFrameAdapter=null; _herdrCaretReader=null; _herdrCaretStatus=null; _herdrSwitchEvents.clear();` |
| **P8** | `session.disposeView()` → `herdr.disposeNotifiers()` → `session.disposeLatency()`（**順序厳守**） | `disposeNotifiers()`: `_herdrDisplayNotifier.dispose(); _herdrPaneIndicatorNotifier.dispose();`（現 L3340-3341 ≒ view→herdrDisplay→herdrPaneIndicator→latency を root が統括） |
| P9 | root ScrollController dispose → `super.dispose()` | — |

- **bridge.reset（P1）と notifier.dispose（P8）は別メソッド・別フェーズ**（critique §4.2 解消）。`HerdrController.dispose()` を 1 本にまとめない。

### 4.5 依存規則（循環防止・arbitration §6）

- `HerdrEnv`（controller の注入 bundle）は **session-runtime を import しない**。session 側 → herdr controller の一方向のみ。
- herdr の import 許可: `herdr 内部 / services / ui（表示・純関数・`MultiplexerSheetHost`・`PaneChooserLauncher`・`HerdrLabelInputDialog`）/ ports / target_source / l10n`。
- **禁止**: `terminal_screen.dart` シムへの逆 import・session_runtime への import・`*_env.dart` 相互 import。
- ui の breadcrumb は `herdr_types.dart`（リーフ）のみ import（ui → herdr controller は不発生・起動は root 配線のコールバック）→ SCC=0 を維持。

---

## 5. 公開 API 維持表

| 公開 API | 維持の根拠（実測） | 措置 |
|---|---|---|
| `enum ScrollModeSource`（L88） | contract `TERM-ENUM-001`（順序） | シム 1 経路 export（arbitration §7・他設計で再定義禁止） |
| `enum HerdrSyncTargetPolicy`（L107） | mutation_sync L644 import | **herdr_types が定義・シム 1 経路 export**（view-input/ui/session で再定義しない） |
| `class TerminalScreen`（L379） | 24 test + 4 lib・コンストラクタ 12 引数＋既定値（scaffold L163-173） | シムに本体存続・シグネチャ不変 |
| `DownloadSnackBarDisplay` / `downloadSnackBarDisplay`（L9472+） | terminal_download_snackbar 2 ファイルが import | ui の download_snackbar_display.dart・**シム export 忘れ禁止** |
| State `@visibleForTesting`（herdr 10 種＋他 6） | epoch/sync/ui/follow_scroll/scroll_send が `tester.state(...)` 動的呼出 | root State フォワード維持 |
| `HerdrLabelInputDialog` | 元 private（L8692）・テストは文言/dialog 操作のみで**名前参照なし** → シム export 不要 | **ui 所有のみ**（C5・両方 public 化禁止） |
| `_PaneLayoutPainter` runtimeType（`'_PaneLayoutPainter'`） | herdr test 7+ 箇所（L45/L1712/L2149-2174）が固定 | **ui 側**が新ファイル内 private のまま定義（typedef 禁止・arbitration §3） |

---

## 6. リスクと対策

1. **エポック照合の非同期ギャップ**（最上位）: `captureIdentity`→await→`isCurrentIdentity` の同一セマンティクス（`identical(cache)`+`epoch`+`paneId`）を維持。世代の再作成後も identity は不変オブジェクトのため照合安全。epoch バンプは cache 内在（services 不変）。
2. **mutation→reconnect の同時実行（H1）**: `_syncAfterHerdrMutation`/`_reResolveHerdrTargetAfterReconnect` は `_fetchHerdrSessions(force:true)` の await 中に相手が cache を作り直しても**常に「現在値」を読むため安全**。`_switchHerdrTarget` の最後勝ち順序も **HEAD と同一（回帰なし）** である旨を本設計の不変条件とする。`mounted`/`_isDisposed` ガード維持。
3. **バッファ破棄 3 段（H2）**: epoch テスト①②③（in-flight / スクロール中バッファ / 深い履歴）は C7 の move 先（view-input）に依存。契約は「view-input が `isCurrentIdentity` を呼ぶ・判定は **herdr API**・破棄は viewer」の 3 段とし、herdr API の実体（`captureIdentity`/`isCurrentIdentity`）は移動しない。
4. **C3/C4 の起動と文言**: `_closeSelectorThen` 200ms・bottomsheet 300ms・`mux-sel-*` ValueKey・`'Select Session/Window/Pane'`・`'Resize Pane'`/`'Selected: /tmp (80x24)'`・`terminal-resize-pane-*` Key は不変。セレクタ本体は自領域だがシートの表示/閉じは ui の `MultiplexerSheetHost`、chooser は `PaneChooserLauncher` に委譲（受け側の責務に含める）。
5. **C5 の二重 public 化防止**: `HerdrLabelInputDialog` は **ui の 1 ファイルのみ**定義。herdr_crud は import で使用。シムの export は行わない（元 private・テストは文言経由）。
6. **C6 の依存方向**: ui の `buildHerdrBreadcrumb` は `herdr_types.dart`（リーフ）しか import せず、セレクタ起動は**引数コールバック**で受ける（ui → herdr controller 逆辺を作らない）。`herdrPaneSegmentLabel` の 'Pane N' 生成は型ファイルの純関数そのまま使用。
7. **SnackBar 多重抑止（H4）**: 追加しない（HEAD 同等）。`_showHerdrErrorSnackBar`/`_showHerdrTargetNotFoundSnackBar`/`_showErrorSnackBar` の重複は仕様どおり許容。実装時に dedup を足すと文言/回数テスト（herdr UI・remaining_contracts）が壊れる。
8. **dispose 順序**: P1（bridge.reset）→ P7（cache/identity null）→ P8（notifier：display→indicator）を**別メソッド**で root が正順に呼ぶ。`_closeSelectorThen` の `Future.delayed` 後の `if (mounted && !_isDisposed)` ガード維持。
9. **UI 文言・タイマー不変**: v1 §1.5 のリテラル一覧（すべて）を変更しない。
10. **型 public 化の波及**: `_Herdr*` → `Herdr*` リネーム漏れ防止のため `grep -rn "_HerdrDisplayData\|_HerdrPaneIndicatorData" lib test` を検証（現状 terminal_screen.dart 内のみ）。

---

## 7. 検証計画

1. `dart format lib/screens/terminal/` + `flutter analyze`（`make analyze`）
2. herdr 担当テスト（C 調停後の移動先に連動）:
   ```
   flutter test test/screens/terminal/terminal_screen_herdr_test.dart \
     test/screens/terminal/terminal_screen_herdr_cc_close_test.dart \
     test/screens/terminal/terminal_screen_herdr_epoch_test.dart \
     test/screens/terminal/terminal_screen_herdr_mutation_sync_test.dart \
     test/screens/terminal/terminal_screen_herdr_mutation_ui_test.dart \
     test/screens/terminal/terminal_screen_contract_test.dart \
     test/screens/terminal/terminal_screen_follow_scroll_test.dart \
     test/screens/terminal/terminal_screen_scroll_send_test.dart
   ```
3. **SCC>=2 検証（arbitration §6・必須追加）**: `/tmp/p3-design/scc_verify_v3.py`（同等スクリプト）を新設ファイル全間に適用し、`SCC>=2`（循環 import）ゼロ・`terminal_screen.dart` シムへの逆 import ゼロ・`herdr` → `session` import ゼロを検証。CI 相当で全 4 設計共通実行。
4. `git diff HEAD -- test/` が空（回帰ゼロ）。
5. 領域間境界（session/view/ui）の v2 確定後に全体 `flutter test`（`make test`）。
6. `make build-apk`（keystore 不在で失敗するがコンパイル通過確認・AGENTS.md 注記）。
7. 移設後 `wc -l` で**全新設ファイル ≤450**（分割必須ファイル 2 本含む）を commit 時に検証。

---

## 8. 未確定点

- **なし**（本領域内は arbitration で確定済み）。

**要請（リードへ）**: ① ui の `MultiplexerSheetHost` / `PaneChooserLauncher` / `HerdrLabelInputDialog` / `buildHerdrBreadcrumb` の公開契約（シグネチャ）が ui.md v2 と一致すること（一致しなければ §4.2/§4.3 の当該行だけ再調整）。② `MultiplexerSheetHost` が `_closeSelectorThen`（200ms）を内包するか、herdr 側で持つかは **ui 所有**で固定する趣旨（自領域は Env 経由のみ）。③ root dispose フェーズ表（P0-P9）1 枚を lead が統合確定し、P7 の identity null（root=`_pendingTargetIdentity` / view-input=バッファ / herdr=自キャッシュ）の 3 主体が表に見えること。