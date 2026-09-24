# P5 設計書 v2: test/widgets ・ test/screens の 500 行超 5 ファイル責務分割

対象ファイル（BRIEF #5, #11, #13, #16, #17）:

| # | ファイル | 実測行数 | 実測テスト件数 |
|---|---|---|---|
| A | test/widgets/special_keys_bar_test.dart | 1101 | 41（41/41 success）|
| B | test/widgets/custom_key_button_editor_dialog_test.dart | 630 | 17（17/17 success）|
| C | test/screens/file_browser/markdown_preview_screen_test.dart | 828 | 30（30/30 success）|
| D | test/screens/custom_keys/custom_keys_screen_test.dart | 569 | 21（21/21 success）|
| E | test/screens/file_browser/file_browser_download_flow_test.dart | 562 | 7（7/7 success）|

> 実測方法: `flutter test <5ファイル> --reporter=json` を実行し、`testStart`(=hidden loading 除く)/`testDone` の非 hidden 件数を集計。**全 116 件が成功、skip/failure 0**。
> メタデータ: 5 ファイル全てに `@Tags` / `@Skip` / `@Timeout` / 先頭 doc コメント **なし**（`rg` で 0 件确认）。CI の `--exclude-tags=repro` に影響する要素は無し。
> サーバデータ: flutter 3.44.9-stable (`make test` と同一環境)。

---

## v2 改訂サマリ（critique.md §2・§5 対応）

| critique 指摘 | v1 の状態 | v2 の対応 |
|---|---|---|
| **2-5【必須】** custom_key_button_editor_dialog の「MediaQuery pump 1 本化」（`pumpDialogMediaQuery`） | §2-B/§3-B/§4 で 4 ブロックの 1 本化を提案 | **撤回**。テスト本体は全ファイル・全テストとも **verbatim（行コピー）移動**に統一。MediaQuery インライン pump 4 ブロック（外側 `MediaQuery(` L379 と直置き L465/L510/L589 の構造差含む）は**無編集で移設**。アサーション・pump 回数・期待値は不変（§2-B・§3-B・§4・§5 に反映） |
| **2-4【必須】** `FakeSaveAsExporter` の設計間二重定義 | widgets 側 helper `download_flow_harness.dart` に独自定義（`{result}` 版） | **providers 設計の決定に合わせ一本化**。誤差対応版（`{result, error}`・`calls` 記録）である providers の `test/providers/helpers/download_provider_test_utils.dart` を shared helper とし、widgets 側は**再定義せず import**（相対 import `../../../providers/helpers/download_provider_test_utils.dart`）。§6 から該当未確定点を削除し決定済みとする |
| **軽微 4【推奨】** `_invokeLinkTap` の helper 移設が `mockUrlLauncher` ローカル維持と非対称 | §2-C/§3-C で helper `markdown_preview_pump.dart` へ移設 | **link_guard ファイル内ローカル維持**に変更（`mockUrlLauncher` と対称）。根拠: リンクガード group 専用（実測使用 3 テストのみ）で helper 肥大化回避。§3-C に追記 |
| **§4(g)（推奨）** 「行コピーのみ」を全体方針として検証項目化 | §4 リスク表に方針はあるが検証項目化なし | §4 に「行コピーのみ」を**全体方針**として明記し、§5 に「テスト本体ブロック行 diff 検証」を追加（旧ファイル削除前に実施）。「EXIT=0・fail 0」も検証計画に明記 |
| 軽微 5（group 追加不可） | — | 対象 5 ファイルは group 追加・改名・削除を一切行わず既存 group 境界のみで分割（v1 方針どおり。fullName 集合 diff 検証は §5 で機械保証） |

**v2 で不変な事項**: 分割構成（4+3+4+2+2 ファイル + 5 helper）、実測マップ、行数見積り（2-B の helper 減・2-C の一部増のみ反映）、全 116 件の件数・名前・タグ。

---

## 1. 現状分析（事実）

### A. test/widgets/special_keys_bar_test.dart（1101 行・41 件）

**共有 harness（`main()` 内ローカル関数・L11-142）** — 全て同一ファイル内のみで使用:

| ヘルパー | 行範囲 | 内容 |
|---|---|---|
| `buildWidget({directInputEnabled, onImagePickRequested, row0Tokens})` | 11-46 | narrow-phone(320px) 用ハーネス |
| `harness({directInput, width=720, row0Tokens})` | 48-80 | wide surface 用ハーネス（`hapticFeedback:false`）|
| `horizontalScroller()` | 81-84 | 水平 SingleChildScrollView の Finder |
| `ck(id, label)` | 85-89 | CustomKeyButton ファクトリ（text step 'x'）|
| `ckToken(id)` | 91 | 'ck:'+id トークン変換 |
| `customHarness({directInput, cjkMode, keepKeyboardOnEnter, width, customButtons, row0/1/2Tokens, rows, onCustomButtonEdit, onManageButtons, onKeyPressed, onSpecialKeyPressed, onImagePickRequested})` | 93-142 | 主要 harness（group 2-7 で使用）|

