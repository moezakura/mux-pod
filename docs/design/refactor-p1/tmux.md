# tmux 3ファイル 責務ベース再設計書（v2）

- 対象: `lib/services/tmux/tmux_command_builder.dart`(632行) / `tmux_parser_adapter.dart`(531行) / `tmux_facade.dart`(643行)
- 出発点: `git show HEAD:<path>` の元ファイル（HEAD = 9f30573）。working tree の既存分割（part + mixin + private基底）は参考情報のみ。
- v2 改訂: design-critic レビュー（/tmp/p1-design/critique.md）対応。更新リストの完全列挙・ops 層の必然性定義・pane_commands からの入力系分離・l10n 所有者明確化・数値実測合わせ。
- 本設計はコード変更を伴わない。実装時は本設計に従う。
- 原則: 1ファイル=1責務 / 合成優先（mixin・基底クラス禁止）/ 公開API変更可（テスト期待値は不変）/ 依存非循環 / 各ファイル<500行 / 挙動不変

---

## 1. 現状責務分析（HEAD ベースの事実）

### 1.1 tmux_command_builder.dart（632行）— 9つの責務が混在

| 責務 | メンバ（行） | 行数 |
|---|---|---|
| セッションコマンド生成 | listSessions / listSessionsSimple / hasSession / newSession / killSession / renameSession / attachSession / detachClient / serverInfo / version / startServer / killServer (32–91, 477–518) | ~120 |
| ウィンドウコマンド生成 | listWindows / listWindowsSimple / newWindow / selectWindow / killWindow / renameWindow / resizeWindow / resizeWindowAuto / selectLayout (93–161, 281–303, 520–526) | ~95 |
| ペインリストコマンド生成 | listPanes / listPanesSimple / listAllPanes (163–221) | ~60 |
| ペイン操作コマンド生成 | selectPane / splitWindowHorizontal / splitWindowVertical / killPane / resizePane / resizePaneToSize (223–278) | ~56 |
| 入力コマンド生成 | sendKeys / sendEnter / loadBufferAndPaste / loadBufferAndPasteNoBracketed / sendInterrupt / sendEscape / enterCopyMode / cancelCopyMode (335–436) | ~102 |
| コンテンツ取得コマンド生成 | capturePane / capturePaneVisible / capturePaneAll / getCursorPosition / getPaneMode / setHistoryLimit (439–475) | ~37 |
| シェルスクリプト生成 | windowRestoreTrap / clearWindowRestoreTrap (305–333) | ~29 |
| シェル文字列合成 | _escapeArg / chain / pipe (528–587) | ~60 |
| 列挙型定義 | SplitDirection / TmuxLayout / TmuxLayoutExtension (589–632) | ~44 |

- 公開 static は **50個**（private _listFormat / _escapeArg 含め static 52）。
- `dart:convert`(base64)・`dart:math`(Random) は paste 系（sendEnter/loadBufferAndPaste/NoBracketed）でのみ使用。
- **`chain` / `pipe` は lib 側の呼出元がゼロ**（テスト専用 API: tmux_commands_test のみ）。

### 1.2 tmux_parser_adapter.dart（531行）— 6つの責務が混在

| 責務 | メンバ | 行数 |
|---|---|---|
| セッションパーサ | parseSessions / parseSessionLine / parseSessionsSimple (28–107) | ~80 |
| ウィンドウパーサ | parseWindows / parseWindowLine / parseWindowsSimple (108–182) | ~75 |
| ペインパーサ | parsePanes / parsePaneLine / parsePanesSimple (183–263) | ~81 |
| コンテンツパーサ | parsePaneContent / stripAnsiCodes (264–298) | ~35 |
| ツリー構築 | parseFullTree (299–417) | ~119 |
| 出力健全性検査・正規化 | isServerRunning / normalizeDelimiters / hasRecordContent / extractError / defaultDelimiters (464–530) | ~67 |
| private ヘルパ | _parseTimestamp / _parseSize / _parseWindowFlags / _guessWidth (418–463) | ~46 |

- parseFullTree は行パーサ（parseSessionLine 等）を**使わない**独自の record 直接解釈（19フィールド）であり、既に独立した責務。
- **extractError は lib 側の呼出元がゼロ**（テスト専用 API。`tmux_parser_test.dart` で検証のみ）。

### 1.3 tmux_facade.dart（643行）— 4つの責務が混在

