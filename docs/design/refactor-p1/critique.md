# 責務ベース再設計（3設計書）への反論・穴探しレポート

- 作成者: design-critic（チームtask #13）
- 対象設計書: `/tmp/p1-design/tmux.md` / `/tmp/p1-design/ssh.md` / `/tmp/p1-design/ansi-herdr-theme.md`
- 検証基点: HEAD = `9f30573`。事実確認は `git show HEAD:<path>` と working tree の grep による。
- 凡例: **重大** = 設計の実現を阻害/挙動・更新リストの欠落で失敗に直結する懸念 / **中** = 実装時に破綻しやすい or 方針矛盾 / **軽微** = 数値誤差・記述の不整合 / **良い点** = 妥当な判断。

---

## 0. 調査サマリ（事実ベース）

| 項目 | 設計書の主張 | 実測（git show HEAD） | 判定 |
|---|---|---|---|
| tmux_command_builder / tmux_parser_adapter / tmux_facade 行数 | 632/531/643 | 632/531/643 | 一致 |
| ssh_client / persistent_shell / caret_manager 行数 | 1298/500/634 | 1298/500/634 | 一致 |
| ansi_parser / herdr_adapter / app_theme 行数 | 679/644/501 | 679/644/501 | 一致 |
| TmuxCommands の lib 参照数 | 「lib 3 / test 6」「facade 33」 | HEAD importers: **lib 7 / test 6**。facade の `TmuxCommands.` 出現数は **42** | **誤り（下記§1-重大-2）** |
| tmux_contract.dart の builder import | 更新リストに言及なし | **`import 'tmux_command_builder.dart'`（L11）があり `SplitDirection`(L137) `TmuxLayout`(L228) を使用** | **更新リスト漏れ（重大）** |
| lib/backend/domain/tmux_pane_writer.dart | テスト版のみ記載 | **lib 版が `import ... tmux_command_builder.dart' show SplitDirection`（L16）し 2 箇所で使用** | **更新リスト漏れ（重大）** |
| terminal_screen SplitDirection 数 | 9 箇所 | 10 箇所 | 軽微 |
| tmux_commands_test tests / expect | 94 / 期待値「約186」 | 94 tests / `expect(` 127 | 数値の過大主張 |
| tmux_parser_test tests / expect | 54 / 131 | 54 / **134** | 軽微 |
| TmuxContract メソッド数 | 46（§7） | **40**（@override 数） | 軽微 |
| TmuxCommands static 数 | 53（§8） | 50 | 軽微 |
| chain / pipe の lib 利用ゼロ | 主張 | 実測ゼロ | 一致 |
| extractError の lib 利用ゼロ | 主張 | 実測ゼロ（test のみ） | 一致 |
| shim（tmux_commands.dart / tmux_parser.dart）import ゼロ | 主張 | 実測ゼロ | 一致 |
| connectionFactory 注入数（ssh_client_test） | 「16 箇所級」 | 14（repro を足すと 15） | 軽微 |
| persistentShellFactory 注入数 | 「約10」 | 6（repro 足すと 7） | 軽微 |
| バグ2 対応（per-command scanner / 閾値3 等） | 「working tree に存在する修正」と表現 | **HEAD に既に存在**（persistent_shell L212/L241/L266、ssh_client L277 `_keepAliveFailureThreshold=3`） | 設計の前提誤認（安全側） |
| ansi importers | 3 ファイル | 一致（ansi_text_view / 2 test） | 一致 |
| parseToTextSpan・resolvePaintColors・standardColors・brightColors の外部参照ゼロ | 主張 | 実測ゼロ（コメント以外） | 一致 |
| getThemeMode 呼出元ゼロ | 主張 | 実測ゼロ | 一致 |
| switchTheme は light のみ | 主張 | `grep -c` 実測 1（light 内） | 一致 |
| `SshClient._l10n` の設定箇所 | 「l10n は SshClient が保持」のみ記載 | **`connect()` 内の L345 `_l10n = l10n` で設定（コンストラクタではない）** | 設計に未反映（下記§2-重大-1） |

