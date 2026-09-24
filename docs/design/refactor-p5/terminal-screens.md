# P5 設計書 v2: test/screens/terminal の herdr / scrollSend テスト群（担当: 500 行超 4 ファイル）

対象 4 ファイル: `terminal_screen_herdr_test.dart`(2785) / `terminal_screen_herdr_mutation_ui_test.dart`(1516) / `terminal_screen_herdr_mutation_sync_test.dart`(1188) / `terminal_screen_scroll_send_test.dart`(591)。合計 6,080 行・**実測テスト件数 120 件**（全テスト成功を実実行で確認済み・exit 0）。

## v2 改訂サマリ（critique.md §1・§2・§5 対応）

| # | critique 指摘 | v2 対応 |
|---|---|---|
| 必須 1-1 | `_pumpHerdrTerminal`（file3 L170-196・27 行・19 テストが使用）の移動先が未定義 | H2 へ `pumpHerdrTerminal` として収容。§2.1 H2 リスト・§3 移動マッピング・§4 に明記。file3 由来 3 本の `setUp(SharedPreferences.setMockInitialValues)` 再現＋参照更新を 1 項目化 |
| 必須 1-2 | `paneIndicatorPainter`（file1 L45-47・3 行）の移動先が未定義（G1-29 と G6 全 11 件の 2 ファイルで使用） | H2 へ `paneIndicatorPainter()` として収容。§2.1・§3 に明記 |
| 必須 2-1 | H1 行数見積り（約 300 行）が実測と乖離 | 実測ベースで H1 を **H1a/H1b の 2 ファイルに分割**。各ファイルの実測行数と 500 行未満の担保を §2.1 に明記 |
| 推奨 軽微1 | §2.3 の G1 内訳記述が混線 | 「9+4+8+4+4(G1)+1(G4)」形式へ修正 |
| 推奨 軽微2 | private→public 化の書き換え範囲・衝突チェックが無い | §4 に H2 公開名一覧と新ファイル内ローカル名との衝突チェックを追記 |
| 推奨 軽微3 | rename fixture 値不変の機械 diff が無い | §5 に「rename fixture 値の機械 diff」を追加 |
| 推奨 §5 | テスト本体行 diff（verbatim 移動検証）・parity import 差し替え順序 | §5 に追加。EXIT=0 / fail 0 も明記 |

（v1 からの残り内容は同一。行番号・件数は critique 実測と照合済み。リポジトリ編集はしていない。）

---

## 1. 現状分析（事実）

### 1.1 共通の基盤ヘルパー（既存 `test/helpers/` の再利用状況）

| 既存ヘルパー | 内容 | 使用ファイル |
|---|---|---|
| `test/helpers/terminal_test_scaffold.dart` | `TerminalTestScaffold.pumpTerminalScreen`（L114 定義）・`FakeImageTransferNotifier`（L80 定義・**既に `terminal_parity_pump.dart` L204 と重複定義**） | 4 ファイル全て |
| `test/helpers/fake_ssh_client.dart` | `FakeSshClient`（`execCommands`/`execPersistentCommands`/`execOutputs`/`execOutputQueues`/`execExitCodes`/`sendKeysCommands`/`setConnected` 等） | 4 ファイル全て |
| `test/helpers/fake_ssh_notifier.dart` | `FakeSshNotifier`（`reconnectCalls`/`onReconnectSuccess`/`onDisconnectDetected`） | file1 / file3 |

→ 既存ヘルパーは再利用済みで重複追加の必要なし。`FakeImageTransferNotifier` の二重定義は P5 前からの既存事実（`terminal_test_scaffold.dart` 経由で使用、P5 で増やさない）。

### 1.2 対象ファイル間・他ファイルとの依存関係（事実）

- `terminal_screen_herdr_test.dart` L21-27 が **`terminal_screen_herdr_mutation_ui_test.dart` を import**（`show kHerdrTwoPaneLayoutSnapshotFixture, kHerdrThreePaneLayoutSnapshotFixture`）。
- `terminal_screen_herdr_parity_test.dart` L17 も **`terminal_screen_herdr_mutation_ui_test.dart` を import**（`show kHerdrTwoPaneLayoutSnapshotFixture`）→ 本ファイル以外にも結合あり。
- 上記以外で `kHerdrSnapshotFixture` 等を参照する他ファイル（`terminal_screen_can/follow_scroll/cc_close/epoch`、`connections_screen_herdr`、`pane_content_reader`、`repro_bug3` 等）は**全て自前コピー**で、本 4 ファイルから import していない（`grep -c "const kHerdrSnapshotFixture"` = 1 を各ファイルで確認）。
- メタデータ: 4 ファイルとも `@Tags` / `@Skip` / `@Timeout` / 先頭 doc コメントの特殊タグは**一切なし**。`setUp` は file3 のみ（L199 `SharedPreferences.setMockInitialValues({})`）。group のネストなし。

### 1.3 file1: `terminal_screen_herdr_test.dart`（2,785 行・**実測 57 件**）

**トップレベル定義（L1-456）**: import L1-27（他テストファイル import 含む）／ `herdrSwitchEvents` L33-38 ／ `paneIndicatorPainter` **L45-47**（使用: G1-29 M2 regression の L1712 と G6 全 11 件 L2149/2168/2187/2212/2222/2381/2403/2418/2457/2503/2532）／ `_ReResolvePropagationReader`（fake, class）L56-86 ／ snapshot fixture 13 本:
`kHerdrTwoPaneNoLayoutSnapshotFixture` L80・`kHerdrSnapshotFixture` L102・`kHerdrSnapshotWithLayoutFixture` L121（**120x24**、参照は L1887=G3-1 / L2210=G6#10 / L2668=G7-3 の 3 箇所のみ）・`kHerdrSnapshotZoomedFixture` L143・`kHerdrSnapshotPane2Fixture` L163・`kHerdrEmptySnapshotFixture` L180・`kHerdrSameLabelSnapshotFixture` L190・`kHerdrTwoWorkspaceSnapshotFixture` L219・`kHerdrLabeledTabSnapshotFixture` L247・`kHerdrMinNormalizeSnapshotFixture` L266・`kHerdrZoomedTwoPaneSnapshotFixture` L297・`kHerdrIndicatorResizeSnapshotFixture` L329・`kHerdrTallLayoutSnapshotFixture` L376 ／ `_herdrConnection()` L357 ／ Phase4 caret 用: `_FakeHerdrCaretReader` L399・`_caretAt` L420・`inTextViewCaret` L440・`caretSeen` L450 ／ `main()` L456。

