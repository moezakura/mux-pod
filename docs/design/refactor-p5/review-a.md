# P5 独立検証Aレポート（terminal / services テスト分割）

- レビュアー: p5-reviewer-a（タスク #57・読み取り専用）
- 対象: 
  - (1) 旧 `test/screens/terminal/{terminal_screen_herdr_test, terminal_screen_herdr_mutation_ui_test, terminal_screen_herdr_mutation_sync_test, terminal_screen_scroll_send_test}.dart`（HEAD 実測 **120 件**）→ 新 21 テストファイル + helper 4 本
  - (2) 旧 `test/services/{ssh/ssh_client_test, tmux/tmux_commands_test, herdr/herdr_adapter_test, terminal/font_calculator_test, tmux/tmux_parser_test}.dart`（HEAD 実測 **271 件**）→ 新 28 テストファイル + helper 4 本
- 設計書: `/tmp/p5-design/BRIEF.md`・`terminal-screens.md`・`services.md`
- 環境: Flutter 3.44.9 stable / `HEAD = 16b56ce`（旧ファイルは HEAD に存在・作業ツリーで削除、新ファイルは未追跡・未コミット）

## 判定: **OK**

以下の全 7 検証項目で NG はゼロ。「テストの意味を変えない再構成」の要件は満たされている。
（検証中に検出した 3 件の exit=1 はいずれも並列 `flutter test` プロセス間のツールロック起因で、単独再実行で全パス。テスト自体の失敗ではない。）

---

## 1. テスト集合の不変（fullName 完全一致・件数・順序・重複）

方法: `flutter test --reporter=json` を旧 9 ファイル（HEAD を `/tmp/p5-reports/work/head/` へ展開したスクラッチ上、lib は HEAD と作業ツリーでバイト一致を確認済み）と新 49 ファイルそれぞれで実行し、`testStart` の `name`（= group パス + テスト名）を「loading」疑似エントリ除きで抽出。

- 旧ファイル実行: **全 exit=0・fail 0**。件数（設計書と一致）:
  - terminal: 57 / 28 / 21 / 14 = **120**
  - services: 30 / 94 / 45 / 48 / 54 = **271**
- 新ファイル実行（49 ファイルを個別+一括で）: 全パス。件数:
  - terminal 21 本: resolve_display 9 / breadcrumb 4 / switch 8 / reconnect 4 / selector_flow 5 / mutation_keys 5 / autofit 3 / scrollback 3 / pane_indicator 11 / caret 5 / resize 10 / paste_image 3 / split_preview 6 / tab_selector_crud 6 / session_resize 3 / sync_mechanism 6 / sync_tab_crud 7 / sync_error 8 / scroll_send_mode 5 / scroll_send_keys 4 / scroll_send_abnormal 5 = **120**
  - services 28 本 = **271**
- 集合比較（旧 1 ファイル ⇔ 対応する新ファイル群の連結）:
  - **multiset（多重度込み）完全一致**: 9/9 ファイル OK（欠落・追加・件数差ゼロ）
  - **順序**: 各新ファイル内の宣言順は旧ファイル内の相対順を保持（subsequence 検証で 9/9 OK）。G1 は設計どおり複数ファイルへ非連続分割（例: selector_flow = G1-26..29 + G4）だが、いずれも旧順序の部分列として一致
  - **重複**: 同一 fullName が複数の新ファイルに出現するケース 0 件。旧側の重複名（tmux の同文言テスト等）は multiset 一致により保全
- 検証スクリプト: `/tmp/p5-reports/work/compare_names.py`（結果 ALL OK）

## 2. テスト本体の verbatim 性（アサーション不変）

方法: Dart トークナイザ（コメント/文字列/括弧対応）で `testWidgets(`/`test(` のコールバック本文を旧/新ソースから抽出し、正規化（コメント除去・空白崩し）の上で**設計のホワイトリスト rename のみ**適用して 1 テストずつ diff。

- 対象 391 テスト（terminal 120 + services 271）すべてについて正文 diff **ゼロ**（missing=0 / extra=0 / body-diff=0）
- 許容した差分は設計 §4-6 の rename のみ:
  - `_pumpHerdrTerminal→pumpHerdrTerminal`、`_herdrConnection→herdrConnection`、file2 の pump/tap 系 `_X→X`、`kHerdrSnapshotWithLayoutFixture(120x24)→kHerdrLargeLayoutSnapshotFixture`、`kHerdrSnapshotNewTabFixture→kHerdrNewTabActiveSnapshotFixture`、scrollSend 系 `_kX→kX` / `_state→state` 等
  - services: `_FakeSocket→FakeSocket` 他、`_fs→kLegacyField` / `_rs→kLegacyRecord`