---

## 1. tmux.md（tmux 3ファイル再設計）

### 重大

1. **更新リスト漏れ: `lib/services/tmux/tmux_contract.dart`**
   - HEAD で `tmux_contract.dart` は `import 'tmux_command_builder.dart'`(L11) をしており、`SplitDirection`(L137) と `TmuxLayout`(L228) をメソッドシグネチャで使用。
   - 設計は Phase1 で「tmux_command_builder.dart を削除（残骸を残さない）」（§5-1）とし、enum は `commands/layout.dart` へ移動（§3.1）。つまり **tmux_contract.dart の import パス変更が必須**だが、§4.1 の lib 更新リスト（facade / shell_lifecycle / connection_form / terminal_screen の4件）に **tmux_contract.dart が無い**。
   - 事実（grep）: `git grep -l "tmux_command_builder" HEAD -- lib` = connection_form_screen / terminal_screen / **tmux_pane_writer(lib)** / tmux_commands(shim) / **tmux_contract** / tmux_facade / tmux_shell_lifecycle の7件。
   - 影響: 設計どおり消すと **コンパイルエラー必発**。facade を「公開面不変」にしてしまうと、`SplitDirection`/`TmuxLayout` の公開元（layout.dart）への import 更新が契約ファイルで必要になる点が抜けている。
   - §4.1 見出しの「更新対象: lib 3 / test 6」も実測（lib 実質5）と食い違う。

2. **更新リスト漏れ: `lib/services/backend/domain/tmux_pane_writer.dart`（lib 本体）**
   - 設計 §4.1 には `test/services/backend/domain/tmux_pane_writer_test.dart` は載るが、**lib 本体**（`import ...'show SplitDirection'` / L16、使用 L96-97）が載っていない。
   - lib と test は別ファイルであり、「lib の import 変更ゼロ」を暗黙に含む記述では破綻する。※lib 側は enum 移動で import パス変更が必要。

3. **ops 層は「設計の本質」ではなく facade のメソッド移動ツール**（形を変えただけの機械的分割の疑い）
   - 提案の `ops/{session,window,pane,content}_operations.dart` は、実質「現在の `TmuxFacade` のメソッド本体をリソース軸で4分割して移植したもの」。設計 §2 の ops メソッド一覧と §3 の facade メソッド一覧はほぼ1:1 対応で、**新たな抽象・不変条件・状態を追加していない**。
   - 前回批判の「機械的分割（1行委譲wrapper・util grab-bag・private共有 mixin）」に照らすと、**facade は「各 Op への 1行委譲」の集合に置き換わる**（§2-3「facade は Op をフィールド合成する委譲クラス」）。委譲先（ops）に実ロジックがある点で「1行委譲wrapper」とは異なるが、
     - ops の大半は「`TmuxXxxCommands.*` で文字列生成 → `TmuxCommandRunner.run` → `TmuxXxxParser` → `_requireRecords`」という同構文の繰り返しで、**ops 単体では責務が「リソース軸」以外に無い**（例: `TmuxSessionOperations.startServer` は run 一回だけ）。
     - 「1ファイル=1責務」の「責務」が「session/window/pane/content」という**データ資源軸**であり、これは前回否定された「util grab-bag」よりは明確だが、**「冪等性」「エラー種別」「状態変化(attach/detach)」「同期/非同期」といった横断責務はどこにも帰属しない**。
   - 推測と区別: ops に実ロジックが残る（例 pollPane ~93行）のは事実。ただし**「ops 層を設ける必然性（facade 500行制限以外の理由）」が設計書に書かれていない**点は事実として指摘。

### 中