| group 名（変更不可） | 行範囲 | 行数 | テスト数 | 主な共有物 |
|---|---|---|---|---|
| `TerminalScreen herdr (backend flow / display)` | 457-1715 | 1,259 | **29** | `kHerdrSnapshotFixture` 他 6 本・`paneIndicatorPainter`・`_ReResolvePropagationReader`・`herdrSwitchEvents` |
| `TerminalScreen herdr mutation enabled (T13)` | 1716-1877 | 162 | **5** | `kHerdrSnapshotFixture` |
| `TerminalScreen herdr AutoFit (bug1)` | 1878-1963 | 86 | **3** | `kHerdrSnapshotWithLayoutFixture`(→後述 rename)・`kHerdrSnapshotZoomedFixture` |
| `TerminalScreen herdr セレクタ再タップガード (bug3)` | 1964-2003 | 40 | **1** | `kHerdrTwoWorkspaceSnapshotFixture` |
| `TerminalScreen herdr スクロールバック (bug4)` | 2004-2120 | 117 | **3** | `kHerdrSnapshotFixture`・`AppSettings` |
| `TerminalScreen herdr pane indicator (Phase 3)` | 2121-2546 | 426 | **11** | 8 fixture（`kHerdrTwoPaneLayoutSnapshotFixture` 等は file2 から import）+ group 内ローカル助関数 `pumpHerdrForIndicator`/`panePainterOf`/`paintedRects`・`TestRecordingCanvas`(flutter_test) |
| `TerminalScreen herdr caret (Phase 4)` | 2547-2785 | 239 | **5** | `kHerdrTallLayoutSnapshotFixture` 等・group 内 local `caretOnSettings`＋トップレベル caret 助関数 |

group 内テスト一覧（L は testWidgets 開始行、テスト名は原文のまま）:
- G1-1 L458 `shows pane content without tmux setup` ／ G1-2 L503 `ライブポーリングは持続的シェル経由（execPersistentCommands）で取得される（バグ2…）` ／ G1-3 L533 `深い履歴は exec チャネル経由で取得され、行数は scrollbackLines と整合する（…バグ2 / バグ4）` ／ G1-4 L570 `sessionId disambiguates same-label workspaces (tmp w3/w4 pattern)` ／ G1-5 L608 `sessionId not in snapshot falls back to same-label workspace resolution` ／ G1-6 L637 `legacy sessionId-null entry on empty snapshot shows the error and records diagnostic events (…)` ／ G1-7 L673 `snapshot fetch failure (HerdrCommandException) records diagnostic events with errorCode/exitCode` ／ G1-8 L714 `snapshot fetch failure (HerdrTargetNotFoundException) records diagnostic events with kind/errorCode` ／ G1-9 L749 `uses an injected paneContentReader when provided`
- G1-10 L776 `breadcrumb shows workspace label, tab segment, and pane segment (A9 display state / T11)` ／ G1-11 L809 `T4: tab segment tap opens the selector at the tab stage (stage 2)` ／ G1-12 L834 `T4: pane segment tap opens the selector at the pane stage (stage 3)` ／ G1-13 L858 `M-4: tab segment shows the snapshot-resolved tab label (not a number)`
- G1-14 L878 `monitors server-down detection in the [HerdrSwitch] ring buffer (A8/T5b)` ／ G1-15 L910 `monitors target-not-found detection in the [HerdrSwitch] ring buffer (A8/T5b)`
- G1-16 L937 `switch commit updates display state and polling target without mutation (A4/T6)` ／ G1-17 L989 `switch to the same target is a no-op (L-3: no flicker)` ／ G1-18 L1019 `server-down stops polling, shows SnackBar with retry, no reconnect (A2/T7)` ／ G1-19 L1084 `target-not-found re-resolves via forced snapshot and switches pane (A2/T7)` ／ G1-20 L1143 `re-resolve propagates the snapshot tabId/workspaceId into the display state (T3)` ／ G1-21 L1199 `target-not-found terminal: re-resolve failure stops polling without reconnect (A2/T7)`
- G1-22 L1266 `herdr reconnect re-resolves the target from a fresh snapshot and keeps polling without tmux tree refresh (T9a)` ／ G1-23 L1338 `herdr reconnect to the same pane keeps the display without a switch (T9a)` ／ G1-24 L1388 `herdr lifecycle: resume restarts polling after server-down suspension without tmux tree refresh (T9b)` ／ G1-25 L1455 `herdr lifecycle: dispose cleans up snapshot cache and ring buffer without exceptions (T9b)`
- G1-26 L1487 `T10 selectors (workspace → tab → pane) each close on selection and switch the displayed pane via the single commit without mutation` ／ G1-27 L1586 `T10 selectors highlight the current display target as initial emphasis (workspace/tab/pane)` ／ G1-28 L1659 `H-1 same-label workspaces (tmp w3/w4 pattern) highlight only the sessionId-matched workspace in the session selector` ／ G1-29 L1708 `M2 regression: tmux では pane indicator が表示される`
- G2-1 L1717 `mutation UI is enabled: SpecialKeysBar shown, no disconnected banner` ／ G2-2 L1738 `special key tap routes accepted keys via PaneKeyMap to send-keys (Q-07 ①)` ／ G2-3 L1771 `special key tap routes rejected keys via PaneKeyMap to send-text escape (Q-07 ②)` ／ G2-4 L1805 `special key tap routes control characters via PaneKeyMap to send-text (Q-07 ③)` ／ G2-5 L1842 `defensive invalid_key notification is shown when send-keys rejects a key`
- G3-1 L1879 / G3-2 L1911 / G3-3 L1937（AutoFit の pane rect・zoom・fallback 80）／ G4-1 L1965（再タップガード）／ G5-1 L2005 / G5-2 L2036 / G5-3 L2073（scrollbackLines・クランプ・末尾アライン）
- G6: #8 L2161 / #9 L2178 / #10 L2207 / #11 L2217 / #12 L2232 / #12b L2297 / #13 L2343 / #14 L2394 / #18 L2411 / #17 L2445 / #19 L2476（pane indicator）
- G7-1 L2556 / G7-2 L2596 / G7-3 L2656 / G7-4 L2690 / G7-5 L2732（caret）

