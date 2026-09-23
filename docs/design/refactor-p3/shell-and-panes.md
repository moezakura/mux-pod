# P3 設計 v3: shell-and-panes（home_screen / notification_panes_screen / markdown_preview_screen）責務ベース再設計

- 担当: p3-shell-designer（タスク#5 → v2 改訂: #11 → v3 改訂: #12）
- 対象 3 ファイル（行数は HEAD 実測 = 作業ツリー同一、`git diff HEAD -- lib/screens/` 空を確認済み）:
  1. `lib/screens/home_screen.dart`（814 行）
  2. `lib/screens/notifications/notification_panes_screen.dart`（519 行）
  3. `lib/screens/file_browser/markdown_preview_screen.dart`（533 行）
- 制約: **設計のみ・リポジトリ編集禁止**。書き込みは `/tmp/p3-design/` のみ。本設計書は `/tmp/p3-design/shell-and-panes.md`。
- 原則: ①1ファイル=1責務・全ファイル500行未満 ②合成優先（part/mixin/private基底禁止）③公開API維持（import パス維持・元ファイルは thin re-export）④挙動不変（既存テスト差分ゼロ）⑤状態所有権の単一化 ⑥テストが固定する挙動を実測してから設計。

---

## 0a. v3 改訂サマリ（ユーザー指摘「相互循環参照が発生する構造が間違っている」への構造修正）

**指摘の実体（実測）**: `lib/screens` の 10 ファイルが 1 つの SCC（強連結成分）を形成（PRE: size=10）。原因は `home_screen.dart` が `CurrentTabNotifier`/`currentTabProvider` を所有し、`connections_screen.dart`（L10）/`keys_screen.dart`（L9）/`settings_search_field.dart`（L6）が home_screen を import している**逆辺 3 本**（home → 各タブ画面 と 各タブ画面 → home の相互参照）。Python/Tarjan でこの 3 本を除去すると screens の循環が完全消滅することを実証済み（§0b・§付録）。

| # | v2 の記述 | ユーザー指摘 / 実測 | v3 の改訂 |
|---|---|---|---|
| A | `CurrentTabNotifier`/`currentTabProvider` を `home/home_tab_provider.dart` へ（home 機能内） | home 内では connections/keys/settings_search_field → home シムの逆辺が残るため SCC が消えない（実測 size=10） | **`lib/navigation/current_tab_provider.dart`（新設・中立）へ抽出**。このモジュールは screens を一切 import しない（依存ゼロ）。connections/keys/settings_search_field は中立モジュールを**直接 import** し、home_screen.dart を import しない。home_screen.dart シムは互換のため中立モジュールを re-export（main.dart の import 不変） |
| B | markdown の static keys（`rawScrollKey`/`renderedScrollKey`）が `markdown_preview_screen.dart`（実装）に残る | v2 では `markdown_preview_screen.dart`（build 委譲 → body を import）と `markdown_preview_body.dart`（`MarkdownPreviewScreen.*ScrollKey` 参照 → screen を import）が **新たな 2-cycle を形成** | **`lib/screens/file_browser/markdown_preview/markdown_scroll_keys.dart`（新設・ファイル内依存ゼロ）へ抽出**。body は中立ファイルのみ参照。`MarkdownPreviewScreen.rawScrollKey/renderedScrollKey` は中立値への**静的 getter** として残す（テストのクラス静的参照を維持）。screen（impl）→ body の**一方向のみ** |
| C | 依存グラフの機械検証が設計書にない | 改修後の SCC ゼロを数値で示す必要 | **改修後 import グラフの全辺リスト + Python/Tarjan 検証スクリプト実行結果**を §0b に追記（screens 配下 SCC size>=2 は NONE）。残存する既知の循環（l10n 生成物 3 種・`pane_content_reader ⇄ pane_frame_reader`）は対象外と明記 |

**v3 で維持する v1/v2 決定**: デッドコード削除（案A・ユーザー承認済み）・全ファイル 500 行未満・合成・part/mixin 禁止・既存テスト差分ゼロ・素の public 化（@internal 不使用）。

---

## 0b. 改修後 import グラフ全辺リスト + SCC 機械検証（必須修正 C・実行結果コピペ）

### 0b-1. 検証方法

- スクリプト: `/tmp/p3-design/scc_verify_v3.py`（配布・リポジトリ編集なし）
  - `lib/**/*.dart`（`.g.dart` 除く）の `import`/`part` を regex で抽出し、relative/`package:` を解決
  - PRE（HEAD 実測）と POST（v3 仮想グラフ）の両方で **Tarjan SCC** を計算
  - POST は次の仮想変換を適用: ①`connections_screen`/`keys_screen`/`settings_search_field` の「→ home_screen」逆辺 3 本を除去し `navigation/current_tab_provider.dart` へ再ターゲット ②`home_screen.dart` シム → `home/home_screen.dart` 実装 → `home/widgets/home_bottom_nav_bar.dart`（home の内部依存） ③markdown を `markdown_scroll_keys.dart`（中立）・`markdown_preview_screen.dart`(impl)→body→中立 の 3 ファイルへ分割
- 実行: `python3 /tmp/p3-design/scc_verify_v3.py`（出力全体は `/tmp/p3-design/scc_v3_output.txt`）

### 0b-2. PRE（HEAD・実測）の SCC

```
size=10: screens/connections/connections_screen.dart, screens/dashboard/dashboard_screen.dart,
        screens/home_screen.dart, screens/keys/keys_screen.dart, screens/notifications/notification_panes_screen.dart,
        screens/settings/category_list_view.dart, screens/settings/master_detail_view.dart,
        screens/settings/settings_screen.dart, screens/settings/widgets/settings_search_field.dart,
        screens/terminal/terminal_screen.dart
```

→ `home_screen.dart` を軸に 10 ファイルが強連結。home への逆辺（connections L10 / keys L9 / settings_search_field L6）が SCC の主因。

### 0b-3. POST（v3 設計）の改修後 import グラフ全辺リスト（screens 配下・実測抽出 + 仮想新規）

