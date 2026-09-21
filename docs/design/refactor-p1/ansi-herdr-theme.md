# 責務ベース再設計: ansi_parser / herdr_adapter / app_theme（v2）

- **v2 改訂**: design-critic レビュー（`/tmp/p1-design/critique.md` §3）反映。主な変更: ①ansi の parse/parseLines「アルゴリズム統合」撤回 → 経路分離 + 入力種別別テスト ②スパンキャッシュ同一性のテスト/assert 追加 ③theme をパレットデータ化（AppThemePalette + 単一ビルダー）へ一本化 + 等価性テスト、getThemeMode 削除推奨 ④herdr の l10n 遅延解決明記 + MutationClient 責務再分割 ⑤mutation メソッド数等の実測合わせ
- 対象リポジトリ: `/home/mox/Projects/mux-pod/worktree/fix/refactor-many-lines`
- 設計の基点: `git show HEAD:<path>` の元ファイル（ワーキングツリーの既存分割は参考のみ）
- HEAD: `9f30573`（fix: auto-scroll terminal output…）
- 設計モード: **設計のみ・コード変更禁止**
- 設計原則（タスク指定）: ①1ファイル=1責務 ②合成(composition/delegation)優先・mixin/基底クラス禁止 ③公開API変更可（テスト期待値は不変） ④依存は明示的・非循環 ⑤500行未満 ⑥挙動不変 ⑦基点はHEAD

---

## 1. 現状責務分析

### 1.1 `lib/services/terminal/ansi_parser.dart`（HEAD 679 行）

| 行範囲 | 責務 | 現状の所在 |
|---|---|---|
| 6–77 | 値型 `AnsiStyle`（copyWith / == / hashCode / defaultStyle） | AnsiParser と同居 |
| 80–85 | 値型 `AnsiSegment` | 〃 |
| 88–99 | 値型 `ParsedLine`（isEmpty） | 〃 |
| 102–107 | 内部キャッシュエントリ `_LineSpan` | 〃 |
| 115–163 | インスタンス状態: defaultForeground/Background + `_lineCache` + `_spanCache` | 〃 |
| 165–195 | **SGR スキャン**（文字列→セグメント列）`parse()` | 〃 |
| 197–345 | **SGR コード解釈** `_parseSgr`（switch 100 行超） | 〃 |
| 347–381 | 256 色パレット計算 `_get256Color` | 〃 |
| 383–419 | セグメント→TextSpan `toTextSpan` / `_segmentToTextSpan`（opaque 化・inverse の NBSP 化） | 〃 |
| 464–531 | **行パース + インクリメンタルキャッシュ** `parseLines` / `_parseLineWithStyle`（`_lineCache` 所有） | 〃 |
| 534–583 | 描画色解決 `resolvePaintColors` / `effectiveLineBackgroundColor` / `_endsWithWhitespace`（R3/HYP-4 の長い doc コメント含む） | 〃 |
| 585–678 | **行→TextSpan + 弱参照キャッシュ** `lineToTextSpan`（`_spanCache` 所有）・キャレット直接挿入 `lineToTextSpanWithCaret` | 〃 |

→ **1 クラスが 6 責務（値型 / SGR 解釈 / 行キャッシュ / TextSpan 変換 / 描画色解決 / キャレット合成）を兼務。**

### 1.2 `lib/services/herdr/herdr_adapter.dart`（HEAD 644 行）

| 行範囲 | 責務 | 現状の所在 |
|---|---|---|
| 34–63 | 状態・設定（BackendAdapter / executablePath / l10n / isConnected） | HerdrAdapter と同居 |
| 66–160 | **read 操作**（preflight / status / snapshot / paneRead） | 〃 |
| 165–397 | **mutation 操作 17 個**（実測: `Future<HerdrMutationResult>` の公開メソッド 17 = sendText / sendKey / focusDirection / edges / resize / zoom / rename / close / split / tab CRUD / workspace CRUD） | 〃 |
| 165–197 | fire-and-forget 送信 `_trySendNoWait`（inputTransport 経由・exec 基盤と mutation の橋渡し） | 〃 |
| 399–505 | **mutation 実行基盤** `_execMutation` / `_parseMutationResult` | 〃 |
| 507–648 | **exec 基盤** `_resolve` / `_execChecked` / `_buildErrorMessageFrom` / `_extractErrorCodeFrom`（エラー分類・ローカライズ） | 〃 |
| 650–679 | 値型 `HerdrMutationResult`（changed / reason / layout / isNoNeighbor / isUnchanged） | 〃 |

→ **1 クラスが 5 責務（read / mutation / exec 基盤 / 値型 / ローカライズ解決）を兼務。** `_trySendNoWait` と `_execChecked` は read・mutation 双方から参照される交差依存の要。

### 1.3 `lib/theme/app_theme.dart`（HEAD 501 行）