### 1.4 file2: `terminal_screen_herdr_mutation_ui_test.dart`（1,516 行・**実測 28 件**）

**トップレベル定義（L1-403）**: import L1-16 ／ fixture 6 本: `kHerdrSnapshotWithLayoutFixture` L31（**80x24**・file1 同名 L121 とは値が異なる ※衝突）・`kHerdrResizedSnapshotFixture` L54（94x39）・`kHerdrResizeUnchangedFixture` L76・`kHerdrTwoPaneLayoutSnapshotFixture` L87（200x70・**file1/parity から import される**）・`kHerdrThreePaneLayoutSnapshotFixture` L118（L字）・`kHerdrNewTabActiveSnapshotFixture` L158 ／ `_herdrConnection()` L181 ／ pump 系ヘルパー `_pumpHerdrAndOpenPaneSelector` L194・`_pumpHerdrAndOpenTabSelector` L221・`_pumpHerdrAndOpenWorkspaceSelector` L288 ／ fake `_UiFakeManagedPty` L248・`_StartPtyResizeClient` L273 ／ 対話ヘルパー `_tapHeaderResizeAndOpenChooser` L318・`_tapChooserResize` L329・`_tapResizeDialogAndConfirm` L342・`_amountOf` L378・`_hasResizeCommand` L388 ／ `main()` L403。

| group 名（変更不可） | 行範囲 | 行数 | テスト数 | 主な共有物 |
|---|---|---|---|---|
| `T14: herdr resize 2段階フロー（選択モーダル→絶対値ダイアログ・Q-04）` | 404-790 | 387 | **10** | `_pumpHerdrAndOpenPaneSelector`・`_tap*`・`_hasResizeCommand`・`kHerdrTwoPane/ThreePaneLayout…` |
| `T15: herdr paste / 画像転送 / copy-mode 代替（Q-06/H7）` | 791-923 | 133 | **3** | `kHerdrSnapshotWithLayoutFixture`・`FakeImageTransferNotifier` |
| `Q-02: herdr pane セレクタの Split（分割プレビュー経由）配線` | 924-1005 | 82 | **2** | `kHerdrSnapshotWithLayoutFixture` |
| `N-T: herdr pane セレクタの分割プレビュー（新規）` | 1006-1183 | 178 | **4** | `kHerdrTwoPaneLayoutSnapshotFixture`・`kHerdrResizedSnapshotFixture` |
| `Q-05: herdr tab セレクタの tab CRUD 配線` | 1184-1385 | 202 | **6** | `_pumpHerdrAndOpenTabSelector`・`kHerdrNewTabActiveSnapshotFixture` |
| `タスク①: herdr ターミナル全体 resize（Select Session）` | 1386-1516 | 131 | **3** | `_pumpHerdrAndOpenWorkspaceSelector`・`_StartPtyResizeClient`・`kHerdrResizedSnapshotFixture` |

### 1.5 file3: `terminal_screen_herdr_mutation_sync_test.dart`（1,188 行・**実測 21 件**）

**トップレベル定義（L1-202）**: import L1-14（`shared_preferences` を含む）／ fixture 8 本: `kHerdrSnapshotFixture` L26・`kHerdrSnapshotPane2Fixture` L43・`kHerdrTwoPanesSnapshotFixture` L60・`kHerdrEmptySnapshotFixture` L82・`kHerdrSnapshotNewTabFixture` L92（**file2 の `kHerdrNewTabActiveSnapshotFixture` と同一内容・別名**）・`kHerdrSnapshotNoFocusInfoFixture` L119・`kPaneNotFoundErrorFixture` L136・`kFocusNoNeighborFixture` L141 ／ `_herdrConnection()` L152 ／ `herdrSwitchEvents` L164（**file1 L33 と同一実装の重複**）／ **`_pumpHerdrTerminal` L170-196（27 行・21 件中 19 件のテストが使用。残り L737 / L856 は `TerminalTestScaffold.pumpTerminalScreen` を直接呼ぶ）** ／ `main()` L198、**`setUp` L199: `SharedPreferences.setMockInitialValues({})`（ファイル全体で有効な唯一の setUp）**。

| group 名（変更不可） | 行範囲 | 行数 | テスト数 |
|---|---|---|---|
| `T18: mutation 後ツリー同期の単一化（H5/S4）` | 203-798 | 596 | **13** |
| `T19: mutation 失敗の分類別通知（S4）` | 799-1188 | 390 | **8** |

T18 の 13 件: #1 L204 `syncAfterHerdrMutation 単一経路: force 再取得後にターゲットが変化すると_switchHerdrTarget で表示切替される` ／ #2 L252 `syncAfterHerdrMutation 単一経路: ターゲットが同一なら切替コミットなし` ／ #3 L283 `split 成功後は単一経路（force 再取得）で反映され、現在 pane が残れば表示継続` ／ #4 L332 `focus 成功後は単一経路（force 再取得）で同期され、フォーカス先の pane へ表示が切り替わる` ／ #5 L389 `rename pane 成功後は単一経路（force 再取得）で同期される（Q-02）` ／ #6 L421 `zoom 成功後は単一経路（force 再取得）で同期される（Q-02）` ／ #7 L454 `create tab（label + --focus）成功後は単一経路（force 再取得）で同期され、新タブの表示へ自動切替わる（Q-05・タスク②）` ／ #8 L512 `空欄ラベル（null / 空文字）は --label なし + --focus で作成される（Q-05・タスク②）` ／ #9 L567 `ラベル付き create は focus の有無で --focus 付与と表示追従が分岐する（Q-05・タスク②）` ／ #10 L626 `followBackendFocus でも focused 情報が欠落していれば現在表示を維持する（タスク②・Codex 観点 ④）` ／ #11 L662 `rename tab 成功後は単一経路（force 再取得）で同期される（Q-05）` ／ #12 L693 `close tab 成功後に再解決でターゲットが別 pane へ遷移する（単一経路・連鎖遷移）` ／ #13 L736 `close 成功後に再解決でターゲットが別 pane へ遷移する（単一経路・連鎖遷移）`。