- 注意点: 旧 scroll_send の `kMaxZoomFactor` は旧ファイルでもローカル定義でなく `lib/.../terminal_zoom.dart`（`= 5.0`）を import 参照であり、新ファイルも同一参照（値不変・実測確認）
- 判定: expect の式・値・数は 1 バイトも変更なし

## 3. 共有コードの重複なし・fixture 値不変

- **定義箇所（rg / grep 実測）**: 共有シンボルは全て helper に 1 箇所のみ:
  - `kHerdrSnapshotFixture` / `kHerdrSnapshotPane2Fixture` / `kHerdrEmptySnapshotFixture` 等 27 fixture → `helpers/herdr_snapshot_fixtures.dart` / `herdr_layout_fixtures.dart` に各 1 定義（旧では file1/file2/file3 に重複していた 6 種が統合）
  - `herdrConnection` / `pumpHerdrTerminal` / `paneIndicatorPainter` / `herdrSwitchEvents` / `pumpHerdrAndOpen*` / `tap*` / `hasResizeCommand` / `amountOf` → `herdr_test_helpers.dart` 各 1
  - `FakeSocket` 等 5 fake → `ssh_client_fakes.dart` 各 1 / `UiFakeManagedPty`・`StartPtyResizeClient` → `herdr_test_helpers.dart` 各 1 / `FakeSshClientWithStderr` 等 3 fake → `herdr_adapter_fakes.dart` 各 1 / `kLegacyField`・`kLegacyRecord` → `tmux_parser_shared.dart` 各 1
  - 新 49 テストファイルは共有シンボルを**再定義していない**（疑似定義 0 件）
- **fixture 値の機械 diff**（トークン正規化・括弧対応抽出、rename 対応込み）: 全 35 fixture 定義の値が旧定義と**完全一致**。特に rename 2 件（120x24→`kHerdrLargeLayoutSnapshotFixture`、`kHerdrSnapshotNewTabFixture`→`kHerdrNewTabActiveSnapshotFixture`）と統合 3 ペア（`kHerdrSnapshotFixture` 等）も値バイト一致
- **既存の重複は P5 前からの事実のみ**: `terminal_screen_can/follow_scroll/cc_close/epoch/repro_bug3/parity` や `herdr_parser/to_domain` の自前 fixture/fake コピーは全て HEAD に存在（`git ls-tree HEAD` で確認）し、本分割が重複を**増やしていない**（BRIEF「重複定義を増やさない」充足）

## 4. helper の非検出

- 8  helper すべてに `void main()` **なし**（grep 実測 0/8）
- ディレクトリ実行 `flutter test test/screens/terminal/ test/services/` の `loading` イベント数 = **123** = `find -name "*_test.dart"` 数 **123** と一致 → helper はテスト対象としてカウントされず（件数へ影響なし）
- helper 名は全て `*_test.dart` パターンに非合致

## 5. タグ・skip・timeout

- 旧 9 ファイル: `@Tags` / `@Skip` / `@Timeout` / `@TestOn` **なし**（grep exit=1）。唯一の一致は旧 ssh_client_test L228 の `SshConnectOptions(timeout: 12)`（引数・メタデータでない）
- 新 49 ファイル + 8 helper: 同様に**一切なし**。`timeout:`/`skip:` の一致は pre-existing の `herdr_caret_helper_manager_test.dart` のテスト名・`persistent_shell_test.dart` の引数のみ（本分割の新規分には無い）

## 6. 構造

- 全ファイル 500 行未満: 対象 49 テスト + 8 helper の最大は `terminal_screen_herdr_pane_indicator_test.dart` の **439 行**（すべての新ファイルで実測）
- `part` / `part of` / `mixin` **不使用**（grep 実測 0 件）
- `git diff HEAD -- lib/` = **空**（出力なしで実測）※ pubspec/analysis_options も差分なし
- `flutter analyze` = **No issues found**（unused import 等ゼロ）

## 7. 担当領域のテスト実行

