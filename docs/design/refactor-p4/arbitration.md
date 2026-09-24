# P4 リード仲裁（critique.md §1.1/§1.2/§2/§4/§5 の確定）

本書は P4 設計 v2 改訂の**唯一の正**。4 設計者は本書の割当に従って自分の設計書を改訂し、
自分の領域外へ割り当てられたメンバを自分の移動マッピングから**削除**すること。

## 1. 所有権の確定（二重 claim の解消）

| # | メンバ（実測行） | 確定所有者 | 補足（API 契約） |
|---|---|---|---|
| C1 | `_scrollToCaret` (L4306) | **view-input**（`TerminalScrollFollowController`） | session poll は port の `scrollToCaret()` を呼ぶ。`mounted || _isDisposed` ガード維持 |
| C2 | `_flushInputQueue` (L1243) | **view-input**（`TerminalKeySender`） | session `_onReconnectSuccess` は `input.flushInputQueue()` を呼ぶ |
| C3 | `_showHerdr{Workspace,Tab,Pane}Selector` (L4664-4930) | **herdr**（`herdr_selectors.dart`） | ui は残置を取り下げる。`_closeSelectorThen` の 200ms・`mux-sel-*` Key・文言は不変 |
| C4 | `_showHerdrResizePaneChooser` (L5716) | **herdr**（`herdr_resize.dart`） | ui は残置を取り下げる。PaneChooserDialog へは ui のアダプタ経由 |
| C5 | `_HerdrLabelInputDialog` + State (L8692) | **ui**（`herdr_label_input_dialog.dart`・素の public） | herdr_crud は ui を import する（一方向）。**両設計で public 化しない** |
| C6 | `_herdrToBreadcrumb` (L4632) | **ui**（`terminal_breadcrumb.dart` 内 `buildHerdrBreadcrumb`） | herdr は `HerdrDisplayData` を提供するのみ |
| C7 | 選択バッファ 4 フィールド (L528-536) | **view-input**（`TerminalModeController`） | session poll は `captureSelectUpdate(...)`、`_applyBufferedUpdate` は `input.takeBufferedUpdate()`。**破棄判定（identity 照合）は herdr API** が行う 3 段契約 |
| C8 | `_savedCommandInput` (L616) | **view-input**（`TerminalInputCoordinator`） | ui の `_showInputDialog` 起動は coordinator 経由。ui の「State 所有」記述は撤回 |
| C9 | `_pendingTargetIdentity` / `_pendingCaret` (L511/519) | **root State フィールド**（値生成は herdr API） | 表現を 4 設計で統一 |
| G1 | `_executeAutoResize` (L5774) | **session-runtime** | autoResize テスト 2 本の挙動不変 |
| G2 | `_restoreResizedWindows` (L5841) | **session-runtime** | `deactivate` 経路の呼出を契約表に明記 |
| G3 | `_scheduleInitialAutoResize` (L5854) | **session-runtime** | `_connectAndSetup` から呼ばれる |
| G4 | `_handleResizeWindow` (L6232) | **session-runtime** | ui は chooser 起動のみ。`resize-window mysession:0` のコマンド不変 |
| G5 | `_handleFileBrowser`/`_handleImageTransfer`/`_injectImagePath`/`_ensureImageTransferListener` | **session-runtime**（`terminal_transfer_flow.dart`） | 転送用 subscription を単一所有。mounted/_isDisposed ガード維持 |
| G6 | `_ensureDownloadListener` (L7558) | **session-runtime**（同上） | 表示仕様（文言・色）は ui の `download_snackbar_display.dart` の純関数を import（session → ui の一方向）。**SnackBar 多重抑止は追加しない（HEAD 同等）** |
| G7 | `_latencyNotifier` (L491) | **session-runtime**（poll が唯一の書込） | dispose は root ④（末尾フェーズ） |
| — | `_handleTwoFingerSwipe` / `_getNavigableDirections` | **view-input** | AnsiTextView の props（onTwoFingerSwipe / navigableDirections）を供給。herdr 固有の番号解決は herdr の navigation API を port 経由で呼ぶ |
| — | `_handleResizePane` (L5869) | **session-runtime** | ui は `onResize` コールバックを渡すのみ |

## 2. root State（`terminal_screen.dart` シム）の最終スコープと 500 行制約

root State に残すのは以下**のみ**:

