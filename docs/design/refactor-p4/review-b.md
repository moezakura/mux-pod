# P4 独立検証B レポート（herdr / ui 領域）

- 検証者: p4-reviewer-b（teammate #42・読み取り専用）
- 対象: `lib/screens/terminal/herdr/**`（13 ファイル）/ `herdr_label_input_dialog.dart` /
  `selector_launch.dart` / `selector_sheet.dart` / `terminal_view_shell.dart` /
  `terminal_menu.dart` / `terminal_overlays.dart` / `terminal_breadcrumb.dart` /
  `input_dialog_content.dart` / `pane_layout_painter.dart` / `pane_layout_visualizer.dart` /
  `resize_window_chooser_dialog.dart` / `tmux_pane_label.dart` / `download_snackbar_display.dart`
- HEAD: `bff0c13`（`terminal_screen.dart` 9,529 行）／ブランチ: `fix/refactor-many-lines`
- 参考設計: `/tmp/p4-design/arbitration.md` / `herdr.md` / `ui.md` / `BRIEF.md`
- 検証時刻: 2026-09-24 04:1x JST（検証中に他エージェントが `session_view_pipeline.dart` /
  `terminal_root_bindings.dart` を更新する動作を確認。最終状態で再実行済み）

## 判定: **NG**（挙動パリティ破れを 2 件検出。うち 1 件は実動作に影響する回帰）

担当テストは全て green・構造制約は全て満たすが、**テストで捕捉されない挙動パリティ破れ**が
複数残る。NG 判定の根拠は §1 の Top5（特に NG-1）。全体像は §0 サマリ表。

---

## 0. 検証サマリ

| 検証項目 | 結果 | 証跡 |
|---|---|---|
| 1. herdr 挙動パリティ（setup/switch/sync/reconnect/selector/resize/CRUD/epoch 照合・コマンド文字列・発行順序） | **NG（2 件）** | §1-1 〜 §1-2・§2.1 |
| 2. UI 固定点（`_PaneLayoutPainter` runtimeType / ValueKey / 文言 / SnackBar） | **OK** | §2.2 |
| 3. 欠落・スタブ検出 | **概ね OK（resetView が実質 no-op 疑い = NG-1 に合流）** | §2.3 |
| 4. 構造（500 行 / part/mixin / 循環 import SCC>=2） | **OK** | §2.4 |
| 5. 既存テスト不変 + 担当テスト実行 | **OK（green 159 件 = 146 + download 13）** | §2.5 |

---

## 1. 重要指摘 Top5

### [NG-1]（HIGH）ヘルドラ切替・セッション確立で view クリアが行われない回帰
- 個所: `terminal_root_bindings.dart` L177-178（`resetTerminalMode` / `resetView` の両方が
  `() => input.resetTerminalMode()` に配線）+ `herdr_controller.dart` `_switchTarget` L421-422
  （`env.resetView()` と `env.resetTerminalMode()` を連続呼び）。
- 内容: HEAD の `_switchHerdrTarget`（L4108-4120）は
  ① `_viewNotifier.value = _viewNotifier.value.copyWith(content: '', caret: null)`
  ② `_hasInitialScrolled = false` ③ `_resetTerminalMode()` の 3 段を実行する。
  新実装 `_switchTarget` は `input.resetTerminalMode()`（mode/scrollSend/バッファのみのリセット）
  2 回呼びに等価で、**view コンテンツ・caret・`hasInitialScrolled` のリセットが欠落**している。
  セッション確立側（`HerdrSetupFlow.setupSession` → `_host.resetView()`）も同様
  （HEAD `_setupHerdrSession` L1833-1834 の `copyWith(content: '')` +
  `_hasInitialScrolled = false` 相当が実行されない）。
- 実証（widget テスト実測）: `/tmp/p4-reports/tmptest/main_test.dart`
  `PARITY-CHECK_RESULT: old content remains immediately after switch = true`
  —— `switchHerdrTargetForTesting('w1:p2')` 直後の 1 フレームで旧 pane（w1:p1）の
  content が表示されたまま。HEAD なら `content: ''` クリアで消える箇所。
- 影響: pane 切替直後（次の poll 到着まで）に旧 pane の最終内容が一瞬残る（チラつき）。
  また `hasInitialScrolled` がリセットされないため、切替後の初回コンテンツ受信時に
  `scrollToCaret`（TERM-SCROLL-004）が発火せず、新 pane の先頭アライン挙動が HEAD と異なる。
- 修正案: `resetView` を「view content/caret クリア + `hasInitialScrolled=false`」を実行する
  コールバックへ配線する（`input.resetTerminalMode()` とは分離）。

### [NG-2]（MED）`hasInitialScrolled` のリセット経路が herdr 側と unmount する（構造的危険）
- 個所: `session_runtime.dart` L76 `bool hasInitialScrolled`（単一所有に統合済み・検証中に
  他エージェントの NG-3 修正で確定）／`session_view_pipeline.dart` L97 `_hasInitialScrolled()`。
