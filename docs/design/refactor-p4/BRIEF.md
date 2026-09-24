# P4 設計ブリーフ（`terminal_screen.dart` 9,529 行・全設計者共通・厳守）

## 目的

`lib/screens/terminal/terminal_screen.dart`（**9,529 行**）を**責務ベース**で
500 行未満の複数ファイルへ再設計する。P1（services/theme）・P2（widgets/providers）・
P3（screens 8 本）は同方針で完了・コミット済み（HEAD: P3 完了状態）。

本ファイルは 4 領域に分けて並列設計する。**各設計者は自分の領域を担当しつつ、
「自分が所有する state」と「他領域から props/コールバックで受ける state」を
明示的なインターフェース契約として書くこと**（critic が領域間の所有権衝突を調停する）。

## 実測事実（前提・各自で再確認すること）

- ファイル: `lib/screens/terminal/terminal_screen.dart` 9,529 行 / import 80 本
- トップレベル公開シンボル（**維持必須**）:
  - `enum ScrollModeSource`（L88）
  - `enum HerdrSyncTargetPolicy`（L107）
  - `class TerminalScreen extends ConsumerStatefulWidget`（L379）
  - `class DownloadSnackBarDisplay`（L9472・lib/test 内で外部参照ゼロ・内部使用）
- 内部トップレベル: `_TerminalViewData`(L123) / `_TmuxTargetSource`(L180) /
  `_HerdrTargetSource`(L194) / `_HerdrTargetIdentity`(L216) / `_HerdrDisplayData`(L229) /
  `_HerdrPaneIndicatorData`(L271) / `_HerdrResolvedTarget`(L287) / `_BreadcrumbData`(L348) /
  `_TerminalScreenState`(L460-7885) / `_PaneLayoutPainter`(L7885) /
  `_PaneLayoutVisualizer`+State(L7993-8307) / `_SplitRightIconPainter`(L8307) /
  `_SplitDownIconPainter`(L8365) / `_InputDialogContent`+State(L8420-8692) /
  `_HerdrLabelInputDialog`+State(L8692-8824) / `_ResizeWindowChooserDialog`+State(L8824-9110) /
  `_SelectorContext`(L9110) / `_MultiplexerSelectorSheet`+State(L9204-9419) /
  `_DisconnectedBanner`(L9419) / `DownloadSnackBarDisplay`(L9472)
- `_TerminalScreenState` 内のメンバは **243 個**（検出ベース）。100 行超が 13 個、
  50 行超が 60 個。最長: `_connectAndSetup` 267行 / `build` 258行 / `_pollPaneContent` 217行 /
  `_showTerminalMenu` 204行 / `_buildBreadcrumbHeader` 160行 /
  `_reResolveHerdrTargetAfterReconnect` 123行
- 外部呼出元（**公開 API を変えない**）:
  - lib: `main.dart`(L130) / `notifications/panes/notification_panes_view.dart`(L82) /
    `connections/connection_list_screen.dart`(L362) / `dashboard/dashboard_screen.dart`(L151)
  - test: **24 ファイル**が `package:flutter_muxpod/screens/terminal/terminal_screen.dart`
    を import（`test/helpers/terminal_test_scaffold.dart` 経由が主）
- P3 で分割済みの隣接 API（**変更禁止**）:
  - `AnsiTextView` / `AnsiTextViewState`（`screens/terminal/widgets/ansi_text_view.dart`）。
    terminal_screen は `GlobalKey<AnsiTextViewState>` で `currentState` の公開メソッド
    （jumpToLineFromTop / scrollToBottom / followToBottom / scrollToTop / scrollToCaret /
    toggleCtrl/Alt/Shift / resetModifiers 等）を呼ぶ。`AnsiTextView` の 18 props も不変。
  - `file_browser_screen.dart` / `special_keys_bar.dart` 等の P2/P3 API も不変。

## 対象ファイルのパスは維持

`lib/screens/terminal/terminal_screen.dart` は 24 テスト + 4 lib 呼出元が import するため、
**元ファイルはロジックを持たない thin re-export シムとして存続**させる（P2/P3 と同方式）。
`TerminalScreen` のコンストラクタ（名前付き引数・必須/任意・デフォルト値）は完全維持。

## 設計原則（P1〜P3 で承認済み・厳守）

1. **1 ファイル = 1 責務**・全ファイル 500 行未満・機械的分割や grab-bag 命名の禁止。
2. **合成（has-a）優先**。構成ルート＋単一の状態所有者＋協調オブジェクト。
   依存方向は一方向（**循環 import 禁止**。新設ファイル間で SCC>=2 を作らない）。
3. **`part` / `mixin` / private 基底での private state 共有は禁止**。
   別ファイルへ移す private シンボルは**素の public 化**（P3 で `@internal` は実績ゼロ・
   不採用と決定済み）。
4. **公開 API 維持**（上記シンボル・コンストラクタ・enum 値・グローバルキー経由の公開
   メソッド）。import パスは変えない（元ファイルはシム）。
