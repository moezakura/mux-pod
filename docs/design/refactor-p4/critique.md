# P4 設計批判レビュー（critique）— terminal_screen.dart（9,529 行）4 領域分割

- レビュアー: p4-critic（タスク #27・読み取り専用）
- 審査対象: `/tmp/p4-design/session-runtime.md` / `herdr.md` / `view-input.md` / `ui.md`（すべて v1。BRIEF.md の必須 8 セクションを整備済み）
- 検証方法: 4 設計書のインターフェース契約表・移動マッピングを**全メンバ突き合わせ**（grep による claim マトリクス）し、実コード `lib/screens/terminal/terminal_screen.dart`（HEAD = 作業ツリー・`bff0c13`）とテストの実測で照合した。
- 全体判定: **要修正（ブロッキング多数）**。4 設計の内容品質は高い（実測・行番号・テスト固定点の列挙は正確）が、**領域間の所有権突き合わせに二重 claim / 所有権空白が 8 件**あり、このまま実装するとコード重複・移動漏れ・コンパイル/テスト失敗が発生する。特に (c) の調停が未完。

---

## 0. 総括・最重要 3 点

1. **複数メンバの二重 claim**（同一メンバを 2 設計が「自分のファイルへ移動」）: `_scrollToCaret` / `_flushInputQueue` / `_showHerdr{Workspace,Tab,Pane}Selector` / `_showHerdrResizePaneChooser` / `_HerdrLabelInputDialog` / `_herdrToBreadcrumb` / `_savedCommandInput` / 選択バッファ 4 フィールド。
2. **所有権空白（誰も移動先を指示していない）**: `_executeAutoResize` / `_restoreResizedWindows` / `_scheduleInitialAutoResize` / `_handleResizeWindow` / `_handleFileBrowser` / `_handleImageTransfer` / `_injectImagePath` / `_ensureImageTransferListener` / `_ensureDownloadListener` / `_latencyNotifier`。
3. **(a) 500 行超過の甘さ**: ui 設計の「シム内残置」が build(258) + セレクタ起動(~479: herdr 3 種含む) + resize chooser(91) + `_handleResizePane`(86) ≈ **900 行超**になり、シム/root State の 500 行制約を破る。herdr 設計が 3 セレクタを herdr_selectors へ移すのと衝突し、両立不能。

---

## 1. (c) 領域間 state 二重所有・所有権空白（最重要・調停結果）

### 1.1 二重 claim（同一メンバ / 同一 state を 2 領域が所有）