| 責務 | メンバ | 行数 |
|---|---|---|
| シングルトン/グローバル | `tmuxFacade` シングルトン / tmuxPollSeparator / _pollSeparatorPattern | ~35 |
| パース委譲 | parseSessions / parseFullTree / parsePaneContent / stripAnsiCodes (51–69) | ~19 |
| セッション操作 | getVersion / hasSession / listSessions / listAllPanes / startServer / createSession / attachSession / killSession / renameSession (71–167) | ~97 |
| ウィンドウ操作 | listWindows / createWindow / selectWindow / killWindow / renameWindow / resizeWindow / autoResizeWindow / selectLayout / setWindowRestoreTrap / clearWindowRestoreTrap / restoreWindows (168–237, 539–604) | ~130 |
| ペイン操作 | listPanes / selectPane / splitPane / killPane / sendKeys / sendKeysNoWait / sendFocusIn/Out / enterCopyModeNoWait / cancelCopyModeNoWait / pasteText / sendBracketedPaste (240–405) | ~166 |
| コンテンツ操作 | pollPane / capturePane / setHistoryLimit (407–526) | ~120 |
| 実行基盤 | _requireRecords / _execChecked (606–643) | ~38 |

- `TmuxCommands.` 参照は **42箇所**（内訳: sendKeys 10、capturePane 2、parse 系は TmuxParser 11箇所: parsePaneContent 3 / parseSessions 2 / parseFullTree 2 / parseWindows 1 / parsePanes 1 / hasRecordContent 1 / stripAnsiCodes 1）。
- **TmuxContract は 40 メソッド**（TmuxFacade の @override 40 と一致）。夜間 parse 委譲4、バージョン1、セッション8（has/list/listAll/start/create/attach/kill/rename）、ウィンドウ5+resize3+layout+life3、ペイン4、入力6、ペースト2、コンテンツ2、履歴1。
- pollPane は capturePane / getCursorPosition / getPaneMode の文字列を `printf` マーカーで**結合した複合シェルコマンド**を実行し、マーカーで区切って結果を合成する（~93行の独立ロジック）。
- `_l10n` はエラーメッセージ（connTmuxCommandFailed / connTmuxOutputUnparsable）用。第3章で所有者を確定する。

---

## 2. 提案構成（1ファイル=1責務）

既存のフラット構成を3レイヤーのサブディレクトリに整理する。クラス名は「リソース/責務」名、メソッド名は短動詞。**コマンド文字列・パース結果の期待値は一切変えない**（リテラルをそのまま移動）。

### レイヤー1: コマンド生成 `lib/services/tmux/commands/`（9ファイル）

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `arg_quoting.dart` | シェルコマンド文字列の合成（引数クオート・連結・パイプ） | `ShellCommandComposer.quote / join / pipeline`（旧 _escapeArg / chain / pipe を公開化） | ~60 |
| `list_commands.dart` | 一覧取得（`-F` 出力）コマンドの生成と共用フォーマット生成 | `TmuxListCommands.sessions / sessionsSimple / windows / windowsSimple / panes / panesSimple / allPanes`（list 系7メソッド + 内部 `_format` を集約。旧 _listFormat はこのクラスの private に内包） | ~100 |
| `session_commands.dart` | セッション操作（一覧以外）のコマンド文字列生成 | `TmuxSessionCommands.has / create / kill / rename / attach / detach / serverInfo / version / startServer / killServer` | ~90 |
| `window_commands.dart` | ウィンドウ操作（一覧以外）のコマンド文字列生成 | `TmuxWindowCommands.create / select / kill / rename / resize / resizeAuto / selectLayout` | ~75 |
| `pane_commands.dart` | ペイン構造操作のコマンド文字列生成 | `TmuxPaneCommands.select / splitHorizontal / splitVertical / kill / resize / resizeToSize` | ~70 |
| `input_commands.dart` | ペインへの入力・ペースト・コピーモード操作のコマンド文字列生成 | `TmuxInputCommands.sendKeys / sendEnter / sendInterrupt / sendEscape / paste / pasteNoBracketed / enterCopyMode / cancelCopyMode`（base64 ペースト / ランダムID はここに内包） | ~110 |
| `content_commands.dart` | ペインコンテンツ取得のコマンド文字列生成 | `TmuxContentCommands.capture / captureVisible / captureAll / cursorPosition / getMode / setHistoryLimit` | ~60 |
| `lifecycle_commands.dart` | セッション復元トラップのシェルスクリプト生成 | `TmuxLifecycleCommands.windowRestoreTrap / clearWindowRestoreTrap` | ~40 |
| `layout.dart` | レイアウト・分割方向の定義 | `SplitDirection / TmuxLayout / TmuxLayoutExtension`（移動のみ・名前不変） | ~50 |