- 内容: runtime 単一所有に統合された後も、**ヘルドラ切替時（`_switchTarget`）に
  `setHasInitialScrolled(false)` を呼ぶ経路が存在しない**。session 側（`session_mutations.dart`
  L46/84/121/202 = tmux セレクタ系）は `runtime.hasInitialScrolled = false` を実行するが、
  herdr 切替経路は `input.resetTerminalMode()` のみで触れない（NG-1 の反映）。
- 影響: herdr で pane 切替後に同じターミナルへ接続し続けると、初回 scrollToCaret の
  再発火が失われる。NG-1 の修正で同時に解消される見込み。
- 修正案: NG-1 の `resetView`（view クリア）実装内に `setHasInitialScrolled(false)` を含める。

### [NG-3]（LOW）`_switchTarget` は `resetView` + `resetTerminalMode` の重複呼び
- 個所: `herdr_controller.dart` L421-422。
- 内容: `resetView` と `resetTerminalMode` が現状同じ実体（`input.resetTerminalMode()`）に
  配線されているため、同一関数を連続 2 回呼ぶだけ。NG-1 の修正後は「view クリア +
  mode リセット」の 2 段に意味が分離される想定だが、現状は意図が消えている。

### [NG-4]（LOW）フック値の診断文字列が HEAD と一部相違
- 個所: `herdr_setup.dart` `resolvePaneId()` の cache null 分岐
  `(backendKind=${_host.backendKind}, )`（HEAD は `hasPaneContentReader=...` を含む）。
- 内容: `[HerdrSwitch]` リングバッファに記録される診断文字列の一部が HEAD と異なる。
  テストは文言でなく `contains` 部分一致のため green だが、運用ログ比較時の不整合要因。
- 影響: 低（診断用）。修正任意。

### [NG-5]（INFO）検証中に他エージェントが同一ファイルを編集中（レビュー基準の時点ずれ）
- 内容: `session_view_pipeline.dart`（04:14 更新・NG-3 コメント追加）、
  `terminal_root_bindings.dart`（04:13 更新・downloadSnackBarDisplay 配線修正）が
  検証中に変化。本レポートは 04:1x 時点の最終スナップショット（`flutter analyze` 0 issue +
  担当テスト green）で判定した。リードは実装完了後に再レビュー推奨。

---

## 2. 検証項目詳細と証跡

### 2.1 herdr 挙動パリティ（命令文字列・発行順序・epoch 照合）

HEAD の参照実装（`git show HEAD:...` を抽出: `/tmp/p4-reports/head_*.txt`）と新実装を
正規化比較した。命令文字列・発行順序は以下のテストが実測検証し、すべて green。

| 検証 | 証跡（テストの expect） |
|---|---|
| ライブポーリング `herdr pane read <pane>` | herdr_test L951/L972/L1123/L1292/L1319/L1381/L1505/L1534 |
| C-c 即送信 `herdr pane send-keys w1:p1 C-c`（確認なし） | cc_close_test L127/L155/L172 |
| 連鎖 close `herdr pane close w1:p1`（文言分岐後） | cc_close_test L299 |
| rename `herdr pane rename w1:p1 'editor'` | mutation_sync_test L405 |
| tab rename `herdr tab rename w1:t1 'work'` / tab close `herdr tab close w1:t1` | mutation_sync_test L678/L715 |
| resize `herdr pane resize`（絶対値→相対換算・Cols→Rows 順） | mutation_ui_test L495/L576/L743 |
| tab create `herdr tab create`（空欄=ラベルなし + `--focus` / 入力時 `--label` + `--focus`） | mutation_ui_test L1316 ほか |
| split `herdr pane split --direction down` | mutation_ui_test（Q-02） |
| epoch 照合（in-flight / スクロール中バッファ / 深い履歴・2500ms 発火前提） | epoch_test 3 件 green |
| `[HerdrSwitch]` イベント記録（偶発 `re-resolve succeeded` 等） | herdr_test 各所 + 実行ログ |

- `_switchHerdrTarget` / `_resolveHerdrTargetFromSessions` / `_syncAfterHerdrMutation` /
  `_reResolveHerdrTargetAfterReconnect` / `_handleHerdrTargetNotFound` / `_showHerdr*Selector` /
  `_handleHerdrResize*` / `_confirmAnd*Herdr*` のロジック比較は**構造一致**（イベントラベル
  `'re-resolve succeeded -> ...'` / `'$eventLabel -> ...'` / `'switch target -> ...'`、
  `target-not-found detected` / `server-down detected`、no-op 判定 L-3 の 3 条件一致、
  target-not-found 終端 = 再接続しない R1 等）。
- 差異として NG-1/NG-2 の view クリア・スクロールフラグ欠落を実測検出。

### 2.2 UI 固定点