| # | メンバ（実測行） | session-runtime.md | herdr.md | view-input.md | ui.md | 調停案（必須） |
|---|---|---|---|---|---|---|
| C1 | `_scrollToCaret` (L4306-4329) | §1.1E: session_poll へ「移」(L241) | — | §3.4: TerminalScrollFollowController へ「移動」(L430) | — | **view-input に一本化**。読む `_viewNotifier`（session 所有）は port 経由。session poll は `_applyUpdate` (L3092) から `viewport.scrollToCaret()` を呼ぶ |
| C2 | `_flushInputQueue` (L1243-1253) | §3: session_connection へ「改」(L230) | — | §3.5: TerminalKeySender へ「移動」(L438) | — | **view-input に一本化**（`_inputQueue`/`_sendKeyData` と同域）。session `_onReconnectSuccess`→`input.flushInputQueue()` |
| C3 | `_showHerdrWorkspaceSelector`/`Tab`/`Pane` (L4664-4930) | — | §3: herdr_selectors へ「改」(L182) | — | §3: **シム内残置**+コールバック化 (L189) | **herdr_selectors に一本化**（末尾トップのセレクタ本体は ui が所有する `_showMultiplexerSheet`/`MultiplexerSelectorSheet` と分離可能）。ui は shim 残置を取り下げ |
| C4 | `_showHerdrResizePaneChooser` (L5716-5751) | — | §3: herdr_resize へ「移」(L188) | — | §3: シム内残置 (L190) | **herdr_resize に一本化**（PaneChooserDialog へは ui のアダプタ経由） |
| C5 | `_HerdrLabelInputDialog`+State (L8692-8823) | — | §3: herdr_crud へ「移」。public `HerdrLabelInputDialog` (L193) | — | §3: herdr_label_input_dialog.dart へ「移動+public 化」(L183)・公開シンボル `HerdrLabelInputDialog` (L151) | **どちらか 1 ファイルに一本化**（提案: ui の独立 Dialog ファイル。herdr_crud から import。**両方に public 化するとシム export 衝突**） |
| C6 | `_herdrToBreadcrumb` (L4632-4648) | — | §3: herdr_controller の `toBreadcrumb`(L185) | — | §3: terminal_breadcrumb.dart の `buildHerdrBreadcrumb`(L174) | **ui に一本化**（BreadcrumbData は ui 所有・P2 の PaneChooser 同様）。herdr は `HerdrDisplayData` 提供のみ |
| C7 | 選択バッファ 4 (`_bufferedContent`/`_hasBufferedUpdate`/`_bufferedCaret`/`_bufferedTargetIdentity`, L528-536) | §1.2: value は view-input / 保管欄は session-runtime (L122) | §4.3②: screen が保管欄を所有 (L245) | §3.1: **TerminalModeController へ移動**(L406 移) | — | **view-input TerminalModeController に一本化**（poll→`captureSelectUpdate`、`_applyBufferedUpdate` は session から `input.takeBufferedUpdate()`）。保存・破棄も view-input 側 |
| C8 | `_savedCommandInput` (L616) | §1.2: view-input へ (L124) | — | §3.6: coordinator へ (L422) | §4-4: **所有者は State**(L235) | **view-input coordinator に一本化**（ui の `_showInputDialog` 起動は coordinator が行うため） |
| C9 | `_pendingTargetIdentity`/`_pendingCaret` (L511/519-522) | §1.2: session-runtime 保管 (L108) | §4.3②: screen 保管 (L245) | —（buffer のみ言及） | — | 実質同意（同一の root State が持つ）だが**表現を統一**（「root State フィールド・値生成は herdr API」） |

### 1.2 所有権空白（誰も移動先を指示していない・移動マッピングに存在しない）

| # | メンバ（実測行・行数） | 現状の参照元（実測） | 空白の根拠 | 調停案（必須） |
|---|---|---|---|---|
| G1 | `_executeAutoResize` (L5774-5840, 66行) | didChangeMetrics(L897) / lifecycle resumed(L855) / settings 購読(L995) / `_selectPane`(L4281) / `_scheduleInitialAutoResize`(L5859) | 全設計の §3 マッピングに**行がない**。テスト固定: `terminal_screen_resize_test`（autoResize 2 本・`resize-window` 非 `-A`） | **session-runtime に明記**（autoResize は lifecycle/tmux 操作の一部・`_isResizing` と同域） |
| G2 | `_restoreResizedWindows` (L5841-5853, 13行) | pause(L843/L865)/detached(L880)/deactivate(L3282)/`_disconnect`(L7269)/dispose | session §1.1 A に挙動言及のみ・§3 に無し。`_disconnect` が参照(L47 言及) | **session-runtime**（disconnect/deactivate と一体） |
| G3 | `_scheduleInitialAutoResize` (L5854-5868, 15行) | `_connectAndSetup`(L1491) | session テスト表のみ言及 (L172)。§3 に無し | **session-runtime** |
| G4 | `_handleResizeWindow` (L6232-6300, 68行) | `_showResizeWindowChooser`→onResize。テスト `TERM-RESIZE-005/007` が `resize-window mysession:0` を固定 | ui §4-2 は「session-runtime（起動フロー）」と記すが **session-runtime.md §3 に存在しない**。ui §3 にも行なし | **session-runtime**（`_handleResizePane` と対で tmux resize 実行）。ui は chooser 起動のみ |
| G5 | `_handleFileBrowser` (L7638-7651)/ `_handleImageTransfer`(L7652-7691)/ `_injectImagePath`(L7692-7722)/ `_ensureImageTransferListener`(L7579-7637) | build の `onImagePickRequested`(ui 配線)/ リスナー | view-input §3.7 は「→ session-runtime（画像/ダウンロード）」と**一方的に押し付ける**が session-runtime.md は一切 claim しない。ui も §1-1 に含めない | **どの領域に置くか lead が確定**（推奨: session-runtime 直轄 or root State の「転送系」に集約する新ファイル。`_imageTransferSub`/`_downloadSub` の破棄は root の dispose と整合させる） |
| G6 | `_ensureDownloadListener` (L7558-7578) + `downloadSnackBarDisplay` 表示 | ui §4-3 は「仕様導出のみ。表示は State が所持」(L234) | view-input は session へ押付・session claim なし。ui は「State 所持」とだけ言い移動先ファイル無し | **表示リスナーは root State 直轄**（`downloadSnackBarDisplay` 仕様導出は ui の download_snackbar_display.dart・そのまま） |
| G7 | `_latencyNotifier` (L491・dispose L3342) | poll が書く(L2304)・build が読む(L4565) | session-runtime §1.2 インベントリに**行がない**（dispose ④にのみ登場）。ui §4-4 は「所有者 State」とだけ書き、**書き手（session poll）を持つ側は自領域所有と明記しない**。破棄責任・書込所有の割当が不明瞭 | **session-runtime 所有**（poll が唯一の書込）・dispose は root State の ④ で維持 |