| 行範囲 | 責務 | 現状の所在 |
|---|---|---|
| 14–48 | Space Grotesk ベース `_textTheme` + JetBrains Mono `monoTextStyle` | AppTheme と同居 |
| 53–260 | **dark ThemeData ビルダー**（ColorScheme + 約 18 のサブテーマ） | 〃 |
| 263–493 | **light ThemeData ビルダー**（同上・switchTheme は light のみ） | 〃 |
| 496–505 | `getThemeMode`（**呼出元ゼロのデッドコード**、後述） | 〃 |

→ 暗/明ビルダーが大部分を占め、構造が 85% 重複（差分は色値 + FAB elevation/foreground + segmented 背景 + enabledBorder + switchTheme 有無）。

### 1.4 ワーキングツリーの既存分割（参考。設計原則違反のため破棄）

| ファイル | 分割方式 | 問題点 |
|---|---|---|
| ansi: `ansi_parser.dart`+`ansi_models.dart`+`ansi_parser_span.dart` | `part of` + `_AnsiParserCore` 基底 + `_AnsiParserSpanMixin` | 責務2「private フィールド共有のための mixin/基底クラス禁止」に反する。part は同一ライブラリ内に閉じ、ファイル間に独立 API が生まれない |
| herdr: `herdr_adapter.dart`+`exec`+`mutation`+`mutation_result` | `part of` + `_HerdrAdapterBase` + 2 mixin | 同上。`herdr_adapter_exec.dart` は名前が広すぎる grab-bag |
| theme: `app_theme.dart`+`app_theme_dark/light` | `part of` | 同上 |

→ 部分的に「500 行未満」は満たすが、**ファイル境界 ≠ 責務境界**。今回の設計はゼロから composition で組み直す。

---

## 2. 提案構成

### 2.1 ansi（5 ファイル・独立ライブラリ・ファサードが合成）

| ファイル | 責務（1 文） | 公開面 | 推定行数 |
|---|---|---|---|
| `ansi_models.dart` | ANSI スタイルの不変値型（AnsiStyle は copyWith/==/hashCode を持つ値オブジェクト）を定義する | `AnsiStyle` / `AnsiSegment` / `ParsedLine`（現行シグネチャ不変） | ~100 |
| `ansi_sgr_parser.dart` | SGR パラメータ文字列を解釈して `AnsiStyle` を更新し、標準/明るい/256 色パレットを保持する | `AnsiSgrParser({defaultForeground, defaultBackground})` + `AnsiStyle apply(String params, AnsiStyle current)`。static として `standardColors`/`brightColors` | ~140 |
| `ansi_line_parser.dart` | ANSI テキストをセグメント列・行リストへ分解し、**行パースキャッシュ（`_lineCache`）を所有**する | `AnsiLineParser({required AnsiSgrParser sgr, defaultForeground, defaultBackground})` + `List<AnsiSegment> parse(String)` + `List<ParsedLine> parseLines(String)` | ~170 |
| `ansi_span_renderer.dart` | ParsedLine/セグメント列から TextSpan を構築し、**行→TextSpan 弱参照キャッシュ（`_spanCache`）を所有**する | `AnsiSpanRenderer({defaultForeground, defaultBackground})` + `toTextSpan` / `lineToTextSpan` / `lineToTextSpanWithCaret` / `resolvePaintColors` / `effectiveLineBackgroundColor`（内部で `TerminalFontStyles` を使用） | ~300 |
| `ansi_parser.dart` | **合成ルートの公開ファサード**。SgrParser / LineParser / SpanRenderer を内部構築し、従来の公開 API をそのまま委譲する | 既存 2 コンストラクタ引数・全メソッド + `export 'ansi_models.dart';`（旧 import 互換） | ~70 |

※実測参考: span 層はワーキングツリーの `ansi_parser_span.dart`（309 行）に一致。

**parse() と parseLines の経路分離（v2・重要）**:
- **`parse()`**: 現行意味論を維持した「**正規化なし・行分割なし**の入力全体スキャン」（HEAD L165-195 と同じ。CRLF/CR の置換も行分割も行わず、SGR マッチを1ストリームで走査）。`parseToTextSpan` 経路の挙動を不変に保つため統合しない。
- **`parseLines()`**: CRLF/CR 正規化 → 行分割 → `_lineCache` 参照 → 各行をスキャン（HEAD L464-531 と同じ。開始スタイル引き継ぎ・インスタンス再利用を維持）。
- 両者の**スキャン走査ループ本体のみ**を共通 private ヘルパー（`(segments, endStyle)` を返す）として共有可能だが、**前処理（正規化・行分割・キャッシュ・開始スタイル）は経路別に固定**し「アルゴリズム統合」は行わない（v2 で撤回）。