**group 構成**（{}内は行範囲・件数）:

| group | 行範囲 | 件数 | テスト開始行 |
|---|---|---|---|
| SpecialKeysBar | 144-217 | 5 | 145,163,180,191,201 |
| SpecialKeysBar custom buttons | 218-509 | 13 | 219,248,267,286,319,347,371,389,410,437,465,481,489 |
| SpecialKeysBar arbitrary layout | 510-638 | 7 | 511,525,542,567,579,590,614 |
| SpecialKeysBar direct input field | 639-777 | 6 | 647,664,689,707,738,757 |
| SpecialKeysBar CJK mode (v0.7.0-pre4 behavior) | 778-896 | 4 | 786,809,839,861 |
| SpecialKeysBar row auto-scroll | 897-1022 | 3 | 898,940,983 |
| SpecialKeysBar dynamic rows | 1023-1101 | 3 | 1026,1057,1082 |

**注意**: `directInputField()` と `visibleText()` が group4（L645-657）と group5（L781-793）で**同一ローカル定義の重複**がある。

### B. test/widgets/custom_key_button_editor_dialog_test.dart（630 行・17 件）

- **group は 1 個**: `CustomKeyButtonEditorDialog`（L9-630、17 件）。
- **共有ヘルパー**: `openDialog(tester, {initialLabel, initialSteps, onResult, onDelete})`（L10-32）— showDialog でダイアログを開く pump ヘルパー。13/17 テストが使用。
- 残り 4 件（t12,t14,t15,t17）は `MediaQuery` + `MaterialApp` を個別インライン pump（L368-430, 454-498, 499-546, 581-630 内）。textScaler 2.0/1.3/1.3 と view サイズ 411/308 の組合せで、`MediaQuery(data: 直置き)`（L465/510/589）と外側 `MediaQuery(`（L379）の**構造差異がある**（v2 では 1 本化せず verbatim 移動）。

| テスト（開始行） | 性質 |
|---|---|
| 45 空ラベル / 72 zero steps / 94 invalid pause / 120 空 text step / 147 空 key step | バリデーション 5 件 |
| 174 adds/reorders/deletes / 236 cancel pops null / 254 onSurface 色 / 290 delete confirm / 325 cancel confirm / 355 no delete | 編集・削除フロー 6 件 |
| 368 full-width 2x / 431 actions inset / 454 narrow screen / 499 type label / 547 action row / 581 action labels | レスポンシブ UI 6 件 |

### C. test/screens/file_browser/markdown_preview_screen_test.dart（828 行・30 件）

**トップレベル shared 要素**:

| 要素 | 行範囲 | 内容 |
|---|---|---|
| `kTinyPng` | 22-25 | 1x1 透明 PNG 定数 |
| `_RecordingSftpClient extends FakeSftpClient` | 27-42 | open 呼び出し記録（`openedPaths`）|
| `_FlakySftpClient extends FakeSftpClient` | 43-57 | open 失敗→成功切替（Retry テスト）|
| `_FakeMarkdownNotifier extends MarkdownPreviewNotifier` | 59-76 | load 呼び出し回数を記録するスタブ |
| `_mdEntry({size, path})` | 77-85 | FileEntry ファクトリ |
| `_bytes(text)` | 86 | utf8 変換 |
| `pumpScreen(tester, {sftpClient, entry, sshClient})` | 92-124 | **provider override**: `sshProvider.overrideWith(() => FakeSshNotifier(client:...))` + `ProviderScope` + MaterialApp |
| `pumpScreenWithState(tester, state)` | 125-151 | `markdownPreviewProvider.overrideWith(() => _FakeMarkdownNotifier(state))` 版 |
| `_invokeLinkTap(tester, linkText)` | 781-800 | RichText スパンから recognizer.onTap 直接呼び出し（リンクガード group 専用）|
| `_hasColoredTextSpan(span)` | 801-814 | 色付きスパン検査（highlight group 専用）|
| `_flatten(span)` | 815-828 | TextSpan 平坦化（highlight group 専用）|

**group 構成**:

| group | 行範囲 | 件数 | テスト開始行 |
|---|---|---|---|
| MarkdownPreviewScreen - 基本表示 | 152-198 | 2 | 153,169 |
| MarkdownPreviewScreen - Raw/Rendered トグル | 199-283 | 2 | 200,228 |
| MarkdownPreviewScreen - 状態表示 | 284-392 | 6 | 285,295,313,335,355,376 |
| MarkdownPreviewScreen - 画像ガード（構造検証・L-3） | 393-453 | 1 | 407 |
| SftpMarkdownImage.resolveImage（純関数・構造検証） | 454-565 | 9 | 455,464,473,481,489,506,514,528,549 |
| SftpMarkdownImage.isBlockedHost（純関数） | 566-609 | 2 | 567,594 |
| MarkdownPreviewScreen - 言語別ハイライト（C-2・M-3） | 610-681 | 4 | 611,639,655,664 |
| MarkdownHighlighter.languageFromClassAttribute | 682-708 | 2 | 683,698 |
| MarkdownPreviewScreen - リンクガード（#11・L-2） | 709-828 | 2 | 730,756 |

