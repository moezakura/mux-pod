# P4 実装ノート（統合・レビュー・修正の記録）

P4（`terminal_screen.dart` 9,529 行の責務ベース再設計）の実装・統合・
独立レビューで判明した事項と修正を残す。

## 結果

- `lib/screens/terminal/terminal_screen.dart` 9,529 → **453 行**（シム + root State）
- 新規/分割ファイル: 66 Dart ファイル（`session/` 14、`input/` 9、`herdr/` 13、
  root/ui 19、既存 widgets 等）。**すべて 500 行未満**（最大 495）
- 検証: `dart format` 0 changed / `flutter analyze` No issues /
  `test/` 既存ファイル差分ゼロ / **2,009 テスト全パス**（新規回帰テスト 9 件を含む） /
  `dart tool/generate_herdr_protocols.dart --check` exit 0 /
  `lib/screens/terminal` 配下の import 循環（SCC>=2）**0**

## 実装中の主要な出来事

1. **統合の未完成**（root State の結線が 65 analyze issues の状態で停滞）を
   統合専任で修復し、シムを 438 行へ縮小。
2. **既存テスト 91 件の回帰**（herdr 80 / スクロール・セッション 11）を
   テストをオラクルに全件修復（`test/` は一切変更していない）。
3. **循環 import の混入を検出**: `terminal_root_bindings.dart` ⇄
   `terminal_screen_ports.dart` を `terminal_screen_access.dart`（中立）へ
   `TerminalScreenAccess` を抽出して解消。

## 独立レビューで検出した挙動パリティ破れと修正

レビュー A（session/input/root）8 件、レビュー B（herdr/ui）4 件。いずれも
「既存テストが捕捉しない HEAD との差分」で、テストは green のままだった。

| # | 内容 | 修正 |
|---|---|---|
| A-1 | ダウンロード進捗 publish ごとに空 SnackBar（非 null sentinel が `display == null` 判定を殺す） | `SessionEnv.downloadSnackBarDisplay` を null 許容戻り値にし、adapter は null をそのまま伝搬 |
| A-2 | `deactivate` で SSH 切断が消失（popUntil 経路） | HEAD 同等の `restore → checkConnection → disconnect` を復元 |
| A-3 | `_hasInitialScrolled` の二重所有で pane 切替後の初回キャレットスクロール消失 | runtime の単一フィールドに統一（pipeline は getter/setter 注入） |
| A-4 | G2 背景復元の 600ms 猶予・復帰後 force 再 fit が未配線 | `inactive → scheduleBackgroundRestore` / `paused,hidden,detached → onBackgroundNow` / `resumed → onResumed` |
| A-5 | エラー SnackBar の Retry がポーリング再開のみ | `connectAndSetup` の再実行に戻す |
| A-6 | `observePaneMode('')` 固定で H4② ガードが死コード化 | 実測 paneMode を渡す（port 引数化） |
| A-7 | copy-mode 自動遷移条件が select(manual) 中にも発火 | HEAD 同等の `source == none` 条件へ |
| A-8 | follow-to-bottom が select/scrollSend/ドラッグ中にも発火 | HEAD 同等の `normal && !dragging` ガードを追加 |
| B-1 | herdr 切替/セッション確立で view クリア（content/caret/`hasInitialScrolled`）が欠落 | `resetView` を専用実装へ配線（`_resetView`） |
| B-2 | 上記に伴う `hasInitialScrolled` の herdr 経路リセット欠落 | B-1 で同時に解消 |
| B-3 | `resetView` と `resetTerminalMode` の重複呼び | B-1 で意味分離（view クリア / mode リセット） |
| B-4 | 診断文字列 `hasPaneContentReader=...` の欠落 | `HerdrHost.hasInjectedPaneContentReader` を追加して HEAD 文言へ |

## 追加した回帰テスト（新規 4 ファイル・9 テスト）

- `test/screens/terminal/terminal_screen_lifecycle_parity_test.dart`
  （deactivate の SSH 切断・inactive 600ms 猶予・paused 即時復元・resumed force 再 fit）
- `test/screens/terminal/terminal_screen_download_parity_test.dart`
  （進捗 publish で空 SnackBar を出さない）
- `test/screens/terminal/terminal_screen_herdr_parity_test.dart`
  （切替時の view クリア）
- `test/helpers/terminal_parity_pump.dart`（上記の最小 pump ヘルパー）

既存 `test/` ファイルは一切変更していない（`git diff HEAD -- test/` は空）。