```
  screens/connections/connections_screen.dart -> screens/connections/connection_form_screen.dart
  screens/connections/connections_screen.dart -> screens/terminal/terminal_screen.dart
  screens/dashboard/dashboard_screen.dart -> screens/connections/connection_form_screen.dart
  screens/dashboard/dashboard_screen.dart -> screens/terminal/terminal_screen.dart
  screens/file_browser/file_browser_screen.dart -> screens/file_browser/markdown_preview_screen.dart
  screens/file_browser/file_browser_screen.dart -> screens/file_browser/widgets/file_action_menu.dart
  screens/file_browser/file_browser_screen.dart -> screens/file_browser/widgets/file_list_tile.dart
  screens/file_browser/file_browser_screen.dart -> screens/file_browser/widgets/path_bar.dart
  screens/file_browser/file_browser_screen.dart -> screens/file_browser/widgets/transfer_progress_sheet.dart
  screens/file_browser/markdown_preview/markdown_preview_body.dart -> screens/file_browser/markdown_scroll_keys.dart
  screens/file_browser/markdown_preview/markdown_preview_screen.dart -> screens/file_browser/markdown_preview/markdown_preview_body.dart
  screens/file_browser/markdown_preview_screen.dart -> screens/file_browser/markdown_preview/markdown_code_block.dart
  screens/file_browser/markdown_preview_screen.dart -> screens/file_browser/markdown_preview/markdown_preview_screen.dart
  screens/file_browser/markdown_preview_screen.dart -> screens/file_browser/widgets/sftp_markdown_image.dart
  screens/home/home_screen.dart -> screens/home/widgets/home_bottom_nav_bar.dart
  screens/home_screen.dart -> screens/connections/connections_screen.dart
  screens/home_screen.dart -> screens/dashboard/dashboard_screen.dart
  screens/home_screen.dart -> screens/home/home_screen.dart
  screens/home_screen.dart -> screens/keys/keys_screen.dart
  screens/home_screen.dart -> screens/notifications/notification_panes_screen.dart
  screens/home_screen.dart -> screens/settings/settings_screen.dart
  screens/home_screen.dart -> screens/terminal/terminal_screen.dart
  screens/keys/keys_screen.dart -> screens/keys/key_generate_screen.dart
  screens/keys/keys_screen.dart -> screens/keys/key_import_screen.dart
  screens/keys/keys_screen.dart -> screens/keys/widgets/key_tile.dart
  screens/notifications/notification_panes_screen.dart -> screens/terminal/terminal_screen.dart
  screens/settings/categories/settings_category_body.dart -> screens/settings/sections/about_section.dart
  screens/settings/categories/settings_category_body.dart -> screens/settings/sections/behavior_section.dart
  screens/settings/categories/settings_category_body.dart -> screens/settings/sections/connection_section.dart
  screens/settings/categories/settings_category_body.dart -> screens/settings/sections/display_section.dart
  screens/settings/categories/settings_category_body.dart -> screens/settings/settings_category.dart
  screens/settings/categories/settings_category_body.dart -> screens/settings/widgets/settings_section_header.dart
  screens/settings/categories/settings_category_list.dart -> screens/settings/settings_category.dart
  screens/settings/category_detail_screen.dart -> screens/settings/categories/settings_category_body.dart
  screens/settings/category_detail_screen.dart -> screens/settings/settings_category.dart
  screens/settings/category_detail_screen.dart -> screens/settings/widgets/settings_app_bar_title.dart
  screens/settings/category_list_view.dart -> screens/settings/category_detail_screen.dart
  screens/settings/category_list_view.dart -> screens/settings/search/settings_search_content_switcher.dart
  screens/settings/category_list_view.dart -> screens/settings/widgets/settings_app_bar_title.dart
  screens/settings/category_list_view.dart -> screens/settings/widgets/settings_search_field.dart
  screens/settings/master_detail_view.dart -> screens/settings/categories/settings_category_body.dart
  screens/settings/master_detail_view.dart -> screens/settings/search/settings_search_content_switcher.dart
  screens/settings/master_detail_view.dart -> screens/settings/search/settings_search_provider.dart
  screens/settings/master_detail_view.dart -> screens/settings/settings_category.dart
  screens/settings/master_detail_view.dart -> screens/settings/widgets/settings_app_bar_title.dart
  screens/settings/master_detail_view.dart -> screens/settings/widgets/settings_search_field.dart
  screens/settings/search/settings_search_content_switcher.dart -> screens/settings/categories/settings_category_list.dart
  screens/settings/search/settings_search_content_switcher.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/search/settings_search_content_switcher.dart -> screens/settings/search/settings_search_provider.dart
  screens/settings/search/settings_search_content_switcher.dart -> screens/settings/search/settings_search_results_view.dart
  screens/settings/search/settings_search_content_switcher.dart -> screens/settings/settings_category.dart
  screens/settings/search/settings_search_item.dart -> screens/settings/settings_category.dart
  screens/settings/search/settings_search_provider.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/search/settings_search_provider.dart -> screens/settings/sections/about_section.dart
  screens/settings/search/settings_search_provider.dart -> screens/settings/sections/behavior_section.dart
  screens/settings/search/settings_search_provider.dart -> screens/settings/sections/connection_section.dart
  screens/settings/search/settings_search_provider.dart -> screens/settings/sections/display_section.dart
  screens/settings/search/settings_search_provider.dart -> screens/settings/settings_category.dart
  screens/settings/search/settings_search_results_view.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/search/settings_search_results_view.dart -> screens/settings/search/settings_search_provider.dart
  screens/settings/search/settings_search_results_view.dart -> screens/settings/settings_category.dart
  screens/settings/search/settings_search_results_view.dart -> screens/settings/widgets/settings_section_header.dart
  screens/settings/sections/about_section.dart -> screens/settings/licenses_screen.dart
  screens/settings/sections/about_section.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/sections/about_section.dart -> screens/settings/settings_category.dart
  screens/settings/sections/behavior_section.dart -> screens/custom_keys/custom_keys_screen.dart
  screens/settings/sections/behavior_section.dart -> screens/settings/pickers/overlay_position_picker.dart
  screens/settings/sections/behavior_section.dart -> screens/settings/pickers/scroll_send_input_picker.dart
  screens/settings/sections/behavior_section.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/sections/behavior_section.dart -> screens/settings/settings_category.dart
  screens/settings/sections/behavior_section.dart -> screens/settings/widgets/settings_section_header.dart
  screens/settings/sections/connection_section.dart -> screens/settings/pickers/clear_host_keys_confirmation.dart
  screens/settings/sections/connection_section.dart -> screens/settings/pickers/conflict_policy_picker.dart
  screens/settings/sections/connection_section.dart -> screens/settings/pickers/output_format_picker.dart
  screens/settings/sections/connection_section.dart -> screens/settings/pickers/resize_preset_picker.dart
  screens/settings/sections/connection_section.dart -> screens/settings/pickers/slider_dialog.dart
  screens/settings/sections/connection_section.dart -> screens/settings/pickers/text_input_dialog.dart
  screens/settings/sections/connection_section.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/sections/connection_section.dart -> screens/settings/settings_category.dart
  screens/settings/sections/connection_section.dart -> screens/settings/widgets/settings_section_header.dart
  screens/settings/sections/display_section.dart -> screens/settings/pickers/adjust_mode_picker.dart
  screens/settings/sections/display_section.dart -> screens/settings/pickers/language_picker.dart
  screens/settings/sections/display_section.dart -> screens/settings/pickers/orientation_picker.dart
  screens/settings/sections/display_section.dart -> screens/settings/pickers/refresh_rate_picker.dart
  screens/settings/sections/display_section.dart -> screens/settings/search/settings_search_item.dart
  screens/settings/sections/display_section.dart -> screens/settings/settings_category.dart
  screens/settings/sections/display_section.dart -> screens/settings/widgets/settings_section_header.dart
  screens/settings/settings_screen.dart -> screens/settings/category_list_view.dart
  screens/settings/settings_screen.dart -> screens/settings/master_detail_view.dart
  screens/settings/settings_screen.dart -> screens/settings/settings_breakpoints.dart
  screens/settings/widgets/settings_search_field.dart -> screens/settings/search/settings_search_provider.dart
  screens/terminal/terminal_screen.dart -> screens/custom_keys/custom_keys_screen.dart
  screens/terminal/terminal_screen.dart -> screens/file_browser/file_browser_screen.dart
  screens/terminal/terminal_screen.dart -> screens/settings/settings_screen.dart
  screens/terminal/terminal_screen.dart -> screens/terminal/widgets/ansi_text_view.dart
  screens/terminal/terminal_screen.dart -> screens/terminal/widgets/terminal_zoom.dart
  screens/terminal/widgets/ansi_text_view.dart -> screens/terminal/widgets/terminal_zoom.dart
```

**注意**: 本リストは「screens 配下の dense 辺」を実測抽出したもの。`connections_screen.dart`（L10）・`keys_screen.dart`（L9）・`settings_search_field.dart`（L6）の `→ home_screen.dart` 逆辺は**除去済み**。`navigation/current_tab_provider.dart` への依存（および各タブ画面からの中立 import）は screens 外ノードのためこのリスト外（§2.1 参照）。

### 0b-4. POST の SCC 検証結果（スクリプト実行結果コピペ）

```
=== POST SCC (lib-wide /*screens*/ size>=2) ===
（空: screens 配下に SCC size>=2 は存在しない = 非巡回 DAG）

=== POST full-lib SCC size>=2 (out-of-scope remnants) ===
  size=3: l10n/app_localizations.dart, l10n/app_localizations_en.dart, l10n/app_localizations_ja.dart
  size=2: services/backend/domain/pane_content_reader.dart, services/backend/domain/pane_frame_reader.dart
```

→ **screens 配下の SCC size>=2 はゼロ**（改修後 import グラフは DAG）。残存する 2 物件は既知・対象外: ①l10n 生成物（`app_localizations*.dart` が互いに import = 生成物の特性） ②`pane_content_reader ⇄ pane_frame_reader`（services/backend/domain。本フェーズ P3 の対象外）。

---

## 0c. v2 改訂サマリ（v2 時点の記録・critique /tmp/p3-design/critique.md §5・§6 反映）

| # | v1 の記述 | 批判（critique） | v2 の改訂 |
|---|---|---|---|
| 1 | private→`@internal` 昇格を「P2 で承認済み」と記載 | §5.2【中】: P2 実装（HEAD）の `@internal` 使用は **0 件**。P2 critique §2.5 は「検討余地として提示」であって承認ではない。`invalid_use_of_internal_member` lint が分析警告になる可能性がある | **`@internal` は使用しない**。別ファイルへ移す private 部品は「素の public 化（または `// ignore_for_file: library_private_types_in_public_api` を明示添付）」を採用。「P2 で承認済み」の記述は削除し、実績ゼロの事実を明記 |
| 2 | §2.3 依存グラフが `markdown_preview_screen.dart → body` の一方向のみ | §5.3【中】: body（別ファイル）が `MarkdownPreviewScreen.rawScrollKey` / `renderedScrollKey` を**クラス静的参照**するため `body → screen（実装クラス）` の辺が必要（循環は生じない） | §2.3 の依存グラフに `markdown_preview_body.dart → markdown_preview_screen.dart`（static key 参照のため）を追記 |
| 3 | connections 設計との間に相互循環の言及なし | §5.5【重大】: home シム ↔ connections シムが互いに相手のシムを import し、循環が現行より 1 段深くなる恐れ | `currentTabProvider` の参照を **home/home_tab_provider.dart の直接 import** へ変更する代替案を §2.1/§4/§6 に提示（paths: 現行 import 維持案と直接 import 案の 2 案比較）。connections 設計（connections-screen.md）との整合を明記 |
| 4 | デッドコード削除後の analyze 警告確認が検証計画にない | §5.1【中】: 削除後、未使用 import / 生成 getter（`context.l10n.homeActiveSessions` 等）が `flutter analyze` で警告にならないかの確認が欠落 | 検証計画 §7 に「デッドコード削除後：`flutter analyze` で未使用 import / 生成 getter の警告ゼロを確認」を追加 |