**注意点**:
- `_RecordingSftpClient` は `file_browser_markdown_flow_test.dart`（L22）にも**同名 private で重複定義**されている（本フェーズ編集対象外）。
- リンクガード group 内に `mockUrlLauncher`（L716-733 付近、MethodChannel mock）がローカル定義（`_invokeLinkTap` と共にローカル維持）。なお `_invokeLinkTap` の実測使用は L743/769/770 の 3 点のみ。
- 純関数 group（resolveImage / isBlockedHost / languageFromClassAttribute）と widget group が混在。

### D. test/screens/custom_keys/custom_keys_screen_test.dart（569 行・21 件）

- **group は 1 個**: `CustomKeysScreen`（L60-569、21 件）。
- **共有 harness**（main 内）: `pumpScreen(tester, container)` L11-30、`addButton` L31-44、`dragChip` L45-53、`tokenOf` L54-59。
- **全 21 テストで同一ボイラープレート**: `SharedPreferences.setMockInitialValues({}); final container = ProviderContainer(); addTearDown(container.dispose);` が繰り返し。

| テスト（開始行） | カテゴリ |
|---|---|
| 61 empty state / 98 chips render / 111 add appears / 131 head of row / 150 edit prefilled / 187 delete removes / 336 persists / 358 edit save unchanged / 380 delete from dialog | ライブラリ CRUD・状態 9 件 |
| 209 standard drag / 230 custom drag / 254 reorder / 280 shelf unused / 299 shelf→row / 317 tap chip opens editor / 418 add row / 446 maxRows / 479 delete row / 503 all deleted / 525 row header create / 551 global add head | ドラッグ&行編集 12 件 |

### E. test/screens/file_browser/file_browser_download_flow_test.dart（562 行・7 件）

**トップレベル shared 要素**:

| 要素 | 行範囲 | 内容 |
|---|---|---|
| `_TestSftpClient extends FakeSftpClient` | 31-61 | stat 実サイズ / open で FakeSftpFile 返却 |
| `_entry(name)` | 62-65 | FileEntry ファクトリ（size 300）|
| `FakeBatchDestinationPicker implements BatchDestinationPicker` | 67-81 | pick 回数記録 |
| `FakeSaveAsExporter implements SaveAsExporter` | 83-101 | export 呼び出しパス記録（**providers 側 shared と二重定義。v2 で解消**）|
| `_pathProviderChannel` | 103 | path_provider MethodChannel 定数 |
| `_settleTransfer(tester, container)` | 104-135 | runAsync で転送完了までポーリング（10s タイムアウト）|
| `_pumpScreen({sshClient, entries, appDocs, appTmp, picker, exporter})` | 136-188 | **provider override**: `fileBrowserProvider` / `sshProvider` / `settingsProvider` / 条件付き `batchDestinationPickerProvider` / `downloadProvider` |
| `setUp` | 198-213 | tmp ディレクトリ作成 + path_provider channel mock |
| `tearDown` | 214-223 | channel mock 解除 + tmp 削除 |
| `_waitUntil` | 529-548 | 条件成立まで runAsync ポーリング |
| `_waitForText` | 550-561 | テキスト出現待ち |

**group 構成**: `ファイルブラウザ 単一ダウンロード導線（tmp→Save-As）` L224-293（2 件: 225,262）、`ファイルブラウザ 一括ダウンロード導線（OS フォルダピッカー）` L294-528（5 件: 295,340,371,423,477）。

**注意点**: `_pumpScreen` 内と `setUp` 内で path_provider channel 登録が**重複記述**されている。

---

## 2. 目標構成

### 2-0. 全体方針（「行コピーのみ」）

**本設計の全てのテスト本体・group・コメント・空行・フォーマットは、旧ファイルから新ファイルへ「行コピーのみ」で移動する（無編集・一刀両断のブロック移動）。** 許される編集は（i）import 追加・整理のみ、（ii）private→public 名への**識別子 rename のみ**（public 化されたヘルパーの呼び出し側参照 1 語を置換）、（iii）main() 冒頭の固定ヘッダ（`TestWidgetsFlutterBinding.ensureInitialized()`・`setUp/tearDown` の helper 呼び出し化）だけである。アサーション・期待値・タイマー値・文字列・pump 回数・テスト名・group 名・doc コメントは 1 バイトも変えない（§5 で機械 diff 検証）。

### 2-A. special_keys_bar_test.dart → 4 ファイル + helper（合計 41 件維持）