4. **`_l10n` の移し先が「Runner へ移動可能」とだけ書かれ、契約上必須の箇所が曖昧**
   - 現状 `_l10n` は facade L39/L609/L636 で `_execChecked`/`_requireRecords` のエラーメッセージに使用。設計は「Runner が保持」（§2 exec/command_runner）と書くが、ops 側のエラーメッセージ生成（例 `connTmuxCommandFailed`）が**すべて Runner 経由になる**ことを明示していない。また `TmuxFacade({AppLocalizations? l10n})` のコンストラクタ互換（`tmuxFacade = TmuxFacade()` で null 運用 → `lookupL10n()` フォールバック）を保つかが未記載。挙動は保てるが「どのレイヤーが l10n を持つか」の責務境界が不十分。

5. **`parseFullTree` の tree_parser と行パーサの二重実装が残る**
   - 設計 §6 で「record 直接解釈を tree_parser にそのまま移動（統合は挙動変更になるため行わない）」と明記。これは事実に忠実だが、**設計の「1ファイル=1責務」から見ると `tree_parser` は行パーサと重複した第2のパース実装を抱え込み、責務の混在が残る**。リスク表で「低」と自己評価しているが、将来 parse ロジック修正時に2箇所直す分岐リスクは中程度。

6. **`pane_commands.dart` が「ペイン操作＋入力(sendKeys/paste)+copy mode」を1ファイルに集め ~230行**
   - 設計 §2 で pane_commands に sendKeys / sendEnter / sendInterrupt / sendEscape / paste / enterCopyMode / cancelCopyMode 等を同居させ ~230行。入力系とペイン操作は技術的には別責務（tmux の key 送信 vs 構造変更）で、230行は「500行未満」は満たすが、**最大ファイルが「入力責務」を含む grab-bag になりかける**。前回批判の「util grab-bag」を別の形で再現しうる。

### 軽微

7. 数値誤差: 契約メソッド数 46→実測40、TmuxCommands static 53→実測50、facade の TmuxCommands 参照 33→実測42、parser_test expect 131→実測134、terminal_screen SplitDirection 9→実測10。
8. `list_format.dart` は `_listFormat` 1メソッド (~4行) のためのファイルで ~20行。単一責務というより**過剰分割**寄り（他に合わせるための粒度は理解できる）。
9. `output_validator.extractError` はテスト専用（実測ゼロ）だが、公開 API として維持する判断は事実に沿う（良）。

### 良い点

- **テスト期待値を1バイト変えない方針**（コマンド文字列・パース期待値）は、リファクタの安全性の最も確実な担保。検証手順も具体的（§5-4）。
- **`parseFullTree` の統合を「挙動変更になるため行わない」判断**は、挙動不変原則に忠実で正しい。
- **shim 2ファイルの削除タイミング**（HEAD で import ゼロを grep 確認済み）は事実に基づく。
- pollPane を「塊のまま移動」する方針は、文字列結合ロジックのズレを防ぐ点で安全。
- dialog の代替案 D（契約を資源別に分割）を将来課題として明確に切り分けた点は、スコープ統制として妥当。

---

## 2. ssh.md（ssh_client / persistent_shell / caret_manager）

### 重大

1. **`_l10n` の引き回しが未定義 → 挙動不変（エラー文言のローカライズ）を崩す恐れ**
   - 事実: `SshClient._l10n` は **コンストラクタではなく `connect()` 内で設定**（HEAD L345 `_l10n = l10n`）。エラーメッセージは execute (L982/L1010/L1141)、keepalive (L818)、connect (L458-473) など広域で `_l10n?.sshXxx ?? 'en fallback'` を参照。
   - 設計 §2.1 は「コラボレータは操作ロジックを担い、必要な資源を**メソッド引数で受け取る**」とするが、**SshCommandExecutor / SshKeepAlive / SshConnector が l10n をいつどう受け取るかが書かれていない**。コラボレータをコンストラクタで生成し l10n を握らせると「接続前に null、接続後に何も更新されず英語フォールバック固定」になり**挙動変化**。per-call 引数にするなら各メソッドのシグネチャに l10n が溢れる（下記3と併発）。
   - 対策（提示）: `_l10n` は SshClient の「可変フィールド」のまま残し、コラボレータには「現在の l10n を返すクロージャ/ゲッター」を注入する、もしくは connect() が全コラボレータの l10n を更新する setter を明示する。