必ず修正（ブロッキング）はなし（critique §6 の shell-and-panes.md 欄）。v2 は上記 4 点の推奨修正のみ反映。

---

## 0d. 本設計の要点（3行）

1. **3ファイルとも「薄い合成ルート（facade）+ 単一状態所有者 + 協調 view/純関数」に分割**し、既存ファイルはロジックなしの thin re-export シム（P2 の `connection_provider.dart` / `resize_dialog.dart` と同パターン）に書き換える。呼出元・テストの import パスは一切不変。
2. **home_screen.dart は `CurrentTabNotifier`/`currentTabProvider` を中立モジュール `lib/navigation/current_tab_provider.dart` へ、ボトムナビ 210 行を `home/widgets/home_bottom_nav_bar.dart` へ分離**。`_TerminalTab`/`_EmptySessionsView`/`_SessionCard`（計 540 行）は **HEAD でインスタンス化ゼロのデッドコード**（ユーザー承認済みで削除案 A）。
3. **markdown はスクロール比率連動トグル・static ScrollKey・`MarkdownCodeBlock` をテストが直接固定**（markdown_preview_screen_test.dart 実測）→ これらを完全維持したまま、状態所有（State）とプレゼンテーション（body/コードブロック）へ分割。notification はフラグ→スタイルの純関数 7 種を分離。

---

## 1. 現状分析（事実・行番号は HEAD 基準）

### 1.1 `lib/screens/home_screen.dart`（814 行）

**1 ファイルに同居する責務:**

| 範囲 | シンボル | 責務 | 行数 | 実行有無 |
|---|---|---|---|---|
| 26-37 | `CurrentTabNotifier` + `currentTabProvider` | タブインデックス状態（Notifier） | 12 | **ACTIVE** |
| 39-272 | `HomeScreen`（ConsumerWidget） | 5 タブの IndexedStack 合成ルート + ボトムナビ | 234 | **ACTIVE** |
| 63-151 | `_buildBottomNavigationBar` | ボトムナビ骨格（Container/SafeArea/Row/中央スペーサ） | 89 | ACTIVE |
| 152-207 | `_buildCenterButton` | 中央の円形 Dashboard ボタン | 56 | ACTIVE |
| 208-272 | `_buildNavItem` | 通常ナビ項目（アイコン/ラベル/インジケータ） | 65 | ACTIVE |
| 274-280 | `_TerminalTab`（ConsumerStatefulWidget） | アクティブセッション一覧タブ | 7 | **デッド** |
| 281-504 | `_TerminalTabState` | 一覧表示・リロード（SSH 接続して全接続先を走査）・開閉 | 224 | **デッド** |
| 378-471 | `_reloadSessions` | 全コネクションを SSH で巡回しセッション一覧を更新 | 94 | **デッド** |
| 505-564 | `_EmptySessionsView` | 未接続時空表示 | 60 | **デッド** |
| 565-814 | `_SessionCard` | セッションカード（Dismissible + 確認ダイアログ） | 250 | **デッド** |

**デッドコードの証拠（実測）:**
- `rg -n "_TerminalTab" lib/ test/` → 定義 4 箇所（L274/275/278/281）のみ。**インスタンス化ゼロ**。home_screen.dart 外の参照ゼロ。
- HEAD の `HomeScreen.build`（L49-62）の IndexedStack children は `ConnectionsScreen/KeysScreen/DashboardScreen/NotificationPanesScreen/SettingsScreen` の 5 画面。`_TerminalTab` は含まれない。
- git 履歴: `8aab2ec` 時点では `children: const [ConnectionsScreen(), _TerminalTab(), ...]`（タブ0）。その後 ConnectionsScreen へ置換され、`_TerminalTab` は残置。
- l10n キー `homeActiveSessions/homeReloadSessions/homeNoActiveSessions/homeConnectToServerToStartTerminal/homeCloseSessionTitle/homeCloseSessionMessage/homeAttached/homeDetached/homeLastWindow` は home_screen.dart のデッドコード内でのみ使用（`rg` で lib/ 他ファイル・test/ 参照ゼロ）。arb 生成物は変更禁止のため**キーは残す**（未使用になっても生成物は不変）。

**状態/コントローラ所有権インベントリ（ACTIVE 部のみ）:**
- `CurrentTabNotifier`（Notifier）: `int` state の所有者。生成: provider 初期化。破棄: なし（ProviderScope 生存期間）。更新通知: `ref.watch`（HomeScreen.build）/ `ref.listen`（settings_search_field L69）。
- HomeScreen は ConsumerWidget で**フィールド状態・コントローラ・タイマーを持たない**。

**呼出元（rg 実測）→ 公開 API 面:**

| 呼出元 | import パス | 使用シンボル |
|---|---|---|
| `lib/main.dart` L12/L177 | `package:flutter_muxpod/screens/home_screen.dart` | `HomeScreen`（`home: const HomeScreen()`） |
| `lib/screens/connections/connections_screen.dart` L10/L172 | `../home_screen.dart` | `currentTabProvider`（`.notifier.setTab(3)`） |
| `lib/screens/keys/keys_screen.dart` L9/L90 | `../home_screen.dart` | `currentTabProvider`（`.notifier.setTab(3)`） |
| `lib/screens/settings/widgets/settings_search_field.dart` L6/L69 | `../../home_screen.dart` | `currentTabProvider`（`ref.listen` → unfocus） |
| `lib/screens/settings/settings_screen.dart` L12 | —（コメントのみ・import なし） | `HomeScreen` 言及 |

→ **`CurrentTabNotifier`・`currentTabProvider`・`HomeScreen` は `screens/home_screen.dart` 経由で利用可能でなければならない**（import パス維持）。

**既存テストが固定する挙動:**
- `test/widget_test.dart`（MyApp smoke）: `home: const HomeScreen()` を build。HomeScreen が例外なく build できれば OK。タブ初期値 2（Dashboard）は CurrentTabNotifier.build() の既定値（L30）。
- home_screen を直接 import するテストは**ゼロ**（rg 実測）。`currentTabProvider` を test/ で override/参照するテストも**ゼロ**。
- keys_screen_test は `KeysScreen()` 単体 pump（L17-24）で、`setTab(3)` 呼び出しは発火しない/発火しても provider が自動生成されるだけ。connections_screen_* テストも ConnectionsScreen 単体。→ タブ Notifier の置き場所変更でテストは影響しない。

### 1.2 `lib/screens/notifications/notification_panes_screen.dart`（519 行）

| 範囲 | シンボル | 責務 | 行数 |
|---|---|---|---|
| 15-22 | `NotificationPanesScreen`（ConsumerStatefulWidget） | 公開 widget エントリ | 8 |
| 23-235 | `_NotificationPanesScreenState` | 状態所有（`_isRefreshing`）・refresh 開始・アラート解放オーケストレーション・一覧/AppBar/空表示 | 213 |
| 28-33 | `initState` | postFrameCallback で `_refresh()` | 6 |
| 35-45 | `_refresh` | `_isRefreshing` ガード → `alertPanesProvider.refresh()` → finally で `mounted` チェック付き解除 | 11 |
| 47-88 | `_openAlertPane` | 同一 windowKey の dismiss → `clearWindowFlag` → `activeSessionsProvider.addOrUpdateSession` → `Navigator.push(TerminalScreen)` | 42 |
| 90-95 | `_dismissAlert` | `dismiss(key)` + `clearWindowFlag` | 6 |
| 98-143 | `build` | RefreshIndicator + CustomScrollView + SliverList（`_AlertPaneCard`） | 46 |
| 144-195 | `_buildAppBar` | SliverAppBar + refresh ボタン（`_isRefreshing` でスピナー） | 52 |
| 196-235 | `_buildEmptyState` | 空表示（アイコン/2 テキスト） | 40 |
| 236-519 | `_AlertPaneCard`（StatelessWidget） | Dismissible カード（フラグアイコン/接続情報/バッジ）+ フラグ→スタイル 7 関数 | 284 |
| 439-511 | `_flagIcon`/`_flagIconColor`/`_flagBackgroundColor`/`_flagBorderColor`/`_flagBadgeBackground`/`_flagBadgeBorder`/`_flagLabel` | `TmuxWindowFlag → IconData/Color/Color/Color/Color/Color/String` の純入出力マッピング | 73 |