| ファイル | 責務（1 文） | 含める group | 行数見積り | テスト数 |
|---|---|---|---|---|
| `test/widgets/special_keys_bar_layout_test.dart` | 基本表示と任意レイアウトの描画契約を検証する | SpecialKeysBar + arbitrary layout | 74+129+ボイラ~15 = **~220** | 5+7=12 |
| `test/widgets/special_keys_bar_custom_buttons_test.dart` | カスタムボタンの描画・タップ・イベント配線を検証する | custom buttons | 292+~15 = **~310** | 13 |
| `test/widgets/special_keys_bar_direct_input_test.dart` | 直接入力フィールドの送信・CJK モードを検証する | direct input field + CJK mode | 139+119+~15 = **~275** | 6+4=10 |
| `test/widgets/special_keys_bar_rows_test.dart` | 行の自動スクロールと動的 rows 契約を検証する | row auto-scroll + dynamic rows | 126+79+~15 = **~220** | 3+3=6 |
| `test/widgets/helpers/special_keys_bar_harness.dart`（新規） | SpecialKeysBar の pump ヘルパー群 + group4/5 重複ヘルパーの一本化 | — | ~165（main なし）| — |

- 既存 `test/helpers/` には SpecialKeysBar 用 harness は**存在しない**（`test/widgets/` 配下に新規 helper ディレクトリを作る）。
- `customHarness`・`ck`・`ckToken`・`horizontalScroller`・`harness`・`buildWidget` を公開関数として移設。group4/5 の `directInputField`/`visibleText` 重複もここで 1 本化（**テスト文面は不変**。呼び出し側のローカル定義ブロック L645-657 / L781-793 は削除し、呼び出し式のみ残る）。
- import 先: `package:flutter_muxpod/services/custom_keys/custom_key_button.dart` / `.../widgets/custom_key_button_widget.dart` / `.../l10n/app_localizations.dart` / `.../widgets/special_keys_bar.dart`。
- `special_keys_bar_test.dart` 自体は**削除**（部品全てが他ファイルへ移動）。

### 2-B. custom_key_button_editor_dialog_test.dart → 3 ファイル + helper（合計 17 件維持）〔critique 2-5 反映〕

| ファイル | 責務（1 文） | 含めるテスト | 行数見積り | テスト数 |
|---|---|---|---|---|
| `test/widgets/custom_key_button_editor_dialog_validation_test.dart` | ラベル・ステップの入力バリデーションを検証する | t1-t5 | 129+~40 = **~170** | 5 |
| `test/widgets/custom_key_button_editor_dialog_edit_test.dart` | ステップ編集・キャンセル・削除フローを検証する | t6-t11 | 195+~40 = **~235** | 6 |
| `test/widgets/custom_key_button_editor_dialog_test.dart`（維持） | 端末幅・テキストスケール下のレスポンシブ UI を検証する | t12-t17（MediaQuery インライン pump 4 ブロック含め **verbatim 行コピー**）| 263+~30 = **~295** | 6 |
| `test/widgets/helpers/custom_key_button_dialog_open.dart`（新規） | `openDialog`（showDialog を開く pump ヘルパー）| — | ~40（main なし）| — |

- **critique 2-5 対応**: v1 の `pumpDialogMediaQuery`（MediaQuery pump テンプレート 1 本化）は**撤回**。t12/t14/t15/t17 の MediaQuery インライン pump（L368-430 / 454-498 / 499-546 / 581-630。外側 `MediaQuery(` L379 と直置き L465/510/589 の構造差あり）は**そのまま本体として行コピー**する。1 本化は BRIEF が求める「共有化」対象外（ヘルパー抽出対象は 13/17 テストで使用される `openDialog` のみ）。
- helper には `openDialog`（L10-32）のみを公開名で収容。import 先: material / flutter_test / custom_key_button / dialog 本体。

### 2-C. markdown_preview_screen_test.dart → 4 ファイル + helper（合計 30 件維持）〔critique 軽微 4 反映〕

| ファイル | 責務（1 文） | 含める group | 行数見積り | テスト数 |
|---|---|---|---|---|
| `test/screens/file_browser/markdown_preview_screen_test.dart`（維持） | 表示状態・Raw/Rendered ビュー切替を検証する | 基本表示 + 状態表示 + Raw/Rendered トグル | 47+109+85+~20 = **~260** | 2+6+2=10 |
| `test/screens/file_browser/markdown_preview_resource_guards_test.dart`（新規） | 画像 URL の解決・ブロック判定（含む純関数）を検証する | 画像ガード + resolveImage + isBlockedHost | 61+112+44+~25 = **~250** | 1+9+2=12 |
| `test/screens/file_browser/markdown_preview_link_guard_test.dart`（新規） | 外部リンクのスキームガードを検証する | リンクガード（`_invokeLinkTap`・`mockUrlLauncher` は**本ファイル内ローカル維持**）| 120+30(~invokeLinkTap+ボイラ) = **~170** | 2 |
| `test/screens/file_browser/markdown_preview_highlight_test.dart`（新規） | コードハイライトと言語クラス抽出を検証する | 言語別ハイライト + languageFromClassAttribute | 72+27+helpers~25+~15 = **~140** | 4+2=6 |
| `test/screens/file_browser/helpers/markdown_preview_pump.dart`（新規） | pump ヘルパー・SFTP fake・notifier スタブ | — | ~180（main なし）| — |