- `flutter test test/screens/terminal/ test/services/`（一括・ディレクトリ実行）: **exit=0 / done.success=true** / 実テスト **1,301 件**（loading 123 件 = 123 テストファイル、`(tearDownAll)` 疑似エントリ除く）
- 新 49 ファイル個別実行: 全ファイル exit=0。1 回目の並列一括実行で 3 ファイル（`tmux_pane_parser_test` / `terminal_screen_herdr_reconnect_lifecycle_test` / `terminal_screen_herdr_tab_selector_crud_test`）が exit=1 となったが、JSON が空のツール死（並列 flutter プロセスが pub 再取得で競合）であり、**単独再実行で 3/3 とも exit=0 全パス**を確認（テスト失敗ではない）
- parity: `terminal_screen_herdr_parity_test.dart` の変更は設計どおり **import 差し替え 1 行のみ**（`git diff` 確認）・テスト数 HEAD=1/現在=1 で不変・実行パス

---

## 重要指摘トップ 5（すべて検証上の観察・NG なし）

1. **並列 `flutter test` 実行の不安定さ（環境要因）**: 複数 flutter プロセスの同時起動で 3 ファイルがツールレベルで落ちた（ロック/pub 再取得競合、JSON 空・テスト本体は無関係）。CI 等では逐次実行を推奨。本分割の実装品質とは無関係。
2. **分割スコープ外の既存重複が残存**: `terminal_screen_can/follow_scroll/cc_close/epoch/repro_bug3` 等の自前 `kHerdrSnapshotFixture` / `herdrConnection` コピーは HEAD から存在（P5 未対応）。本分割は重複を増やしていないが、将来 `helpers/herdr_snapshot_fixtures.dart` / `herdr_test_helpers.dart` への集約が望ましい。
3. **旧ファイルの 3 重 fixture 統合は安全に実施済み**: `kHerdrSnapshotWithLayoutFixture`（120x24 vs 80x24 同名別値）は設計どおり 120x24 側を `kHerdrLargeLayoutSnapshotFixture` へ rename し値バイト一致を確認。波及 3 箇所（G3-1・G6#10・G7-3）の assert 不変も正文 diff で担保。
4. **file3 の `setUp` 再現・参照更新の正確性**: `SharedPreferences.setMockInitialValues({})` が sync 3 ファイル各 main に再現済み（grep 実測）、`_pumpHerdrTerminal`→`pumpHerdrTerminal` の置換はホワイトリスト内のみ。T18/T19 全 21 件がパス。
5. **残存する無関係な未追跡アーティファクト**: リポジトリ直下の未追跡ディレクトリ `` `${tmp.path}` ``（シェル変数未展開のゴミ）と `test/helpers/fake_save_as_exporter.dart`（他担当の分割 helper）を確認。本スコープ外だが、コミット時の混入防止のため削除/管理を推奨。

## 再現手順（NG 該当なし・参考）

- 旧 baseline: `/tmp/p5-reports/work/head/`（`git archive HEAD test` 展開 + lib/pubspec は作業ツリーとバイト一致）にて `flutter test test/screens/terminal/<old>.dart --reporter=json` 等
- 新旧 fullName 比較: `/tmp/p5-reports/work/compare_names.py`（結果 ALL OK）
- 正文 verbatim 比較: `/tmp/p5-reports/work/compare_bodies.py`（diff ゼロ）
- fixture 値比較: `/tmp/p5-reports/work/check_fixtures.py`（VALUE ISSUES=0）+ 個別精密比較（`kHerdrIndicatorResizeSnapshotFixture` 等 byte一致）

## 証跡ファイル一覧

| 証跡 | パス |
|---|---|
| 旧 9 ファイル名抽出 | `/tmp/p5-reports/work/old_*.names` |
| 旧実行 JSON | `/tmp/p5-reports/work/old_*.json`（全 exit=0） |
| 新 49 ファイル個別 JSON | `/tmp/p5-reports/work/newer/*.json` |
| 一括ディレクトリ実行 JSON | `/tmp/p5-reports/work/dirtest.json`（exit=0 / 1,301 件） |
| fullName 比較 | `/tmp/p5-reports/work/compare_names.py` → ALL OK |
| 正文比較 | `/tmp/p5-reports/work/compare_bodies.py` → diff 0 |
| const/fixture 値比較 | `/tmp/p5-reports/work/check_fixtures.py` → VALUE ISSUES 0 |
| 実行ログ | `/tmp/p5-reports/work/newer/exit.log`（単独再実行後 49/49 exit=0） |

---
*完了報告: 検証は全て /tmp/p5-reports 配下で実施。リポジトリは一切編集していない（git status の作業ツリー状態を変更なし）。*