**状態所有権:**
- `_isRefreshing`（bool）: 所有者 State。生成: フィールド初期化（L24）。破棄: なし（State 生存期間・`setState(false)` で解除）。更新通知: `setState` → build。
- Timer/StreamSubscription/FocusNode/Controller: **なし**。
- 非同期ギャップ: `_refresh` の finally 内 `if (mounted)`（L43）→ 分割後も維持。

**呼出元（rg 実測）→ 公開 API 面:**
- import 元は **`lib/screens/home_screen.dart` の 1 ファイルのみ**（`import 'notifications/notification_panes_screen.dart';`、HomeScreen L57 で `NotificationPanesScreen()`）。
- テスト: **直接参照ゼロ**（`rg -n "NotificationPanesScreen|notification_panes_screen" test/` → 0 件）。`notification_panes_provider_test.dart` は provider 層のみ（画面非依存）。
- 間接実行経路: `test/widget_test.dart` の MyApp smoke で `NotificationPanesScreen` が IndexedStack の子として build され、initState → postFrame → `_refresh` が走る。SSH 失敗時も provider が例外を throw しないため smoke は成功（現行仕様・分割で変更しない）。

### 1.3 `lib/screens/file_browser/markdown_preview_screen.dart`（533 行）

| 範囲 | シンボル | 責務 | 行数 |
|---|---|---|---|
| 27-47 | `MarkdownPreviewScreen`（ConsumerStatefulWidget） | 公開 widget。`static const rawScrollKey/renderedScrollKey` | 21 |
| 40-41 | `static const Key rawScrollKey/renderedScrollKey` | トグル・スクロール用安定キー（`'mdScrollRaw'`/`'mdScrollRendered'`） | 2 |
| 48-475 | `_MarkdownPreviewScreenState` | 状態所有 + 全ビュー構築 | 428 |
| 50-51 | `_rawController`/`_renderedController`（ScrollController×2） | per-view スクロール保持（合意#5） | 2 |
| 54 | `_showRendered` | Rendered 既定（D-4） | 1 |
| 57 | `_mdBaseDirectory`（late final） | 相対画像の SFTP 解決基準（合意#7） | 1 |
| 59-67 | `initState` | postFrame → `_reload` | 9 |
| 69-74 | `dispose` | `_rawController.dispose(); _renderedController.dispose(); super.dispose();` | 6 |
| 76-86 | `_reload` | `markdownPreviewProvider.notifier.load(connectionId, entry)` | 11 |
| 88-104 | `_onToggleView` | スクロール比率連動トグル（postFrame jumpTo） | 17 |
| 106-124 | `build` | Scaffold + トグルバー + body | 19 |
| 126-163 | `_buildToggleBar` | ファイル名 + Raw/Rendered SegmentedButton | 38 |
| 164-327 | `_buildBody` | 状態分岐（loading/error/tooLarge/binary/empty/content） | 164 |
| 328-361 | `_buildTruncatedBanner` | 切詰め警告バナー | 34 |
| 362-383 | `_buildRenderedView` | MarkdownBody + builders/imageBuilder/onTapLink + 縦スクロール | 22 |
| 384-407 | `_buildRawView` | SelectableText + 縦スクロール | 24 |
| 408-452 | `_buildImage` | `SftpMarkdownImage.resolveImage` 3 分岐（sftp/network/denied） | 45 |
| 453-475 | `_onTapLink`/`_launchExternal`（static） | https/http のみ外部ブラウザ起動 | 23 |
| 476-503 | `_MarkdownCodeElementBuilder`（MarkdownElementBuilder） | language-xxx class 抽出 → `MarkdownCodeBlock` | 28 |
| 504-533 | `MarkdownCodeBlock`（StatelessWidget） | フェンスドコードのハイライト表示（横スクロール） | 30 |

**状態所有権:**
- `_rawController`/`_renderedController`: 所有者 State。生成: フィールド初期化。破棄: `dispose`（**既知順序: `_raw` → `_rendered` → `super.dispose()`**）。更新通知: `controller.position`（SingleChildScrollView 経由）。
- `_showRendered`: 所有者 State。破棄なし。更新通知: `setState` → `_buildBody` 分岐・SegmentedButton.selected。
- `_mdBaseDirectory`: 所有者 State（late final）。`p.posix.dirname(widget.entry.fullPath)`。
- 非同期ギャップ: `_onToggleView` の postFrame 内 `if (!mounted) return; if (target.hasClients ...)`（L92-103）。initState の postFrame 内 `if (!mounted) return;`（L61-63）。

**呼出元（rg 実測）→ 公開 API 面:**

| 呼出元 | import パス | 使用シンボル |
|---|---|---|
| `lib/screens/file_browser/file_browser_screen.dart` L20/L638 | `import 'markdown_preview_screen.dart';` | `MarkdownPreviewScreen(connectionId:, entry:)` |
| `test/.../file_browser_markdown_flow_test.dart` L12 | `package:flutter_muxpod/screens/file_browser/markdown_preview_screen.dart` | `MarkdownPreviewScreen`（byType, 5 箇所） |
| `test/.../markdown_preview_screen_test.dart` L12 | 同上 | `MarkdownPreviewScreen`（コンストラクタ）/ `MarkdownPreviewScreen.rawScrollKey` / `.renderedScrollKey` / `MarkdownCodeBlock`（byType） |

※ タスク説明の「関連テスト 2 本（file_browser_download_flow_test, markdown_preview_screen_test）」のうち、**file_browser_download_flow_test は markdown を一切参照しない**（rg 実測 0 件）。実際の markdown 関連テストは **file_browser_markdown_flow_test（236 行）+ markdown_preview_screen_test（828 行）**。設計は実測を基準とする。

**既存テストが固定する挙動（markdown_preview_screen_test.dart 実測・テスト名付き）:**
- **基本表示**（L153: `AppBar タイトルとファイル名を表示する`）: `find.text('Markdown Preview')` / `find.text('readme.md')` / RichText で `Title`・`world` → Rendered 既定（D-4）。
- **H-3**（L169: `H-3: initState 直後の postFrame で load が開始される`）: `_FakeMarkdownNotifier` override で `notifier.loadCalls == 1` → **initState postFrame で `notifier.load` が 1 回だけ呼ばれる**ことが固定。
- **トグル**（L200: `Rendered→Raw（SelectableText）→Rendered を往復できる`）: `find.byType(SelectableText)` の有無 / RichText の有無。**L212: 言語なしコードは `MarkdownCodeBlock` が生成されない**（既定 pre 描画）。
- **スクロール比率連動**（L228: `トグル時に現在ビューのスクロール比率を他ビューへ適用する（合意#5）`）: `MarkdownPreviewScreen.renderedScrollKey` / `rawScrollKey` の `Scrollable` を取得し、postFrame 後に `ratio × 新 maxScrollExtent` へ `jumpTo`。→ **static key と `_onToggleView` の実装（postFrame ×2 pump、offset/maxScrollExtent 比率、hasClients ガード）が固定**。
- **状態表示**（L285-392 の 6 本）: mdEmpty / mdLoadFailed+mdRetry 再試行復帰（`onPressed: _reload`）/ mdBinaryFile（本文非表示）/ mdFileTooLarge（SFTP 非アクセス・`openedPaths` 空）/ mdTruncatedMessage バナー / バイナリ&&切詰め複合時はバイナリ優先。
- **画像ガード**（L407）: `_RecordingSftpClient.openedPaths` で「md 本体 + 許可相対パス 1 件のみ」→ `SftpMarkdownImage.resolveImage` の呼び出し経路と placeholder/Image.network 分岐が固定。
- **言語別ハイライト**（L611: `言語指定フェンスドコードはハイライト（色付きスパン）で表示する`）: `find.byType(MarkdownCodeBlock)` が **1 つ**、その子 `RichText` のスパンに色付き（`_hasColoredTextSpan`）→ `MarkdownCodeBlock` のウィジェット名・内容表示・ハイライトが固定。
- **リンクガード**（L730: `https リンクのみ外部ブラウザへ launch する`）: MethodChannel モックで `launch` 1 回 + `canLaunch` 1 回、URL 完全一致。L756（mailto/#anchor はタップ無視・canLaunch も呼ばれない）→ `_onTapLink`/`_launchExternal` のスキーム検証が固定。
- `MarkdownCodeBlock` は**公開**（byType で参照）。`_MarkdownCodeElementBuilder` は private（テスト直接参照なし、builder 登録は `MarkdownBody.builders: {'code': ...}` 経由）。

---

## 2. 目標構成（全ファイル 500 行未満・数値根拠つき）

### 2.1 home（現行 814 行 → 分割後 5 ファイル + thin re-export 1 + 中立 1）