- **軽微 4 対応**: `_invokeLinkTap`（L781-800）は**link_guard ファイル内ローカル維持**（`mockUrlLauncher` と対称）。根拠: リンクガード group 専用（実測使用 L743/769/770 の 3 テストのみ）で、helper へ移すと helper 肥大化と公開名化の書き換えが増えるだけ。選択の根拠は本項に記録。
- `_hasColoredTextSpan` / `_flatten`（L801-828）は highlight 専用のため highlight ファイル内ローカルに維持。
- helper `markdown_preview_pump.dart` の収容物: `kTinyPng` / `RecordingSftpClient`（旧 `_RecordingSftpClient`） / `FlakySftpClient`（旧 `_FlakySftpClient`） / `FakeMarkdownPreviewNotifier`（旧 `_FakeMarkdownNotifier`） / `mdEntry`（旧 `_mdEntry`） / `bytes`（旧 `_bytes`） / `pumpScreen` / `pumpScreenWithState`。

### 2-D. custom_keys_screen_test.dart → 2 ファイル + helper（合計 21 件維持）

| ファイル | 責務（1 文） | 含めるテスト | 行数見積り | テスト数 |
|---|---|---|---|---|
| `test/screens/custom_keys/custom_keys_screen_test.dart`（維持） | ボタンのライブラリ CRUD と永続化を検証する | t1-t6,t13-t15 | 224+~20 = **~245** | 9 |
| `test/screens/custom_keys/custom_keys_screen_layout_test.dart`（新規） | チップのドラッグ&ドロップと行の追加・削除を検証する | t7-t12,t16-t21 | 279+~20 = **~300** | 12 |
| `test/screens/custom_keys/helpers/custom_keys_screen_pump.dart`（新規） | pumpScreen / addButton / dragChip / tokenOf | — | ~65（main なし）| — |

### 2-E. file_browser_download_flow_test.dart → 2 ファイル + helper（合計 7 件維持）〔critique 2-4 反映〕

| ファイル | 責務（1 文） | 含める group | 行数見積り | テスト数 |
|---|---|---|---|---|
| `test/screens/file_browser/file_browser_download_flow_test.dart`（維持） | 単一ダウンロード（tmp→Save-As）導線を検証する | 単一ダウンロード導線 | 70+setUp/tearDown~30+main ~ = **~120** | 2 |
| `test/screens/file_browser/file_browser_batch_download_test.dart`(新規) | 一括ダウンロード（フォルダピッカー・衝突対応）導線を検証する | 一括ダウンロード導線 | 235+~45 = **~280** | 5 |
| `test/screens/file_browser/helpers/download_flow_harness.dart`（新規） | SFTP fake・picker fake・settle/pump/wait ヘルパー・tmp セットアップ | — | ~185（main なし）| — |

- **critique 2-4 対応（providers 設計と一本化）**: `FakeSaveAsExporter` は**本設計では再定義しない**。providers 設計（providers.md §2-2/§2-3）が shared helper `test/providers/helpers/download_provider_test_utils.dart` に定義する誤差対応版（`{result, error}`・`calls` 記録。旧 `test/providers/download_provider_test.dart` L134-152）を唯一の定義とし、widgets 側 2 ファイルはここから **相対 import** する（`../../../providers/helpers/download_provider_test_utils.dart`）。
  - 互換性: providers 版は widgets 版のスーパーセット。`result`/`calls` の挙動は同一（`export()` は `calls.add(sourceFilePath)` → `error` 無ければ `return result`）。widgets 側テストは error を指定せず使うため、`exporter.calls == ['$appTmp/sftp_download/report_1.pdf']` 等のアサーションは不変。
- 上記に伴い v1 の「widgets 側 helper に FakeSaveAsExporter を収容」は撤回。`download_flow_harness.dart` の収容物は以下: `TestDownloadSftpClient`（旧 `_TestSftpClient`）/ `FakeBatchDestinationPicker` / `downloadEntry`（旧 `_entry`）/ `settleTransfer`（旧 `_settleTransfer`）/ `pumpDownloadScreen`（旧 `_pumpScreen`）/ `waitUntil`（旧 `_waitUntil`）/ `waitForText`（旧 `_waitForText`）/ `setUpTmpChannel`・`tearDownTmp`（setUp/tearDown 本文の関数化）。

**helper に移す共有要素（全 5 ファイル分まとめ）**:

