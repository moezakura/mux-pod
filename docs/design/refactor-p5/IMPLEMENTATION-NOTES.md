# P5 実装ノート（テスト分割の検証記録）

P5（`test/` の 500 行超 18 ファイルの責務分割）の結果と検証を残す。

## 結果

- 対象 18 ファイル（計 約 19,000 行）を **約 60 テストファイル + 約 15 helper** へ分割。
  分割後は `test/` 全体で **500 行超のファイルはゼロ**（最大 439 行）。
- **テスト総数 2,009 は不変**（分割のみで追加・削除・改変なし）。
- `lib/` は一切変更していない（`git diff HEAD -- lib/` は空）。

## 検証（統合 + 独立レビュー）

| 検証 | 結果 |
|---|---|
| テスト集合の不変（fullName 集合・多重度・順序） | terminal 120 / services 271 / providers・widgets 254 = **完全一致** |
| テスト本体の verbatim 性（正規化 diff） | terminal・services **diff ゼロ**（rename/import 差し替えのみ）。providers・widgets は整形由来の改行 7 行のみ |
| 共有コードの単一性 | fake / fixture / harness は helper 1 箇所定義。`FakeSaveAsExporter` は `test/helpers/fake_save_as_exporter.dart` の 1 定義 |
| helper の誤検出なし | helper に `main()` なし（テスト対象数 = test ファイル数 123 で一致） |
| メタデータ | 旧ファイルにタグ・skip・timeout はなし（実測）。新ファイルにも付与なし |
| 構造 | 全ファイル 500 行未満 / part・mixin 不使用 |
| スイート | `flutter test --exclude-tags=repro` = **2,009 全パス** / `flutter analyze` No issues / `dart format` 0 changed |

独立レビュー 2 本（terminal+services / providers+widgets+screens）はいずれも **OK**。
証跡は `review-a.md` / `review-b.md` を参照。

## 留意事項

- 分割時に fixture を統合した箇所（terminal の 27 fixture → H1a/H1b）は、
  rename 統合（LargeLayout / NewTab）を含めて値のバイト一致を独立レビューで確認済み。
- `tmp` / `appTmp` のようなテスト内の変数は、設計どおり「main の late 変数へ
  setUp で再代入」する方式を採り、テスト本体の記述は書き換えていない。
- 既存テストが旧ファイルを import していた箇所（terminal の parity テスト等）は
  helper 経由の import に差し替えている。