T19 の 8 件: L800 target-not-found（pane_not_found）／ L853 close の pane_not_found／ L918 focus の no_neighbor／ L969 rename pane の target-not-found／ L1014 zoom の pane_not_found／ L1057 close tab の target-not-found／ L1098 server-down／ L1145 再同期でも対象が残らない場合は終端通知。

### 1.6 file4: `terminal_screen_scroll_send_test.dart`（591 行・**実測 14 件**）

**トップレベル定義（L1-87）**: import L1-14 ／ `_kTickPx` L18・`_kFixedFontSettings` L20・`_kKeySendSettings` L26・`_kFitZoomSettings` L34・`_state` L42・`_mode` L45・`_currentZoom` L49・`_enterMode` L57・`_dragUpTicks` L65・`_expectSelectedMode` L75 ／ `main()` L87。**これらの助関数・定数は 3 つの group 全てで共用**（scrollSend 専用・herdr 系とは無関係）。

| group 名（変更不可） | 行範囲 | 行数 | テスト数 |
|---|---|---|---|
| `scrollSend P0: モード状態機械・単一選択・原子性（D9/C1）` | 88-289 | 202 | **5** |
| `scrollSend P1: 合流送信・キー入力・方向反転（D6/H3/L0-a #4/#6）` | 290-434 | 145 | **4** |
| `scrollSend P2: 異常系（R6/M4/H4②）` | 435-591 | 157 | **5** |

テストは `TERM-SCROLL-016/018/019/020/021/022/023/024/025/026/027/028` + `scrollSend 自動フィットズーム: 突入で縮小・終了で復元` + `autoFitZoomOnScrollSend OFF ではズームを変更しない`（P0: 016/018/028/019/020・P1: 021/022/023/024・P2: 025/026/027/fit zoom x2）。

### 1.7 重複の実測サマリ（分割で解消すべき）

| 共有要素（同一内容） | 定義箇所 | 判定 |
|---|---|---|
| `kHerdrSnapshotFixture` | file1 L102 = file3 L26 | **同一**（769 バイト一致を実測） |
| `kHerdrSnapshotPane2Fixture` | file1 L163 = file3 L43 | **同一** |
| `kHerdrEmptySnapshotFixture` | file1 L180 = file3 L82 | **同一** |
| `kHerdrSnapshotWithLayoutFixture` | file1 L121(120x24) vs file2 L31(80x24) | **同名・別値（衝突）**※file1 側は参照 3 箇所のみ（L1887 / L2210 / L2668） |
| `kHerdrNewTabActiveSnapshotFixture`（file2 L158）| = `kHerdrSnapshotNewTabFixture`（file3 L92）| **同一内容・別名** |
| `_herdrConnection()` | file1 L357 = file2 L181 = file3 L152 | 同一実装を 3 重定義 |
| `herdrSwitchEvents()` | file1 L33 = file3 L164 | 同一実装を 2 重定義 |
| `_pumpHerdrTerminal` | file3 L170-196（file3 内 19 テストが使用） | 抽出対象（**H2 へ**）。他ファイルに同実装なし |
| `paneIndicatorPainter` | file1 L45-47（G1-29 と G6 11 件が使用） | 抽出対象（**H2 へ**）。他ファイルに同実装なし |
| `kHerdrTwoPaneLayoutSnapshotFixture` / `kHerdrThreePaneLayoutSnapshotFixture` | file2 定義、file1（L21-27）と `terminal_screen_herdr_parity_test.dart`（L17）が import | テストファイル間 import（匂い） |
| 既存 `test/helpers/` との重複 | — | この 4 ファイルの定義はどれも既存ヘルパーとは非重複 |

---

## 2. 目標構成

### 2.1 新設ヘルパー（`main()` を持たない・`flutter test` 対象外）

`test/screens/terminal/helpers/` を新設。**BRIEF 厳守事項の「全ファイル 500 行未満」は helper ファイルにも適用される**（helper は main() を持たず `flutter test` 対象にならないが、`flutter analyze` の対象であり、行数管理はテストファイルと同水準で行う）。

**H1a `herdr_snapshot_fixtures.dart`**（実測ベース見積り **約 230 行**）
- 責務: herdr の「単一 pane / 基本表示・解決・同期・エラー応答」次元の JSON fixture のみを収容。
- 収容（const 本文 187 行・doc ~35 行・header ~8 行 = ~230 行）: `kHerdrSnapshotFixture`(15)・`kHerdrSnapshotPane2Fixture`(15)・`kHerdrEmptySnapshotFixture`(5)・`kHerdrSnapshotWithLayoutFixture`(20)・`kHerdrLargeLayoutSnapshotFixture`(20 ※rename)・`kHerdrSnapshotZoomedFixture`(18)・`kHerdrTallLayoutSnapshotFixture`(18)・`kHerdrResizedSnapshotFixture`(20)・`kHerdrResizeUnchangedFixture`(8)・`kPaneNotFoundErrorFixture`(3)・`kFocusNoNeighborFixture`(10)・`kHerdrTwoPanesSnapshotFixture`(20)・`kHerdrSnapshotNoFocusInfoFixture`(15)。
- 500 行未満の担保: 実測で「このバッチの const 本文 = 187 行」であるため、doc/header を全て保持しても **~230 行**（余裕 ~270）。