- キャッシュの所有者を明示: **行キャッシュ = LineParser、スパンキャッシュ = SpanRenderer**。スパンキャッシュ（`Expando<ParsedLine>`）は「LineParser が返す ParsedLine インスタンスの同一性」に依存するため、ファサードは LineParser の返却インスタンスをそのまま SpanRenderer へ渡す（現行と同一の動作。依存関係は doc に明記し、**規約違反を検知する assert + テストを追加**（v2 対応）: ①ファサードの委譲箇所に `assert(identical(renderer へ渡す ParsedLine, lineParser が返却した ParsedLine))` 相当のデバッグチェック ②同一行の再 `parseLines` で返る ParsedLine が `identical` であること ③同一 ParsedLine に対する `lineToTextSpan` の2回呼び出しが同一 `TextSpan` インスタンスを返すこと（スパンキャッシュヒット）、の 3 テスト）。
- defaultForeground/defaultBackground は LineParser（256色フォールバック用の fg）と SpanRenderer（色解決用）の両方が必要 → ファサードが両方へ注入（composition root 方式）。

### 2.2 herdr（5 ファイル・独立ライブラリ・ファサードが委譲）

| ファイル | 責務（1 文） | 公開面 | 推定行数 |
|---|---|---|---|
| `herdr_command_executor.dart` | BackendAdapter 経由で herdr CLI を実行し、エラーを target-not-found / command / SSH 切断に分類して例外化する exec 基盤（read / mutation 共通）を提供する | `HerdrCommandExecutor(BackendAdapter, {userExecutablePath, l10n})` + `Future<String> execChecked(String, {timeout, viaPersistent})`（read 用）+ `Future<String> execMutation(String, {timeout})`（mutation 用: `ephemeralOnly + separatedOutput` の CommandRequest 組立と例外分類を共通化）+ `bool trySendNoWait(String)` + `isConnected`。内部: `_resolve` / `_buildErrorMessageFrom` / `_extractErrorCodeFrom`（execChecked / execMutation が共有する private 実行ヘルパー）。**ローカライズは `AppLocalizations get _strings => _l10n ?? lookupL10n();` の遅延解決をそのまま移設**（head 版 L35-37 と同じ。構築時解決に変更しない） | ~230 |
| `herdr_read_client.dart` | read 操作（preflight / status / snapshot / paneRead）を exec 基盤へ委譲し stdout をパーサで検証する | `HerdrReadClient(HerdrCommandExecutor)` + read 4 メソッド（現行シグネチャ不変） | ~110 |
| `herdr_mutation_result.dart` | mutation 応答の値型 `HerdrMutationResult` と、応答 stdout から値を抽出する静的パーサを提供する | `HerdrMutationResult`（不変）+ `HerdrMutationResult.parse(String stdout)` | ~90 |
| `herdr_mutation_client.dart` | mutation 操作 17 個を宣言し、**送信経路選択**（sendNoWait 成功 → 素の結果 / 失敗 → executor へ委譲）のみを行う | `HerdrMutationClient(HerdrCommandExecutor)` + mutation 17 メソッド（現行シグネチャ不変） | ~250 |
| `herdr_adapter.dart` | **公開ファサード**。Executor / ReadClient / MutationClient を内部構築し、従来の全公開 API を委譲する | `HerdrAdapter(BackendAdapter, {userExecutablePath, l10n})` + **全 22 公開メンバー**（isConnected + read 4 + mutation 17、実測）を委譲（現行と完全互換・継承可能な通常クラス） | ~90 |

※実測参考: mutation パートはワーキングツリーの `herdr_adapter_mutation.dart`（352 行）に一致。

**mutation client の責務再確認（v2）**: 送信経路選択（sendNoWait 成功 → 素の結果 / 失敗 → Executor.execMutation へ委譲）に絞り、**実行（CommandRequest 組立・例外分類）= `HerdrCommandExecutor.execMutation`**、**結果解析 = `HerdrMutationResult.parse`** へ委譲する。HEAD の `_execMutation`（L399-445）は「実行 + 例外分類」と「結果解析」を `_parseMutationResult`（L447-505）に分離しており、前者を Executor、後者を parse へ移すことで mutation client に実ロジックが残らない。

- mux-pod の `herdr_mutation_result.dart`（39 行・part）は独立ライブラリ化して拡張する。
- テストのサブクラス化（`_FakeSnapshotAdapter extends HerdrAdapter`、`_MinimalAdapter extends HerdrAdapter`：いずれも `snapshot()` を override）は、ファサードが通常の継承可能クラスである限り維持できる（詳細は §5）。

### 2.3 theme（4 ファイル・独立ライブラリ・パレットデータ化を第一案に）