### 1.3 整合が取れている所有権（問題なし・確認済み）

- `_viewNotifier`（session） / `_herdrDisplayNotifier`・`_herdrPaneIndicatorNotifier`（herdr controller / dispose は root ④ で順序維持） / `_pollTimer`・`_treeRefreshTimer`・frame スロットル・適応型間隔・`_pollingSuspended`（session） / `_paneReader`/`_frameReader`/`_paneWriter`（session・生成は `_recreatePaneReader` 一元化・herdr 固有部は composer 呼出） / `_targetSource` フィールド（session・値生成は herdr `switchTarget`） / 4 ProviderSubscription（root） / `_terminalScrollController`（root） / `_scrollSendTimer`・`_keyOverlayTimer`・`_keyOverlayState`・`_inputQueue`・scrollSend 群・zoom 群（view-input） / follow/lock 4 フラグ（view-input） / `_zoomScale`（view-input） / `_sshState`・`_isConnecting`・`_connectionError`・`_backendKind`（session・ui は read-only） / `_isResizing`・`_isCreatingWindow`（session） / `_secureStorage`（session connection・view-input の画像転送が使う場合は root 昇格を要確認 → session §8-6 で言及済み）。
- `_hasInitialScrolled`: **session-runtime 所有**（view-input §1.1 でも session 側と明記・唯一の書込。ただし herdr の `_switchHerdrTarget`/`_setupHerdrSession` が `onLiveReset` 経由で false 化する点は port 化して衝突回避）。

---

## 2. (a) 500 行超過の見積り甘さ・機械的/grab-bag 分割

### 2.1 【重大】ui 設計: シム残置 ≈ 900 行超で 500 行制約を破る
ui.md §3 が「シム内残置」とする合計（実測行数ベース）: `build`(258) + `_showSessionSelector`(26) + `_showWindowSelector`(71) + `_showPaneSelector`(95) + `_selectorContextOf`(8) + `_showHerdrWorkspaceSelector`(67) + `_showHerdrTabSelector`(87) + `_showHerdrPaneSelector`(113) + `_herdrSelectorContext`(12) + `_showResizePaneChooser`(33) + `_showHerdrResizePaneChooser`(38) + `_showResizeWindowChooser`(20) + `_handleResizePane`(86) ≈ **914 行**。さらに State テストフック・keys・subscriptions・dispose・deactivate・`_closeSelectorThen`（同設計が「selector_sheet へ移動」と混在記述）が乗る。**シム（`terminal_screen.dart`）が 500 行未満という BRIEF 原則を単純に破る**。
- さらに C3/C4 の調停で herdr 3 セレクタと resize chooser を herdr 側へ出せば 279+38 減るが、残っても ~600 行となり**超える**。
- 必須修正案: セレクタ起動（tmux `_show*Selector`、`_selectorContextOf`）を ui の独立ファイル `selector_launch.dart`（または herdr と同じく「起動コーディネータ」ファイル）へ分離。`_handleResizePane`/`_handleResizeWindow` は session-runtime（G1-G4 調停）へ。root State は「鍵・subscription・dispose・hook フォワード・残り build 配線」のみに絞る（<500 を実測保証すること）。

