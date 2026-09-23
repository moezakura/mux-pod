# P3 設計ブリーフ（全設計者共通・厳守）

## 目的

`mux-pod` Flutter リポジトリの **P3 = lib/screens 配下の 500 行超ファイル 8 本** を、
**責務ベース**で 500 行未満の複数ファイルへ再設計する。

P1（services/theme 9本）・P2（widgets/providers 7本）は同方針で完了・コミット済み。
P2 の設計書 `docs/design/refactor-p2/*.md` と `critique.md` を必ず読んで前提を把握すること。

## 対象（P3）

| # | ファイル | 行数 | 既存テスト参照数 |
|---|---|---|---|
| 1 | lib/screens/connections/connections_screen.dart | 1702 | 3 |
| 2 | lib/screens/terminal/widgets/ansi_text_view.dart | 1670 | 12 |
| 3 | lib/screens/connections/connection_form_screen.dart | 1391 | 3 |
| 4 | lib/screens/file_browser/file_browser_screen.dart | 983 | 5 |
| 5 | lib/screens/home_screen.dart | 814 | 0 |
| 6 | lib/screens/file_browser/markdown_preview_screen.dart | 533 | 2 |
| 7 | lib/screens/notifications/notification_panes_screen.dart | 519 | 0 |
| 8 | lib/screens/dashboard/dashboard_screen.dart | 503 | 2 |

P4 = terminal_screen.dart（9529）は本フェーズ対象外・触れない。
生成物（lib/l10n/app_localizations*.dart, lib/services/herdr/herdr_protocols.g.dart, tools/herdr-caret-helper/src/protocols.rs）は対象外・変更禁止。

## ツール制約

- **読み取り専用**: リポジトリ内のファイルを編集してはならない。
- 書き込み可能なのは `/tmp/p3-design/` 配下のみ。
- cwd: `/home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines`（branch: fix/refactor-many-lines）
- HEAD は P2 完了状態。設計対象ファイルは HEAD と作業ツリーが同一（`git diff HEAD -- lib/screens/` が空であることを各自確認）。

## 設計原則（P1/P2 で承認済み・厳守）

1. **1 ファイル = 1 責務**。全ファイル 500 行未満。命名は責務を表す（`*_part1` 等の機械的分割・grab-bag 命名は不可）。
2. **合成（composition）を優先**。構成ルート（facade）＋単一の状態所有者＋協調オブジェクト群（has-a）。依存方向は一方向（循環 import 禁止）。
3. **`part` / `mixin` / private 基底クラスでの private state 共有は禁止**（ユーザーが機械的 v1 を却下した経緯による）。
   - 例外は P1 で承認された tmux facade の `_TmuxFacadeHost` 型のみ。今回も同種の例外を使うなら **理由と代案の比較を設計書に明記**し、 critic の審査対象とする。
4. **公開 API 維持**: Widget クラス名・コンストラクタ・プロパティ、公開関数・enum・typedef、export シンボルを変えない。
   - 他ファイル/テストが import するパスは維持する。中身を別ファイルへ移す場合は **元ファイルをロジックなしの thin re-export シム**（doc comment に実装先を明記）にする。P2 の `connection_provider.dart` / `resize_dialog.dart` が前例。
5. **挙動不変**: 既存テストファイルは **差分ゼロ**（`git diff HEAD -- test/` が空）。テストを書き換えて通すのは不可。新規テスト追加は可（回帰テスト・単体テスト）。
6. **状態所有権の単一化**: StatefulWidget の State に同居する Controller / FocusNode / Timer / StreamSubscription / ScrollController / GlobalKey / TextEditingController は、**破棄責任を持つ所有者を 1 つ**に決めて設計書に表で示す。dispose / didUpdateWidget / build の呼び出し順序を HEAD と一致させる。
7. Widget ツリー形状・キー（ValueKey/GlobalKey）・AnimatedBuilder の再構築範囲は、既存テストが固定している場合がある。**テストが何を固定しているか実測**してから設計すること。

## 各設計書の必須セクション

1. **現状分析（事実）**: 行番号付きで、現在 1 ファイルに同居している責務を列挙。state/controller/timer/subscription の所有権インベントリ。呼出元（rg 実測）と import パス。既存テストが固定している挙動（テストファイル名と該当テスト名）。
2. **目標構成**: 新規/変更ファイルごとに「責務・推定行数・公開シンボル・依存先」。全ファイル 500 行未満を数値で保証（概算でよいが根拠を示す）。
3. **移動マッピング**: 既存メンバー（メソッド/フィールド/Widget）を行範囲で「どこへ移す / そのまま残す」を一覧化。移動のみのものは移動のみと明記。
4. **公開 API 維持表**: 維持するシンボル、thin re-export にするファイル、呼出元・テストの import が変わらないことの根拠（rg 結果）。
5. **状態所有権表**: 上記 6 の表（所有者 / 生成 / 破棄 / 更新通知経路）。
6. **リスクと対策**: 想定される回帰（ライフサイクル、リビルド範囲、IME、スクロール、非同期ギャップ、`ref.mounted`、dispose 順序）と、それを検出する既存テスト/新規テスト。
7. **検証計画**: 実行コマンド（`dart format --output=none --set-exit-if-changed .` / `flutter analyze` / `flutter test --exclude-tags=repro` / `git diff HEAD -- test/` ゼロ確認 / `dart tool/generate_herdr_protocols.dart --check`）。
8. **未確定点**: ユーザー判断が必要な選択肢（あれば。無ければ「なし」）。

## 事実主義

- 推測・仮定で設計しない。**行番号・メンバー名・rg 結果・テスト名**を根拠として示す。
- 不明点は「不明」と書く。勝手に補完しない。
- 比較は `git show HEAD:<path>` と作業ツリーの実ファイルで行う（本フェーズでは同一だが、行番号の基準を明記）。

## 成果物

指定パスに Markdown 1 本。完成後、リードへ「完了・成果物パス・要点 3 行」を報告すること。
他の設計者と情報共有すべき発見（共通の落とし穴等）は直接メッセージしてよい。