| ファイル | 責務（1 文） | 公開面 | 推定行数 |
|---|---|---|---|
| `app_theme_palette.dart` | dark / light の**色値バンドルと構造差分フラグ**を不変データとして保持する | `AppThemePalette`（値オブジェクト）+ static `AppThemePalette.dark` / `.light` | ~90 |
| `app_theme_builder.dart` | パレットと Brightness から**単一の ThemeData 構築ロジック**を提供する（dark/light の重複 85% を排除） | `AppThemeBuilder` + `ThemeData build(AppThemePalette palette, Brightness brightness)` | ~200 |
| `app_text_theme.dart` | Space Grotesk のテキストテーマと JetBrains Mono のモノスペーススタイルを定義する | `AppTextTheme` + static `TextTheme get spaceGrotesk` / `TextStyle get mono` | ~40 |
| `app_theme.dart` | **公開ファサード**。パレットとビルダーを合成し、従来の静的公開面を維持する | `AppTheme.dark` / `AppTheme.light` / `AppTheme.monoTextStyle`（`getThemeMode` は**削除推奨**・v2） | ~50 |

- **パレットにエンコードする内容（挙動不変の要）**: 暗/明で値が異なる全色（scheme 8 + scaffold / surface / border / input / text 系 / canvas / FAB / navBar 等）に加え、**構造差分 6 箇所** — FAB `elevation`(0/2) と `foregroundColor`(black/white)・segmentedButton の非選択背景（`Colors.black a0.4` / `DesignColors.inputLight`）・enabledBorder（`Colors.white a0.1` / `borderLight`）・**switchTheme の有無（light のみ）** － をフラグ/フィールドとして明示エンコードする。
- **挙動不変の検証方法**: ①HEAD 現行の dark/light をまず「逐語版ビルダー 2 分割」へ移して既存テスト OK を確保（＝金の基準）②パレット抽出 + 共通ビルダー化の際、①の出力と `AppThemeBuilder.build(palette)` の出力 ThemeData を**全サブテーマ・全色フィールドで deep compare する等価性テスト**（dark / light 両方）を追加し diff ゼロを確認 ③既存 `app_theme_test`（secondaryContainer 検証 + LinearProgressIndicator 描画）をそのまま実行。詳細は §6-4・§7-R3。
- `AppTheme.getThemeMode` は **削除を推奨**（判断根拠は §4.3 / §8）。

---

## 3. 依存グラフ

```
┌──────────────────────────── 呼出元（lib/・test/） ────────────────────────────┐
│ ansi_text_view.dart   main.dart  markdown_preview_screen.dart                  │
│ connection_form ✓ connections ✓ home ✓ terminal_screen ✓                       │
│ herdr_pane_writer ✓ herdr_pane_content_reader ✓ herdr_pane_frame_reader ✓      │
│ herdr_snapshot_cache ✓ caret(→snapshot chain)                                   │
└──────────────┬──────────────────────┬───────────────────────────────┬─────────┘
               ▼                      ▼                               ▼
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│   ansi_parser.dart   │  │  herdr_adapter.dart  │  │    app_theme.dart    │
│      (ファサード)      │  │     (公開ファサード)   │  │     (公開ファサード)   │
└──┬───────┬───────┬───┘  └──┬──────────┬───────┘  └──┬────────┬───────────┘
   ▼       ▼       ▼         ▼          ▼             ▼        ▼
 ansi_sgr_parser  ansi_line_parser  ansi_span_renderer    app_text_theme
   └───►(注入)────┘       │               │                 app_theme_palette
                          │               ▼                         │
          ansi_models（値型: AnsiStyle/AnsiSegment/ParsedLine）  app_theme_builder
                          │        terminal_font_styles.dart    （palette+brightness→ThemeData）
                          └──────────►(全レイヤーが値型へ依存)        │
                                                                   ▼
 herdr 側:                                                   design_colors.dart
 herdr_command_executor ⇒ BackendAdapter / CommandRequest /   (既存・色定数)
   CommandResult / connection_error / l10n / herdr_commands / herdr_errors
   └─► herdr_read_client（⇒ herdr_parser / herdr_models）
   └─► herdr_mutation_client ⇒ herdr_mutation_result
   └─► herdr_adapter（ファサードが上記 3 つを合成）
```

- 依存はすべて上→下（呼出元 → ファサード → 部品 → 既存基盤）。**Peer 間・下→上の依存なし・循環なし**。
- 値型（ansi_models / herdr_mutation_result）は無依存（flutter のみ）で最下層。
- 既存の `herdr_parser.dart` / `herdr_models.dart` / `herdr_commands.dart` / `herdr_errors.dart` / `design_colors.dart` / `terminal_font_styles.dart` は本設計の対象外（いずれも 500 行未満・単一責務）だが依存先として維持。

---

## 4. API 変更点 before-after

### 4.1 ansi