- **v2 変更点**: list 系（`-F` 系7メソッド）を `list_commands.dart` へ集約し `list_format.dart` を廃止（過剰分割の解消。delimiters 整合テスト TMUX-CMD-001 もこのクラスに集約）。入力系を `input_commands.dart` へ分離し、pane_commands を構造操作のみに（grab-bag 化の回避）。

### レイヤー2: パーサ `lib/services/tmux/parsers/`（6ファイル）

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `session_parser.dart` | tmux セッション出力のパース | `TmuxSessionParser.parse / parseLine / parseSimple` | ~95 |
| `window_parser.dart` | tmux ウィンドウ出力のパース | `TmuxWindowParser.parse / parseLine / parseSimple / parseFlags`（_parseWindowFlags を公開化し tree から再利用） | ~95 |
| `pane_parser.dart` | tmux ペイン出力のパース | `TmuxPaneParser.parse / parseLine / parseSimple` | ~95 |
| `content_parser.dart` | ペインコンテンツのパースと ANSI 除去 | `TmuxContentParser.parse / stripAnsi` | ~65 |
| `tree_parser.dart` | セッションツリー全体の構築 | `TmuxTreeParser.parse`（parseFullTree の record 直接解釈をそのまま移動） | ~130 |
| `output_validator.dart` | 出力の健全性検査とレガシー区切り正規化 | `TmuxOutputValidator.isServerRunning / normalizeDelimiters / hasRecordContent / extractError` + `defaultDelimiters` | ~85 |

### レイヤー3: 実行・操作 `lib/services/tmux/exec|ops/` + Facade 合成（6ファイル）

| ファイル | 責務（1文） | 公開面 | 推定行数 |
|---|---|---|---|
| `exec/command_runner.dart` | tmux コマンド実行と結果検証（l10n エラー文言の生成・出力健全性判定を含む） | `TmuxCommandRunner({AppLocalizations? l10n})` / `.run(command)` / `.requireRecords(output, records)`（旧 _execChecked / _requireRecords） | ~70 |
| `ops/session_operations.dart` | セッション領域のドメイン操作（生成→実行→（パース）→検証の順序づけ） | `TmuxSessionOperations`（hasSession / listSessions / listAllPanes / startServer / createSession / attachSession / killSession / renameSession / getVersion） | ~95 |
| `ops/window_operations.dart` | ウィンドウ領域のドメイン操作 | `TmuxWindowOperations`（listWindows / createWindow / selectWindow / killWindow / renameWindow / resizeWindow / autoResizeWindow / selectLayout / setWindowRestoreTrap / clearWindowRestoreTrap / restoreWindows） | ~85 |
| `ops/pane_operations.dart` | ペイン領域のドメイン操作 | `TmuxPaneOperations`（listPanes / selectPane / splitPane / killPane / sendKeys / sendKeysNoWait / sendFocusIn / sendFocusOut / enterCopyModeNoWait / cancelCopyModeNoWait / pasteText / sendBracketedPaste） | ~120 |
| `ops/content_operations.dart` | ペインコンテンツ取得のドメイン操作 | `TmuxContentOperations`（pollPane / capturePane / setHistoryLimit）+ トップレベル `tmuxPollSeparator` | ~150 |
| `tmux_facade.dart` | TmuxContract 実装の公開面と各 Operation の合成・シングルトン | `TmuxFacade({AppLocalizations? l10n})`（**公開面不変**）/ `tmuxFacade` シングルトン | ~140 |

### 2.1 ops 層の必然性と責務境界（v2 で明確化）

ops 層を設ける理由は「500行制限」ではなく、**TmuxFacade（契約実装）とドメイン操作（実行手順）の責務分界**である:

- **TmuxFacade の責務**: TmuxContract の実装契約（シグネチャ・例外の公開規約・Operation の合成と l10n 伝達）。メソッド本体は持たず、Op への委譲のみ。
- **ops 層の責務**: 各操作の**実行手順とドメイン不変条件**。単なる生成→実行の羅列ではなく、以下の横断知識を ops が保持する:
  - **delimiters の mint→同一ペアの保証**: list 系5操作（listSessions / listWindows / listPanes / listAllPanes）はコマンド生成とパースで**同一の TmuxDelimiters** を使わなければならない。この「往復同一ペア」契約は ops 内の各メソッドに帰属する（現行 facade に同じ知識がある）。
  - **「空リスト」と「解析不能」の区別**: `requireRecords`（TmuxCommandRunner）により、出力はあったが 0 レコードの場合に TmuxOutputParseException を上げる。list 系 ops はパース結果を必ず Runner.requireRecords に通す。
  - **操作固有の順序・フォールバック**: selectPane のフォーカス順序（前ペインへ `\x1b[O` → select → `\x1b[I`）、pasteText の bracketed→no-bracketed フォールバック、pollPane のマーカー合成と切り出し（~93行）。
  - **エラー種別の変換**: Runner が exitCode/stderr を TmuxCommandException（l10n 文言付き）へ変換する（§3.3 参照）。