5. **挙動不変**: `test/` 配下の既存ファイルは**差分ゼロ**（`git diff HEAD -- test/` が空）。
   新規テスト追加は可。**テストが何を固定しているかを実測してから設計する**
   （タイマー / SnackBar 文言 / ツリー形状 / GlobalKey / pump 回数など）。
6. **状態所有権の単一化**: Controller / FocusNode / Timer / StreamSubscription /
   ScrollController / GlobalKey / TextEditingController / ProviderSubscription は
   破棄責任を持つ所有者を 1 つに決め、表で示す。`initState` / `didUpdateWidget` /
   `dispose` の順序を HEAD と一致させる。
7. **非同期ライフタイム**: `mounted` / `ref.mounted` ガード、`context.mounted`、
   `use_build_context_synchronously` の扱いを HEAD と等価に維持する。

## 領域分担（各自の担当領域を実測で確定させること）

| 領域 | 目安 | 主な内容（実測ベースの出発点） |
|---|---|---|
| **session-runtime** | 86 メンバ / 約 3,330 行 | 接続〜切断〜再接続（`_connectAndSetup` 267行 / `_recreatePaneReader` / `_setupListeners` 93行 / `_pollPaneContent` 217行 / `_resolveHerdrTargetFromSessions`）、target source 実装、display data、window/pane 選択・作成・kill（`_selectPane` / `_createWindow` / `_killWindow` / `_killPane` / `_confirmAndKillPane`）、エラー・再接続状態 |
| **herdr** | 74 メンバ / 約 2,291 行 | herdr sync/epoch/mutation（`_syncAfterHerdrMutation` / `_reResolveHerdrTargetAfterReconnect` 123行）、workspace/tab/pane セレクタ（`_showHerdr*Selector`）、resize（`_handleHerdrResize*`）、label、`HerdrSyncTargetPolicy`・`HerdrSyncTarget` 周辺 |
| **view-input** | 41 メンバ / 約 882 行 | AnsiTextView 配線、キー/特殊キー送信（`_sendKey` / `_sendSpecialKey` / `_handleKeyEvent`）、paste、入力ダイアログ（`_showInputDialog`）、モード遷移（`_enterScrollSendMode` / `_enterSelectMode` / `_exitToNormalMode` / `_resetTerminalMode`）、scroll-send（`_flushScrollSend` / `_applyScrollSendFitZoom`）、history ロード（`_loadHistoryForScroll`）、zoom、`ScrollModeSource` |
| **ui** | 42 メンバ / 約 1,236 行 | `build` 258行、breadcrumb（`_buildBreadcrumbHeader` 160行）、メニュー（`_showTerminalMenu` 204行）、overlay（`_buildErrorOverlay` / `_buildReconnectingIndicator`）、pane レイアウト可視化（`_PaneLayoutVisualizer` / Painter 3 種 / `_buildPaneLayoutPreview` 256行）、resize ダイアログ・`_ResizeWindowChooserDialog`、`_MultiplexerSelectorSheet`、`_DisconnectedBanner`、`_InputDialogContent`、`_HerdrLabelInputDialog`、`DownloadSnackBarDisplay` |

※ 上記の分類は機械的な目安。実際の所有関係を読み、境界の誤りは設計書で根拠付きで修正してよい。

## 各設計書の必須セクション

1. **現状分析（事実）**: 担当領域のメンバを**行番号付き**で列挙（メソッド/フィールド）。
   状態・リソース所有権インベントリ。呼出元/呼出先（領域内外）。担当領域に固定挙動を課す
   テスト（ファイル名・テスト名・何を固定しているか）。
2. **目標構成**: 新規/変更ファイルごとに「責務（1文）・推定行数・公開シンボル・依存先」。
   全ファイル 500 行未満の数値根拠。既存ファイルのシム化の有無。
3. **移動マッピング**: 既存メンバ（行範囲）→ 移動先ファイル／残すもの。移動のみ／改造を区別。
4. **インターフェース契約（最重要）**: 「自領域が所有する state」「他領域から受ける props /
   コールバック」「他領域へ提供する API」。**同一 state の二重所有を提案しない**。
   `dispose` 責任の所在も明記。
5. **公開 API 維持表**: `TerminalScreen` コンストラクタ・enum・公開メソッドの維持根拠。
6. **リスクと対策**: ライフサイクル、タイマー、非同期ギャップ、`mounted` ガード、
   テストが固定する文言・ツリー・グローバルキー、herdr epoch/mutation、IME など。
7. **検証計画**: 実行コマンド（format / analyze / 担当領域の該当テスト /
   `git diff HEAD -- test/` ゼロ / 最終的に全体テスト）。
8. **未確定点**: ユーザー判断が必要なもののみ（無ければ「なし」）。

## 事実主義

行番号・メンバ名・rg 結果・テスト名を根拠に書く。不明は「不明」と明記。推測は「推測」と
ラベルする。比較は `git show HEAD:<path>` と作業ツリー実ファイルで行う。

## ツール制約

- **読み取り専用**: リポジトリ内のファイルを編集してはならない。書き込みは `/tmp/p4-design/` のみ。
- cwd: `/home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines`（branch: fix/refactor-many-lines）
- 成果物は指定パスに Markdown 1 本。完成後、リードへ成果物パスと要点を報告すること。