### 2.2 【中】session-runtime: `session_runtime.dart` 480 行見積り
poll 制御 + pending/buffer 保管 + reader/writer ポインタ + 能力 getter + `_hasInitialScrolled` 等を 1 ファイル 480 行は上限寸前（コメント込みで超過リスク）。設計側にスロット（`session_view_pipeline.dart`）が明記されている点は良い。→ 実装時に 480 超過なら §2 のスロットへ即時分割（現行は「超過時」条件付き・必須化推奨）。

### 2.3 【軽微】herdr/ui の行数見積り
- herdr: `herdr_controller.dart` 480 / `herdr_selectors.dart` 460 — 上限接近だが分割スロット明記あり。OK。
- ui: `pane_layout_visualizer.dart` ~490 は「Painter108+Visualizer295+アイコン113 ≈ 516 行」と自己計測。**516 > 500**。設計 §2 は「2 分割すれば各 250」と言うが、**分割を「実装時に再計測」と条件付きにせず必須化**すること。

### 2.4 grab-bag 判定
- `SessionEnv` / `HerdrEnv` bundle は「外部依存の束」だが各フィールドの用途が明記され、grab-bag ではない。OK。
- ui の `terminal_overlays.dart`（Error/Reconnecting/Latency/Connection/Disconnected 5 種）は「overlay」で同一カテゴリ・責務 1 文で説明可能。OK。
- `terminal_input_ports.dart`（4 interface）は port 定義のみで grab-bag ではない。OK。

---

## 3. (b) part / mixin / private 基底による state 共有

- 4 設計すべて「part / mixin / private 基底不使用」を明記（ui §2・view-input 冒頭・session 原則・herdr §2）。全ファイルで `mixin`/`part of` の提案なし。**合格**。
- private シンボルの public 化方針（素の public・`@internal` 不採用）も 4 設計一致。**合格**。
- 注意（軽微）: C5 `_HerdrLabelInputDialog` を herdr と ui の**両方が public 化**して移動すると、シムからの export 名衝突（あるいは同一名の 2 クラス）が発生する。§1.1 C5 の調停必須。

---

## 4. (d) dispose / ライフサイクル順序の帰結（誰が何を破棄するか）

### 4.1 dispose の master 順序は 4 設計とも「HEAD L3293-3345 を維持」で同意
session §4.5④ / herdr §4.1 / view-input §4.4 / ui §4-4 はすべて「`_isDisposed=true` → bridge.reset → removeObserver → Wakelock → subscriptions → poll/tree timer → scrollSend/keyOverlay → autoResize/bg timer → herdr cache null → identity null → notifiers(view→herdrDisplay→herdrPaneIndicator→latency) → scrollController → super」で一致。**合格**。

### 4.2 【重大】notifier 破棄の所有権が 4 領域に散っており「誰が ④ のどこで何を呼ぶか」が未完
- `_viewNotifier`(session) / `_herdrDisplayNotifier`・`_herdrPaneIndicatorNotifier`(herdr) / `_latencyNotifier`(G7・未割当) が root の ④ で**順序付き**で dispose される必要があるが、各 controller の `dispose()` がどこで呼ばれるか（先頭の bridge.reset と、末尾の notifier dispose の間）が 4 設計とも「root が統括」としか書いていない。
- 必須修正案: root State の dispose に「**controller.dispose() の分割呼出順**」を明記する（例: `herdr.disposeBridge()` を先頭 → … → `session.disposeView()` / `view.disposeTimers()` の中間 → `herdr.disposeNotifiers()` / `session.disposeNotifiers(latency)` を L3339-3343 準拠で末尾）。**各設計書は自分の controller が「どのフェーズで何を dispose するか」を enum/表で明記**すること。

### 4.3 【中】`_restoreResizedWindows` の deactivate 経路
L3282 `deactivate()` が `unawaited(_restoreResizedWindows().then(...))` を呼ぶ（G2 未割当）。この経路がどの領域の dispose/deactivate 契約に含まれるか全設計に未記載。session-runtime が `deactivate` を「root 残置」としつつ復元実行が G2 なので、**session-runtime の契約表に deactivate 内の `_restoreResizedWindows` 呼出を明示**すること。

### 4.4 【軽微】`_scrollToCaret` の 100ms `Future.delayed`
dispose 後も遅延コールバックが走るが `mounted || _isDisposed` ガード（L4308）があり HEAD 同等。C1 で view-input に移す際も**ガードを必ず維持**（view-input の `TerminalInputHost.isDisposed` 経由）。OK 前提で要継続確認。