| # | ファイル | 責務 | 公開シンボル | 推定行数 | 根拠 |
|---|---|---|---|---|---|
| 0 | `lib/navigation/current_tab_provider.dart`（**新設・中立**） | タブインデックス状態（Notifier）。現 L26-37 を 1:1 移動。**screens を一切 import しない**（依存ゼロ・SCC 不入り） | `CurrentTabNotifier` / `currentTabProvider` | ~15 | 現行 12 行 + doc/import。パス根拠: §付録 ①。P2 の `providers/` がデータ系・サービス系に整理済みで「UI タブ状態」の置き場が無いため lib 直下に新規 `navigation/` を設ける |
| 1 | `screens/home_screen.dart`（**既存を書き換え**） | **thin re-export シム**。doc に「実装は home/ 配下 + navigation/ へ」と明記し、`currentTabProvider`・`HomeScreen` を再 export（または中立から re-export） | `CurrentTabNotifier` / `currentTabProvider` / `HomeScreen`（現行と同一） | ~10 | export 2 行 + コメント。P2 の `connection_provider.dart` / `resize_dialog.dart` と同パターン。**再 export は一方向（中立は screens を import しない）ため循環にならない** |
| 2 | `screens/home/home_screen.dart` | 5 タブの IndexedStack **合成ルート**（facade）。`HomeBottomNavBar` を合成し、`ref.watch(currentTabProvider)` → `onSelectTab` を配線。中立モジュールを import | `HomeScreen`（コンストラクタ不変） | ~70 | 現行 L39-62（build 24 行）+ import + 合成呼び出し |
| 3 | `screens/home/widgets/home_bottom_nav_bar.dart` | ボトムナビゲーションバー（骨格/中央ボタン/ナビ項目/インジケータ）。現 L63-272 の 3 メソッドを `HomeBottomNavBar`（`currentTab` + `onSelectTab` を props 注入）へ統合 | `HomeBottomNavBar`（**素の public 化**・home 内部専用 doc） | ~230 | 現行 210 行 + class 境界・doc・props。500 未満を満たす |
| 4 | `screens/home/active_sessions/`（デッドコード） | `_TerminalTab` 等 540 行。**削除（ユーザー承認済み）** | — | 0 | 項 8 の確定事項 |

**相互循環の解消（v3・ユーザー指摘反映）:**

現行 `currentTabProvider` は `home_screen.dart` 定義のため、connections/keys/settings_search_field → home_screen の**逆辺 3 本**が存在し、`lib/screens` の 10 ファイルが 1 SCC を形成（実測・§0b）。v3 では: 

- **必ず**: `CurrentTabNotifier`/`currentTabProvider` を `lib/navigation/current_tab_provider.dart` へ抽出（**中立・screens 非依存**）。
- **必ず**: connections/keys/settings_search_field の 3 ファイルは **`home_screen.dart` を import しない**。代わりに `navigation/current_tab_provider.dart` を**直接 import** して `currentTabProvider` を使う（`import '../../navigation/current_tab_provider.dart'` 等。相対パスは実装時解決）。
- home_screen.dart シムは互換のため中立モジュールを re-export する（`export 'package:flutter_muxpod/navigation/current_tab_provider.dart' show CurrentTabNotifier, currentTabProvider;`）。**main.dart の `import 'package:flutter_muxpod/screens/home_screen.dart'; home: const HomeScreen()` は不変**。
- 本設計の eval で SCC ゼロを実証（§0b: PRE size=10 → POST なし）。connections-screen.md §6-6 の「現行どおり維持」方針に対し、**本設計が受け皿として中立モジュール直接 import を確定**する（2 書間の整合事項・§8-4）。

合計（主案・デッドコード削除）: ≈ **325 行**（現行 814 行から -60%）。全ファイル最大 ~230 行 < 500。依存方向: `navigation/current_tab_provider.dart`（依存ゼロ）← `home_screen.dart`(re-export)・`home/home_screen.dart`・connections/keys/settings_search_field。`home_screen.dart` → `home/home_screen.dart` → `widgets/home_bottom_nav_bar.dart`。**screens 配下に循環なし**（§0b 機械検証）。

### 2.2 notification（現行 519 行 → 3 ファイル + thin re-export 1）

| # | ファイル | 責務 | 公開シンボル | 推定行数 | 根拠 |
|---|---|---|---|---|---|
| 1 | `notifications/notification_panes_screen.dart`（**既存を書き換え**） | **thin re-export シム**。doc に実装先明記 | `NotificationPanesScreen` | ~8 | home_screen.dart の import パス維持 |
| 2 | `notifications/panes/notification_panes_view.dart` | **画面ルート（facade）+ 単一状態所有者**。State（`_isRefreshing`・refresh・解放オーケストレーション・一覧/AppBar/空表示）を移設 | `NotificationPanesScreen`（実体・コンストラクタ不変） | ~225 | 現行 L15-235（213 行）+ class 境界。`_AlertPaneCard` 呼び出しは props 配線へ |
| 3 | `notifications/panes/alert_pane_card.dart` | アラートペインカード 1 枚の表示（Dismissible + フラグアイコン/情報/バッジ）。現 L236-438 を移設 | `AlertPaneCard`（**素の public 化**・private から昇格） | ~210 | 現行カード部 203 行（L236-438）+ class/import |
| 4 | `notifications/panes/alert_flag_style.dart` | `TmuxWindowFlag → 見た目` の純関数 7 種（icon/iconColor/背景/枠/バッジ背景/バッジ枠/label）。現 L439-519 をトップレベル関数へ 1:1 移動 | `alertFlagIcon` ほか 7 関数（**素の public 化**） | ~90 | 現行 73 行 + doc。純ロジック・単体テスト容易化 |

合計: ≈ **533 行**（ほぼ現行並み・境界/import の増分を吸収して +3%）。全ファイル最大 ~225 行 < 500。依存: `notification_panes_screen.dart`(re-export) → `panes/notification_panes_view.dart` → `panes/alert_pane_card.dart` + `panes/alert_flag_style.dart`。一方向。

### 2.3 markdown（現行 533 行 → 4 ファイル + thin re-export 1 + 中立 1）

| # | ファイル | 責務 | 公開シンボル | 推定行数 | 根拠 |
|---|---|---|---|---|---|
| 0 | `file_browser/markdown_preview/markdown_scroll_keys.dart`（**新設・中立**） | **static ScrollKey の中立定義**。`const Key('mdScrollRaw')` / `const Key('mdScrollRendered')` を公開。**screens の他ファイルを一切 import しない**（依存ゼロ・SCC 不入り） | `rawScrollKey` / `renderedScrollKey`（または `MarkdownScrollKeys` クラスの static const） | ~8 | 現行 L40-41 の値を 1:1 移動。パス根拠: §付録 ②。body・screen(impl)・テストがここを参照 |
| 1 | `file_browser/markdown_preview_screen.dart`（**既存を書き換え**） | **thin re-export シム**。doc に実装先明記 | `MarkdownPreviewScreen` / `MarkdownCodeBlock` | ~12 | file_browser_screen + テスト 2 本の import パス維持 |
| 2 | `file_browser/markdown_preview/markdown_preview_screen.dart` | **Screen + 単一状態所有者**。`MarkdownPreviewScreen` + State（controllers/showRendered/baseDirectory/init/dispose/reload/toggle/build 骨格）。**static keys は中立値への静的 getter として残す** | `MarkdownPreviewScreen`（コンストラクタ不変・`rawScrollKey`/`renderedScrollKey` は getter 化） | ~150 | 現行 L27-163（137 行）+ import 整理。build は body へ委譲 |
| 3 | `file_browser/markdown_preview/markdown_preview_body.dart` | **状態→ビュー構築のプレゼンテーション層**。`_buildBody`/`_buildTruncatedBanner`/`_buildRenderedView`/`_buildRawView`/`_buildImage`/`_onTapLink`/`_launchExternal`。`MarkdownPreviewBody` が state/controllers/showRendered/onReload/onToggle を props 受領し、State は委譲。**ScrollKey は中立 `markdown_scroll_keys.dart` のみを参照**（screen 実装を import しない） | `MarkdownPreviewBody`（**素の public 化**） | ~280 | 現行 L164-475（312 行）から props 化・doc を差し引き |
| 4 | `file_browser/markdown_preview/markdown_code_block.dart` | フェンスドコードハイライト。現 L476-533 を移設 | `MarkdownCodeBlock`（**公開維持**・byType 参照）/ `MarkdownCodeElementBuilder`（**素の public 化**） | ~65 | 現行 58 行 + import。テストの `find.byType(MarkdownCodeBlock)` を維持 |

合計: ≈ **515 行**（-3%）。全ファイル最大 ~280 行 < 500。依存（v3）: `markdown_preview_screen.dart`(re-export) → `markdown_preview/markdown_preview_screen.dart` → `markdown_preview_body.dart` + `markdown_code_block.dart`。**`markdown_preview_screen.dart`(impl) と `markdown_preview_body.dart` は共に中立 `markdown_scroll_keys.dart` を import**。body → 中立（既定的方向）のため **body → screen の逆辺は存在しない**（v2 の 2-cycle は解消）。screen（impl）→ body の一方向のみ。SCC 検証 §0b で POST 非巡回を確認。