| シンボル | before（HEAD） | after | 変更 |
|---|---|---|---|
| `AnsiParser({defaultForeground, defaultBackground})` | 全責務を内蔵 | ファサード（内部で 3 部品を合成） | シグネチャ不変 |
| `parse / parseLines / parseToTextSpan / toTextSpan / lineToTextSpan / lineToTextSpanWithCaret / effectiveLineBackgroundColor / resolvePaintColors` | Herdr…ではなく AnsiParser のインスタンスメソッド | 同一名で委譲。parseToTextSpan は LineParser.**parse（正規化なし）** + SpanRenderer.toTextSpan の合成で現行挙動不変 | シグネチャ・戻り値不変 |
| `parse` の前処理 | 正規化なし・行分割なしの全体スキャン（HEAD L165-195） | **同意味論を維持**（CRLF/CR 正規化・行分割を混入させない）。lineToTextSpan 経路へ影響させない | 挙動不変 |
| `AnsiStyle / AnsiSegment / ParsedLine` | ansi_parser.dart 内 | ansi_models.dart へ移動 + ファサードから `export` | 型名・メンバ不変（import パスはファサード経由なら互換） |
| `standardColors / brightColors`（static） | AnsiParser | AnsiSgrParser | **外部コード参照ゼロ**（事実）のため影響なし |
| `AnsiSgrParser / AnsiLineParser / AnsiSpanRenderer` | – | 新規公開クラス | 追加のみ |

### 4.2 herdr

| シンボル | before | after | 変更 |
|---|---|---|---|
| `HerdrAdapter(BackendAdapter, {userExecutablePath, l10n})` + 全 22 公開メンバー（isConnected + read 4 + mutation 17・実測） | 全責務を内蔵 | ファサード（Executor/ReadClient/MutationClient に委譲） | **不変**（継承可能クラスのまま） |
| `HerdrMutationResult`（changed / reason / layout / isNoNeighbor / isUnchanged / toString） | herdr_adapter.dart 内 | herdr_mutation_result.dart（独立ライブラリ） | 型・メンバ不変 |
| `_HerdrAdapterBase / _HerdrAdapterExec / _HerdrAdapterMutation`（mixin・part） | ワーキングツリーの分割実装 | **削除**（composition に置換） | private のため外部影響なし |
| `HerdrCommandExecutor / HerdrReadClient / HerdrMutationClient` / `HerdrMutationResult.parse` | – | 新規公開 | 追加のみ |

### 4.3 theme

| シンボル | before | after | 変更 |
|---|---|---|---|
| `AppTheme.dark / AppTheme.light / AppTheme.monoTextStyle` | static getter | ファサード（Palette + Builder へ委譲） | 不変（等価性テストで同等値を保証） |
| `AppTheme.getThemeMode` | 実装 | **削除（推奨）** | **削除**。判断根拠: ①lib/・test/ で参照ゼロ（grep 実測）②タスクが公開 API 変更を許容 ③残すと責務ベースに反する粘着コード。削除時は PR 差分で明示する。代替: 残す場合は「system 対応時用」コメント付きで facade に維持（消極的選択・非推奨） |
| `AppThemePalette / AppThemeBuilder / AppTextTheme` | – | 新規公開 | 追加のみ |
| `_textTheme`（private） | AppTheme 内 | AppTextTheme.spaceGrotesk へ移設 | private のため影響なし |

**方針**: 公開 API は「変えてよいが変えない」。@return 呼出元・テストの変更ゼロ + 挙動不変の検証が最小化される。責務ベースの構造は内部（ファサード配下の部品）で達成する。

---

## 5. 呼出元・テスト更新リスト

### ansi（import 互換のため更新ゼロが原則・新規テスト追加あり）

| 対象 | 現状 | 更新 |
|---|---|---|
| `lib/screens/terminal/widgets/ansi_text_view.dart` | `import '.../ansi_parser.dart'`・parseLines / lineToTextSpan / lineToTextSpanWithCaret / effectiveLineBackgroundColor を利用 | **不要**（ファサード互換） |
| `test/services/terminal/ansi_parser_test.dart` | import 同上・parse / toTextSpan / parseLines / effectiveLineBackgroundColor / AnsiStyle / AnsiSegment を利用 | **不要**（期待値不変） |
| `test/services/terminal/ansi_parser_incremental_test.dart` | import 同上・parseLines / ParsedLine | **不要** |
| `test/services/terminal/ansi_parse_semantics_test.dart`（**新規**） | – | **追加**: ①「CR のみ / CRLF / 改行混在」入力を `parse()` に入れた時の期待値（正規化なし = CR はテキストのまま残る）を固定し、parseLines 経路（正規化あり）との差を明示 ②スパンキャッシュ同一性規約: 同一行の再 parseLines で ParsedLine が `identical`/同一行 lineToTextSpan 2 回目が同一 `TextSpan` を返す ③ファサード委譲の `assert(identical)` 動作確認 |

### herdr（ファサード維持により更新ゼロ）