---

## 5. (e) 公開 API 破壊

| 公開面 | 判定 | 根拠 |
|---|---|---|
| `TerminalScreen` コンストラクタ（12 引数・既定値） | **OK** | 4 設計すべて「shim に本体存続・シグネチャ不変」。scaffold が全指定 |
| `ScrollModeSource` enum（3 値・順序） | **OK（要調整）** | view-input が `terminal_input_mode.dart` へ移設し shim re-export。contract test `TERM-ENUM-001` の値順序を維持。ただし**シムからの export 経路を 1 本化**（herdr/ui/session が別途定義しないこと） |
| `HerdrSyncTargetPolicy` enum | **OK** | view-input が `terminal_input_mode.dart` へ移設し shim re-export。contract test `TERM-ENUM-001` の値順序を維持。ただし**シムからの export 経路を 1 本化**（herdr/ui/session が別途定義しないこと） |
| `DownloadSnackBarDisplay` / `downloadSnackBarDisplay`（純関数） | **OK** | ui が `download_snackbar_display.dart` へ移設・shim export（テスト 2 ファイルが `terminal_screen.dart` から import するため）。session §5 と整合。**シム export を忘れないこと** |
| `AnsiTextView` 18 props / `AnsiTextViewState` 公開 5 メソッド | **OK** | view-input §5・ui §5 が「絶対変更禁止」。`TerminalViewportPort` がラップ |
| State テストフック（`scrollModeSourceForTesting` 等 6 + herdr 10 種） | **OK** | 4 設計すべて root State にフォワード維持。`tester.state(...)` の `dynamic` 呼出に適合 |
| `GlobalKey<AnsiTextViewState>` 経由 9 箇所 | **OK** | view-input §1.2 が全 9 箇所を実測列挙（+L6605 resetZoom・L3417 key）。port 化で解決 |
| `_PaneLayoutPainter` runtimeType（`'_PaneLayoutPainter'`） | **【重大】未解決** | herdr test L45/L1712/L2149-2174 が `runtimeType.toString() == '_PaneLayoutPainter'` + dynamic で `panes`/`activePaneId` を読む。ui §5 で「public 化と衝突」と正しく検出。**しかし ui の提案（typedef で runtimeType 維持）は Dart 上成立しない**（`typedef _PaneLayoutPainter = PaneLayoutPainter` の runtimeType 文字列は `PaneLayoutPainter` になる。テストは `_Pixel` 付きを要求）。ui §6-5 の「シムに同名 private クラスとして残置」が正解: **新ファイル内で `_PaneLayoutPainter`（private）のまま定義・同ファイル内で使用**（P3 の `_EagerScaleGestureRecognizer` と同方式・定義と使用が同一ファイル内なら private 可）。`buildPaneIndicatorShell` も同ファイルに置く |

---

## 6. (f) 既存テストを落とすリスク

### 6.1 【重大】`_PaneLayoutPainter` runtimeType（上記 §5 参照・テスト 7+ 箇所）
### 6.2 【重大】二重 claim メンバの移動競合
C1/C2/C3/C4/C5/C6/C8 のメンバを 2 設計が同時に各自ファイルへ移すと、**同一メソッドが 2 箇所に存在**（コピー実装）または実装時に一方が放置。`_showHerdr*Selector`（C3）は `terminal_screen_herdr_test.dart`・`herdr_mutation_ui_test`・`remaining_contracts` が `find.text('Select Session/Window/Pane')`・`mux-sel-*` ValueKey・`_closeSelectorThen` 200ms を固定するため、表示/閉じ動作がズレると直接落ちる。C4 は `terminal_screen_herdr_mutation_ui_test`（resize 2 段階）が固定。
### 6.3 【中】G1-G4（autoResize/resizeWindow）テスト落下
`terminal_screen_resize_test.dart`（autoResize 2 本）と `remaining_contracts_test`（`TERM-RESIZE-004..007`）が `_executeAutoResize`/`_handleResizeWindow` の発行を固定。所有権空白のまま移動されないと**挙動は維持されるが、設計どおり NEW ファイルに移せない**（どこにも居場所がない）→ 実装フェーズで必ず「シム残留 or 移動漏れ」になり差分可能性。
### 6.4 【中】`terminal_screen_contract_test` / `lifecycle_test` / `setup_test` の順序固定
- setup: `tmux -V` → `list-panes -a` の exec 順序（session §4.5①の順序維持が必須・session が検証計画に含む）OK。
- lifecycle: `dispose` で `onReconnectSuccess`/`onDisconnectDetected` が null 化 → root の dispose 契約（§4.1 参照）OK。
- contract: `TERM-ENUM-001/002`（enum 順序）・`TERM-SCREEN-002..003`（props）→ シム維持 OK。
### 6.5 【軽微】タイマー/時刻リテラル
- `_scrollToCaret` 100ms（C1 移動先で維持・herdr/epoch/ui テストが参照）
- `_closeSelectorThen` 200ms・bottomsheet 300ms・key overlay 1500ms・適応型上限 2000ms・boost 50ms・epoch テストの 2500ms pump 前提 — 4 設計すべて同一値を列挙済み（herdr §1.5 文言、bottomsheet 300ms は ui が §6-2 で言及）。OK。
- scrollSend flush の `pump(100ms)` は view-input が §6 R6 で記載。OK。
### 6.6 【軽微】`_PaneLayoutVisualizer` の ValueKey 恒定
`terminal-pane-layout-%0` / `terminal-split-right-%0` / `terminal-resize-window-*` を ui が保持。OK（移動先実装で文字列不変必須）。