| 固定点 | 結果 | 証跡 |
|---|---|---|
| `_PaneLayoutPainter` runtimeType `'_PaneLayoutPainter'` | **OK** | `pane_layout_painter.dart` L10 で private 定義・同ファイル内のみ使用。herdr_test L45 の `paneIndicatorPainter()` が runtimeType 参照し green |
| ValueKey `terminal-pane-layout-*` / `terminal-split-right-*` / `terminal-split-down-*` | **OK** | `pane_layout_visualizer.dart` L97/L240/L249（HEAD L8076/L8219/L8228 と一致） |
| ValueKey `terminal-resize-window-*` | **OK** | `resize_window_chooser_dialog.dart` L130（HEAD L8942 と一致） |
| ValueKey `mux-sel-session/window/pane-*` | **OK** | `selector_launch.dart` L226/L285/L374・`herdr_selectors.dart` L55/L103/L188（HEAD と一致） |
| 文言 (`Select Session/Window/Pane` / `Resize Pane` / `Estimated` / `Cols` / `Rows` / `80x24 (Standard)` / `Close Pane?` / `Close Tab?` / `New Tab` / `Create` / `Rename`) | **OK** | l10n ファイルは `git diff HEAD -- lib/l10n/` = 0 行（未変更）。mutation_ui_test が実測 green |
| SnackBar（`Target pane disappeared. Re-synced.` / `No pane in that direction` / `No change at the split boundary` / `This key could not be sent via herdr` / `Herdr target pane not found` / `Herdr server is not responding`） | **OK** | herdr_messages.dart が l10n 参照・文言不変。mutation_sync_test / remaining_contracts_test green |
| タイマー（`_closeSelectorThen` 200ms / bottomsheet 300ms / keyOverlay 1500ms / boost 50ms） | **OK** | `selector_launch.dart` L163 `Future.delayed(200ms)`・テストの pump 値で実測 |

### 2.3 欠落・スタブ検出

- `terminal_view_shell.dart` の `onHerdrWorkspaceTap ?? () {}` 等は防御的フォールバックで、
  root（`terminal_screen.dart` build）が `_adapter.herdr.showWorkspaceSelector` 等の実体を
  供給するため**未接続スタブではない**。
- `onOpenSettings` は `Navigator.push(... SettingsScreen)` に配線済み（no-op なし）。
- 上記の「空実装・no-op」スキャンで実体なし。ただし NG-1（`resetView` = `resetTerminalMode`
  と実質同一）が「意図した view クリアが配線されていない」no-op 相当として残留。

### 2.4 構造

- 500 行ゲート: terminal 配下の最大は `herdr_controller.dart` 495 行 < 500（全ファイル OK）。
  `terminal_screen.dart` 438 行。
- part/mixin: 不使用（`grep -rln "^part \|mixin "` = 0）。
- 循環 import: `/tmp/p3-design/scc_verify_v3.py` 適用 → terminal 配下 SCC>=2 は **0**。
  残る SCC は HEAD 既存の l10n（3）/ pane_content_reader⇔pane_frame_reader（2）のみ。
- シム逆 import（新ファイル → `terminal_screen.dart`）= 0。herdr → session 逆 import = 0。
- hasInitialScrolled は検証中に他エージェントが runtime 単一所有へ統合済み（NG-3 解消）だが、
  ヘルドラ切替経路からの false 化が無い点が NG-2。

### 2.5 既存テスト不変 + 担当テスト

- `git diff HEAD -- test/` = **0 行（空）**（証跡: 上記コマンド出力）。
- 担当 9 ファイル実行（2 回実施・最終状態）: **全 146 件 green**
  （herdr 37 / epoch 3 系統 / mutation_sync 25 / mutation_ui 69 系統 / cc_close 5 / resize 18 /
  remaining_contracts 49 系統）。
- download 2 ファイル: **全 13 件 green**。
- `flutter analyze`（最終状態）: **No issues found**（検証中は他エージェントの編集途上で
  一時 type error を観測したが現在は解消済み）。

---

## 3. 再現手順（NG-1 の実証）

```bash
# リポジトリ変更なし（読み取り専用）
cd /home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines
flutter test /tmp/p4-reports/tmptest/main_test.dart   # PARITY-CHECK_RESULT を確認
```

実行結果: `PARITY-CHECK_RESULT: old content remains immediately after switch = true`
（HEAD 相当の即時クリアが失われている）。

---

## 4. 判定根拠まとめ

| 判定要素 | 値 |
|---|---|
| 担当テスト（159 件） | 全て green |
| `git diff HEAD -- test/` | 空（回帰ゼロ） |
| 構造（500 行 / part / mixin / SCC） | 全て OK |
| UI 固定点（runtimeType / ValueKey / 文言 / SnackBar / タイマー） | 全て OK |
| 挙動パリティ | **NG-1（HIGH・view クリア欠落）/ NG-2（MED・hasInitialScrolled リセット欠落）** |

テスト green・固定点維持を踏まえつつ、**「テストで捕捉されない挙動パリティ破れ」が実動作に
影響する**ため総合判定は **NG**。修正方針: `resetView` の配線を「view content/caret クリア +
`hasInitialScrolled=false`」のコールバックへ分離（NG-1/NG-2 同時解消）。修正後は担当テスト
再実行 + 再度の実測検証（`/tmp/p4-reports/tmptest/main_test.dart`）を推奨。