**H1b `herdr_layout_fixtures.dart`**（実測ベース見積り **約 290 行**）
- 責務: herdr の「layout 付き・マルチ pane・セレクタ（workspace/tab/pane 解決・indicator・分割プレビュー）」次元の JSON fixture を収容。
- 収容（const 本文 247 行・doc ~35 行・header ~8 行 = ~290 行）: `kHerdrTwoPaneLayoutSnapshotFixture`(27)・`kHerdrThreePaneLayoutSnapshotFixture`(34)・`kHerdrTwoPaneNoLayoutSnapshotFixture`(20)・`kHerdrSameLabelSnapshotFixture`(24)・`kHerdrTwoWorkspaceSnapshotFixture`(24)・`kHerdrLabeledTabSnapshotFixture`(15)・`kHerdrMinNormalizeSnapshotFixture`(27)・`kHerdrZoomedTwoPaneSnapshotFixture`(27)・`kHerdrIndicatorResizeSnapshotFixture`(27)・`kHerdrNewTabActiveSnapshotFixture`(22)。
- 500 行未満の担保: const 本文 247 行 + doc ~35 行 + header ~8 行 = **~290 行**（余裕 ~210）。

> **分割根拠（実測）**（critique 2-1 対応）: H1 を 1 ファイルに集約した場合の実測は「定義 25 本（kHerdr* のみ。file1=13 / file2=6 / file3=6）+ 非 kHerdr 2 本 = 27 定義」「固有名 23 個・固有 const ブロック行 **414 行**（重複解消後。`kHerdrSnapshotNewTabFixture`→`kHerdrNewTabActiveSnapshotFixture` 統合で −22、同名別値の `kHerdrSnapshotWithLayoutFixture` 2 本は rename 後も 2 定義で維持）+ 直上 doc コメント **67 行** + header ≈ **480-490 行**」。500 行制限の余裕がほぼ無く、**要件 5（全ファイル 500 行未満）の安全マージンを確保するため、上記の「snapshot 系 / layout 系」で 2 分割する**。これにより各 helper は 500 行未満を実測ベースで担保する。

**H2 `herdr_test_helpers.dart`**（実測ベース見積り **約 190 行**）
- 責務: herdr テスト共通の接続生成・監視読み出し・paneIndicator 判定・pump / 対話ヘルパー。
- 収容（private→公開名化）:
  - `herdrConnection()`（file1 L357 = file2 L181 = file3 L152 の 3 重定義を解消）
  - `herdrSwitchEvents()`（file1 L33 = file3 L164 の 2 重定義を解消）
  - **`paneIndicatorPainter()`**（file1 L45-47 を verbatim 移動。critique 1-2 対応）
  - **`pumpHerdrTerminal(...)`**（file3 L170-196 を verbatim 移動。critique 1-1 対応。本体は `kHerdrSnapshotFixture` + `'herdr pane read': 'hello\n'` を使うため H1a を import）
  - file2 由来: `pumpHerdrAndOpenPaneSelector`・`pumpHerdrAndOpenTabSelector`・`pumpHerdrAndOpenWorkspaceSelector`・`tapHeaderResizeAndOpenChooser`・`tapChooserResize`・`tapResizeDialogAndConfirm`・`hasResizeCommand`・`amountOf`（L194/221/288/318/329/342/388/378 から公開名化）
  - file2 由来 fake class: `UiFakeManagedPty`・`StartPtyResizeClient`（L248/L273 から公開名化）
- 見積り根拠: 27（pumpHerdrTerminal）+ 3（paneIndicatorPainter）+ 11 種の既存 helper（~120 行）+ header/import 等 ≈ **190 行**（余裕 ~300）。

**H3 `scroll_send_test_helpers.dart`**（約 40 行見積り・変更なし）
- 責務: file4 の scrollSend 専用定数・助関数（`kTickPx`・`kFixedFontSettings`・`kKeySendSettings`・`kFitZoomSettings`・`state()`・`mode()`・`currentZoom()`・`enterMode()`・`dragUpTicks()`・`expectSelectedMode()`。private `_` を外して公開）。

### 2.2 新規テストファイル（21 本）と行数見積り

「テスト本体行（現行 group 行範囲実測）+ import/header 約 30 + group 宣言/閉 2」で算定。**全ファイル 500 行未満**。

#### file1 由来（10 本。G1=1,259 行は責務別に 5 分割。分割ピースは**同じ group 名** `TerminalScreen herdr (backend flow / display)` を宣言し、テスト識別子（group+test 名）を不変に保つ）

| 新ファイル名 | 責務 | 含める group（テスト番号） | 見積り | 上限根拠 |
|---|---|---|---|---|
| `terminal_screen_herdr_resolve_display_test.dart` | 初回解決・表示・失敗 diagnostics・injected reader | G1-1..9 | 318+32=**350** | <500 |
| `terminal_screen_herdr_breadcrumb_selector_test.dart` | パンくず表示とセレクタ Opening 段（T4/M-4） | G1-10..13 | 102+32=**134** | <500 |
| `terminal_screen_herdr_switch_test.dart` | 切替コミット・A8 監視リングバッファ・A2/T7 再解決 | G1-14..21 | 388(59+329)+32=**420** | <500 |
| `terminal_screen_herdr_reconnect_lifecycle_test.dart` | 再接続再解決・ライフサイクル（T9a/T9b） | G1-22..25 | 221+32=**253** | <500 |
| `terminal_screen_herdr_selector_flow_test.dart` | T10 セレクタ切替・強調・H-1・M2 回帰＋再タップガード | G1-26..29 + G4-1 | 269(229+40)+32=**301** | <500 |
| `terminal_screen_herdr_mutation_keys_test.dart` | mutation 有効（T13）と SpecialKeysBar のキー経路 | G2-1..5 | 162+32=**194** | <500 |
| `terminal_screen_herdr_autofit_test.dart` | AutoFit（bug1） | G3-1..3 | 86+32=**118** | <500 |
| `terminal_screen_herdr_scrollback_test.dart` | スクロールバック要求・クランプ・末尾アライン（bug4） | G5-1..3 | 117+32=**149** | <500 |
| `terminal_screen_herdr_pane_indicator_test.dart` | pane indicator（Phase 3・#8-#19） | G6-1..11 | 426+32=**458** | <500（余裕 42。`paneIndicatorPainter` は H2 から import するため追加行なし） |
| `terminal_screen_herdr_caret_test.dart` | caret（Phase 4） | G7-1..5 | 239+32=**271** | <500 |