---

## 7. (g) 循環 import（新設ファイル間 SCC>=2）

### 7.1 【中】潜在的な逆辺
- view-input の port 設計（neutral interface）は**循環を正しく防ぐ設計**。session は view-input の具象を import せず port 経由（§2.1 図）。herdr は ui のシート基底を「Env 注入」で受ける（§8-2）。この方針は良い。
- ただし下記が残る:
  1. **C5 `HerdrLabelInputDialog`**: herdr_crud が ui の Dialog を import + ui が herdr を import すると SCC。調停案（ui が独立 Dialog を public 化し herdr_crud が import）は一方向。OK だが「両方 public 化」は禁止と明記。
  2. **C6 `_herdrToBreadcrumb`**: herdr_controller → ui(terminal_breadcrumb) の依存か、ui → herdr_types かで逆辺が生じうる。調停案（ui が変換を持ち herdr は display 提供のみ）で一方向化。
  3. `SessionEnv`/`HerdrEnv` が互いの controller を import し合わないこと（session_env → herdr controller は一方向で可。herdr が session_runtime を import しないこと）を、**各設計の依存先列に「env 相互 import 禁止」を明記**。
- 必須修正案: 実装前に P3 と同様の SCC>=2 検証スクリプト（`/tmp/p3-design/scc_verify_v3.py` 相当）を新ファイル全間に実行し、**全 4 設計の検証計画に組み込む**（現状 session §7 のみ言及・他 3 設計は未記載 = 7 章 (i) でも指摘）。

---

## 8. (h) 未検討の回帰経路