2. **execute() 内の「再起動フォールバック」の実行主体が定まらない（shellManager との循環/引数集中）**
   - 事実: HEAD の `execute()` は `PersistentShellError` の `closed`/`disposed` で `restartPersistentShell()` を呼び再実行する（L1044-1080）。このリトライは**シェル再生成（SshShellManager 管轄）と routing（SshCommandExecutor 管轄）が相互に触り合う**操作。
   - 設計 §2.1 は executor の責務に「PersistentShellError からのフォールバック/再起動」を入れる一方、**依存グラフ（§3）では `ssh_command_executor → persistent_shell.dart` のみで SshShellManager への辺が無い**。executor が再起動を誰に依頼するか（facade コールバック / shellManager 注入）が未定義。
   - `_inputShell`/`_persistentShell` は execute の routing 判定（L1008/1010 等）にも使われるため、「資源をメソッド引数で渡す」とすると execute() の引数が `(request, client, persistentShell, inputShell, l10n, lock, restartCallback...)` 級になり、**責務が facade から引数集中へ移るだけ**の「形を変えた機械的分割」に近づく。

3. **SshClient ファサードが「状態・イベント・keepalive・資源・cleanup・委譲」を残す = 6責務併存**
   - 設計 §2.1 の ssh_client.dart 行は「接続資源・状態・イベント・keep-alive・各コラボレータの所有と委譲、dispose/cleanup 統括」（~330行) としており、**1ファイル=1責務の原則に反する大きな副責務群**を facade が保持し続ける。l10n(実は上記1)・`_execLock`・`_events`・`_persistentShell`/`_inputShell` ポインタ・fingerprint 移行保留の所有者が揺れる。
   - これは「責務ベース」と言いつつ facade への**逆再集中**であり、前回批判で問題視した「状態所有者の曖昧さ」を契約/コラボレータ境界ではなく、**facade と collaborator の間で再定義しただけ**の可能性がある。実際の単一責務化は「SshConnectionState を扱う状態機械」「イベントデリゲーション」「資源のライフサイクル」等を独立クラスにする代替案（§7 で「接続を独立オブジェクト化」を不採用にした）を再考すべき。

### 中

4. **SshKeepAlive の状態（間隔カウンタ・失敗数）の所有者が曖昧**
   - HEAD では `_keepAliveFailureCount` / `_keepAliveSuccessCount` / `_currentKeepAliveIntervalSeconds` が SshClient フィールド（L280-286）。設計は SshKeepAlive コラボレータ（~110行）を作るが、**カウンタ類をどちらが持つか書いていない**。keepalive と状態が離れると「3回閾値」挙動（L277 は HEAD に存在）の回帰リスク。

5. **FakeSshClient の継承前提は正しいが、その上に ops 流だともう一つ整合確認が要る**
   - 事実: `FakeSshClient extends SshClient implements TmuxCommandExecutor, TmuxPathDetector, BackendAdapter`（test/helpers/fake_ssh_client.dart）で ~19 メソッドを override しており、**SshClient を普通の継承可能クラスに保つ設計判断は必須で正しい**。
   - ただし execute 内部で restartPersistentShell 等の「override される公開メソッド」を呼ぶ構成だと、Fake の stub と内部委譲の相互作用が変わりうる（コラボレータ経由にすると override が効かなくなる経路が生じる）。設計書は Fake のバイパス経路を検証していない。

6. **persistent_shell: `ShellMarkerProtocol` が「マーカー構築＋出力後処理(CR正規化/RC抽出/trim)」の2機能を持つ**
   - 設計 §2.2 で protocol に「マーカー文字列の生成 **+** 出力の後処理」を同居させ ~140行。マーカー生成(nonce 管理)と出力解析(スキャナ結果の後処理)は別責務。**前回批判の「一つに押し込む」匂い**がある（スキャナー自体は既存 ShellMarkerScanner 独立ファイルとして正しく分離済み）。
   - さらに **nonce は PersistentShell インスタンス毎に生成されなければならない**（SHELL-002 `_markerId` はインスタンスフィールド、HEAD L30）。protocol を共有/シングルトン化すると**偽装耐性が壊れる**。protocol をインスタンス化する前提が設計に明記されていない。