- ops の各メソッドが「run 1回の薄い実装」になるもの（startServer 等）があるのは事実だが、それは**契約メソッドの実装単位**であり、wrapper ではない（実ロジックは ops 側にある。facade のみが委譲）。
- **将来の再利用**: 契約に「Herdr backend 等の別実装」が想定されている（TmuxContract の doc コメント）。操作手順を ops に分離しておくと、別 backend は「コマンド生成/パースを差し替えた同手順」を再利用できる。ただしこれは副次便益であり、主目的は上記の責務分界。

### 2.2 レイヤー依存グラフ（非循環）

```
layout.dart ──────────────────────────────┐
arg_quoting.dart ──┐                      │
delimiters ────────┼── commands/{list, session, window, pane, input, content, lifecycle}
models ────────────┼── parsers/{session, window, pane, content}
                   │        ▲
output_validator ◄─┴── parsers/tree ──► window_parser(parseFlags)
                   │
command_runner ────┼──(contract, command_request, app_localizations)
ops/* ─────────────┴──► command_runner, commands/*, parsers/*, contract, models, version
tmux_facade ──────────► ops/*, contract（export ssh_tmux_command_executor）
```

矢印は import 方向。下位レイヤー（commands / parsers）は上位（ops / facade）を一切 import しない。commands 間の相互 import もない（list_commands に -F 系を集約したため、session/window/pane コマンドクラスからの `_listFormat` 参照が不要になり、**commands 層内の循環可能性がゼロ**になった）。

---

## 3. API 変更点 before → after（テスト期待値は不変）

### 3.1 コマンド生成（TmuxCommands 公開 static 50 → リソース別クラス）

| before | after |
|---|---|
| `TmuxCommands.listSessions(d)` / `listSessionsSimple()` | `TmuxListCommands.sessions(d)` / `sessionsSimple()` |
| `TmuxCommands.listWindows(n,d)` / `listWindowsSimple(n)` | `TmuxListCommands.windows(n,d)` / `windowsSimple(n)` |
| `TmuxCommands.listPanes(n,i,d)` / `listPanesSimple(n,i)` / `listAllPanes(d)` | `TmuxListCommands.panes(n,i,d)` / `panesSimple(n,i)` / `allPanes(d)` |
| `TmuxCommands._listFormat(fields, d)` | `TmuxListCommands._format`（private・list 系の内部実装に内包） |
| `TmuxCommands.hasSession(n)` / `newSession({...})` / `killSession(n)` / `renameSession(o,n)` | `TmuxSessionCommands.has(n)` / `create({...})` / `kill(n)` / `rename(o,n)` |
| `TmuxCommands.attachSession(n)` / `detachClient({n})` | `TmuxSessionCommands.attach(n)` / `detach({n})` |
| `TmuxCommands.serverInfo()` / `version()` / `startServer()` / `killServer()` | `TmuxSessionCommands.serverInfo()` / `version()` / `startServer()` / `killServer()` |
| `TmuxCommands.newWindow({...})` / `selectWindow(n,i)` / `killWindow(n,i)` / `renameWindow(n,i,new)` | `TmuxWindowCommands.create({...})` / `select(n,i)` / `kill(n,i)` / `rename(n,i,new)` |
| `TmuxCommands.resizeWindow(t,{c,r})` / `resizeWindowAuto(t)` / `selectLayout(t,l)` | `TmuxWindowCommands.resize(t,{c,r})` / `resizeAuto(t)` / `selectLayout(t,l)` |
| `TmuxCommands.selectPane / splitWindowHorizontal / splitWindowVertical / killPane / resizePane / resizePaneToSize` | `TmuxPaneCommands.select / splitHorizontal / splitVertical / kill / resize / resizeToSize` |
| `TmuxCommands.sendKeys / sendEnter / sendInterrupt / sendEscape` | `TmuxInputCommands.sendKeys / sendEnter / sendInterrupt / sendEscape` |
| `TmuxCommands.loadBufferAndPaste / loadBufferAndPasteNoBracketed` | `TmuxInputCommands.paste / pasteNoBracketed` |
| `TmuxCommands.enterCopyMode / cancelCopyMode` | `TmuxInputCommands.enterCopyMode / cancelCopyMode` |
| `TmuxCommands.capturePane / capturePaneVisible / capturePaneAll` | `TmuxContentCommands.capture / captureVisible / captureAll` |
| `TmuxCommands.getCursorPosition / getPaneMode / setHistoryLimit` | `TmuxContentCommands.cursorPosition / getMode / setHistoryLimit` |
| `TmuxCommands.windowRestoreTrap / clearWindowRestoreTrap` | `TmuxLifecycleCommands.windowRestoreTrap / clearWindowRestoreTrap` |
| `TmuxCommands._escapeArg(arg)` / `chain(...)` / `pipe(...)` | `ShellCommandComposer.quote(arg)` / `join(...)` / `pipeline(...)` |
| `SplitDirection / TmuxLayout / TmuxLayoutExtension` | 移動のみ（名前・値・`.name` 不変）→ `commands/layout.dart` |