| # | 経路 | 評価 | 必須/推奨 |
|---|---|---|---|
| H1 | **reconnect 中の mutation 競合** | herdr §6-1 は poll のエポック照合のみ分析。`_syncAfterHerdrMutation`(L2614-2667) は `_fetchHerdrSessions(force:true)`(await) 中に `_reResolveHerdrTargetAfterReconnect` が cache を作り直した場合、**mutation 側の `_herdrSnapshotCache` 参照は常に「現在値」を読むので安全な一方、`resolved` 判定と `_switchHerdrTarget` が reconnect の再解決結果を上書きしうる**（HEAD と同一挙動のため回帰はしないが、**設計書に「mutation 中 reconnect は前者の結果を破棄しない・但し順序は HEAD と同一」と明記がない**）。 | 推奨: herdr.md に「mutation→reconnect の同時実行は HEAD と同じく cache 現在値参照で安全。`_isDisposed`/`mounted` ガード維持」を追加 |
| H2 | **epoch 不一致時のバッファ破棄** | epoch test ①②③（in-flight 照合・バッファ破棄・履歴照合）が C7 のバッファ移動先に依存。view-input §4.1 が所有を mode controller に一本化し、session は `captureSelectUpdate`/`takeBufferedUpdate` を使う契約は成立するが、**破棄判定（`isCurrentTarget`）の実体は herdr のまま**であることを 3 設計の契約表に明記する必要がある。 | 推奨: バッファの identity 照合を「view-input が呼ぶ・herdr API が判定・session が破棄」の 3 段と明文化 |
| H3 | **dispose 中の非同期完了** | `_ensureImageTransferListener` の await（L7596-7601 `_injectImagePath`）・`_sendMultilineText` 等の disposed 後の完了。HEAD と同じ `mounted`/`_isDisposed` ガードを G5/G6 の移動先で維持する必要があるが、**G5/G6 が未割当のためガードの帰属も未確定**。 | 必須: §1.2 G5/G6 の調停後に「ガードは root state の port(`isMounted`/`isDisposed`) 経由で維持」と明記 |
| H4 | **SnackBar 多重表示** | `_showHerdrErrorSnackBar`/`_showHerdrTargetNotFoundSnackBar`/`_showErrorSnackBar` は HEAD に多重抑止なし（表示は仕様どおり多重起こりうる）。設計が dedup を追加すると文言/回数テスト（herdr UI・remaining_contracts）が壊れ、追加しなければ従来挙動維持。**「HEAD と同一（多重抑止なし）」を明記**して実装時に dedup を足さないこと。 | 推奨: herdr.md/messages・session に「SnackBar 多重抑止は追加しない（HEAD 同等）」と明記 |
| H5 | **copy-mode 自動遷移の順序** | poll `_pollPaneContent` L2346-2390 の「select 遷移→discard→restoreZoom→recordHerdrSwitchEvent→`_applyBufferedUpdate`」を session が view-input の `handleTmuxCopyModeDetected/Ended`（view-input §8 #8）に委譲する契約は成立。ただし **`_discardPendingScrollTicks` → `_cancelScrollSendTimer` の順序**（HEAD L2360-2368）を coordinator が 1 メソッドで保証すること。 | 推奨: view-input の coordinator 実装で「1 メソッド・副作用順厳守」を明記 |
| H6 | **画像転送の listener 2 重登録** | `_ensureImageTransferListener` は「`_imageTransferSub != null` なら return」で 1 回だけ登録。G5 移動時に `_ensure*` を 2 回呼ぶ構造（root + flow）にしないこと。 | 推奨: listener は root 直轄 1 本。flow は context 非保持でメソッド引数渡し（P3 FileBrowserDownloadFlow 方式） |

---

## 9. (i) 検証計画の妥当性

| 設計 | 検証計画 | 評価 |
|---|---|---|
| session-runtime | format / analyze / 本領域テスト 10 本 / 全体 / `git diff HEAD -- test/` / SCC | **良好**。SCC 検証は「P3 の scc_check を流用」とあるが**具体的コマンド/スクリプトが未定**。テスト範囲に `terminal_screen_herdr_mutation_ui`（resize 配線）が欠けるが追加可。 |
| herdr | format / analyze / herdr テスト 8 本 / `git diff` / 全体 / build-apk(keystore 注記) | 良好。**SCC 検証ステップが §7 に無い**（§8-2 で Env 注入を要請するのみ）。§1.1 C3/C4/C5 の調停後の移動先で実行すべきテストが変わるため、**テスト範囲を C 調停結果に連動**させること。 |
| view-input | format / analyze / 本領域テスト 11 本 / `git diff` / 全体 | **良好**。SCC 検証ステップなし。`ansi_text_view_*`（P3）を含めるのは過剰だが安全。 |
| ui | format / analyze / ui テスト 10 本 / `git diff` / `make test` | **良好**。`terminal_screen_herdr_test`（runtimeType L45）を含めている点が正しい。ただし**移動先の runtimeType 案（typedef）が実装不能**なため §5/e の修正が前提。 |

**共通の追加必須**: ① SCC>=2 検証スクリプトを 4 設計すべての検証計画に追加（新設ファイル間・シム import 禁止も対象）。② `git diff HEAD -- test/` ゼロ確認を 4 設計とも明記（既に全設計が記載 = OK）。③ 各設計の「移動後 500 行未満」を**実測コミット時に検証**（wc -l + CI 相当）。④ lead 統合時に「root dispose フェーズ表」（§4.2）を 1 枚作成。

---

## 10. 設計者別 必須修正（ブロッキング）/ 推奨修正