7. **caret manager: 静的ユーティリティ移動と「memo のスコープ」の整合**
   - 事実: `deriveClientSocket`/`isValidPaneId`/`shellQuote` は manager の static(HEAD L191 等)で、**test が `HerdrCaretHelperManager.deriveClientSocket` 等として直接参照**（manager_test 195-227 行は実測一致）。type 移動で参照先が変わるのは設計が §4.3 で認識（良い）。
   - ただし install memo（`_installMemo[_ssh]`、HEAD L157/L260-268、`identical` による single-flight + 失敗時除去）を「installer 内で完結（connection 単位）」にするのは妥当だが、**key が `_ssh`（SshClient インスタンス）であること**に依存している。installer を Manager とは別オブジェクトにしたとき、**Manager が複数 connection を扱える契約**（`_CountingSshClient` 差替えテスト等）と memo の生存期間の対応が曖昧。接続単位を「インスタンス単位」に読み替えないこと。

### 軽微

8. 数値: connectionFactory 16箇所級→実測14、persistentShellFactory 約10→実測6。
9. 「working tree に修正されたバグ（閾値3/バグ2対応）」という記述は**実際には HEAD に既にある**ため、設計書の前提記述は誤りだが**リスク方向ではなく安全側**（HEAD 起点で失われない）。文書の事実誤認として指摘。

### 良い点

- **FakeSshClient 継承・3ファクトリ注入点の維持**はテストと一致し、必須の制約として認識している。
- **状態遷移の書込を SshClient のみにする方針**（コールバックで委譲）は、状態所有者を一意化しようとする姿勢として方向性は正しい。
- `Dialogue` 代替案「part+private」を混在として拒否し、独立クラス+引数授受にする判断は mixin 禁止原則に沿う。
- persistent_shell で Scanner を下層、プロトコルを上層と位置付けた階層認識は正確。

---

## 3. ansi-herdr-theme.md

### 重大

（該当なし — ただし下記の2点は「中」として残る）

### 中

1. **ansi: `parse()` と `parseLines` の「同一アルゴリズム統合」宣言は挙動不変を危うくする**
   - 事実: HEAD の `parse()`（L165-195）は入力全体を1ストリームで SGR スキャンするのに対し、`parseLines()`（L464-491）は **CRLF/CR 正規化 + 行分割 + `_lineCache` 再利用**で `_parseLineWithStyle` を呼ぶ。両者のスキャン本体は確かに同じだが、**前処理（正規化・分割）は異なる**。
   - 設計 §2.1 は「`parse` は parseLines と同等スキャンの薄いラッパー」、付録A は「1アルゴリズムに統一」と書く。**統一時に CR 正規化や改行分割の意味が `parse()` 側へ混入すると出力が変わる**。`parse()` は外部参照ゼロ（事実）で影響は限定的だが、「挙動不変をテストで担保」とだけ書き、**期待値が無い入力（CR のみ/改行混在）に対する方針が未定**。lineToTextSpan 経路（ansi_text_view L824/L887）は renderer 側なので直接は影響しないが、`parseToTextSpan`(L451) をfacade互換で残す以上 `parse` の意味論を変えないことが必須。