| 対象（import 元） | 利用メソッド | 更新 |
|---|---|---|
| connection_form_screen.dart | preflight | 不要 |
| connections_screen.dart | snapshot / workspaceClose / workspaceCreate | 不要 |
| home_screen.dart | snapshot | 不要 |
| terminal_screen.dart | status / 構築（PaneWriter・ContentReader・SnapshotCache・FrameReader への注入） | 不要 |
| herdr_pane_writer.dart | mutation 17 個 + result.changed / result.reason | 不要 |
| herdr_pane_content_reader.dart | paneRead | 不要 |
| herdr_pane_frame_reader.dart | paneRead | 不要 |
| herdr_snapshot_cache.dart | snapshot | 不要 |
| test: herdr_adapter_test.dart | 全メソッド + `userExecutablePath:` コンストラクタ | 不要（期待値不変） |
| test: herdr_snapshot_cache_test.dart | `_FakeSnapshotAdapter extends HerdrAdapter`（snapshot override、`identical` 差替え検出） | **不要**（ファサードを継承可能に維持） |
| test: herdr_caret_snapshot_reader_test.dart | `_MinimalAdapter extends HerdrAdapter`（snapshot override） | **不要** |
| test: herdr_pane_writer_test.dart / pane_content_reader_test.dart | HerdrAdapter(client) 構築 | 不要 |

### theme（公開面維持により更新ゼロ・新規テスト追加あり）

| 対象 | 利用 | 更新 |
|---|---|---|
| main.dart | AppTheme.light / AppTheme.dark | 不要 |
| markdown_preview_screen.dart | AppTheme.monoTextStyle（copyWith） | 不要 |
| test/theme/app_theme_test.dart | AppTheme.dark / AppTheme.light の colorScheme + widget 描画 | 不要（期待値不変） |
| `test/theme/app_theme_equivalence_test.dart`（**新規**） | – | **追加**: `AppThemeBuilder.build(palette, brightness)` と逐語版ビルダー（金の基準）の出力 ThemeData を全サブテーマ・全色フィールド deep compare（dark / light 両方・diff ゼロ） |

→ **既存呼出元・既存テストは無更新で通り、期待値（assert 内容）も一切変更しない。** 追加するのは新規テスト（ansi 意味論/同一性・theme 等価性）のみ。

※注: `AppTheme.getThemeMode` を削除する場合（§4.3 推奨）、参照ゼロのため呼出元更新は不要（`make analyze` で検証）。

---

## 6. 移行手順（実装時の指針）

各ステップで `make analyze` → `flutter test`（対象範囲）を通してから次へ進む。

1. **準備**: 作業ブランチ上で `git show HEAD:<path>` を基準に、対象 3 ファイルを退避（今後の実装は HEAD 版をコピーして着手）。既存の part 分割ファイルは `git rm` で撤去。
2. **ansi**
   - ansi_models.dart を独立ライブラリ化（値型のみ。`_LineSpan` は renderer 側へ）
   - ansi_sgr_parser.dart 新規（palette + apply。HEAD の `_parseSgr` / `_get256Color` を移動）
   - ansi_line_parser.dart 新規。**parse は現行どおり「正規化なしの全体スキャン」として独立経路で維持**（parseLines の正規化・行分割・キャッシュに混ぜない。共通化するのはスキャン走査ループ本体のみ。v2 で「統合」は撤回済み）
   - ansi_span_renderer.dart 新規（toTextSpan / resolvePaintColors / effectiveLineBackgroundColor / lineToTextSpan(+_spanCache) / lineToTextSpanWithCaret）
   - ansi_parser.dart をファサード化（`export 'ansi_models.dart';` + 3 部品への委譲。委譲箇所に `assert(identical(...))` デバッグチェックを追加）
   - **新規テスト**: `ansi_parse_semantics_test.dart`（parse 入力種別別期待値 + スパンキャッシュ同一性。§5 参照）
   - 検証: `flutter test test/services/terminal/ test/screens/terminal/ansi_text_view_bg_test.dart` + ansi_text_view の widget テスト
3. **herdr**
   - herdr_command_executor.dart 新規（HEAD の `_resolve` / `_execChecked` / `_buildErrorMessageFrom` / `_extractErrorCodeFrom` / `_trySendNoWait` / l10n 解決を移動。`_strings` はここに集約）
   - herdr_mutation_result.dart を独立ライブラリ化し `HerdrMutationResult.parse` を追加（HEAD の `_parseMutationResult` を移動）
   - herdr_read_client.dart 新規（preflight / status / snapshot / paneRead）
   - herdr_mutation_client.dart 新規（mutation 17 個の操作宣言 + 送信経路選択。実行は `Executor.execMutation`・結果解析は `HerdrMutationResult.parse` へ委譲。`trySendNoWait` 成功時は素の結果を返す分岐を維持）
   - herdr_adapter.dart をファサード化（part / mixin 撤去）
   - 検証: `flutter test test/services/herdr/ test/services/backend/domain/herdr_pane_writer_test.dart test/services/backend/domain/pane_content_reader_test.dart`