**static keys の getter 化（必須修正 B・テスト維持）:**

```dart
// lib/screens/file_browser/markdown_preview/markdown_scroll_keys.dart（新設・中立）
abstract final class MarkdownScrollKeys {
  static const Key rawScrollKey = Key('mdScrollRaw');
  static const Key renderedScrollKey = Key('mdScrollRendered');
}

// lib/screens/file_browser/markdown_preview/markdown_preview_screen.dart（impl）
class MarkdownPreviewScreen extends ConsumerStatefulWidget {
  /// トグル・スクロール操作用の安定キー（テストから参照可）。
  /// 実体は中立 [MarkdownScrollKeys] の static const。
  static Key get rawScrollKey => MarkdownScrollKeys.rawScrollKey;
  static Key get renderedScrollKey => MarkdownScrollKeys.renderedScrollKey;
  ...
}
```

- テスト（markdown_preview_screen_test L246/251/270）は `MarkdownPreviewScreen.rawScrollKey` / `.renderedScrollKey` を**クラス静的参照** → getter が中立の const Key を返すため、`find.byKey` は同じ const インスタンスに一致（const 正準化により identity 一致）。**テスト変更ゼロ**。
- `Key('mdScrollRaw')` が const であるため、getter は常に同一の canonical インスタンスを返す → `byKey`/`find.byKey` の等価性が保証される（実測: 現 L40-41 も const Key）。

---

## 3. 移動マッピング

### 3.1 home_screen.dart

| 既存メンバー（HEAD 行範囲） | 移動先 | 種別 |
|---|---|---|
| `CurrentTabNotifier` + `currentTabProvider`（L26-37） | `lib/navigation/current_tab_provider.dart`（**中立**） | **移動のみ**（1:1 写経）。screens を import しない |
| `HomeScreen.build`（L41-62） | `home/home_screen.dart` | 移動 + `_buildBottomNavigationBar` → `HomeBottomNavBar` 合成へ変更 | 
| `_buildBottomNavigationBar`（L63-151） | `home/widgets/home_bottom_nav_bar.dart` の `HomeBottomNavBar.build` | 移動 + メソッド→props（currentTab/onSelectTab）化 |
| `_buildCenterButton`（L152-207） | 同上 `_buildCenterButton` | 移動のみ（props 化） |
| `_buildNavItem`（L208-272） | 同上 `_buildNavItem` | 移動のみ（props 化） |
| `_TerminalTab`/`_TerminalTabState`（L274-504） | **削除（ユーザー承認済み・デッドコード）** | 削除 |
| `_EmptySessionsView`（L505-564） | 同上 | 削除 |
| `_SessionCard`（L565-814） | 同上 | 削除 |
| import 群（L1-24 のうち herdr/tmux/ssh/secure_storage の 8 本） | 削除（デッドコード専用 import） or 移設先へ | 条件付き削除/移動 |

### 3.2 notification_panes_screen.dart

| 既存メンバー（HEAD 行範囲） | 移動先 | 種別 |
|---|---|---|
| `NotificationPanesScreen`（L15-22）+ State（L23-235） | `panes/notification_panes_view.dart` | **移動のみ**。`_refresh` の finally `mounted` ガード（L43）・`build` の RefreshIndicator/SliverList 形状・`_buildAppBar`・`_buildEmptyState` は 1:1 写経 |
| `_AlertPaneCard`（L236-438） | `panes/alert_pane_card.dart` の `AlertPaneCard` | 移動 + private→**素の public 化**（`// ignore_for_file: library_private_types_in_public_api` を明示添付してもよい）。Dismissible key `Key(alert.key)`・`onDismissed`→`onDismiss` props は不変 |
| `_flagIcon` ほか 7 関数（L439-519） | `panes/alert_flag_style.dart` のトップレベル関数 | **移動のみ**（switch の分岐・alpha 値・色は 1:1） |
| `_openAlertPane`/`_dismissAlert`（L47-95） | `panes/notification_panes_view.dart`（State 内に残す） | 移動のみ（`addOrUpdateSession`・`clearWindowFlag` の順序は不変） |

### 3.3 markdown_preview_screen.dart

| 既存メンバー（HEAD 行範囲） | 移動先 | 種別 |
|---|---|---|
| `MarkdownPreviewScreen`（L27-47） | `markdown_preview/markdown_preview_screen.dart` | **移動のみ**。コンストラクタ（connectionId/entry）は不変。**static keys L40-41 は中立 `markdown_scroll_keys.dart` へ移動し、本クラスは getter 化**（v3・必須修正 B） |
| `_MarkdownPreviewScreenState` の状態所有部（L50-104） | 同上（State） | **移動のみ**。controllers 初期化・initState postFrame・dispose 順序・`_reload`・`_onToggleView` は 1:1 写経 |
| `build`・`_buildToggleBar`（L106-163） | 同上（State） | 移動のみ。`MarkdownPreviewBody` へ props 配線 |
| `_buildBody`（L164-327） | `markdown_preview_body.dart` の `MarkdownPreviewBody.build` | 移動 + `_buildRenderedView`/`_buildRawView`/`_buildImage`/`_buildTruncatedBanner` を営み先として props 化 |
| `_buildTruncatedBanner`（L328-361） | 同上 | 移動のみ |
| `_buildRenderedView`（L362-383） | 同上 | 移動のみ（**`key: MarkdownScrollKeys.renderedScrollKey`・`controller: _renderedController` の配線は不変**。body は中立参照） |
| `_buildRawView`（L384-407） | 同上 | 移動のみ（`MarkdownScrollKeys.rawScrollKey`・`_rawController` 配線不変） |
| `_buildImage`（L408-452） | 同上 | 移動のみ（`SftpMarkdownImage.resolveImage` 分岐は 1:1） |
| `_onTapLink`/`_launchExternal`（L453-475） | 同上（トップレベル **素の public 関数**へ） | 移動のみ（static のためクラス非依存） |
| `_MarkdownCodeElementBuilder`（L476-503） | `markdown_code_block.dart` | 移動 + private→**素の public 化**（言語抽出・null フォールバック D-2 は不変） |
| `MarkdownCodeBlock`（L504-533） | 同上 | **移動のみ**（公開のまま・`find.byType` 維持） |

---

## 4. 公開 API 維持表

| 維持シンボル | 実装先 | thin re-export するファイル | import 不変の根拠（rg 実測） |
|---|---|---|---|
| `HomeScreen` | `home/home_screen.dart` | `screens/home_screen.dart`（`show HomeScreen`） | `main.dart` L12/L177（`package:.../screens/home_screen.dart`）。re-export で同パスから解決 |
| `CurrentTabNotifier` / `currentTabProvider` | `navigation/current_tab_provider.dart`（**中立・新設**） | `screens/home_screen.dart`（`show` re-export・互換） | **v3 必須対応**: `connections_screen.dart` L10/L172・`keys_screen.dart` L9/L90・`settings_search_field.dart` L6/L69 は現行 `home_screen.dart` を import するが、これは **SCC を生む逆辺 3 本**（実測・§0b）。v3 では 3 ファイルは `home_screen.dart` を import せず、**`navigation/current_tab_provider.dart` を直接 import** して `currentTabProvider` を使用（相対パスは実装時に解決）。Riverpod の NotifierProvider はトップレベル最終フィールドのため、**定義位置が変わっても同一 provider インスタンスとして機能**。`main.dart` は `screens/home_screen.dart` のまま（シムが中立を re-export → `home: const HomeScreen()` 不変）。re-export は一方向のため循環にならない。SCC 機械検証済み（§0b-4: POST 非巡回） |
| `NotificationPanesScreen` | `notifications/panes/notification_panes_view.dart` | `notifications/notification_panes_screen.dart` | `home_screen.dart` L57 が `notifications/notification_panes_screen.dart` を import |
| `MarkdownPreviewScreen`（+ `rawScrollKey`/`renderedScrollKey`） | `markdown_preview/markdown_preview_screen.dart`（getter 実装）+ `markdown_preview/markdown_scroll_keys.dart`（中立 const） | `file_browser/markdown_preview_screen.dart` | `file_browser_screen.dart` L20/L638・`file_browser_markdown_flow_test.dart` L12・`markdown_preview_screen_test.dart` L12 が同パスを import。テストは `MarkdownPreviewScreen.rawScrollKey` / `.renderedScrollKey` を**クラス静的参照**（L246/L251/L270）→ **v3 では中立値への静的 getter として残す**（const 正準化により `find.byKey` は同一インスタンスに一致・テスト変更ゼロ）。静的参照ができるためクラス定義の維持が必須（やはり getter は記述を満たす） |
| `MarkdownCodeBlock` | `markdown_preview/markdown_code_block.dart` | `file_browser/markdown_preview_screen.dart`（`show MarkdownCodeBlock`） | テスト L212/L622/L623/L651 が `find.byType(MarkdownCodeBlock)`。re-export によりテストの import 1 行で解決 |