#### file2 由来（5 本）

| 新ファイル名 | 責務 | 含める group | 見積り | 上限根拠 |
|---|---|---|---|---|
| `terminal_screen_herdr_resize_test.dart` | resize 2 段階フロー（T14） | T14（10 件） | 387+32=**419** | <500 |
| `terminal_screen_herdr_paste_image_test.dart` | paste/画像転送/copy-mode 代替（T15） | T15（3 件） | 133+32=**165** | <500 |
| `terminal_screen_herdr_split_preview_test.dart` | pane セレクタの分割プレビュー＋配線（Q-02・N-T） | Q-02 + N-T（6 件） | 260+32=**292** | <500 |
| `terminal_screen_herdr_tab_selector_crud_test.dart` | tab セレクタ CRUD 配線（Q-05） | Q-05（6 件） | 202+32=**234** | <500 |
| `terminal_screen_herdr_session_resize_test.dart` | ターミナル全体 resize（タスク①） | タスク①（3 件） | 131+32=**163** | <500 |

#### file3 由来（3 本。T18=596 行は「同期機構」「tab 操作同期」に 2 分割し、**同じ group 名** `T18: mutation 後ツリー同期の単一化（H5/S4）` を維持）

| 新ファイル名 | 責務 | 含める group（テスト番号） | 見積り | 上限根拠 |
|---|---|---|---|---|
| `terminal_screen_herdr_sync_mechanism_test.dart` | 単一化機構・pane mutation（split/focus/rename/zoom）同期 | T18-1..6 | 250+32+setUp4=**286** | <500 |
| `terminal_screen_herdr_sync_tab_crud_test.dart` | tab CRUD（create/rename/close）同期・followBackendFocus | T18-7..13 | 345+32+setUp4=**381** | <500 |
| `terminal_screen_herdr_sync_error_test.dart` | mutation 失敗の分類別通知（T19） | T19（8 件） | 390+32+setUp4=**426** | <500 |

※ file3 由来 3 本は `main()` 冒頭に同一の `setUp(() { SharedPreferences.setMockInitialValues({}); })` を各ファイルへ再現（現行は T18/T19 が 1 ファイルの setUp を共用）。加えて `_pumpHerdrTerminal` の呼び出しを **H2 の `pumpHerdrTerminal`** へ参照更新する（typo・引数バグ等の導入を防ぐため **verbatim 移動 + 呼び出し名のみ置換**）。

#### file4 由来（3 本）

| 新ファイル名 | 責務 | 含める group | 見積り | 上限根拠 |
|---|---|---|---|---|
| `terminal_screen_scroll_send_mode_test.dart` | モード状態機械・原子性（P0） | P0（5 件） | 202+32=**234** | <500 |
| `terminal_screen_scroll_send_keys_test.dart` | 合流送信・キー入力・方向反転（P1） | P1（4 件） | 145+32=**177** | <500 |
| `terminal_screen_scroll_send_abnormal_test.dart` | 異常系・自動フィットズーム（P2） | P2（5 件） | 157+32=**189** | <500 |

#### 旧 4 ファイル
- `terminal_screen_herdr_test.dart` / `terminal_screen_herdr_mutation_ui_test.dart` / `terminal_screen_herdr_mutation_sync_test.dart` / `terminal_screen_scroll_send_test.dart` は**削除**（実体は派生ファイル群へ置換）。

### 2.3 テスト件数バランス（分割前後で不変）

- file1 57 = **9+4+8+4+4（G1-26..29）+1（G4-1）**〔= G1 29 件 + G4 1 件、うち selector_flow ファイルには G1-26..29(4)+G4-1(1)=5 件〕 + **5(G2)+3(G3)+3(G5)+11(G6)+5(G7)**
- file2 28 = 10+3+6(Q-02:2+N-T:4)+6+3
- file3 21 = 6+7（T18）+8（T19）
- file4 14 = 5+4+5
- **合計 120 = 120**（分割前に実実行で確認済: 57/28/21/14）

### 2.4 import 先（各派生ファイル）

- herdr 系 18 テストファイル（file1/2/3 由来）: 既存 `../../helpers/terminal_test_scaffold.dart`・`../../helpers/fake_ssh_client.dart`（必要時）＋ **`helpers/herdr_snapshot_fixtures.dart`（H1a）／`helpers/herdr_layout_fixtures.dart`（H1b）**（使用する batch のみ）＋ **`helpers/herdr_test_helpers.dart`（H2）**＋必要最小の package import。
- scrollSend 系 3 本: `helpers/scroll_send_test_helpers.dart`（H3）＋ `../../helpers/terminal_test_scaffold.dart`。
- **`terminal_screen_herdr_parity_test.dart`**（既存・本タスク外のファイル）は import を old `mutation_ui_test.dart` から `helpers/herdr_layout_fixtures.dart`（`kHerdrTwoPaneLayoutSnapshotFixture`）へ差し替え。テスト本体・件数は不変（parity 側の `_herdrConnection` は独自定義のまま）。

---

## 3. 移動マッピング

### 3.1 group / テストの移動先