### 3.2 パーサ（TmuxParser → リソース別クラス）

| before | after |
|---|---|
| `TmuxParser.parseSessions(o,{delimiters})` / `parseSessionsSimple(o)` / `parseSessionLine(l)` | `TmuxSessionParser.parse / parseSimple / parseLine` |
| `TmuxParser.parseWindows / parseWindowsSimple / parseWindowLine` | `TmuxWindowParser.parse / parseSimple / parseLine` + `parseFlags`（公開化） |
| `TmuxParser.parsePanes / parsePanesSimple / parsePaneLine` | `TmuxPaneParser.parse / parseSimple / parseLine` |
| `TmuxParser.parseFullTree(o,{delimiters})` | `TmuxTreeParser.parse` |
| `TmuxParser.parsePaneContent(...)` / `stripAnsiCodes(t)` | `TmuxContentParser.parse(...)` / `stripAnsi(t)` |
| `TmuxParser.isServerRunning / normalizeDelimiters / hasRecordContent / extractError` | `TmuxOutputValidator.isServerRunning / normalizeDelimiters / hasRecordContent / extractError` |
| `TmuxParser.defaultDelimiters` | `TmuxOutputValidator.defaultDelimiters`（または `TmuxDelimiters.legacy` 参照に一本化） |
| 引数シグネチャ（named param 名・デフォルト値・戻り値型） | **不変**（テストの呼び出し形 `TmuxParser.parseSessions(kOutput)` 等がクラス名変更のみで追従する） |

### 3.3 l10n の所有者とエラーメッセージ生成（v2 で確定）

- **l10n の所有者は `TmuxCommandRunner` のみ**とする。
  - `TmuxCommandRunner({AppLocalizations? l10n})` が `_l10n` を保持し、エラーメッセージ生成（`connTmuxCommandFailed(exitCode)` / `connTmuxOutputUnparsable`）は **Runner.run / Runner.requireRecords 内に一元化**する（現行の facade L39/L609/L636 のロジックをそのまま移動）。
  - ops 層は l10n を直接持たず、常に Runner 経由で例外・文言を得る。
- **`TmuxFacade({AppLocalizations? l10n})` コンストラクタ互換を維持**する:
  - `TmuxFacade({l10n})` は受け取った l10n を内部の Runner（および l10n を必要とする注入先）へ**そのまま渡す**。
  - シングルトン `tmuxFacade = TmuxFacade()` は null を渡す → Runner 内で `_l10n ?? lookupL10n()` の**遅延解決**を維持（現行と同じ動作。テスト互換の英語フォールバックも不変）。
  - これにより「l10n の生成時解決」による言語切替の破損は起こらない（現行の挙動をそのまま移すだけ）。

### 3.4 Facade 層

- `TmuxContract`（40メソッド）/ `TmuxFacade` / `tmuxFacade` シングルトンの公開 API: **不変**。
- `tmuxPollSeparator(String id)` は `ops/content_operations.dart` へ移動（テスト側 import 更新のみ。`poll_pane_realworld_test.dart` が参照）。

---

## 4. 呼出元・テスト更新リスト（v2: grep 完全列挙・実測ベース）

### 4.1 `tmux_command_builder.dart` 参照（HEAD 実測: lib 7 / test 6）

#### lib 側（7ファイル。うち shim 1 は削除対象）