2. **theme: dark/light ビルダー分割は「責務ベース」ではなく「変数分離」で、85% 重複が残る**
   - 事実: HEAD の app_theme.dart は `AppTheme.dark`(L38-256) と `AppTheme.light`(L257-493) で **構造的にほぼ同一**（設計自身も85%重複と認める）。switchTheme は light のみ（実測 grep=1）。
   - 設計は「ビルダー2分割（逐語移動）+ facade」を採用し、パレット一元化（R3）を不採用。これは**動作不変を優先する現実的解**だが、「1ファイル=1責務」の観点では**dark と light は「同じ責務(const ThemeData 構築)の2変数」**であり、責務の分割になっていない。結果、220行+240行のほぼ同じコードが残る = **「形を変えただけの機械的分割」の温存**になる。少なくとも「なぜパレット(色値)をデータ化しないのか」の根拠（検証コスト）をリスク表以上に明示すべき。
   - なお `AppTheme.getThemeMode` がデッドコード（実測: lib/test で参照ゼロ）なのに「公開面維持」で残す判断は、挙動不変の観点では安全だが「責務ベース」とは矛盾する粘着コード。削除は API 変更で許容されている（§8 事実）ため、削除を推奨する。

3. **ansi スパンキャッシュ（Expando）同一性の制約は認識済みだが、テスト不十分**
   - 事実: `_spanCache` は `Expando<ParsedLine>`（HEAD L162）で **ParsedLine インスタンス同一性**に依存。`_lineCache`(L157) の再利用とセットで意味を持つ。
   - 設計 R1 で「同一インスタンス委譲で等価」と正しく認識しているが、**LineParser と Renderer を分離した場合、同一性が履行されるのは「facade が LineParser の返却インスタンスをそのまま Renderer へ渡し続ける」実装規約がある間だけ**。呼出元（ansi_text_view）が間にコピー/再構築を挟むとキャッシュが破綻する。設計はこれを doc 注記に留めており、**規約違反を検知するテスト（明示的なインスタンス同一性 assert）が無い**。

### 軽微

4. herdr:`HerdrCommandExecutor` に「l10n + userExecutablePath」を渡す設計は良いが、`_strings => _l10n ?? lookupL10n()`（HEAD herdr_adapter L36-37）の**遅延解決**を保存するか未記載。構築時に解決すると言語切替反映が壊れる。
5. `HerdrMutationClient` ~350行は「mutation 16個＋`_execMutation`＋trySendNoWait 分岐」で、500行未満は満たすが**1クラスに複数責務（送信選択・実行・結果構文解析）を含む**。`HerdrMutationResult.parse` への静的抽出で緩和されるが、mutation client 自体の規模が目安を圧迫。
6. 数値: mutation 16個（実測 `Future<HerdrMutationResult>` は 18、L144-216 等）等の粒度差。

### 良い点

- **現行引数を「parse は外部参照ゼロ」等の事実確認とセットで提示**しており、grep の再現性が高い（標準/明るい色パレット・parseToTextSpan・effectiveLineBackgroundColor 等の外部利用ゼロも一致）。
- **HerdrAdapter を継承可能に保つ判断**（snapshot_cache_test の `_FakeSnapshotAdapter extends HerdrAdapter`、caret の `_MinimalAdapter extends HerdrAdapter`）は実測どおりで必須であり、保留せず関係を表で示している。
- **mutation_result の独立ライブラリ化と export 互換**、および「単一責務はクラス+依存方向で担保しファサードは薄い」という R6 の設計意図の明示は、レビュー指摘への誠実な回答。
- ansi のレイヤー(値型→SGR→line→renderer→facade)の依存方向は非循環で明確。

---

## 4. 「元の批判（機械的分割）を解消できていない箇所」のまとめ

| 批判要素 | tmux | ssh | ansi/herdr/theme |
|---|---|---|---|
| 1行委譲 wrapper | **facade が Op への委譲集合になる（§2-3）→ 一部再発** | ファサードが委譲+状態保持（§2-1） | ファサードは薄い（R6 明記）→ 解消 |
| util / grab-bag 命名 | **pane_commands 230行に送受信+copy-mode 同居（§6-中）** | (`list_format は監視圏`) | theme が dark/light の重複を残す（§3-中-2） |
| private共有 mixin/基底 | 解消（合成・禁止明記） | 解消（削除明記） | 解消（part 撤去・独立ライブラリ化） |
| 依存循環 | 解消（非循環グラフあり） | **executor↔shellManager の未定義（§2-重大-2）** | 解消 |
| 状態所有者の曖昧さ | 状態が少ないので軽微 | **facade に再集中（l10n/keepalive/execLock）（§2-重大-1/3）** | ansi キャッシュ同一性の規約依存（§3-中-3） |
| 呼出元更新リストの漏れ | **tmux_contract.dart / lib tmux_pane_writer.dart 欠落（重大）** | 概ね網羅（Fake・3ファクトリ） | 概ね網羅 |