4. **theme（2 段階・金の基準方式）**
   - ① HEAD 現行の dark/light を**逐語版ビルダー**（`DarkThemeBuilder` / `LightThemeBuilder`）へ移し、`flutter test test/theme/` で既存テスト OK を確保（＝**金の基準・一時的な中間産物**。③の等価性テスト通過後に撤去）
   - ② `app_theme_palette.dart` を新規（HEAD の dark/light から**色値と構造差分 6 箇所を抽出してエンコード**。対応表をコメントで残す）
   - ③ `app_theme_builder.dart` を新規（単一 `build(palette, brightness)`）
   - ④ **等価性テスト追加**: `AppThemeBuilder.build(AppThemePalette.dark/light, ...)` と ①の逐語版出力を全サブテーマ・全色で deep compare（dark / light 両方・diff ゼロ）
   - ⑤ app_theme.dart をファサード化（`getThemeMode` は削除・§4.3）。逐語版ビルダーと part ファイルを撤去
   - 検証: `flutter test test/theme/`
5. **統合**: `make analyze` → `make test` 全通し
6. **PR**: Draft PR 作成（グローバルルール）。`build-apk` は当該 checkout で署名鍵欠如により失敗する既知事象（AGENTS.md）のため確認不要。

---

## 7. リスクと代替案

| # | リスク | 評価 | 代替案 |
|---|---|---|---|
| R1 | **スパンキャッシュの間接依存**（Expando\<ParsedLine\> が LineParser のインスタンス再利用に依存） | 低。ファサードが同一インスタンスを委譲する限り現行と等価。**v2 で規約違反を検知する 3 テスト + 委譲時の `assert(identical)` を追加**（§5 / §6-2）により回帰を早期検出 | AnsiParser を廃止し呼出元が LineParser+Renderer を直接所有（公開 API 変更大・却下） |
| R2 | **mixin/基底クラスの撤去漏れ**（ワーキングツリーの part ファイルが残る） | 低。`git rm` + analyze で検出可能 | なし（撤去必須） |
| R3 | **テーマの挙動差分**（FAB elevation 0/2・foreground black/white・segmented 背景・enabledBorder・**switchTheme は light のみ** 等の暗/明構造差 6 箇所） | 中。**v2 ではパレットデータ化を第一案**とし、①逐語版ビルダー（金の基準）→ ②パレット抽出 → ③共通ビルダーという 2 段階移行で挙動不変を担保。等価性テスト（①と②の出力を全サブテーマ deep compare、dark/light 両方）で diff ゼロを確認。既存 widget テスト（app_theme_test の描画検証）もそのまま実行 | ビルダー 2 分割のみ（パレット化しない）案: 重複 85% が残るため「責務ベース」評価は低いが、実装コスト最小。**非推奨**（第一案はパレット化） |
| R4 | `getThemeMode` の扱い | **低。削除を推奨**。事実: lib/・test/ で参照ゼロ（grep 実測）+ main.dart は `settings.darkMode ? ThemeMode.dark : ThemeMode.light` を直接使用（getThemeMode 非依存）。削除はタスク許容の API 変更であり、粘着コードを残さない。外部統合の理論的可能性のみリスク | 維持案: 「system 対応時用」コメント付きで facade に残す（消極的選択）。削除時の検証は `make analyze` + 全テストで十分（参照ゼロのためコンパイル影響なし） |
| R5 | ファサードが厚くなり「合成以外の責務」を持ち込む | 低。各ファサード 60–90 行に留め、ロジックは部品に置く（設計レビューで監視） | なし（タスク方針「HerdrAdapter は公開ファサードとして委譲」に合致） |
| R6 | 呼出元・テスト無更新方針が「責務ベース」と矛盾的では、というレビュー指摘 | 設計意図として §4 に明記: 責務境界はファイルではなく「クラス+依存方向」で担保し、ファサードは薄い合成ルート。要求「公開APIは変更してよい」は変更できるという意味であって、変更必須ではない | テストを各新規クラスへ直 import に更新する案（churn 増・責務の明確化が進む）。優先度低 |

---

## 8. 事実と推測の区別

### 事実（grep / コマンドで確認済み）