| ファイル | 箇所数 | 更新内容 |
|---|---|---|
| `lib/services/tmux/tmux_facade.dart` | 42（`TmuxCommands.` 出現、sendKeys 10 含む） | 内部分割先で再配置（本設計の対象） |
| `lib/services/tmux/tmux_contract.dart` | import + シグネチャ2 | **import を `commands/layout.dart` へ変更**。`SplitDirection`(L137) / `TmuxLayout`(L228) のメソッドシグネチャは**名前不変**のため本文変更不要 |
| `lib/services/tmux/tmux_shell_lifecycle.dart` | 3 | windowRestoreTrap / clearWindowRestoreTrap → `TmuxLifecycleCommands`、resizeWindowAuto → `TmuxWindowCommands` |
| `lib/services/backend/domain/tmux_pane_writer.dart` | `import ... show SplitDirection`(L16) + 使用2（L96-97） | **import を `commands/layout.dart` へ変更**（本文不変） |
| `lib/screens/connections/connection_form_screen.dart` | 1 | `TmuxCommands.version()` → `TmuxSessionCommands.version()` |
| `lib/screens/terminal/terminal_screen.dart` | 0（import のみ） | SplitDirection 使用 10 箇所 → import パス変更のみ |
| `lib/services/tmux/tmux_commands.dart` | shim（export のみ） | **削除**（§4.4） |

#### test 側（6ファイル）