→ **特に直すべきは「tmux の更新リスト2件」と「ssh の l10n / execute再起動の受け渡し定義」「ssh facade の副責務6つ」**。

---

## 5. 重要指摘トップ5

1. **［tmux・重大］ `lib/services/tmux/tmux_contract.dart` と `lib/` 側 `tmux_pane_writer.dart` が更新リスト・設計グラフから欠落**。builder 全削除時に import パス変更を見落とすとコンパイル不可。更新リストを「lib 7 / test 6」に修正せよ。
2. **［ssh・重大］ l10n が connect() 時にのみ設定される（L345）のにコラボレータへの伝達手段が未定義**。現状どおりの継承/ゲッター注入を明記しないとローカライズが英語固定化する。
3. **［ssh・重大→中］ execute() の再起動フォールバックが executor と shellManager の境界外**。依存グラフを更新し、再起動の依頼経路（facade コールバック or shellManager 注入）を確定せよ。引数だらけで「機械的分割」に逆行しないこと。
4. **［tmux・中〜重大］ ops 層はリソース軸以外の責務を持たない「facade の移植」**。500行制限以外の必然性を明示するか、ops/pane の入力系を分離して grab-bag 化を防ぐべし。
5. **［ansi・中］ parse() と parseLines の「アルゴリズム統一」は CR 正規化・行分割の意味論を変えうる**。経路別の期待値テストを用意しない限り「挙動不変」を宣言しない。加えて theme の dark/light 85% 重複は責務分割になっておらず、パレットデータ化を推奨（挙動優先なら明示の継続判断）。

## 6. 設計修正が必要な箇所（推奨アクション）

1. tmux.md: §4.1 に `lib/services/tmux/tmux_contract.dart`、`lib/services/backend/domain/tmux_pane_writer.dart`（lib 本体）を追記。enum 移動時の import パス変更対象一覧を grep ベースで再掲。
2. ssh.md: ①l10n 伝達（connect() 時更新 or ゲッター注入）を明記 ②execute の再起動経路を依存グラフに追記 ③SshKeepAlive カウンタと `_execLock` の所有者を確定 ④protocol の nonce を「インスタンス毎」と明記。
3. ansi-herdr-theme.md: ansi の parse/parseLines 統合に「入力種別別（CR/CRLF/マルチライン）期待値」を追加。theme は dark/light 重複の許容根拠（変更禁止観点）とパレット化の将来課題を分けて記載。getThemeMode の削除可否を明文化。
4. 全設計書: 「更新対象ファイル」の数値（tmux lib 実質5・parser expect 134、ssh ファクトリ数等）を実測に合わせる。

---

## 補足: 事実と推測の区別

- **事実（実測確認済み）**: 各ファイル行数、importers 一覧（tmux_contract/tmux_pane_writer の builder import、ansi importers 3、shim0、chain/pipe/extractError lib0）、`_l10n` は connect() 内設定、execute 内 restartPersistentShell 使用、FakeSshClient extends SshClient・override 一覧、parser expect 134、contract メソッド40、CaretMemo の `_ssh` キー、`parseLines` の CR 正規化 vs `parse()` なし、theme 85% 重複構造・switchTheme light のみ、getThemeMode 参照ゼロ。
- **推測（要実装時検証）**: ops 層が実装時に「どの程度の追加責務」になるか、executor↔shellManager の受け渡し設計、protocol のインスタンス化単位、theme パレット化の実コスト。（本文中は「推測」と断った項目のみ。）