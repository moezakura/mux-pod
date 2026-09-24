# P5 独立検証B レビュー結果（providers / widgets・screens）

- 検証者: p5-reviewer-b（読み取り専用。書き込みは /tmp のみ）
- 対象: 旧 test/providers 4 ファイル＋旧 test/widgets 2 ファイル＋旧 test/screens 3 ファイルの分割
- cwd: /home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines（HEAD = 16b56ce）
- 旧ベースライン: `git worktree add /tmp/p5-old HEAD` を /tmp に作成して実行（検証後削除済み、リポジトリ未編集）
- 実行環境: flutter 3.44.9 stable（make test と同一）/ python3 解析ツール群（/tmp/p5-tools/）

---

## 判定: **OK**（軽微指摘 2 件あり・要対応 1 件）

---

## 検証項目と証跡

### 1. テスト集合の不変 ✓

`flutter test --reporter=json` の `testStart` 非 hidden イベント（`loading <path>` 擬似イベント除外）で
fullName（`test.name`、group 連結済み）の集合を比較。

| 区分 | 旧（HEAD 時・9 ファイル） | 新（36 ファイル） |
|---|---|---|
| 総件数 | 254 | 254 |
| success / skipped / fail | 254 / 0 / 0 | 254 / 0 / 0 |
| EXIT | 0 | 0 |

- fullName 集合 diff: **0 行**（`old_names.txt` vs `new_names.txt` 完全一致）。
- 内訳（旧→新・件数不変）:
  - download 35: basic_flow 7 / cancel_reset 5 / disconnect_error 5 / progress_speed 2 / batch_lifecycle 5 / notification 5 / single_download 6
  - active_session 33: crud 13 / persistence 5 / model_json 5 / domain_sync 4 / domain_migration 6
  - connection 37: connection_provider 8 / connection_model 17 / connection_migration 10 / corrupted_record 2
  - custom_keys 33: buttons 6 / row0 7 / placement 9 / rows 6 / migration 5
  - special_keys 41: layout 12 / custom_buttons 13 / direct_input 10 / rows 6
  - dialog 17: validation 5 / edit 6 / 本体維持 6
  - markdown 30: screen 10 / resource_guards 12 / link_guard 2 / highlight 6
  - custom_keys_screen 21: 本体 9 / layout 12
  - file_browser_download_flow 7: 本体 2 / batch_download 5
- 旧ファイルの @Tags/@Skip/@Timeout 0 件（9 ファイル全 grep）＝新ファイルも 0 件。

### 2. テスト本体の verbatim 性 ✓（7 箇所の整形のみ差異・意味同一）

Dart 対応のテスト本体抽出ツール（/tmp/p5-tools/extract_bodies.py：文字列・コメント除外部、隣接文字列連結・
エスケープデコード対応）でリポジトリ非依存に 254/254 本を抽出し、設計の rename マップのみ適用して正規化比較。

| ファイル | 正規化比較結果 |
|---|---|
| download | 29/35 完全一致。6 件は `makeDownloadProviderContainer(...)` の**引数改行（dart format 整形）のみ**差分（アサーション・期待値・タイマー値に変化なし） |
| active_session | 33/33 完全一致（rename 不要） |
| connection | 37/37 完全一致 |
| custom_keys（provider） | 33/33 完全一致 |
| special_keys | 41/41 完全一致（group4/5 の `directInputField`/`visibleText` 重複ローカル定義は helper 一元化・呼出側は無変更） |
| dialog | 17/17 完全一致 |
| markdown | 29/30 完全一致。1 件は `FakeMarkdownPreviewNotifier(` の**引数改行のみ**差分 |
| custom_keys_screen | 21/21 完全一致 |
| download_flow | 7/7 完全一致 |

注: 差分 7 件はすべて「helper 呼び出し引数の 1 行→複数行」の整形で、意味・アサーション・pump 回数は不変。
テスト本文の意味改変は 0 件（BRIEF 1 項の趣旨には適合。厳密な「行コピーのみ＝§2-0」からの逸脱は 7 行）。