| 旧 group / テスト | 移動先（新ファイル） |
|---|---|
| G1 テスト 1-9 | `…_resolve_display_test.dart` |
| G1 テスト 10-13 | `…_breadcrumb_selector_test.dart` |
| G1 テスト 14-21 | `…_switch_test.dart` |
| G1 テスト 22-25 | `…_reconnect_lifecycle_test.dart` |
| G1 テスト 26-29 ＋ G4 | `…_selector_flow_test.dart` |
| G2（5 件） | `…_mutation_keys_test.dart` |
| G3（3 件） | `…_autofit_test.dart` |
| G5（3 件） | `…_scrollback_test.dart` |
| G6（11 件・group 内ローカル助関数 `pumpHerdrForIndicator`/`panePainterOf`/`paintedRects` も同梱） | `…_pane_indicator_test.dart` |
| G7（5 件・group 内 `caretOnSettings`＋トップレベル caret 助関数 4 個を同梱） | `…_caret_test.dart` |
| T14（10 件） | `…_resize_test.dart` |
| T15（3 件） | `…_paste_image_test.dart` |
| Q-02（2 件）＋N-T（4 件） | `…_split_preview_test.dart` |
| Q-05（6 件） | `…_tab_selector_crud_test.dart` |
| タスク①（3 件） | `…_session_resize_test.dart` |
| T18 テスト 1-6 | `…_sync_mechanism_test.dart` |
| T18 テスト 7-13 | `…_sync_tab_crud_test.dart` |
| T19（8 件） | `…_sync_error_test.dart` |
| P0（5 件） | `terminal_screen_scroll_send_mode_test.dart` |
| P1（4 件） | `terminal_screen_scroll_send_keys_test.dart` |
| P2（5 件） | `terminal_screen_scroll_send_abnormal_test.dart` |

### 3.2 共有コードの移設先

| 共有要素 | 元 | 移設先 |
|---|---|---|
| fixture 27 定義（固有 23 名） | file1/file2/file3 | **H1a / H1b**（重複解消: `kHerdrSnapshotFixture`/`kHerdrSnapshotPane2Fixture`/`kHerdrEmptySnapshotFixture` の 3 ペア統合、`kHerdrSnapshotNewTabFixture`→`kHerdrNewTabActiveSnapshotFixture` 統合） |
| `_herdrConnection` ×3 | file1 L357 / file2 L181 / file3 L152 | H2 → `herdrConnection()` |
| `herdrSwitchEvents` ×2 | file1 L33 / file3 L164 | H2 → `herdrSwitchEvents()` |
| **`paneIndicatorPainter`** | file1 L45-47 | **H2** → `paneIndicatorPainter()`（G1-29 と G6 の両方から参照） |
| **`_pumpHerdrTerminal`** | file3 L170-196 | **H2** → `pumpHerdrTerminal()`（sync_mechanism / sync_tab_crud / sync_error の 3 ファイルで使用） |
| file2 の pump/対話/fake 11 種（private 名） | file2 L194/221/288/318/329/342/388/378/248/273 | H2 へ公開名化 |
| file4 の定数・助関数 10 種（private 名） | file4 L18-86 | H3 へ公開名化 |
| file1 G1 の `_ReResolvePropagationReader` | file1 L56-86（テスト 20 専用） | `…_switch_test.dart` 内に local 保持 |
| **file3 の `setUp`（SharedPreferences）** | file3 L199 | file3 由来 3 本それぞれの `main()` 冒頭に再現（**＋ `_pumpHerdrTerminal` の参照を `pumpHerdrTerminal` に更新**。この setUp 再現と参照更新を 1 項目として実施する） |
| テストファイル間 import | file1 L21-27・parity L17 | H1a/H1b への import に置換し解消 |

---

## 4. リスクと対策

1. **group 名の不変性（rule 1）**: G1・T18 を分割したピースは同一 group 名を各ファイルで宣言する。flutter test のテスト識別子は `group名 + test名` で一意になるため、group 名・テスト名双方を維持すれば「実行されるテストの集合」は byte 一致で不変（`--reporter=json` の fullName で検証）。
2. **同名・別値 fixture（`kHerdrSnapshotWithLayoutFixture`）**: file1 側 120x24 を `kHerdrLargeLayoutSnapshotFixture` へ rename。波及は実測で **file1 内 3 箇所のみ**（L1887=G3-1 `paneWidth==120` assert / L2210=G6#10 findsNothing のみで width 非依存 / L2668=G7-3）。G3-1 の assert が正しく 120 に結合することは「rename 後の fixture 値 vs 旧 L121-141 の値を機械 diff」で保証（§5）。**値は 1 バイトも変えない**。
3. **`kHerdrSnapshotNewTabFixture`（file3）→ `kHerdrNewTabActiveSnapshotFixture` へ統合**: 同一内容を実測確認済み。file3 由来の create tab テスト（T18-7・8・9）の参照名を更新。
4. **他テストファイルへの波及（結合）と削除順序**: `terminal_screen_herdr_parity_test.dart` は**旧 `mutation_ui_test.dart` が削除される前に** import を H1b へ差し替え、`flutter analyze` と parity 単体実行で pass を確認してから旧ファイルを削除する（順序: helper 作成 → import 差し替え → analyze/テスト → 旧 4 ファイル削除 → 全体件数検証）。それ以外の参照ファイルは自前コピーで非影響（確認済）。
5. **`setUp` の共有範囲（file3）＋ヘルパー参照更新**: `SharedPreferences.setMockInitialValues({})` を file3 由来 3 本それぞれの `main()` へ再現し、`_pumpHerdrTerminal` の呼び出しを H2 の公開名へ更新する（ライブラリ追加/import 追加と同じ commit で実施）。省略すると MissingPluginException で fail する。
6. **H2 公開名と新ファイル内ローカル名の衝突チェック（軽微2 対応）**: H2 公開名は `herdrConnection` / `herdrSwitchEvents` / `paneIndicatorPainter` / `pumpHerdrTerminal` / `pumpHerdrAndOpen*` / `tap*` / `hasResizeCommand` / `amountOf` / `UiFakeManagedPty` / `StartPtyResizeClient`。新ファイル内ローカル名は G6 の `pumpHerdrForIndicator`/`panePainterOf`/`paintedRects`・G7 の `caretOnSettings`/`_FakeHerdrCaretReader`/`caretSeen`/`inTextViewCaret` で、H2 名と衝突なし（grep 実測）。private→public 化に伴う呼び出し書き換え範囲は「file2 由来 5 ファイル（resize / paste_image / split_preview / tab_selector_crud / session_resize）＋ file3 由来 3 ファイル（pumpHerdrTerminal のみ）」で、**変数名・assert は不変、呼び出し識別子のみ置換**。
7. **group 内ローカル助関数**: G6 の 3 助関数・G7 の 4 助関数は該当ファイル内に local で維持（global 化しない）。`paneIndicatorPainter` だけは 2 ファイル（selector_flow / pane_indicator）で使うため H2 へ移す（1-2 対応）。
8. **グローバル状態**: provider container は各テストで `pumpTerminalScreen` が新規構築（テスト間独立）。タイマー類は各テスト末尾の `tester.pump(...)` で消化済み。分割で実行順序は変わらず（各 suite 内の順は維持）、件数・成功は不変。
9. **`_` private 名の公開名化**: H2/H3 へ抽出するヘルパーは private→公開（BRIEF rule 5「part/mixin/private 基底禁止」を満たすための必須対応）。テスト本文の呼び出し名も機械的に更新（テスト名・assert は不変）。
10. **helper の行数管理**: H1a/H1b/H2/H3 にも 500 行未満を適用（§2.1 で実測ベース担保）。H1 を単一にしない理由は §2.1 の実測。