### session-runtime
- 【必須】G1-G4 を §3 マッピングに明記（`_executeAutoResize`/`_restoreResizedWindows`/`_scheduleInitialAutoResize`/`_handleResizeWindow` → session-runtime。`_handleResizePane` は ui 残置または本領域へ一本化）。
- 【必須】C1/C2 の二重 claim 解消（`_scrollToCaret`/`_flushInputQueue` は view-input へ委譲・本領域は port 経由）。
- 【必須】G7 `_latencyNotifier` を所有・dispose（root ④）に明記。
- 【必須】§4.2 の「controller.dispose フェーズ表」で自分の dispose 呼出位置を書く。
- 【推奨】mutation 中 reconnect（H1）をリスク表に追加。`session_runtime.dart` 480 行超過時の分割を必須化（§2.2）。

### herdr
- 【必須】C3/C4（`_showHerdr*Selector` × 3 / `_showHerdrResizePaneChooser`）を自領域に一本化するか ui へ明け渡すかを確定（本書は herdr_selectors へ一本化を推奨。ui は残置を取り下げ）。
- 【必須】C5 `_HerdrLabelInputDialog` を ui 独立 Dialog に一本化（両方 public 化禁止・シム export 衝突）。
- 【必須】C6 `_herdrToBreadcrumb` は ui へ（herdr は display 提供のみ）。
- 【必須】§4.1 dispose の「bridge.reset は先頭 / notifier.dispose は末尾」を**2 フェーズに分離して記載**（現記述は controller 1 回呼出で両立不能に見える）。
- 【推奨】§7 に SCC 検証追加。SnackBar 多重抑止を追加しない（H4）。

### view-input
- 【必須】C1/C2 を自領域に一本化し根拠（`_viewNotifier` は port 経由・`_inputQueue`/`_sendKeyData` と同域）を明記。
- 【必須】C7 バッファ 4 フィールドを mode controller に一本化（session は `captureSelectUpdate`/`takeBufferedUpdate`経由・破棄判定は herdr API）。
- 【必須】C8 `_savedCommandInput` を coordinator に一本化（ui は「State 所有」を取り下げ）。
- 【必須】`_handleTwoFingerSwipe`/`_getNavigableDirections`（§1.5 で除外）の**最終帰属**を確定（本設計は「領域外」としたまま誰も持たない。推奨: session-runtime/root がディスパッチ・herdr 分岐は herdr_navigation）。
- 【推奨】SCC 検証追加。`_scrollToCaret` 100ms ガード（§4.4）を明記。

### ui
- 【必須】(a) シム残置 ≈900 行を解消（セレクタ起動・resize 実行の移設・root State を <500 に）。
- 【必須】(e) `_PaneLayoutPainter` を**新ファイル内 private のまま**残置（typedef では runtimeType 不変・テスト 7+ 箇所が壊れる）。P3 `_EagerScaleGestureRecognizer` と同じ「定義と使用が同一ファイル」方式。
- 【必須】C5 `_HerdrLabelInputDialog` を独立 Dialog に一本化。
- 【必須】C3/C4 の残置を取り下げ（herdr へ）または lead 確定。
- 【必須】G5/G6 画像/ダウンロードのリスナー/ハンドラの帰属を確定（本領域 or session 直轄）。`_downloadSub`/`_imageTransferSub` dispose を root ④ に明記。
- 【推奨】`pane_layout_visualizer.dart` の 500 行超過を「必須 2 分割」に変更（§2.3）。

---

## 11. 結論

4 設計書は単独では質が高い（BRIEF 必須セクション完備・実測に正確）が、**領域間調停（critic の役割）が未完了**のため、このままでは:
- 実装開始直後に C1/C2/C3/C4/C5/C6/C8 の**二重移動**によるコード重複/コンパイル競合が発生する。
- G1-G7 の**所有権空白**により autoResize・resizeWindow・画像/ダウンロード・latency が「どこでも動かない」状態になる。
- ui のシム残置 900 行 + `_PaneLayoutPainter` runtimeType 問題により (a)/(e)/(f) が連鎖失敗する。

**リードへの要請**: §1.1 の調停案（C1〜C9）と §1.2（G1〜G7）を 4 設計へ通知して設計書 v2 を依頼し、堆積後の再審査（本タスクは v1 時点での批判として確定）を行うことを推奨します。