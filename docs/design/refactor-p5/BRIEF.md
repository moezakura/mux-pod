# P5 設計ブリーフ（test/ の 500 行超 18 ファイルの責務分割）

## 目的

`test/` 配下の **500 行超テストファイル 18 本**（計 約 19,000 行）を、
**テストの意味を一切変えずに** 500 行未満の複数ファイルへ再構成する。
P1〜P4（lib 側）は完了・コミット済み。P5 はテスト側のみを対象とする。

## 対象 18 ファイル（行数・実測）

| # | ファイル | 行数 |
|---|---|---|
| 1 | test/screens/terminal/terminal_screen_herdr_test.dart | 2785 |
| 2 | test/providers/download_provider_test.dart | 1703 |
| 3 | test/screens/terminal/terminal_screen_herdr_mutation_ui_test.dart | 1516 |
| 4 | test/screens/terminal/terminal_screen_herdr_mutation_sync_test.dart | 1188 |
| 5 | test/widgets/special_keys_bar_test.dart | 1101 |
| 6 | test/services/ssh/ssh_client_test.dart | 1032 |
| 7 | test/providers/active_session_provider_test.dart | 1027 |
| 8 | test/providers/connection_provider_test.dart | 908 |
| 9 | test/services/tmux/tmux_commands_test.dart | 899 |
| 10 | test/services/herdr/herdr_adapter_test.dart | 849 |
| 11 | test/screens/file_browser/markdown_preview_screen_test.dart | 828 |
| 12 | test/providers/custom_keys_provider_test.dart | 673 |
| 13 | test/widgets/custom_key_button_editor_dialog_test.dart | 630 |
| 14 | test/screens/terminal/terminal_screen_scroll_send_test.dart | 591 |
| 15 | test/services/terminal/font_calculator_test.dart | 587 |
| 16 | test/screens/custom_keys/custom_keys_screen_test.dart | 569 |
| 17 | test/screens/file_browser/file_browser_download_flow_test.dart | 562 |
| 18 | test/services/tmux/tmux_parser_test.dart | 525 |

## 厳守事項（テストの意味を変えない）

1. **テスト名・グループ名・アサーション・期待値・タイマー値・タグ・skip/timeout を変更しない**。
   分割前後で「実行されるテストの集合」が完全に一致すること
   （`flutter test <元ファイル>` のテスト件数 = 分割後ファイル群の合計件数）。
2. `@Tags([...])` / `@Skip` / `@Timeout` / ファイル先頭の doc コメント等の**メタデータを保持**
   （特に `test/repro/` 系のタグは CI の `--exclude-tags=repro` に影響するため厳守）。
3. **共有コードは helper ファイルへ抽出**する（`test/<dir>/helpers/<name>.dart` 等）。
   - helper は `main()` を持たない（`flutter test` のテスト対象にならない）。
   - fake / fixture / 定数 / pump ヘルパー / セットアップ関数を共有化する。
   - 既存の `test/helpers/*.dart` を再利用できる場合は再利用する（重複定義を増やさない）。
4. **lib/ は変更しない**（P5 はテストのみ。テストが実装バグを示しても本フェーズでは扱わない）。
5. 全ファイル 500 行未満。`part` / `mixin` / private 基底での共有は禁止（helper ファイル＋通常の
   公開名/クラスで共有する）。
6. ファイル名は責務を表す（例: `terminal_screen_herdr_display_test.dart` /
   `..._selectors_test.dart` / `..._mutation_test.dart`）。`*_part1` 等の機械的命名は禁止。
7. 分割後も **`flutter test --exclude-tags=repro` の総件数 2,009 が不変**であること。
8. 1 ファイル 1 責務（テストの観点単位）。既存の `group` 境界を基本単位とし、大きすぎる group は
   さらに分割してよい（その場合もテスト名は変えない）。

## 各設計書の必須セクション

1. **現状分析（事実）**: 対象ファイルの構造（`group` 名と行範囲、`setUp`/`tearDown`/`setUpAll`、
   共有 fake/fixture/定数、トップレベル関数、タグ等のメタデータ）を**行番号付き**で列挙。
   テスト件数（実測）。
2. **目標構成**: 新規/変更ファイルごとに「責務（1文）・行数見積り・含める group・import 先」。
   全ファイル 500 行未満の数値根拠。helper に移す共有要素の一覧。
3. **移動マッピング**: 既存の各 `group`／テストをどの新ファイルへ移すか。共有コードの移設先。
4. **リスクと対策**: `setUp` の共有範囲、fixture のスコープ、グローバル状態（provider container /
   static キャッシュ / タイマー）、実行順序依存、`pumpWidget` ヘルパーの重複回避。
5. **検証計画**: 分割前後でのテスト件数一致の確認コマンド（`flutter test <file> --reporter=json`
   の件数比較など）、対象テスト実行、`flutter analyze`、全体テスト（リードが実施）。
6. **未確定点**: ユーザー判断が必要なもののみ（無ければ「なし」）。

## 事実主義

行番号・group 名・テスト名・実測件数を根拠に書く。不明は「不明」と明記。
設計は読み取り専用（リポジトリ編集禁止）。書き込みは `/tmp/p5-design/` のみ。

## 成果物

指定パスに Markdown 1 本。完成後リードへ要点を報告すること。