変更される公開面（いずれも private → **素の public 化**のみで**破壊的変更なし**）: `AlertPaneCard`・`HomeBottomNavBar`・`MarkdownPreviewBody`・`MarkdownCodeElementBuilder`・`alert_flag_style.dart` の 7 関数。**v2 注記**: v1 で「P2 の `rdialog.md` と同方針（@internal）」と記載していたが、**P2 実装（HEAD）に `@internal` 使用は 0 件**（rg 実測）であり「承認済み」ではない（P2 critique §2.5 は検討余地の提示に留まる）。`@internal` を別ファイル（別ライブラリ）の public シンボルへ付けると `invalid_use_of_internal_member` lint が警告になり得るため、**素の public 化（または `// ignore` 明示）を採る**。public 化で `library_private_types_in_public_api` が発出するのは「private 型を public シグネチャへ晒す場合」のみであり、本設計の移設対象は同名の public クラスへ昇格するため該当しない。

---

## 5. 状態所有権表（原則 6）

### home

| 状態 | 所有者 | 生成 | 破棄 | 更新通知経路 |
|---|---|---|---|---|
| `int` タブインデックス | `CurrentTabNotifier`（Notifier） | provider 初期化（`build() => 2`） | なし（ProviderScope 生存期間） | `state =` → `ref.watch`（HomeScreen）/ `ref.listen`（settings_search_field L69）→ build/unfocus |
| コントローラ/Focus/Timer/Subscription | —（なし） | — | — | — |

### notification

| 状態 | 所有者 | 生成 | 破棄 | 更新通知経路 |
|---|---|---|---|---|
| `_isRefreshing` | `_NotificationPanesScreenState`（通知 view の State） | フィールド初期化（false） | State 生存期間（finally で `setState(false)`・L43 の `mounted` ガード維持） | `setState` → AppBar スピナー/`onPressed: null`・RefreshIndicator |
| アラート一覧・loading・error | `AlertPanesNotifier`（provider・**変更しない**） | provider | provider | `state =` → `ref.watch(alertPanesProvider)` → SliverList |

### markdown

| 状態 | 所有者 | 生成 | 破棄 | 更新通知経路 |
|---|---|---|---|---|
| `_rawController` / `_renderedController` | `_MarkdownPreviewScreenState`（markdown view の State） | フィールド初期化 | **`dispose`: `_raw.dispose()` → `_rendered.dispose()` → `super.dispose()`（現行順序を維持）** | `controller` → SingleChildScrollView（key は中立 `MarkdownScrollKeys.rawScrollKey`/`.renderedScrollKey`（body が参照）・値は `MarkdownPreviewScreen.*` getter と同一 const） |
| `_showRendered` | 同上 | フィールド初期化（true） | State 生存期間 | `setState` → SegmentedButton.selected + body 分岐 + `_onToggleView` の比率連動 |
| `_mdBaseDirectory` | 同上（late final） | 初回参照時（`p.posix.dirname`） | State 生存期間 | `_buildImage` → `SftpMarkdownImage.resolveImage(mdBaseDirectory:)` |
| md コンテンツ・フラグ | `MarkdownPreviewNotifier`（provider・**変更しない**） | provider | provider | `state =` → `ref.watch(markdownPreviewProvider)` → body 分岐 |

**ライフサイクル順序（HEAD と一致させる箇所）:**
- markdown: `initState` → `WidgetsBinding.addPostFrameCallback` → `_reload`（`notifier.load`）。`dispose` 順序は上記。`_onToggleView` 内の postFrame ×2 pump（テスト L238-241）・`hasClients`/`maxScrollExtent > 0` ガード・`mounted` チェックは State 内に残す（body へ移さない）。
- notification: `initState` → postFrame → `_refresh`。`_refresh` の `_isRefreshing` ガード（L35）と finally `mounted`（L43）は State 内に残す。

---

## 6. リスクと対策

| # | リスク | 影響 | 検出テスト（既存/新規） | 対策 |
|---|---|---|---|---|
| 1 | `_onToggleView` のスクロール比率連動が props 化で崩れる（postFrame/jumpTo のタイミング） | Raw⇄Rendered トグル時に他ビューのスクロール位置が一致しない | `markdown_preview_screen_test` L228（既存・差分ゼロ対象） | トグル・controller・`_showRendered` は State に残し、body へは**表示専用**として渡す。`_onToggleView` は移動しない |
| 2 | `dispose` の controller 破棄順序が変わる | Android で SchedulerBinding 例外・リーク | 既存テストなし → 新規単体（State dispose で controller が破棄済みになることを推測でなく構造で担保） | 移動マッピング §3.3 のとおり 1:1 写経。レビュー項目として明記 |
| 3 | `MarkdownPreviewScreen.rawScrollKey/renderedScrollKey` のクラス静的参照位置が変わる（中立ファイルへ移動） | テスト（L246/251/270）が `find.byKey` できなくなる | 既存 L228（差分ゼロ対象） | **v3 必須対応 B**: static const は中立 `markdown_scroll_keys.dart` へ移し、`MarkdownPreviewScreen` クラスは**同値を返す静的 getter** を残す（`static Key get rawScrollKey => MarkdownScrollKeys.rawScrollKey;`）。const 正準化により `find.byKey` は同一インスタンスに一致 → テスト変更ゼロ。body は中立のみ参照（screen を import しない） |
| 4 | `H-3`（initState postFrame で `load` 1 回）が崩れる | loadCalls==1 にならない | 既存 L169（差分ゼロ対象） | initState → postFrame → `_reload` → `notifier.load` の経路を State 内に 1:1 維持 |
| 5 | `CurrentTabNotifier` 型や `currentTabProvider` の中立モジュール移動で分析エラー（循環 import） | analyze 失敗 / SCC 残存 | `make analyze`（新規ゲート）+ `python3 /tmp/p3-design/scc_verify_v3.py`（SCC 機械検証） | **v3 必須対応 A**: 中立 `navigation/current_tab_provider.dart` は screens を一切 import しない。3 呼出元（connections/keys/settings_search_field）は中立を直接 import し home_screen を import しない。home_screen シムの re-export は一方向。§0b で SCC 非巡回（POST）を実証 |
| 6 | `_refresh` の `finally { if (mounted) setState(false) }` を State 外へ出すと setState-after-dispose | 通知画面の非同期ギャップ | 既存なし → レビュー指示で担保 | 状態所有（`_isRefreshing`・`_refresh`）は State に残し、`panes/notification_panes_view.dart` が単一所有者 |
| 7 | `MarkdownCodeBlock` を private のまま別ファイルへ移動するとコンパイル不能（同一ライブラリ制約） | build 失敗 | `make analyze` / `make test`（新規ゲート） | **素の public 化**（v2。`@internal` は P2 実績ゼロで lint 警告リスクのため不採用）。`MarkdownCodeBlock` は公開維持のまま `markdown_code_block.dart` へ |
| 12 | markdown の screen(impl) と body が相互 import（v2 の 2-cycle）になると改修後も SCC 残存 | ユーザー指摘の「相互循環参照が間違っている」が解消されない | `python3 /tmp/p3-design/scc_verify_v3.py`（POST で screens SCC ゼロ） | **v3 必須対応 B**: body は中立 `markdown_scroll_keys.dart` のみ参照し、screen(impl) を import しない。screen(impl) → body の一方向のみ。§0b で POST 非巡回を確認 |
| 8 | ボトムナビの `HomeBottomNavBar` props 化でタブ切替の tap 経路が変わる | タブ遷移（setTab）が発火しない | `widget_test.dart`（既存・MyApp smoke）+ 新規 home 合成テスト | `onTap: () => onSelectTab(index)` へ 1:1 移設。`setTab` 呼び出しは `home/home_screen.dart` が `ref.read(currentTabProvider.notifier)` で行う |
| 9 | `_flagLabel` の `AppLocalizations` 型引数（L511）を移設時に落とす | バッジ文言が変わる | 既存テストなし（provider テストのみ）→ 新規：`alert_flag_style` の純関数単体テスト | `alert_flag_style.dart` は `AppLocalizations` を import し `String Function(AppLocalizations, TmuxWindowFlag?)` の形を維持 |
| 10 | デッドコード（`_TerminalTab` 等 540 行）の扱いで行数制約が崩れる or 挙動に影響 | — | 削除ならば既存テストゼロ影響（rg 実測）。移設なら行数増 | 未確定点② 参照。**どちらでも HomeScreen の実行経路（widget_test）は不変**（IndexedStack children に含まれないため） |
| 11 | デッドコード削除後、未使用 import（herdr/tmux/ssh/secure_storage の 8 本）や l10n 生成 getter（`context.l10n.homeActiveSessions` 等 9 種）が `flutter analyze` で警告になる | v1 で検証計画に欠落していた（critique §5.1【中】） | 既存テストには出ない（未使用警告は analyzer）→ `make analyze` で確認する | 削除時は import 8 本を除去し、`flutter analyze` で**未使用 import 警告ゼロ**を確認。生成 getter は Dart の生成物（abstract getter）のため未使用でも警告なしが想定だが、**実際の警告出力を実装時に確認してゼロであること**をゲートに含める（§7 手順 2） |