| helper ファイル | 移設要素（現行→公開名） |
|---|---|
| widgets/helpers/special_keys_bar_harness.dart | buildWidget, harness, horizontalScroller, ck, ckToken, customHarness（+ directInputField/visibleText を 1 本化） |
| widgets/helpers/custom_key_button_dialog_open.dart | openDialog（pumpDialogMediaQuery は撤回により無し） |
| screens/file_browser/helpers/markdown_preview_pump.dart | kTinyPng, RecordingSftpClient(_RecordingSftpClient), FlakySftpClient, FakeMarkdownPreviewNotifier, mdEntry(_mdEntry), bytes(_bytes), pumpScreen, pumpScreenWithState |
| screens/custom_keys/helpers/custom_keys_screen_pump.dart | pumpScreen, addButton, dragChip, tokenOf |
| screens/file_browser/helpers/download_flow_harness.dart | TestDownloadSftpClient(_TestSftpClient), FakeBatchDestinationPicker, downloadEntry(_entry), settleTransfer(_settleTransfer), pumpDownloadScreen(_pumpScreen), waitUntil(_waitUntil), waitForText(_waitForText), setUpTmpChannel / tearDownTmp（setUp/tearDown 本文） |
| （import のみ）| **FakeSaveAsExporter → `test/providers/helpers/download_provider_test_utils.dart`**（providers 設計の決定に一本化）|

既存 `test/helpers/`（**再利用・重複定義を増やさない**）: `FakeSftpClient`, `FakeSftpFile`, `FakeSshClient`, `FakeSshNotifier`, `FakeFileBrowserNotifier`, `FakeSettingsNotifier` は継続利用。Additional helper: なし追加。

---

## 3. 移動マッピング

### A. special_keys_bar
| 現 group（行範囲・件数） | 移動先 |
|---|---|
| SpecialKeysBar（144-217・5） | special_keys_bar_layout_test.dart |
| SpecialKeysBar arbitrary layout（510-638・7） | special_keys_bar_layout_test.dart |
| SpecialKeysBar custom buttons（218-509・13） | special_keys_bar_custom_buttons_test.dart |
| SpecialKeysBar direct input field（639-777・6） | special_keys_bar_direct_input_test.dart |
| SpecialKeysBar CJK mode（778-896・4） | special_keys_bar_direct_input_test.dart |
| SpecialKeysBar row auto-scroll（897-1022・3） | special_keys_bar_rows_test.dart |
| SpecialKeysBar dynamic rows（1023-1101・3） | special_keys_bar_rows_test.dart |
| harness（11-142）＋ group4/5 ローカル helper（645-657/781-793） | helpers/special_keys_bar_harness.dart |

### B. custom_key_button_editor_dialog〔critique 2-5 反映〕
| 現テスト（行範囲） | 移動先 |
|---|---|
| t1-t5（45-173）| custom_key_button_editor_dialog_validation_test.dart（verbatim）|
| t6-t11（174-368）| custom_key_button_editor_dialog_edit_test.dart（verbatim）|
| t12-t17（368-630）| custom_key_button_editor_dialog_test.dart（維持・**verbatim**）|
| openDialog（10-32）| helpers/custom_key_button_dialog_open.dart |
| ~~MediaQuery pump 1 本化（L368-430/454-498/499-546/581-630 の pump 部）~~ | **撤回**。1 本化せず、t12-t17 の一部として本体を無編集で行コピー（§2-B 参照）|

### C. markdown_preview_screen〔critique 軽微 4 反映〕
| 現 group（行範囲・件数） | 移動先 |
|---|---|
| 基本表示（152-198・2）| markdown_preview_screen_test.dart（維持） |
| Raw/Rendered トグル（199-283・2）| markdown_preview_screen_test.dart（維持） |
| 状態表示（284-392・6）| markdown_preview_screen_test.dart（維持） |
| 画像ガード（393-453・1）| markdown_preview_resource_guards_test.dart |
| resolveImage（454-565・9）| markdown_preview_resource_guards_test.dart |
| isBlockedHost（566-609・2）| markdown_preview_resource_guards_test.dart |
| 言語別ハイライト（610-681・4）| markdown_preview_highlight_test.dart |
| languageFromClassAttribute（682-708・2）| markdown_preview_highlight_test.dart |
| リンクガード（709-828・2）| markdown_preview_link_guard_test.dart |
| トップレベル shared（22-151）| helpers/markdown_preview_pump.dart |
| ~~_invokeLinkTap（781-800）~~ | **markdown_preview_link_guard_test.dart 内ローカル維持**（軽微 4。mockUrlLauncher と対称・リンクガード group 専用のため helper 化しない）|
| _hasColoredTextSpan/_flatten（801-828）| markdown_preview_highlight_test.dart（ローカル維持）|

### D. custom_keys_screen
| 現テスト（開始行） | 移動先 |
|---|---|
| 61,98,111,131,150,187,336,358,380（9 件）| custom_keys_screen_test.dart（維持） |
| 209,230,254,280,299,317,418,446,479,503,525,551（12 件）| custom_keys_screen_layout_test.dart |
| pumpScreen/addButton/dragChip/tokenOf（11-59）| helpers/custom_keys_screen_pump.dart |