**(a) tmp/appTmp 参照** ✓ — 旧 download の tmp/appTmp 参照は 67 行（実測 60+7、設計§2-3補の 67 と一致）。
新 7 ファイルの対応テスト本文にも 67 行が**テスト毎にバイト一致**（`check_tmp.py` で全差分 0）。
`FakeDownloadDestination(tmp.path)` 30 行・`File('${tmp.path}/...')` 実IO 等・`'$appTmp/sftp_download/data_1.bin'`
期待値 7 行すべて不変。変数参照方式（各 main の `late Directory tmp; late String appTmp;` ＋ setUp 再代入）の実装を確認。
`TestWidgetsFlutterBinding.ensureInitialized()` は 7 download ファイル全ファイルに 1 回ずつ存在。

**(b) MediaQuery pump の回数・位置** ✓ — dialog 本体 17/17 verbatim。4 ブロックの構造（外側 `MediaQuery(` 1 ＋
直置き 3・textScaler 2.0/1.3×2・view 幅 411/308）は旧 L379/465/510/589 → 新 L21/107/152/231 に同形で保持。
pump 回数・位置の変化なし。

**(c) provider override の順序** ✓ — helpers の pump 関数を旧とバイト比較。
- markdown: `pumpScreen`（sshProvider のみ）/ `pumpScreenWithState`（sshProvider → markdownPreviewProvider）の
  overrides 順・`tester.view` サイズ設定・`pumpAndSettle` 呼び出しが旧と同一（rename のみ）。
- download_flow: `pumpDownloadScreen` の overrides 順（fileBrowser → ssh → settings →
  batchDestinationPicker → download）・channel モック手順が旧 `_pumpScreen` と同一。

### 3. 共有コード（1 定義のみ）✓

- `FakeSaveAsExporter` → `test/helpers/fake_save_as_exporter.dart` に**1 定義のみ**
  （`rg -l "class FakeSaveAsExporter"` = この 1 ファイル）。providers は `download_provider_test_utils.dart` の
  re-export（`export ... show FakeSaveAsExporter`）、widgets は `file_browser_download_flow_test.dart` が
  直接 import。二重定義なし。critique §2-4 の一本化方針どおり。
- P5 導入 fake は全て helper 1 定義: FakeDownloadDestination / TestSftpClient / TestDownloadSftpClient /
  GatedSaveAsExporter / OpenSftpFailingSshClient / RecordingSftpClient / FlakySftpClient /
  FakeMarkdownPreviewNotifier / DownloadProviderTmpScope（`rg -l "class <名>"` で確認）。
- 注: `FakeBatchDestinationPicker` は helper と `file_browser_multi_select_test.dart` に計 2 定義だが、
  **HEAD 時点で既に** multi_select L56 と旧 download_flow L67 に二重存在（`git show HEAD:` で確認）。
  P5 が新たに増やした重複ではない（本フェーズ対象外の既存状態を維持）。

### 4. helper の非検出・タグ・構造 ✓（指摘 2 件）

- helper 非検出: 8 helper すべて `main()` なし（`rg -l "void main"` = 検出 0）。ディレクトリ実行の
  43 スイート URL に helper ファイルは含まれない。
- 構造: 全 P5 ファイル 500 行未満（最大 connection_migration 362 行）。`part`/`mixin` なし。
  `git diff HEAD -- lib/` = **空**（lib 未変更）。
- 指摘 1（要対応）: リポジトリ直下に**仮の junk ディレクトリ `'${tmp.path}/'`**（未追跡・14:21 作成）。
  `app_tmp/` と `docs/downloads/{a.pdf,b.pdf}`（実 DL のテスト出力と思料）を含む。シェル変数未展開の実装時
  アーティファクトと判断。Merge 前に必ず削除すること（誤コミットの危険）。