---

## 7. 検証計画

```bash
# 1. フォーマット（差分ゼロ or 実装側のみ整形）
dart format --output=none --set-exit-if-changed .

# 2. 静的解析（P2 完了状態と同じゲート）
#    ※ v2 追加（critique §5.1）: デッドコード削除（案 A）を採る場合、
#      ここで「未使用 import」（herdr/tmux/ssh/secure_storage 系 8 本）が
#      除去済みであることと、l10n 生成 getter（homeActiveSessions 等 9 種）の
#      未使用警告がゼロであることを確認する
flutter analyze          # または make analyze

# 3. 全テスト（repro タグ除外・既存テストの差分ゼロ前提）
flutter test --exclude-tags=repro

# 4. 既存テストファイルが無変更であること（挙動不変・原則 4）
git diff HEAD -- test/    # 空であること（実装時に検証）

# 5. 生成物整合（P3 対象外ファイルの変更検出）
dart tool/generate_herdr_protocols.dart --check

# 6. 重点実行（テストが固定する挙動の回帰検出・上記 3 と重複可）
flutter test test/screens/file_browser/markdown_preview_screen_test.dart
flutter test test/screens/file_browser/file_browser_markdown_flow_test.dart
flutter test test/widget_test.dart
flutter test test/providers/notification_panes_provider_test.dart

# 7. 新規回帰テスト（任意・責務ベースの単体化）
#    - alert_flag_style: 7 関数の入出力（TmuxWindowFlag × l10n）
#    - home: currentTabProvider の既定値 2 / setTab
#    - markdown: dispose 順序（controller 破棄後アクセスで例外）

# 8. 構造循環の機械検証（v3 必須・ユーザー指摘対応）
#    PRE（実測）が screens SCC size=10、POST（v3 設計）が SCC=NONE であることを確認
python3 /tmp/p3-design/scc_verify_v3.py
#    期待: `=== POST SCC (lib-wide /*screens*/ size>=2) ===` の直後が空（screens 非巡回）
#    残存する既知の対象外循環（l10n 生成物 3 種・pane_content_reader⇄pane_frame_reader）のみ
```

**v3 追加の実装時チェック（必須）:**
- [ ] `lib/navigation/current_tab_provider.dart` が screens を import していない（`rg "screens/" lib/navigation/` が空）
- [ ] connections/keys/settings_search_field から `home_screen.dart` の import が消えている（`rg "home_screen.dart" lib/screens/connections lib/screens/keys lib/screens/settings/widgets/settings_search_field.dart` が空）
- [ ] markdown の body が `markdown_preview_screen.dart`（impl）を import していない（`rg "markdown_preview_screen" lib/screens/file_browser/markdown_preview/markdown_preview_body.dart` が空）
- [ ] `MarkdownPreviewScreen.rawScrollKey` / `.renderedScrollKey` が中立 const を返す getter として存在（markdown_preview_screen_test が差分ゼロで通る）

---

## 8. 未確定点

1. **re-export 削減（判定不要・既存方針に従う）**: P2 の `connection_provider.dart` / `resize_dialog.dart` 前例に従い、3 ファイルすべて thin re-export 方式を採用。export 戦略の分裂（P2 critique §0）を避けるため**全ファイル re-export で一本化**。
2. **`_TerminalTab`/`_EmptySessionsView`/`_SessionCard`（home_screen.dart L274-814・計 540 行）は削除（v3 で確定・ユーザー承認済み）**:
   - 事実: HEAD でインスタンス化ゼロ（rg 実測）・IndexedStack 非登録・テスト参照ゼロ。git 8aab2ec ではタブ0に使用されていた「アクティブセッション一覧」の遺産。
   - **確定: 案 A（削除）**。デッドコードの保守コスト排除。挙動不変（実行経路なし）。l10n 生成物（arb）は変更禁止のためキーは残置。将来タブ拡張時は git 履歴（8aab2ec 以前）から復元可能。
3. **private 部品の公開化方針（v2 で確定）**: `AlertPaneCard`/`MarkdownCodeElementBuilder`/`HomeBottomNavBar`/`MarkdownPreviewBody`/alert_flag_style の 7 関数は **素の public 化**する（v1 の `@internal` は P2 実績ゼロ・lint 警告リスクのため不採用。critique §5.2）。public 化に伴う `library_private_types_in_public_api` が発生する場合は `// ignore_for_file:` を明示添付（実装時の analyze 出力で判断）。
4. **home シム ⇄ connections シムの相互循環の解消（v3 で確定）**: `currentTabProvider` を中立 `lib/navigation/current_tab_provider.dart` へ抽出し、connections/keys/settings_search_field の 3 ファイルは home_screen を import せず中立を直接 import する（**必須修正 A・確定**）。これにより screens の SCC は消滅（§0b 機械検証）。connections-screen.md §6-6 の「現行どおり維持」方針とは、**中立モジュールを P3 で新設して直接 import する方向で更新して整合させる**（connections 設計側は `import '../navigation/current_tab_provider.dart'` に更新）。
5. **行数見積の扱い**: §2 の行数は概算（P2 実績で State 骨格が +10-20% 膨らむケースあり）。全ファイル 500 行未満の保証は「最大見積 ~280 行」と余裕を持たせたことで担保。実装時に 500 行を超えそうなファイルが 1 つでも出た場合は、そのファイル内の**重複パターン**（例: flag スタイルの switch ×5 が似て非なる分岐）を純関数化して回避する（P2 critique §2.3 の過剰分割批判には該当しない範囲で）。

---

## 付録: 他の設計者へ共有すべき発見（共通の落とし穴）

- **home_screen.dart の `_TerminalTab` は 540 行のデッドコード**。P3 の行数対象に含まれているが、実質の ACTIVE コードは L26-272（~250 行）のみ。行数集計時は注意（担当外の dashboard_screen.dart 等も同種の置換履歴を持つ可能性があるため、分割前に `rg` でインスタンス化を確認することを推奨）。
- **「関連テスト 2 本（file_browser_download_flow_test）」は実測と食い違う**: download_flow_test は markdown へ一切依存しない。実際は `file_browser_markdown_flow_test`（236 行）が該当。タスク説明の参照に依存せず、rg で実測すること。
- P2 で `@internal` は**実績ゼロ**（HEAD・rg 実測）。P3 では private 部品の分離には**素の public 化 + thin re-export** を使う（v2 方針）。`@internal` は同パッケージ内でも `invalid_use_of_internal_member` lint の警告対象になり得るため使用しない。
- **【新規】lib/screens は現行 10 ファイルが 1 SCC**。主因は `home_screen.dart` が `CurrentTabNotifier`/`currentTabProvider` を所有し、3 タブ画面（connections/keys/settings_search_field）が home_screen を import する逆辺。**他 P3 設計者への連絡**: タブ状態を参照する画面（connections 等）は、v3 の中立 `lib/navigation/current_tab_provider.dart` を**直接 import** する方針に合わせること（home_screen シム経由は NG）。

### 付録-パス根拠: 中立モジュールの場所

| # | 候補 | 採用 | 根拠 |
|---|---|---|---|
| ① | `lib/navigation/current_tab_provider.dart`（新設） | **採用** | タブ状態は「ナビゲーション状態」であり、P2 で整理済みの `lib/providers/`（データ・サービス系）とは責務が異なる。`lib/screens/` 配下に置くと screens の SCC の一部として計算されるため、**screens 外（lib 直下）に置く必要がある**。既存に `lib/navigation/` は無く新設。中立（screens 非依存・依存ゼロ） |
| ② | `lib/providers/current_tab_provider.dart` | 不採用 | P2 で `providers/` は「ダウンロード/設定/接続/アクティブセッション」等のアプリ状態に整理済み。UI タブの遷移状態は provider の責務境界（データ取得・ドメイン状態）と異なる。P2 の分類を乱さないため避ける |
| ③ | `lib/screens/home/home_tab_provider.dart` | 不採用 | screens 配下に残ると connections/keys/settings_search_field からの参照が screens 内 SCC を再形成しうる（v2 の失敗）。中立性が満たせない |

**markdown 中立ファイル（必須修正 B）**: `lib/screens/file_browser/markdown_scroll_keys.dart`。markdown 機能固有の値（スクロールキー）であり、`file_browser/` 内の leaf（依存ゼロ）として置く。screens 内だが出力辺ゼロのため SCC 不入り（§0b POST で実証）。`lib/navigation/` に入れるほど汎用ではなく、markdown 機能に閉じた中立値が適切。