### E. file_browser_download_flow〔critique 2-4 反映〕
| 現要素（行範囲） | 移動先 |
|---|---|
| 単一ダウンロード導線 group（224-293・2）| file_browser_download_flow_test.dart（維持） |
| 一括ダウンロード導線 group（294-528・5）| file_browser_batch_download_test.dart |
| shared（31-58, 62-101, 103-188, 529-561）| helpers/download_flow_harness.dart |
| `FakeSaveAsExporter`（83-101）| **本設計では再定義せず providers の shared helper から import**（`test/providers/helpers/download_provider_test_utils.dart`。§2-E）|
| setUp/tearDown（198-223）| 各 main() で helpers/setUpTmpChannel・tearDownTmp を呼ぶ形に整理 |

---

## 4. リスクと対策

**全体方針（§2-0 と一体）**: テスト本体・group ブロックは**行コピーのみ**で移動し、書き換えは「import 追加」「公開名への識別子 rename」「main() 固定ヘッダの helper 呼び出し化」の 3 種に限定。この方針自体を §5 の検証項目として機械的に確認する。

| リスク | 影響 | 対策 |
|---|---|---|
| **setUp 共有範囲の食い違い**（B/E） | E: tmp/path_provider は group 共通だが、スプリット後はファイルごとに独立 suite。| setUp/tearDown の**本文を helper 関数化**（`setUpTmpChannel`/`tearDownTmp`）し、各 main() で呼ぶ。テスト本体の変更はしない。削除/作成の try-catch も helper 内へ。`TestWidgetsFlutterBinding.ensureInitialized()` は各新 main() 冒頭に保持（現行 L189→現行 L189 相当を全ファイルへ）。|
| **設計間共有 helper の衝突**（E × providers） | `FakeSaveAsExporter` が widgets 側 `download_flow_harness.dart` と providers 側 `download_provider_test_utils.dart` で二重定義になり得る（critique 2-4）。| **providers 設計の決定に一本化**。widgets 側は再定義せず、`../../../providers/helpers/download_provider_test_utils.dart` を import。providers 版（`{result, error}` 誤差対応版）は `result`/`calls` の挙動が widgets 版と同一のスーパーセットなので、widgets の `exporter.calls` アサーションは不変。実装時に providers 設計者と helper 収容物・公開シグネチャの最終確認を行う。|
| **fixture スコープ・private→public 化**（C/E） | private fake の公開名化時の命名衝突。| helpers 内で接頭辞付き公開名に変更（`RecordingSftpClient`/`TestDownloadSftpClient` 等）。既存 `file_browser_markdown_flow_test.dart` の同名 private `_RecordingSftpClient` は**別物のため残す**（本フェーズ編集対象外）。rename は「呼び出し側の該当識別子 1 語のみ」の機械置換に限定。|
| **グローバル状態**（C/E） | path_provider MethodChannel mock は BinaryMessenger に登録され、同一ファイル内の前テストが mock を残すと次テストへ影響。| 現状どおり `tearDown`（channel null 化）と `addTearDown` を必ず維持。リンクガードの `mockUrlLauncher` も `addTearDown` を維持。各新ファイルは独立 isolate（flutter_test の suite 単位）のため、ファイルを跨ぐ汚染は生じない。|
| **provider container 状態**（D/E） | `ProviderContainer`/`SharedPreferences.setMockInitialValues` は各テスト内で新規作成。スプリットで跨テスト共有は生じない。| D は各テスト冒頭のボイラープレートをそのまま維持（行コピー方針）か、helper `newContainerWithPrefs()` に抽出（判定要・§6）。E は `addTearDown(container.dispose)` を維持。|
| **タイマー/ポーリング**（E） | `_settleTransfer`/`_waitUntil` の 10s タイムアウト値・`runAsync(20ms)` 間隔・保留回数（10 回）・`Stopwatch` ロジックを変更しない。| helper 移設時も定数を同一値でコピー（行コピーのみ）。|
| **MediaQuery pump の重複**（B） | v1 の 1 本化は構造差（外側 `MediaQuery(` L379 vs 直置き L465/510/589）があり書き換えを伴うためアサーション検証境界が曖昧になる（critique 2-5）。| **1 本化を撤回**し、4 ブロックは本体の一部として verbatim 行コピー。ヘルパー重複問題は生じない（t12-t17 が単一ファイルに留まるため）。|
| **pumpWidget ヘルパー重複回避** | 各 helper 化で同一 pump がファイル間重複しない。| helper ファイルは `main()` を持たない（flutter test のテスト対象外）。1 箇所定義のみ。`_split` 等の識別子は公開名化した際の衝突を §5 の analyze で確認。|
| **localizations 前提**（A/C/E） | `AppLocalizations.localizationsDelegates/supportedLocales` は各 pump に必須。| helpers へ集約し、全スプリット先が helper 経由で MaterialApp を組むため脱落しない。|
| **テスト名・件数・タグ不変** | 名称・group 名・assert・期待値・タイマー・skip/timeout の変更禁止。| 行コピーのみ方針（§2-0）＋§5 の「テスト本体ブロック行 diff 検証」で機械保証。group の追加・改名・削除は行わない（軽微 5 方針）。|
| **実行順序依存** | 全 group が独立テスト（共有フィールド無し、実測）。| 特になし。|