- 指摘 2（設計逸脱・軽微）: `test/providers/helpers/custom_keys_test_harness.dart`
  （`createCustomKeysContainer`）は**どこからも import されないデッドコード**。設計 §3-4 はボイラープレートの
  helper 抽出を意図したが、実装は本文にボイラープレートを残し（verbatim 維持）、helper を未使用のまま放置。

### 5. 担当領域のテスト実行 ✓

```
flutter test test/providers/ test/widgets/ test/screens/file_browser/ test/screens/custom_keys/ --reporter=json
→ EXIT=0 / 599 テスト / success 599 / skipped 0 / fail 0
flutter analyze test/providers test/widgets test/screens/file_browser test/screens/custom_keys
→ No issues found!
```
（注: JSON 上、testWidgets 系は flutter_test の `widget_tester.dart` URL に帰属する reporting quirck があるが、
件数は 599 に一致。P5 対象 36 ファイルは明示実行で旧 254 件と fullName・件数完全一致を別途確認済み。）

---

## 重要指摘トップ 5

1. **（要対応・NG 級ではないが必須）リポジトリ直下の junk ディレクトリ `'${tmp.path}/'` の削除**。
   未追跡・シェル変数未展開のテスト実行アーティファクト（`app_tmp/`＋`docs/downloads/*.pdf`）。
   Merge 前に必ず除去すること。※ 検証側は読み取り専用のため未削除。
2. **`custom_keys_test_harness.dart`（createCustomKeysContainer）が未使用のデッドコード**。設計 §3-4 の
   コード抽出意図（33 テスト共通 5 行）が未実現で、ボイラープレートは 5 ファイルに重複残置。
   不要なら削除、または本文を helper 化して意味を共有するかの判断が必要（テスト意味は不変）。
3. **「行コピーのみ」からの 7 行整形逸脱**（semantic 無し）。download 6 件＋markdown 1 件で
   helper/notifier 呼出の引数が 1 行→複数行に改行（おそらく dart format）。アサーション・期待値・
   タイマー値・pump は不変のため NG ではないが、厳密な「1 バイトも変えない」方針からの差異として記録。
4. **`FakeBatchDestinationPicker` の 2 定義は P5 起因ではない**（HEAD 時点で multi_select と旧 download_flow に
   既存）。helper 化は現状維持のみ。将来の統一は本フェーズ対象外としてリードの認識を推奨。
5. **URL 帰属の quirk は混同しないこと**。`--reporter=json` の testWidgets 系 suite は
   `package:flutter_test/src/widget_tester.dart` に集計されるため、「ファイル別件数」をこの URL で数えないこと
   （fullName で比較すること。本検証は fullName 集合で一致確認済み）。

---

## 証跡ファイル

- /tmp/p5-tools/old_all.jsonl, new_all.jsonl（旧/新の `flutter test --reporter=json` 生ログ、本領域）
- /tmp/p5-tools/dirs_all.jsonl（`flutter test <4 ディレクトリ> --reporter=json`）
- /tmp/p5-tools/old_names.txt / new_names.txt / fullname_diff.txt（fullName 集合・diff=空）
- /tmp/p5-tools/old_bodies/・new_bodies/（254 テスト本体の抽出結果・9+36 ファイル）
- /tmp/p5-tools/compare_bodies.py（renames 正規化 diff）、/tmp/p5-tools/check_tmp.py（tmp/appTmp 67 行検証）
- /tmp/p5-tools/extract_bodies.py（Dart テスト本体抽出器）
- /tmp/p5-old（HEAD 時点 worktree・検証後 `git worktree remove` 済み）

## 検証環境の整合

- 旧ベースラインは HEAD（16b56ce）の実物で実行（純正 repositry 由来、guess なし）。
- リポジトリ本体への編集はゼロ（`git status` 変化なし・`git diff HEAD -- lib/` 空を確認）。