---

## 5. 検証計画

1. **分割前ベースライン（実施済み）**: 旧 4 ファイルを個別実行し **EXIT=0・fail 0** / 件数（`--reporter=json` の `testStart` 数 − loading 1 件）: **57 / 28 / 21 / 14 = 120** を確認。
2. **分割後: 件数一致**: 新 21 ファイルを `flutter test test/screens/terminal/<file>` で個別実行し、各ファイルの件数が §2.2 表と一致（合計 120）すること、**かつ EXIT=0・fail 0** であることを確認（件数だけでは fail も同数になり得るため EXIT/fail を明示する）。
   - resolve_display 9 / breadcrumb 4 / switch 8 / reconnect 4 / selector_flow 5 / mutation_keys 5 / autofit 3 / scrollback 3 / pane_indicator 11 / caret 5 / resize 10 / paste_image 3 / split_preview 6 / tab_selector_crud 6 / session_resize 3 / sync_mechanism 6 / sync_tab_crud 7 / sync_error 8 / scroll_send_mode 5 / scroll_send_keys 4 / scroll_send_abnormal 5
3. **識別子一致検証**: 旧 4 ファイル実行時と新 21 ファイル実行時の `--reporter=json` `test.fullName` 集合を diff し完全一致（group 名・テスト名・タグ不変の機械保証）。
4. **テスト本体行 diff（verbatim 移動検証）（推奨対応・v2 追加）**: 各 group について「旧ファイルの group 本文ブロック行（Lx-Ly 抽出）」と「新ファイルの対応ブロック行」を diff し、**移動による変更が「import 追加・呼び出し識別子の公開名置換・group 内のファイルローカル定義位置保持」のみ**であること（アサーション・期待値・タイマー値・コメント本文は不変）を確認。置換パターンはホワイトリスト（`_pumpHerdrTerminal`→`pumpHerdrTerminal` 等 §4-6 の一覧）に限る。
5. **rename fixture 値の機械 diff（軽微3 対応・v2 追加）**: `kHerdrLargeLayoutSnapshotFixture`（旧 file1 L121-141 の文字列連結体）と `kHerdrSnapshotWithLayoutFixture`（旧 file2 L31-52）等、統合・rename した fixture について「旧定義の JSON 正規化ダンプ」と「新 helper のダンプ」を diff し**バイト一致**を確認（rename 誤爆・値変化ゼロの保証）。
6. **parity import 差し替え順序（推奨対応・v2 追加）**: ①H1a/H1b/H2 を作成 → ②`terminal_screen_herdr_parity_test.dart` と派生ファイルの import を差し替え → ③`flutter analyze` が 0 issue → ④parity 単体を pass 確認 → ⑤旧 4 ファイルを削除 → ⑥フル件数 120 検証。**旧ファイル削除を先に行わない**。
7. **`flutter analyze`**: 0 issue（旧 4 ファイル削除・import 差し替え漏れ・`unused_import` の検出）。
8. **全体検証（リード実施）**: `flutter test --exclude-tags=repro` の総件数 **2,009** 不変。本 4 ファイル由来分は 120 件。

---

## 6. 未確定点（ユーザー判断が必要なもの）

1. **fixture 名称衝突の解決方針**: `kHerdrSnapshotWithLayoutFixture`（120x24 と 80x24）について、本設計では「80x24 を原名維持・120x24 を `kHerdrLargeLayoutSnapshotFixture` に rename」を推奨。反対に「120x24 を原名維持・80x24 を rename」でも可（§5-5 の機械 diff で値不変を保証）。
2. **G1 の分割粒度**: 本設計は 5 分割（resolve/breadcrumb/switch/reconnect/selector_flow）。「switch ファイルに監視 2 件（G1-14・15）を統合」「G4 を selector_flow へ統合」は本設計で実施済みの判断だが、より細かく（監視を独立ファイルにする等）する選択肢もある。**group 追加は不可（fullName が変わるため）**。
3. **ヘルパー配置**: `test/screens/terminal/helpers/` の新設を採用（BRIEF の `test/<dir>/helpers/` 形式）。全プロジェクト共通で使う場合のみ `test/helpers/` への追加も可能。`FakeImageTransferNotifier` の既存二重定義（terminal_test_scaffold vs terminal_parity_pump）の解消は P5 対象外。
4. **T18 の 2 分割方針**: 「単一化機構＋pane mutation」「tab CRUD 同期＋followBackendFocus」で分割。別の切り口（pane mutation / tab mutation）でも可。`_pumpHerdrTerminal` を H2（汎用）に置くか sync 専用 helper に置くかは H2 収容を推奨（herdrConnection/herdrSwitchEvents と併置で file3 由来 3 本の import が揃う）。