- HEAD の行数: ansi_parser.dart=679・herdr_adapter.dart=644・app_theme.dart=501（`git show HEAD | wc -l`）
- ansi_parser.dart の import 元は **3 箇所のみ**: `lib/screens/terminal/widgets/ansi_text_view.dart` / `test/services/terminal/ansi_parser_test.dart` / `ansi_parser_incremental_test.dart`
- ansi_text_view が利用する AnsiParser メソッドは **parseLines / lineToTextSpan / lineToTextSpanWithCaret / effectiveLineBackgroundColor** とコンストラクタ 2 引数（L251-252, 301, 824, 887, 908）
- `parseToTextSpan`・`resolvePaintColors`・`standardColors`・`brightColors` は外部（lib/・test/）から**コード参照ゼロ**
- `edges()` は lib/ 内に実呼出元なし（テストのみ）
- herdr_adapter.dart の import 元は 4 画面 + 3 サービス + 5 テストファイル。全呼出元の利用メソッドを §5 に列挙
- **テスト 2 件が `HerdrAdapter` を継承して `snapshot()` を override**（herdr_snapshot_cache_test / caret テスト）→ ファサードは通常の継承可能クラスで維持する必要がある（事実ベースの制約）
- `AppTheme.getThemeMode` は lib/・test/ の**どこからも参照されない**（`grep -rn "getThemeMode"` で定義 1 件のみ）。main.dart は `settings.darkMode ? ThemeMode.dark : ThemeMode.light` を直接使用（L163）
- `AppTheme` の import 元は main.dart / markdown_preview_screen.dart / app_theme_test.dart のみ。dark/light/monoTextStyle の 3 シンボルだけが使われる
- **switchTheme は light ビルダーにのみ存在**（HEAD で `grep -c "switchTheme"` = 1）
- **mutation メソッドは公開 17 個**（`git show HEAD | grep -c "Future<HerdrMutationResult>"` = 18 = 公開 17 + `_execMutation` 1）。read 4 個 + isConnected で HerdrAdapter の公開メンバーは全 22
- **`parse()` は正規化・行分割を行わない**（HEAD L165-195 に `replaceAll` なし）のに対し、**`parseLines()` は CRLF/CR 正規化 + 行分割 + キャッシュ参照**（HEAD L464-491）→ 前処理は経路別で、スキャン走査ループ本体のみ共通（v2 の `AnsiLineParser` はこの事実に基づき経路分離を維持）
- ワーキングツリーの既存分割は `part of` + mixin/基底クラス方式（AGENTS 設計原則 2 に反するため破棄対象）
- `make build-apk` は本 checkout で署名鍵欠如により packaging で失敗する既知環境事象（AGENTS.md）でコード起因ではない
- テスト期待値（assert 内容・比較値）は本設計で一切変更しない（**新規テストの追加のみ**: `ansi_parse_semantics_test.dart`・theme の等価性テスト）

### 推測・見積り（要確認事項・実装時に検証）

- 各ファイルの**推定行数**（§2）は HEAD の責務別行数（§1）からの積算見積り。うち ansi_span_renderer / herdr_mutation_client はワーキングツリーの実測分割サイズ（309 行 / 352 行）と突き合わせて整合済み。doc コメント移動量により ±15% 程度変動しうる
- ファサードの `export 'ansi_models.dart';` がパッケージ pub ベースで問題なく解決されること（flutter 標準の export 機構・アナライザで検証）
- `HerdrMutationResult.parse` の静的パーサ化が `_parseMutationResult` と完全等価であること（レイアウト欠損許容・rc=0 尊重の分岐をそのまま移動）
- herdr のローカライズは `_strings => _l10n ?? lookupL10n()` の**遅延解決**を Executor に移設して維持（構築時解決にしない）。lookupL10n は言語切替後の**最新値**を返すため、現行と同一の反映タイミングになる
- theme のパレット抽出で「構造差分 6 箇所のエンコード漏れ」が無いこと（等価性テストの deep compare で検知）
- ansi の `parseToTextSpan`（外部未使用）もファサードに残し公開面を完全互換に保つこと（削除は「公開 API 変更」であり挙動不変の範囲を超えるため）
- 内部の inventory 注記（HERDR-ADAPTER-xxx 等）は新構造では不要となるため撤去してよい（文書化コメントは残す）

---

## 付録 A: 判明した副次事実（設計外・報告のみ）

- `lib/services/terminal/ansi_parser.dart` の `parse()` と `_parseLineWithStyle` の**スキャン走査ループ本体は同一**（差分は endStyle の返却有無のみ）だが、**前処理（parse = 正規化なし全体スキャン / parseLines = CRLF/CR 正規化 + 行分割 + キャッシュ）は経路により異なる**（v2 で確認）。**統合は行わない**: `AnsiLineParser` は parse（正規化なし）と parseLines（正規化あり）を**別経路として維持**し、共通化は走査ループのみ。入力種別別（CR のみ / CRLF / 改行混在）の期待値テスト（`ansi_parse_semantics_test.dart`）で意味論を固定する
- `AppTheme.getThemeMode` の代替ロジック（`settings.darkMode ? ThemeMode.dark : ThemeMode.light`）は main.dart に直書きで存在（L163）。getThemeMode 自体が未参照のため、削除しても main.dart のテーマモード選択に影響しない
- `HerdrAdapter.isConnected` は外部から未参照（BackendAdapter 透過）。公開 API として維持