| ファイル | 箇所数 | 更新内容 |
|---|---|---|
| `test/services/tmux/tmux_commands_test.dart` | **94 tests / expect( 127** | クラス名・メソッド名一括更新。**コマンド文字列期待値は1バイトも不変** |
| `test/services/tmux/ssh_tmux_command_executor_test.dart` | 6（version×3, sendKeys×3） | `TmuxSessionCommands.version()` / `TmuxInputCommands.sendKeys()` へ |
| `test/helpers/fake_ssh_client.dart` | 1 | resizeWindowAuto → `TmuxWindowCommands.resizeAuto()` |
| `test/screens/terminal/terminal_screen_herdr_mutation_sync_test.dart` | SplitDirection×3 | import パス変更のみ |
| `test/services/backend/domain/tmux_pane_writer_test.dart` | `import ... show SplitDirection` + 使用多（splitCalls） | import を `commands/layout.dart` へ変更（本文不変） |
| `test/services/tmux/tmux_parser_test.dart` | import（TmuxDelimiters / TmuxLayout.name テスト 1） | import パス変更 + layout 参照先変更 |

### 4.2 `tmux_parser_adapter.dart` 参照（HEAD 実測: lib 2 / test 2）

| ファイル | 箇所数 | 更新内容 |
|---|---|---|
| `lib/services/tmux/tmux_facade.dart` | 11（`TmuxParser.` 出現） | 内部分割先で再配置 |
| `lib/services/tmux/tmux_parser.dart` | shim（export のみ） | **削除**（§4.4） |
| `test/services/tmux/tmux_parser_test.dart` | **54 tests / expect( 134** | クラス名一括更新。**パース期待値は不変** |
| `test/providers/tmux_provider_test.dart` | 1 | parseSessions → `TmuxSessionParser.parse()` |

### 4.3 TmuxFacade / tmuxFacade 参照（更新不要: 公開面不変）

- lib: terminal_screen(22) / connections_screen(2) / home_screen(1) / tmux_provider(2) / notification_panes_provider(1) / tmux_pane_writer(7) / tmux_pane_content_reader(2)
- test: tmux_facade_test(11) / poll_pane_realworld_test(5, `TmuxFacade()` 直接構築 + tmuxPollSeparator) / tmux_pane_writer_test(1) / notification_panes_provider_test(1)
- テストは private メンバに依存していない（`tmuxPollSeparator` は公開トップレベル関数のみ参照）。

### 4.4 非推奨 shim の削除

- `lib/services/tmux/tmux_commands.dart` / `tmux_parser.dart` はいずれも **HEAD 時点で import 箇所ゼロ**（`git grep "tmux_command_builder|tmux_parser_adapter" HEAD -- lib test` で、shim 自身以外の参照なし）。本リファクタ完了後に**削除可能**（deprecated export のため lint 警告の温床でもある）。

### バイト一致検証テスト（文字列を変えてはならない）

- `test/services/tmux/tmux_commands_test.dart`: 94 tests / expect( **127** 個（コマンド文字列・連結結果が期待値）
- `test/services/tmux/tmux_parser_test.dart`: 54 tests / expect( **134** 個（TSV フォーマット・区切り・エラー文言）
- これらの期待値が含まれる行は **1バイトも変更しない**。変更は呼び出しシンボルのみ。

---

## 5. 移行手順（各フェーズで `make analyze` / `make test` を実行）

1. **Phase 1: コマンド生成層の作成**
   - `commands/` 9ファイルを新規作成し、HEAD の TmuxCommands からメソッド本文をリテラル単位で移動（コピペではなく移動）。
   - 同時に builder 参照全13ファイル（lib 7 / test 6）の参照を新クラスへ更新。特に:
     - `tmux_contract.dart` / `lib tmux_pane_writer.dart` / `terminal_screen.dart` / `tmux_pane_writer_test.dart` / `terminal_screen_herdr_mutation_sync_test.dart` は import パスのみ。
     - `tmux_commands_test.dart` / `ssh_tmux_command_executor_test.dart` / `fake_ssh_client.dart` / `tmux_shell_lifecycle.dart` / `connection_form_screen.dart` はクラス名・メソッド名。
   - `tmux_command_builder.dart` を削除（残骸を残さない。1行委譲 wrapper 禁止のため）。
2. **Phase 2: パーサ層の作成**
   - `parsers/` 6ファイルを新規作成し、`tmux_parser_adapter.dart` から移動。
   - `tmux_parser_test.dart` / `tmux_provider_test.dart` / facade 内部参照（11箇所）を更新。旧ファイル削除。
3. **Phase 3: 実行基盤 + 操作層への facade 分割**
   - `exec/command_runner.dart` に `_execChecked` / `_requireRecords` を移動（**l10n も Runner が保持**。§3.3）。
   - `ops/` 4ファイルを作成し、TmuxFacade の各メソッド本体を移動。**delimiters 同一ペア・requireRecords 適用・フォールバック順序等の不変条件（§2.1）も ops に移動**。
   - `TmuxFacade` は Op をフィールド合成する委譲クラスに書き換え。**公開面は不変なので lib/test の更新は不要**（`TmuxFacade({l10n})` 互換を含む）。
   - `tmuxPollSeparator` を content_operations へ移動し `poll_pane_realworld_test.dart` の import を更新。
4. **Phase 4: 整理**
   - shim（tmux_commands.dart / tmux_parser.dart）を削除。
   - `make analyze` / `make test` で全体検証（コマンド文字列・パース期待値の差分ゼロを確認）。
   - 補助検証: リファクタ前後の `flutter test` の失敗数が同一であること。

---

## 6. リスクと代替案

### リスク

| リスク | 重大度 | 対策 |
|---|---|---|
| コマンド文字列・パース期待値の移動ミス（expect( 127 + 134 のリテラル） | 高 | 文字列リテラルを含む行は「移動」のみ許可。Phase 終了ごとに `git diff` で期待値側の差分ゼロを確認する。tmux_commands_test / tmux_parser_test が回帰を検出 |
| 94+54 tests の機械的シンボル置換ミス | 中 | 置換はクラス名置換 → メソッド名置換の2段階で実施し、`flutter analyze` の未解決参照ゼロをゲートにする。import パスのみのファイル（contract / pane_writer / terminal_screen / 2テスト）は本文変更しない方針を明示 |
| pollPane の複合コマンド文字列が分割でズレる | 中 | pollPane は content_operations へ**塊のまま**移動（文字列結合ロジックを細分化しない）。poll_pane_realworld_test(実実行) と tmux_facade_test が検証 |
| ops 層が「同構文の繰り返し」になる（startServer 等の薄い実装） | 低 | 薄い実装は契約メソッドの実装単位であり wrapper ではない（§2.1）。横断不変条件（delimiters 同一ペア・requireRecords・フォールバック）を ops が保持することを実装時に遵守 |
| parseFullTree の record 直接解釈が行パーサと二重実装のまま | 中 | 統合は挙動変更になるため**行わない**（挙動不変優先）。将来課題として tree パーサ内に「record 解釈の再利用」を検討。直し忘れを防ぐため tree_parser の doc に「行パーサとは独立」と明記 |
| テスト専用 API（extractError / chain / pipe）の行き場 | 低 | output_validator / ShellCommandComposer に置きテストを維持（削除は挙動変更扱い） |
| `_FakeTmuxContract` 等のテスト fake(2種) への影響 | なし | TmuxContract（40メソッド）不変のため影響なし |

### 代替案

| 案 | 内容 | 判定 |
|---|---|---|
| A（採用） | リソース別クラス + 3レイヤー分割 + facade は合成委譲（v2: list/input も独立責務化） | 原則1〜5を全て満たす |
| B | part ファイル分割（現 working tree 方式） | private 共有のため基底/mixin が必要になり**原則2違反**。棄却 |
| C | 1行委譲 wrapper を残す shim 方式 | 重複 wrapper だらけで**原則1違反**（前回指摘の再発）。棄却 |
| D | TmuxContract 自体をリソース別契約（TmuxSessionContract 等）に分割 | 40メソッド契約の再編。テスト fake 2種・利用側8ファイルが全更新。変更コストが大きい。**今回のスコープ外**として将来課題に |
| E | ops 層を設けず facade 単一ファイルに残す | 500行を超過し原則5違反。また契約実装と操作手順の分界（§2.1）が失われる。棄却 |
| F | list 系をリソース別クラスに分散したまま（v1 の list_format.dart 案） | list_format が4行の過剰分割になる。v2 では list_commands.dart へ集約して解消 |

---

## 7. 事実と推測の区別

### 事実（grep / git show HEAD で確認済み・v2 で再計測）

- HEAD の3ファイルは 632/531/643 行。メソッド構成は §1 の表の通り（TmuxCommands 公開 static **50**、TmuxContract **40** メソッド= @override 40 と一致）。
- builder 参照: **lib 7ファイル / test 6ファイル**（§4.1 完全列挙。`git grep "tmux_command_builder" HEAD -- lib test` で確認）。facade 内 `TmuxCommands.` 出現は **42**、`TmuxParser.` 出現は **11**。
  - `tmux_contract.dart` は builder を import し `SplitDirection`(L137) / `TmuxLayout`(L228) をシグネチャ使用（**v1 の更新リスト漏れ。v2 で追記**）。
  - `lib/services/backend/domain/tmux_pane_writer.dart` は `import ... show SplitDirection`(L16) で 2 箇所使用（**v1 の更新リスト漏れ。v2 で追記**）。
  - terminal_screen の SplitDirection 使用は **10 箇所**（import のみの変更で対応）。
- parser_adapter 参照: lib 2（facade 11箇所 + shim）/ test 2（parser_test 54 tests / expect( **134**、provider_test 1）。
- tmux_commands_test: 94 tests / expect( **127**（v1 の「約186リテラル」は grep 合算の誤り。v2 で修正）。
- TmuxFacade/tmuxFacade 参照: lib 7ファイル、test 4ファイル（計 ~48 箇所）。テストの private 依存なし。
- TmuxContract の実装クラス: 本番は TmuxFacade のみ（他 backend 実装は本リポジトリに存在しない）。テスト fake は 2 種（_FixtureTmuxContract / _FakeTmuxContract）。
- shim 2ファイル（tmux_commands.dart / tmux_parser.dart）は HEAD 時点で import 箇所ゼロ。
- chain / pipe / extractError の lib 利用はゼロ（テスト専用）。
- テストは `tmuxFacade`（シングルトン）または `TmuxFacade()` 直接構築（poll_pane_realworld_test）の両方を使う。

### 推測（実装時に再検証が必要）

- 新構成の行数見積もり（§2）は各メソッドの実測行数からの概算。実装後の実測で 500 行未満を確認する（最大想定は content_operations ~150 行）。
- 「facade 公開面を不変にすれば lib/test の更新がゼロ」は、公開 API のシグネチャと例外規約を保持することを前提とした帰結（変更しないという設計判断）。
- ops 層の「将来の別 backend 再利用」は副次便益であり、実現性はその backend 実装の設計次第（§2.1 の主目的は責務分界）。
- Phase 1〜4 の順序は依存の向きから導いた推奨手順であり、実装時はコミット粒度を調整してよい。

---

## 8. 成果物サマリ

- 設計書: `/tmp/p1-design/tmux.md`（v2: critique 対応）
- 提案構成: 3レイヤー **21ファイル**（commands 9 / parsers 6 / exec 1 / ops 4 / facade 1 + 既存 delimiters・models・contract は不変）
- API 変更: TmuxCommands(公開 static 50) → リソース別7クラス + 合成2、TmuxParser(公開17) → リソース別5クラス + 検査1、Facade 公開面は**不変**（TmuxContract 40メソッド維持）
- 更新必要: **lib 7ファイル / test 6ファイル**（builder 参照）+ lib 1 / test 2（parser 参照、うち facade は内部分割）。テスト数 94+54、期待値リテラルは不変
- 削除: tmux_command_builder.dart・tmux_parser_adapter.dart・shim 2ファイル
- 最大リスク: コマンド文字列・パース期待値（expect( 127+134）の移動ミス → 期待値行の差分ゼロ検証で防ぐ