---

## 5. 検証計画

1. **分割前件数確定（実施済み）**: `flutter test <5ファイル> --reporter=json` → **116 件（全 success・skip 0）**。件数カウントは「非 hidden `testDone` の `success`」とし、**EXIT=0・fail 0** を明記（件数だけで fail も同数になるため pass を区別）。
2. **テスト本体ブロック行 diff 検証（critique §4(g) 対応・推奨反映）**: 旧 5 ファイル削除の**前に**、各 group/テスト本体ブロックについて「旧ファイルの該当行範囲」と「新ファイル対応ブロック」を一括で比較し、**差分ゼロ**を確認する。手順: 旧ファイルから対象ブロックを `sed -n 'L1,L2p'` で抽出し、新ファイルの該当ブロックと `diff`（`git diff --no-index` または temp ファイル比較）。対象は「アサーション・期待値・コメント・空行・pump 回数・タイマー値を含む本体全体」。rename（private→public 化）と import 行のみ差分として許容し、それ以外の差分 0 を機械検証。
3. **分割後件数・fullName 一致**: `flutter test <新ファイル群> --reporter=json` で非 hidden `testDone success` 件数を集計し、合計 **116**（special_keys 41 / dialog 17 / markdown 30 / custom_keys 21 / download 7）と一致。加えて「テスト名（JSON `test.name`、group 連結含む fullName）の集合」が分割前後で完全一致することを diff で確認（group 追加・改名・テスト名変更の検出）。コマンド例:
   ```bash
   flutter test test/widgets/special_keys_bar_layout_test.dart \
     test/widgets/special_keys_bar_custom_buttons_test.dart \
     test/widgets/special_keys_bar_direct_input_test.dart \
     test/widgets/special_keys_bar_rows_test.dart --reporter=json | \
     python3 -c 'import sys,json; c=0
     for l in sys.stdin:
       try: e=json.loads(l)
       except Exception: continue
       if e.get("type")=="testDone" and not e.get("hidden") and e.get("result")=="success": c+=1
     print(c)'
   ```
   ※ glob（`special_keys_bar_*.dart` 等）を使う場合は `*_test.dart` に限定し、helper（`_harness.dart` 等・main なし）を含まないこと・旧ファイル削除後であることを前提とする（critique 2-6 方式の誤検知防止）。
4. **「行コピーのみ」方針の検証**: §2-0 の 3 種限定編集（import / 識別子 rename / main() ヘッダ）以外の編集が無いことを、新ファイルから旧ファイル対応ブロックへの逆 diff で確認（手順 2 と同一の比較を双方向で実施）。
5. `flutter analyze`（test/ 領域の静的解析エラー 0 を確認、`make analyze`）。import 追加・公開名化による衝突（A の harness 公開名・E の helpers 公開シグネチャ等）の検出。
6. **全体**: リードが `flutter test --exclude-tags=repro` で **2,009 件不変かつ EXIT=0** を確認。
7. `part`/`mixin`/private 基底の不使用・全ファイル（helper 含む）500 行未満を `wc -l` で確認。

---

## 6. 未確定点

- **helper ディレクトリの位置**: BRIEF 指示 `test/<dir>/helpers/` に新規作成（`test/widgets/helpers/`, `test/screens/custom_keys/helpers/` 等）。既存 `test/helpers/`（フラット）に寄せる代替案がある。→ リード判断を仰ぐ。※ `FakeSaveAsExporter` は批判対応（2-4）で **providers 側 `test/providers/helpers/download_provider_test_utils.dart` に決定済み**のため、この未確定点の対象外。
- **D（custom_keys）の setMockInitialValues/ProviderContainer ボイラープレート**: テスト本文の冒頭行のため「テストの意味不変」に含めて helper 抽出してよいか、それとも各行を残すか。→ ユーザー/リード判断（推奨: 意味不変の範囲内で helper 抽出可。v2 の基本方針は「行コピーのみ」なので安静側は抽出しない）。
- **A（special_keys）における group1+group3 の合体**（1 ファイル 12 件 vs 3 ファイル別々）: 「1 ファイル 1 責務」の観点で合体を提案。分離が必要なら全 7 グループで 4 ファイル→別構成に変更可。→ リード確認。
- **critique 2-4 で「どちらかを §6 未確定点へ追加」の指定**: v2 で **providers 設計の決定（shared helper 一本化・error 対応版）に合わせたため決定済み**。widgets 側の実装時に providers 設計者と helper シグネチャ（`result`/`error`/`calls`）を再確認の上、差異が出た場合は定義を 1 本に保つ（重複再生成しない）。
- 上記以外: **なし**。