- 状態: `_isDisposed` / テストフック forwarding / `_scrollToBottomKey` 等の GlobalKey /
  `_terminalScrollController` / 4 ProviderSubscription / `_pendingTargetIdentity`/`_pendingCaret`（C9）
- ライフサイクル: `initState` / `didUpdateWidget` / `deactivate` / `dispose`（**§4 のフェーズ表どおり**）
- 配線: `build` の協調オブジェクト合成とコールバック接続（**表示ツリー本体は ui の
  `terminal_view_shell.dart` 等へ外出し**。root の build は「合成 + 引渡し」に限定）
- セレクタ起動（tmux `_show*Selector` / `_selectorContextOf`）: **ui の
  `selector_launch.dart`** へ（シム内に残さない）
- resize 実行: session-runtime へ（§1 G1-G4）

→ 全員が「root State に残る行数」を見積もり、**実測で 500 行未満**を数値で示すこと。
   ui 設計者は root State の残置インベントリを v2 で更新し、行数合計を明記する。

## 3. `_PaneLayoutPainter` の扱い（runtimeType 維持）

- herdr テスト 7+ 箇所が `runtimeType.toString() == '_PaneLayoutPainter'` を固定。
- **新ファイル（例: `pane_layout_visualizer.dart`）内で `_PaneLayoutPainter` を private のまま
  定義し、同ファイル内でのみ使用する**（P3 `_EagerScaleGestureRecognizer` と同方式）。
- typedef による別名は runtimeType が変わるため**禁止**。
- `buildPaneIndicatorShell` 等も同ファイルに置く。

## 4. dispose フェーズ表（root State が統括）

各設計者は「自分の controller がどのフェーズで何を破棄するか」を表で明記:

| フェーズ | 内容（HEAD L3293-3345 の順序を維持） |
|---|---|
| P0 | `_isDisposed = true` |
| P1 | herdr: bridge.reset（先頭） |
| P2 | WidgetsBinding.removeObserver / Wakelock 解除 |
| P3 | ProviderSubscription 群（4 本 + transfer 2 本） |
| P4 | poll/tree タイマー停止（session） |
| P5 | scrollSend / keyOverlay タイマー（view-input） |
| P6 | autoResize / background タイマー（session） |
| P7 | herdr cache / identity / resolved target の null 化 |
| P8 | notifier 群の dispose（**順序厳守**: view → herdrDisplay → herdrPaneIndicator → latency） |
| P9 | root の ScrollController dispose → `super.dispose()` |

- herdr の「bridge.reset（先頭）」と「notifier.dispose（P8）」は**別フェーズ**であることを明記。
- session の `deactivate` 内 `_restoreResizedWindows` 呼出も契約表に記載。

## 5. 500 行制約の必須化（条件付き分割の禁止）

- ui: `pane_layout_visualizer.dart` は **必ず 2 ファイルに分割**（Painter 群 と Visualizer）。
- session: `session_runtime.dart` が 480 行見積り → **450 行を超えたら分割を実施**（条件ではなく閾値で必須）。
- 全員: 見積りが 450 行超のファイルは分割先を事前に設計書へ記載。

## 6. 依存方向（循環防止）

- `*_env.dart`（SessionEnv / HerdrEnv）は**相互 import 禁止**。herdr は session を import しない。
- 依存の向き: `ui（表示・純関数） ← session-runtime → ports ← view-input`、`herdr → ports / ui(純関数) / herdr 内部`。
- 4 設計すべての検証計画に **SCC>=2 検証スクリプトの実行**を追加
  （`/tmp/p3-design/scc_verify_v3.py` を新設ファイルグラフに適用、または同等スクリプト）。
- `terminal_screen.dart` から新ファイルへの**逆 import（新ファイル → シム）を禁止**。

## 7. その他の確定事項

- SnackBar の多重抑止は追加しない（HEAD 同等・文言/回数テスト保護）。
- `_closeSelectorThen` 200ms / bottomsheet 300ms / key overlay 1500ms / 適応型 2000ms /
  boost 50ms / `_scrollToCaret` 100ms は不変。
- テストフック（`scrollModeSourceForTesting` 等 6 + herdr 10 種）は root State で forwarding 維持。
- `ScrollModeSource` / `HerdrSyncTargetPolicy` / `DownloadSnackBarDisplay` /
  `downloadSnackBarDisplay` は**シムから 1 経路のみ export**（他設計で再定義禁止）。
