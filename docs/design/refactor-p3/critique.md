# P3 責務ベース再設計（5設計書）に対する批判的レビュー

- レビュアー: p3-critic（タスク#6・読み取り専用）
- 対象: `/tmp/p3-design/` 配下 5 設計書
  - connections-screen.md（connections_screen.dart 1702行）
  - ansi-text-view.md（ansi_text_view.dart 1670行）
  - connection-form.md（connection_form_screen.dart 1391行）
  - browser-and-dashboard.md（file_browser_screen.dart 983行 + dashboard_screen.dart 503行）
  - shell-and-panes.md（home_screen.dart 814行 + notification_panes_screen.dart 519行 + markdown_preview_screen.dart 533行）
- 検証方法: 対象 8 ファイル・関連テスト 25+ 本・P2 設計書/実装に対する grep/read による実測（HEAD a86fbdd = P2 完了・`git diff HEAD` 空確認済み）
- 凡例: 【重大】挙動不変・コンパイル成立性を損ない得る設計穴 【中】設計不備・事実の歪曲 【軽微】事実誤認・表記 【良い点】実測と一致していた点

---

## 0. 全体サマリ（5設計書横断）

1. **【重大・横断】private クラス/関数を「別ファイルへ」移す設計が Dart の可視性規則に抵触**（connections-screen・browser-and-dashboard）。
   Dart の private シンボル（`_` 接頭辞）は**ライブラリ＝ファイル単位**でスコープされる。`_ConnectionCard` を `connection_card.dart` へ移し「private のまま維持」と書いても、呼出元の `connection_list_screen.dart` からは参照できない。同様に `_FileBrowserAppBar`・`_FileBrowserBody`・`_FileBrowserUploadTransferPanel`（browser 設計）も private のまま別ファイル化は**コンパイル不能**。移すなら public（@internal 昇格を含む）化が必須。P2 実装では @internal 使用実績がゼロ（`rg "@internal" lib/` = 0 件）で、「承認済み」と書いた shell 設計の根拠も薄い。**全書で「private を保てる」という誤った前提を 1 行でも書いた箇所は修正対象**。
2. **【中・横断】行数の総計増が P2 の批判水準を超える**。P2 critique は「+17% でも大きい」と指摘した。今回 ansi は**+31%**（2,180 vs 1,670）、browser は +20.5%。個別の反論（真の所有者への分割）はもっともだが、「責務ベース 500 行未満」の達成だけが目的化し、ファイル数（ansi 10 / connections 9 / form 7）と増分の肥大が監視されていない。
3. **【中・横断】シム化前提の相互不整合**（connections ↔ shell）。home_screen も connections_screen も「元ファイル＝シム」になる予定だが、**両設計書は相手のシム化を前提にしていない**。統合時、connection_list_screen が currentTabProvider（home_screen シム経由）を import し、home 側 IndexedStack が ConnectionsScreen（シム経由）を build する相互循環が生じる。一方は「現行どおり」、他方は「export で一本化」とだけ書いており、**実装順序・並行編集の整合ルールが未定義**。
4. **【良い点】テスト固定事項の洗い出しは概ね正確**。connections（kill→reload 順序・herdr workspace 流れ・damaged key）、ansi（ListView itemExtent/padding・SelectionArea・ValueKey 3 種・`AnsiTextViewState()` 直接 new・`TerminalMode.values` 順序）、form（TextFormField index 0-6・dropdown 個数）、markdown（static ScrollKey・`MarkdownCodeBlock` byType・loadCalls==1）は**すべて実測と一致**。P2 に比べ事実精度が格段に上がっている。
5. **【軽微】シムの export 形式が未統一**（全体 export vs `show`）。挙動差はないが、P2 critique §0 の「export 戦略 3 分裂」の再発防止のため、リーダーが 1 形式に揃えること。

---

## 1. connections-screen.md（connections_screen.dart）

### 1.1 【重大】`_ConnectionCard` 等 private クラスの別ファイル移動は不可（可視性規則）

- 事実: 現在 `_ConnectionCard` は connections_screen.dart **同ファイル内**で build（L332 SliverList itemBuilder）から生成される。設計は
  - `_ConnectionCard`/`_ConnectionCardState`（L593-1468）→ **connection_card.dart** へ「private のまま移動」（§3.4）
  - 呼出元シェル（=connection_list_screen.dart）がこれを使う（§3.1）
  - `_SearchField`（L1469-1556）→ connection_search_field.dart「private のまま」（§3.3）、呼出はシェルの `_buildAppBar`
  - `_showSortDialog`（L175-289）→ connection_sort_sheet.dart に**関数として**移設（§3.2）、呼出はシェル `_buildAppBar` の `onPressed: () => _showSortDialog(context, ref)`
  - `_NewSessionDialog`（L1592-1702）→ connection_new_session_dialog.dart「private のまま」（§3.8）、呼出は connection_card.dart の State
- 評価: Dart では `_` 始まりのシンボルは**同一ライブラリ（同一ファイル）内でのみ**参照できる。別ファイルへ移した private クラス/関数は、呼出元の別ファイルから**コンパイル不能**。設計書の §2「private クラスはファイル外参照ゼロ（rg 確認済み）のため新ファイルへ自由に移動可能（ただし名前は private のまま維持）」は、**「ファイル外参照ゼロ」＝「このプライベート名を将来も誰も参照しない」ことの確認であり、「移動後に呼出元から参照できる」ことの根拠ではない**。呼出元（シェル/カード）が名指しで参照する以上、public 化（または @internal 化）が必須。
- 必須修正: connection_card / connection_search_field / connection_sort_sheet / connection_new_session_dialog / card_header / sessions_panel の各シンボルを **public（`@internal` アノテーション付き public）** にすることを設計書に明記。private のまま移動と書いた §2・§3.4・§3.3・§3.2・§3.8 の記載を修正。呼出元と移動先の import 構成を追記。

### 1.2 【重大】operations オブジェクトが「ref 非依存」なら、`updateSessionsFromDomain` の配線が定義欠落

- 事実: §5 は「`updateSessionsFromDomain` 同期は **State 骨格**が行う（operations は ref 非依存）」と記載。しかし設計書 §2 の operations の責務は「SSH 接続・snapshot/listSessions・kill/close/create・domain 変換の協調オブジェクト」で、**各メソッドの戻り値レイアウト（Snapshot?->`toDomainSessions()` の結果をいつ誰が `ref.read(activeSessionsProvider.notifier)` に渡すか）の受渡契約が明文化されていない**。
- 評価: 実装者が「operations が直接 updateSessionsFromDomain を呼ぶ」実装をすると、**ref 依存が漏れて P2 critique §4.1（orchestrator の state 書き込み経路未定義）と同型の穴**になる。逆に State 骨格が domain 変換結果を受けてから ref を呼ぶ実装なら安全だが、どちらかが未定義。
- 必須修正: operations の各メソッドの**戻り値型**（例: `Future<SnapshotResult>` 等）と、「State 骨格がその結果を `updateSessionsFromDomain` に渡す」1 行を §3.7・§5 に明記。

### 1.3 【中】`_CardHeader`/`_ExpandedSessionsPanel`/`_SessionRow` を別ファイルに移すが props 化後の状態経路が省略

- 事実: `liveWindowCounts`（L1337-1340）は **provider 最新ウィンドウ数優先**の計算で、`activeSessions`（State の `ref.watch(activeSessionsProvider)` 由来）から `sessionId ?? sessionName` キーで引く。設計書 §3.5 は「L1337-1340 の liveWindowCounts 計算は State 側または panel 側で維持」と**二者択一を未決定**のまま残し、§3.6 は「statusColor 導出（hasActiveSessions 有無・lastConnectedAt 有無の 3 分岐）は header 側に移すか呼出側に残すか未決」。
- 評価: どちらに寄せても実装は可能だが、**「どちらにしても挙動不変」を根拠付きで示せるのは一方**（export の provider watch を header 内に持つと、カードの rebuild 範囲が変わる）。state 経路を 1 つに確定しないまま「State 側または panel 側」と書くのは確認作業の先送り。
- 推奨修正: liveWindowCounts 導出と statusColor 導出の**所有者を 1 つに確定**（推奨: 呼出側 State で導出し、view へは値を渡す）。理由: provider watch を view 側に置くと、`_ConnectionCardState` の setState 再構築と二重の再構築源になるため。

### 1.4 【中】循環 import（connections_screen ↔ home_screen）の実体認識は正しいが、対応が「現行どおり維持」で先送り

- 事実: connections_screen.dart L10 が `import '../home_screen.dart'`、home_screen.dart L19 が `import 'connections/connections_screen.dart'` = **現行で循環 import が実在**（rg 実測）。§6-6 はこれを認識し「シム化で export と import が絡む。コンパイル成立」とする。
- 評価: Dart では import 循環はコンパイル可能で、現行が動いている事実は正しい。ただし connections 設計の**接続リスト側シム（export connection_list_screen）と、shell 設計の home シム（export home/home_screen + home_tab_provider）が同時に実装される**と、名前解決の順序が 2 設計書の実装タイミングに依存する。少なくとも「どちらを先に実装するか」「相互のシム更新で一時的にどちらかが壊れる可能性」を統合計画に含めるべき。
- 推奨修正: シム 2 本の相互依存を明記し、実装順序（home 先 or connections 先）と検証手順（両シム成立後の `flutter analyze`）をリーダーへ明示。

### 1.5 【中】行数見積の甘さ（シェル ~430 が 500 を越え得ることを自認しながら放置）

- 事実: §2 は自ら「実装が膨らむ想定（+20%）でも 434×1.2=521 で 500 を超え得る」と書き、§6-7 で「分解避難先（connection_list_states.dart）」を提示。ただし §2 の目標構成表ではそれを織り込まず「~430」のまま。
- 評価: 回避スロットがあるのは良いが、**「~430」が実装初期値として提示されると、実装者が 500 目前まで書いてから再分割する流れになる**。「~430 は実装時に 450 を超えたら即座に states 分離」と閾値を先に出しておくべき。
- 推奨修正: §2 のシェル行数を「~430（超過時は §6-7 の states 分離で ~330）」と双値で記載。

### 1.6 【軽微】`_SearchVisibleNotifier` の移動先が「同ファイル内 private のまま」で問題なし — 良い点

- `_SearchVisibleNotifier`（L29-42）はファイル内 private で、同ファイル内の ConnectionsScreen からのみ使用。connection_list_screen.dart に**実装ごと**移すので可視性の問題はない。正しい。

### 1.7 元の批判（機械的分割）はどこまで解消されたか → 構造は質的だが、1.1 がブロッカー

- 5 つの協調ファイル（card_header / sessions_panel / session_operations / sort_sheet / search_field / new_session_dialog）は真の責務持ちで機械的分割ではない。kill→reload の await 順担保・確認前未発行・mounted ガードの維持方針（§5）は的確。
- 未解消: 1.1「private のまま移動」は**表層の分割を試みた瞬間にコンパイル不能**になる致命穴。写経前の設計書修正が必要。

---

## 2. ansi-text-view.md（ansi_text_view.dart）

### 2.1 【中】10 ファイル構成 +31% の増分に対する正当化はあるが、「1 ファイル 500 未満」が目的化して分割粒度が暴れうる

- 事実: 合計 ≈2,180 行（現行 1,670 ・+31%）。P2 critique は「+17% でも大きい」と批判。§2 は「rdialog 批判は単一用途の小部品を目的化分割だった。本設計の 9 コラボレータはいずれも現行で 34〜342 行の実コード＝真の所有者」と反論。
- 評価: 反論の根拠（各ファイルが現行の実コード塊を持つ）は**実測と一致**し、機械的分割ではない。ただし `ansi_terminal_model.dart`（55 行: KeyInputEvent + TerminalMode の 2 値型）と `ansi_display_model.dart`（180 行）の境界は、**値型とモデルの分離に実質の状態移動が 50 行**であり、「行数削減のための細切れ」の匂いが残る。
- 推奨修正: 明示的な「これは過剰分割ではない」要件（全コラボレータが現行実コード 100 行超の塊を移す / 値型・View プレゼンテーションは除く）を §2 に 1 行追加し、レビュー時点で緩和される residual risk を確定させる。

### 2.2 【中】`AnsiDisplayModel.updatePalette` は新規メソッドであり、現行の「parser 再生成」との等価性が明記されていない

- 事実: 現行 didUpdateWidget（L264-276）は色変更時に `_parser = AnsiParser(defaultForeground:..., defaultBackground:...)` を**再生成**し `_invalidateCache()` を呼ぶ。設計書 §3 は「`_parser`・キャッシュ 4 値・`_lineHeight`・`_getParsedLines` → ansi_display_model.dart（キャッシュキー: text/fontSize/fontFamily・色変更時 updatePalette で invalidate を維持）」と書き、§5 は「`didUpdateWidget` 色不一致のときのみ `content.updatePalette(...)`」とする。
- 実測: **AnsiParser に updatePalette メンバは存在しない**（`rg "updatePalette" lib/` 0 件、ansi_parser.dart L18 定義のみ）。つまり display_model の `updatePalette` は**新設 API** であり、内部実装は「parser 再生成＋キャッシュクリア」に相当するはず。
- 推奨修正: `updatePalette` が「新規メソッド（内部で parser を defaultForeground/Background から再生成しキャッシュを無効化）」である旨を明記。既存メソッドの「移動」と新規 API の追加を区別する。

### 2.3 【重大】`AnsiTextViewState()` 直接 new テスト（modifier_test 19 本）の維持は「静的な委譲」で担保されている — 良い点・ただし唯一の穴

- 事実: modifier_test は `AnsiTextViewState()` を**直接 new**して `deriveBaseChar` / `isAsciiPrintable` を呼ぶ（L50/55/91/100/104/113/115/138/143/149/153/157/161/162/166 等）。設計書は「deriveBaseChar は静的委譲（`AnsiKeyComposer.deriveBaseChar` へ）で、インスタンス状態不使用」「isAsciiPrintable も静的」とし、State に同名 public を残す（§3・§4・§8-3）。
- 評価: 対応は**正しい**。State を直接 new しても `initState` は走らず、協調オブジェクト（initState で生成する late final 等）は未初期化のため、委譲先がインスタンス状態に触れないことが必須。設計書はこれに言及済み。
- 必須修正補足: 実装者が協調オブジェクトを「フィールド初期化子」ではなく「initState/late final で生成」する設計を守ること（§5 の生成列を「attach 時 / late final」と明記）を、§3 の移動マッピングに 1 行追記。これが漏れると `LateInitializationError` で既存テストが落ちる。
- **ただし** `AnsiTextViewState.jumpToLineFromTop` 等（5+1 メソッド）は terminal_screen が `GlobalKey<AnsiTextViewState>.currentState` 経由で呼ぶ（L464 / L1080/3020/3029/3100/3224/4316/4321）。State の**public 委譲メソッド**として残すと明記済みで妥当。

### 2.4 【中】`_EagerScaleGestureRecognizer`（L1623-1670）を「view の private」に置くのは不可（可視性・1.1 と同型）— ただし view 内で完結するなら可

- 事実: 現行は ansi_text_view.dart 同ファイル内 private で build L1027-1040 の GestureRecognizerFactory から参照。設計書は「ansi_terminal_view.dart 内 private」とする（§3・§8-1）。
- 評価: **view 内で定義し view 内でのみ使うなら可視性は成立する**。ただし §6 リスク11 は「public 化を避けた場合、view 内で typedef 公開せず import は不可のため public 化検討を critic に提示」と書く。**public 化なしでも view 内 private + 同ファイル内使用なら問題なし**。§8-1 も「現行同様 view 層の private に置く」としており、実質は正しい。必要なのは「view 内 private に置けば可視性 OK」であることの明記のみ。
- 推奨修正: §8-1 に「private のままでも、定義と使用が同一ファイル内なら可」の根拠を追記（1.1 の横断指摘と整合させる）。

### 2.5 【軽微】実測とのズレ

- 「プロパティ 21」: 実測で public final フィールドは **18**（text/paneWidth/paneHeight/onKeyInput/backgroundColor/foregroundColor/mode/zoomEnabled/onZoomChanged/verticalScrollController/cursorX/cursorY/caret/onArrowSwipe/onTwoFingerSwipe/onScrollSendTicks/navigableDirections/onTap、L60-125）。コンストラクタ名付き引数も 18。**「21」は誤り**（本質影響なし）。
- 「`toggleCtrl` 等は呼出元ゼロ（rg 実測・lib/test 0 件）」: 実測で lib 内の `toggleCtrl` 呼出元は **special_keys_bar_rows.dart L100 / special_keys_token_view.dart L103 などがあり、これは P2 済み special_keys_bar 側の別オブジェクト**。ansi_text_view.dart の `toggleCtrl`（L1426-）自体は外部呼出ゼロで**確認結果は正しい**（対象が異なるだけ）。ただし「呼出元ゼロ」の根拠が ambiguous なので、`AnsiTextViewState.` 接頭辞で絞る旨を注記。
- didUpdateWidget は「色変更のみ」: 実測（L264-276）と一致 ✓。

### 2.6 元の批判は解消されたか → 概ね解消・ブロッカーはない（修正 3 点のみ）

- 実行時 prop（onKeyInput/mode）のライブ参照（毎呼び出し引数 / host getter）は P2 critique §1.1 の教訓（keepKeyboardOnEnter）を**正確に反映**している。モード切替（terminal_screen が onKeyInput を毎ビルド差し替え、L3431-3441 付近）の実経路もリスク1で言及済み。
- `TerminalMode.values` の順序・`SelectionArea` 有無・ValueKey 3 種・ListView itemExtent/padding・`NeverScrollableScrollPhysics`・scroll tick 換算（1 tick = lineHeight×1.5・±25% ヒステリシス）はすべてテスト固定として実測一致。設計全体の質は 5 書中最良。

---

## 3. connection-form.md（connection_form_screen.dart）

### 3.1 【重大】`runFileBrowserUpload` 系のトップレベル関数化は form 側ではない — 誤記（該当なし）

- 対象外（これは browser 設計の指摘。form 設計書に当該記述なし）。form 側の下記 3 点に絞る。

### 3.2 【中】`ConnectionSaver` / `ConnectionTester` の `ref` 受け渡し（`connectionsProvider.notifier` / `connectionFormSshClientFactoryProvider`）の配線が表にない

- 事実: 現行 `_save` は `ref.read(connectionsProvider.notifier).add/update`（L1336/1343 付近）、`_testConnection` は `ref.read(connectionFormSshClientFactoryProvider)()`（L1157）を**State 内**で呼ぶ。設計書 §4 は「_testConnection は State から ref.read し tester へ注入（現行 L1157 と同一タイミング）」と記載（良い点）、**ただし** §2 の saver の責務（password 保存・Connection 構築・add/update）を実現するのに saver がどう `connectionsProvider.notifier` を得るか（引数で notifier を渡す / ref を渡す）が §3・§5 に**未記載**。
- 推奨修正: §5 に「`ConnectionSaver.save(..., {required ConnectionsNotifier notifier})`（State が `ref.read(connectionsProvider.notifier)` を渡す）」と 1 行明記。§4 の「現行 L1157 と同一タイミング」の記載と同じ粒度に揃える。

### 3.3 【中】TextFormField の index 0-6 固定を「ListView の子を [server, auth] にしただけで保証」とするのは不十分

- 事実: テストは `find.byType(TextFormField).at(0..6)`（index 固定）で入力する（connection_form_screen_test L140-147 等）。実測の現行出現順は
  name → host → port → username → (backend toggle※TextFormField ではない) → multiplexerPath → deepLinkId → (auth) authMethod toggle → password → keyDropdown。
  **TextFormField 限定では name(0)/host(1)/port(2)/username(3)/path(4)/deepLinkId(5)/password(6)**。
- 評価: 設計書 §6-1 は「ListView の子を [ConnectionServerSection, ConnectionAuthSection] とし、フィールド出現順を HEAD と同一に保つ」と書く。方向は正しいが、**「セクションを 2 つに割っただけでは並び順は保証されない」**（各セクション内の子の順序も維持する必要がある。特に ServerSection 内の backend toggle の位置）。§3 の移設表に「各セクション内の子順序不変」を明記すること。
- 推奨修正: §3 に「ConnectionServerSection の子順序（name→host→port→username→backend toggle→path→deepLinkId）と ConnectionAuthSection の子順序（authMethod→password→keyDropdown）を現行どおり維持」と追記。Port/Username の **Row 横並び**（L242-267）は widget 化で崩れやすいので特に明記。

### 3.4 【中】`_buildServerSection` 実測 841 行の内訳は正しいが、common chrome 抽出後の再構成で見た目が変わるリスクは「写経レビュー必須」に留まる

- 事実: server+auth セクション実測は L211-1051 = **841 行**。設計書の `ConnectionServerSection` ~430 / `ConnectionAuthSection` ~245 / `ConnectionInputStyle` ~90 は 8 フィールドの共通 decoration（~32 行×8≈148 行）抽出を前提にしており**計算自体は成立**。
- 評価: `ConnectionInputStyle.decoration` のパラメータマッピング（角丸 12・filled・contentPadding・prefix/suffix icon・hint 等）を「1:1」にすると明記（§3 注意・§6-10）。ただし**似て非なる 8 個の decoration を 1 つに統合した瞬間の見た目差はテストで検出不能**（decoration 非検証）。設計書も認めており、実装レビュー工程を必須化している点は妥当。
- 推奨修正: §7 検証計画に「ConnectionInputStyle の引数マッピングは実装レビューで HEAD と diff 確認」を明記（既に §7-8 にあるが、**差分確認の具体手順（`diff <(git show HEAD:... ) <(新実装)` 等）**を添える）。

### 3.5 【軽微】実測とのズレ

- 「テスト 3 本（451 行）」: 実測 connection_form_screen_test.dart は **459 行**。本質影響なし。
- §1.4「testWidgets 10 本」: 実測 10 本 ✓（一致）。
- §1.1「import 18 本」: 実測 **18** ✓（一致）。
- `_loadExistingConnection` の同期 getById（L70-87）: 設計の「State に残す（写経）」✓。migration E2E テスト（field4 の controller.text == `/legacy/tmux`）への言及 ✓。

### 3.6 元の批判は解消されたか → 構造は質的・blocker なし（ただし 3.2・3.3 の配線明文化が必要）

- `connectionFormSshClientFactoryProvider` を tester へ移し、元ファイル `export ... show` で再供給（P2 compat と同型）は、テスト 3 ファイル（overrideWith 3 箇所・import パス維持）と整合 ✓。
- 全分割を「公開クラス（feature 内部利用）への合成」で行う（part/mixin 不使用）✓。
- `appendable` 記述は最小限の修正で実装可能な水準。ブロッカーなし。

---

## 4. browser-and-dashboard.md（file_browser_screen.dart + dashboard_screen.dart）

### 4.1 【重大】`_FileBrowserAppBar` / `_FileBrowserBody` / `_FileBrowserUploadTransferPanel` を「private widget（同ディレクトリ）」として別ファイルへ移すのは不可（1.1 と同型）

- 事実: 設計書 §2.1 は
  - `file_browser_app_bar.dart`: **`_FileBrowserAppBar`（private widget・同ディレクトリ）** と明記
  - `file_browser_body.dart`: **`_FileBrowserBody`（private widget・同ディレクトリ）**
  - `file_browser_upload_flow.dart`: `_FileBrowserUploadTransferPanel`（private widget）
  と呼出元は改修後の `_FileBrowserScreenState`（file_browser_screen.dart）。
- さらに実測で `_buildAppBar`（L133-264）は `ref.watch(fileTransferProvider)`（L168）・`ref.read(fileBrowserProvider.notifier).toggleShowHidden/setSort`（L204/219）を**直接使う**。widget 化すると `ref` の受け渡し（ConsumerWidget 化 or コールバック注入）も必要。
- 評価: private のまま移動＝コンパイル不能。ref 依存は private を public 化しただけでは解決せず（非 Consumer の StatelessWidget に埋め込むか props 化）。
- 必須修正: 3 つの view を **public（@internal）ConsumerWidget 化**（またはコールバック+X 引数化）し、呼出元から import する構成に明記。§2.1 の「private widget」という表現を全箇所修正。

### 4.2 【重大】`runFileBrowserUpload` をトップレベル関数にするが、`ref`・`context.mounted`・SnackBar の受け渡し契約が未定義

- 事実: `_handleUpload`（L266-388）は 123 行で、内部に
  - `ref.read(fileTransferProvider.notifier)`（L276）/ `ref.read(fileTransferProvider)`（L280/295/296/324）
  - `!mounted` チェック 5 箇所（L274/279/303/323/359）
  - `ScaffoldMessenger.of(context)` 7 箇所（L282/306/310/319/334/348/363）
  - `ref.read(fileBrowserProvider.notifier).refresh()`（L385）
  を**多数使う**。トップレベル関数化には `WidgetRef` と `BuildContext` と `mounted` 判定の持ち方（現行 `!mounted` = State.mounted）の置換が必須。
- 設計書 §3.1 は「`runFileBrowserUpload`（`context` と `remoteDir` を引数で受ける）」とだけ書き、§6-3 で「await 後は context.mounted チェック（現行 `if (!mounted) return;` の等価）」に言及するが、**WidgetRef の受け渡しが表から漏れている**。
- 評価: `context.mounted` への置換は等価で可能だが、**`ref` を 9 箇所で使う関数の引数に `WidgetRef` が含まれないと実装不能**。これは「移動のみ」ではなく「シグネチャ変更を伴う設計変更」である。
- 必須修正: `runFileBrowserUpload(BuildContext, WidgetRef ref, String remoteDir)` と明記。現行 `!mounted` → `context.mounted` の置換箇所（5 箇所）も列挙。

### 4.3 【重大】`FileBrowserDownloadFlow` の `_downloadFlowSub` / `_sheetOpen` 移設は「状態所有権の単一化」に反する可能性

- 事実: 設計書は `_downloadFlowSub`（ProviderSubscription）と `_sheetOpen` を **FileBrowserDownloadFlow が単一所有者**とする（§1.1・§2.1・§5）。しかし `_handleAwaitingOverwrite`（L744-757）と `_showDownloadProgressSheet`（L758-771）は **context を使って `showOverwriteConfirmDialog` / `showTransferProgressSheet` を呼ぶ**（実測 L765 等）。flow が context を持つか、それとも State が渡すかは「未確定点 2」で (a)(b) の 2 択として critics に丸投げ。
- 評価: これは**設計書の自己完結度不足**ではなく、分離境界の妥当な論点ではある。ただし、**flow に context を持たせると State.dispose後にフレーム外で context を使う（use_build_context_synchronously）リスク**、逆に State がコールバックで渡すと flow の「単一所有者」が形骸化する。設計書は「(b) 引数渡しを推奨」と明示しつつ、**listen コールバック（flow 内）から State へ context を返す経路を図示していない**。
- 推奨修正: 「flow の API は `attach(WidgetRef)` + `startSingleTmp/startBatch` + `handleAwaitingOverwrite(BuildContext)` 等、**context は必ずメソッド引数**で取り、flow は context を保持しない」を §5 に明記。`_sheetOpen` は flow 内 bool で維持可（破棄は dispose 時）と明記。

### 4.4 【中】`_buildTransferPanel`（責務 E）を upload_flow へ移すのは命名・責務の片寄り（download も表示する）

- 事実: `_buildTransferPanel`（L390-453）は `transferState.items[i].status == uploading` の active 行を表示するが、**表示対象は `fileTransferProvider`（upload path）**。download の進捗は別経路（`showTransferProgressSheet` = widgets/file_browser/transfer_progress_sheet.dart、既抽出）。実測で「転送中パネル」は upload 専用であることは確認。
- 評価: 設計書が E を upload_flow に含める判断は**実体と一致**（upload 専用）。命名だけ「transfer panel」でなく「upload panel」にすれば誤解が減る。軽微。

### 4.5 【中】`SessionHistoryCard` の public 化に伴う `find.byType(_SessionHistoryCard)` の影響はなし — ただし DashboardScreen 側のコードが Consumer 依存

- 事実: dashboard テスト 2 本（herdr_workspace / damaged_key）は `find.text` / `find.byIcon` のみで **byType(_SessionHistoryCard) を参照しない**（実測）。設計書の「public 化」は安全。
- ただし `_SessionHistoryCard` は ConsumerWidget（build 内 `ref.watch(connectionsProvider)` / `ref.watch(keysProvider)`、実測 L193/L197）。新ファイルへ移す際は同様に ConsumerWidget 化が必要だが、設計書は §6-5 で「ConsumerWidget にし現行 build を無改変移設」と明記 ✓。
- 推奨修正: なし（§4.5 は確認済み事項として記録）。

### 4.6 【中】dashboard の `_navigateToTerminal` 等 3 関数は呼出元維持 — ただしテストが固定する nav 経路（touchSession→push）の言及不足

- 事実: dashboard のテストは `_navigateToTerminal` を直接検証しない（実測: damaged_key / herdr_workspace ともナビテスタなし）。設計書は §1.2 で「touchSession + TerminalScreen push」を列挙し、§3.2 は「残す」。
- 評価: `DashboardScreen` は ConsumerWidget のまま残す設計で**呼出元（home_screen.dart:54 の IndexedStack）も不変**。リスクは低い。ただし `touchSession` の順序（L137-163）は connections 側の `_connectToServer`（updateLastConnected→touchSession→push）と同型のため、共通の注意書きを 1 行置く価値がある。軽微。

### 4.7 元の批判は解消されたか → 構造は妥当だが 4.1・4.2 がブロッカー

- 「共通 abstract を作らない」判断（§2.4）は P2 critique §2.3（過剰分解批判）を踏まえて正しい。`AsyncSliverList<T>` 型の grab-bag を忌避した点も良い。
- 実測不一致: `_buildFileListTile`（L586-601）を body 内部へ、`_SortSelection`（L978-983）を app_bar へ移す — 実測一致 ✓。

---

## 5. shell-and-panes.md（home_screen / notification_panes_screen / markdown_preview_screen）

### 5.1 【中】デッドコード（`_TerminalTab` 等 540 行）の「削除（案A）」は挙動不変で正しいが、l10n キー 9 種の扱いの記述が不正確

- 事実: `_TerminalTab` クラスのインスタンス化はゼロ（rg で定義 4 箇所のみ・IndexedStack children 非登録）を実測確認。l10n キー（homeActiveSessions/homeReloadSessions/homeNoActiveSessions/homeConnectToServerToStartTerminal/homeCloseSessionTitle/homeCloseSessionMessage/homeAttached/homeDetached/homeLastWindow）が home のデッドコードでのみ使われることも実測一致（lib 他・test 参照ゼロ）。
- 評価: 削除自体は「挙動不変」で正しい。ただし設計書は「arb 生成物は変更禁止のためキーは残す」と言うが、**app_localizations*.dart 生成物にキーが残ることと、`context.l10n.homeActiveSessions` といった getter が未使用になる**ことで、`flutter analyze` が**未使用警告を出さないか**の確認が省略されている（Dart では生成 getter は未使用でも警告なしの想定だが、検証計画に含めないのは甘い）。
- 推奨修正: 削除後の `flutter analyze` で未使用 import や生成 getter の警告が出ないことを検証計画に追加。案 B（移設）と案 A（削除）の**実装順序・行数見積**（削除なら home ≈325 / 移設なら各 500 未満）も表に反映済みだが、「他人が実装する場合どちらを選ぶか」のデフォルトが明確でないため、`**推奨: 案 A 削除**（git 8aab2ec 以前から復元可）を明記済み ✓ — 優先度はそのまま。

### 5.2 【中】`HomeBottomNavBar` / `AlertPaneCard` / `MarkdownPreviewBody` 等の「@internal 昇格」は P2 で「承認済み」と書くが、実績ゼロで lint リスクがある

- 事実: P2 実装（HEAD）で `@internal` 使用は **0 件**（`rg "@internal" lib/`）。P2 critique §2.5 は「internal 化＋テストは同ライブラリ内テストでも可能な点を**検討余地として提示**」であり、「承認済み」ではない。`@internal`（package:meta）を別ファイル（別ライブラリ）の public シンボルに付けると、同パッケージ内からは使用可能だが **`invalid_use_of_internal_member` lint が analyzer で警告**になる（analysis_options で内部向け設定は実測ゼロ）。
- 評価: 設計書 §8-3 は「private widget の公開化は lint 回避の標準手段として提示」とするが、**確実なのは「public 化（@internal なし）」**であり、@internal は同一ライブラリ外利用で警告を出す可能性が高い。特に `MarkdownPreviewBody` を State（markdown_preview_screen 側）から呼ぶ場合、**別ファイル＝別ライブラリ**なので警告対象。
- 推奨修正: @internal ではなく素の public 化（または `// ignore:` を明示的に添付）を採る。P2 実績ゼロの事実を設計書に反映し、「P2 で承認済み」という記述を削除。

### 5.3 【中】markdown の `MarkdownPreviewScreen.rawScrollKey/renderedScrollKey` は「クラス静的参照」の維持で合っているが、**static key が body（別ファイル）から参照される経路**が設計にない

- 事実: テストは `find.byKey(MarkdownPreviewScreen.renderedScrollKey)` / `rawScrollKey`（markdown_preview_screen_test L246/251/270）を**クラス静的に**参照。設計書 §4 は「static keys は実装先クラスに残し、シムから export」と明記 ✓。
- 評価: **static key は `markdown_preview/markdown_preview_screen.dart` の `MarkdownPreviewScreen` クラスに残す**ことになる。しかし描画先の `markdown_preview_body.dart`（別ファイル）が `MarkdownPreviewScreen.rawScrollKey` を参照するには、**body 側が screen クラスを import する**必要がある。設計書 §6 リスク3 は「body は `MarkdownPreviewScreen.rawScrollKey` を参照」と書くが、**依存グラフ（§2.3）は `markdown_preview_screen.dart → body` 一方向のみで、`body → screen` の逆辺が明記されていない**。body → screen（実装クラス）の import で循環は生じない（screen は body を import せず、シムが両者を export）ので**実装可能**だが、依存グラフの欠落は書面上のミス。
- 推奨修正: §2.3 のグラフに `markdown_preview_body.dart → markdown_preview_screen.dart`（static key 参照のため）を追記。

### 5.4 【中】notification の `_isRefreshing` は State に残す方針 — ただし `finally { if (mounted) setState(false) }` の実測位置が正しいか確認済み

- 事実: `_refresh`（L35-45）は finally で `mounted` チェック。実測で **L43 `if (mounted)`** を確認 ✓。設計書は「finally mounted（L43）は State 内に残す」と明記 ✓。
- 評価: 正しい。アラート一覧・loading・error は provider 側（AlertPanesNotifier）不変 ✓。

### 5.5 【重大】`home_screen.dart` のシム化と connections のシム化による**相互循環**（0-3 で横断指摘したもの）の個別記述が欠落

- 事実: shell 設計は home_screen.dart → `export 'home/home_screen.dart'` + `export 'home/home_tab_provider.dart'`。connections 設計は connections_screen.dart → `export 'connection_list_screen.dart'`。実装後、`connection_list_screen` が `import '../home_screen.dart'`（シム）で currentTabProvider を参照（現行 L10/L172 と同等）、home 側 `home/home_screen.dart` が `import '../connections/connections_screen.dart'`（シム）で ConnectionsScreen を build（現行 home L19/L52 と同等）→ **互いに相手のシムを import する 2 設計書間の循環**が現行より 1 段深くなる（シム → 実装 → シム）。
- 評価: Dart で循環 import はコンパイル可能（現行が存在証明）なので即死はないが、**シムの export が絡むと名前解決の順序が実装順に依存**する。shell 設計書は「export は show で明示」「home_tab_provider は他画面を import せず」と防御はしているが、**connections 側のシムも同時に export する**事実への言及がない。
- 推奨修正: `currentTabProvider` の参照を**home_screen シム経由ではなく `home/home_tab_provider.dart` を直接 import** する代替を提示（connections 設計の §6-6 と連結）。そうすれば connections → home シムの依存が消え、循環の深さが現行並みに戻る。

### 5.6 【軽微】実測とのズレ

- 「task 説明の関連テスト 2 本のうち file_browser_download_flow_test は markdown を一切参照しない」: **実測一致** ✓（download_flow_test の import は markdown なし）。良い指摘。
- markdown_preview_screen_test.dart（828 行）の該当テスト名（基本表示/H-3/トグル/比率連動/状態表示6本/画像ガード/言語別ハイライト/リンクガード）は**実測一致** ✓。
- `MarkdownCodeBlock`（L504-533）は public でテストが `find.byType(MarkdownCodeBlock)` — 実測一致 ✓。

---

## 6. 設計者別サマリ（必須修正＝ブロッキング / 推奨修正）

### connections-screen.md
- **必須修正（ブロッキング）**
  1. §2/§3.2-3.8 の「private のまま別ファイルへ移動」を全削除し、**public（@internal）化**と import 構成を明記。`_ConnectionCard`/`_SearchField`/`_showSortDialog`/`_SortOptionTile`/`_NewSessionDialog`/`_CardHeader`/`_ExpandedSessionsPanel`/`_SessionRow`（1.1）。
  2. operations の**戻り値型と `updateSessionsFromDomain` への受け渡し**（ref 非依存の維持）を §3.7/§5 に明記（1.2）。
- **推奨修正**
  - liveWindowCounts / statusColor の導出所有者を 1 つに確定（1.3）。
  - 循環 import の実装順序と検証手順をリーダーへ明示（1.4）。
  - シェル行数を「~430（超時 ~330）」と双値化（1.5）。

### ansi-text-view.md
- **必須修正（ブロッキング）**: なし。
- **推奨修正**
  1. `updatePalette` が新規 API（parser 再生成＋invalidate）であることを明記（2.2）。
  2. 協調オブジェクトの生成＝initState/late final（テスト直接 new 対応）の規約を §3 に 1 行追加（2.3 補足）。
  3. 「プロパティ 21」→実測 18 に修正（2.5）。+31% の分割粒度の緩和要件を §2 に 1 行（2.1）。

### connection-form.md
- **必須修正（ブロッキング）**: なし。
- **推奨修正**
  1. `ConnectionSaver` への notifier 受け渡し契約（ref.read を State が行う）を §5 に明記（3.2）。
  2. 各セクション内の子順序不変（Port/Username の Row 横並び含む）を §3 に追記（3.3）。
  3. テスト 459 行表記への修正（3.5・軽微）。

### browser-and-dashboard.md
- **必須修正（ブロッキング）**
  1. `_FileBrowserAppBar`/`_FileBrowserBody`/`_FileBrowserUploadTransferPanel` を **public(@internal) ConsumerWidget 化**に変更（4.1）。
  2. `runFileBrowserUpload(BuildContext, WidgetRef, String)` のシグネチャと `!mounted`→`context.mounted` 置換 5 箇所を明記（4.2）。
  3. `FileBrowserDownloadFlow` の context 保持方針（不保持・メソッド引数）を §5 に確定（4.3）。
- **推奨修正**
  - `_buildTransferPanel` の命名を upload に（4.4・軽微）。
  - dashboard の `touchSession→push` 順序の注意書き 1 行（4.6・軽微）。

### shell-and-panes.md
- **必須修正（ブロッキング）**: なし。
- **推奨修正**
  1. @internal 昇格の記述を「素の public 化 or ignore 明示」に修正し「P2 で承認済み」を削除（5.2）。
  2. $2.3 の依存グラフに `markdown_preview_body → markdown_preview_screen`（static key 参照）を追記（5.3）。
  3. home シム ⇄ connections シムの相互循環を解消する直接 import 代替を提示（5.5）。
  4. デッドコード削除後の analyze 警告確認を検証計画へ（5.1）。

---

## 7. 検証計画の妥当性（観点 i）

| 設計書 | 検証コマンド | 対象テスト | 評価 |
|---|---|---|---|
| connections | format/analyze/対象3/全体/`git diff HEAD -- test/` 空/generate check/wc | session_kill・herdr・damaged_key | **妥当**。ただし対象 3 本だけでなく `terminal_screen_contract_test`（ConnectionsScreen が TerminalScreen へ遷移する側）も含めるべき |
| ansi | format/analyze/全体/重点12+1/diff 空/generate | ansi 系 5 + terminal_screen 系 8 | **妥当**（13 本の列挙は実測と一致） |
| form | format/analyze/connections 系/全体/repro/diff 空/generate/写経レビュー | form 3 + connections 4 | **妥当**。repro_bug5 の「(read-only) なし」検証を内容に含めている ✓ |
| browser | format/analyze/全体/diff 空/generate/make build-apk 代替 | file_browser 5 + dashboard 2 + contract | **妥当**。ただし `transfer_progress_sheet` パネルの「under 時のキャンセル」テスト（upload_test L212-）を重点に含めるべき |
| shell | format/analyze/全体/diff 空/generate/重点 4 | markdown 2 + widget_test + provider | **妥当**。`NotificationPanesScreen` 系テストが実存しない（rg 0 件）点を正しく前提化 ✓ |

共通: `dart format --output=none --set-exit-if-changed .` / `flutter analyze` / `flutter test --exclude-tags=repro` / `git diff HEAD -- test/` 空 / `dart tool/generate_herdr_protocols.dart --check` の 5 点は全書で過不足なし。

---

## 8. 事実と推測の区別（レビュー側の注記）

- **事実**: 本レビューで【事実】としたものは HEAD a86fbdd の実ファイル・テスト・P2 実装に対する grep/read の直接観測（行番号付き）。特に 1.1（private スコープ規則）、1.2（updateSessionsFromDomain の配線欠落）、4.1/4.2（browser の private widget・ref 引数欠落）、5.6（download_flow_test 実測一致）はコードと Dart 仕様から直接確定的。
- **推測**: 1.4（シム 2 本の相互循環のコンパイル可能性）、1.5（シェル +20% で 521）、2.1（分割粒度の緩和リスク）、4.3（flow への context 保持リスク）、5.2（@internal の lint 警告挙動）は実装前に観測不能の見積・判断であり、設計書側の「推測」ラベルと同格。
- **未検証（要実装時確認）**: AnsiParser のインクリメンタル再パース（ansi_parser.dart 内部実装）、form の `ConnectionInputStyle` 引数マッピングの視覚等価性、browser の `runFileBrowserUpload` の SnackBar 文言・色（現行値の写経）は実装レビューでのみ確定。

---

## 9. 重要指摘トップ5（リーダー向け要約・報告用）

1. **【重大・横断】「private クラスを別ファイルへ private のまま移動」は Dart の可視性規則でコンパイル不能**。connections-screen（`_ConnectionCard` 等 8 シンボル）と browser-and-dashboard（`_FileBrowserAppBar` 等 3 シンボル）が該当。public（@internal）化を必須修正に。
2. **【重大・browser】`runFileBrowserUpload` は 9 箇所の `ref.read` を使うのに引数に WidgetRef が無い**。`_handleUpload` の「移動のみ」は不可能で、シグネチャ変更を伴う設計変更として明記せよ。
3. **【中・横断】シム化の相互不整合**: connections と home の両シムが互いを import する循環が現行より深くなる。`currentTabProvider` は home シム経由でなく `home/home_tab_provider.dart` 直接 import にする代替を両設計書で連結せよ。
4. **【中・ansi】行数 +31% と `updatePalette` 新規 API**。2,180 行は P2 の批判水準（+17%）を大幅超。updatePalette は AnsiParser に存在しない新設メソッドであり、parser 再生成との等価性を明記せよ。
5. **【中・shell】@internal 昇格は P2 で実績ゼロ**。「P2 で承認済み」は P2 critique §2.5 の「検討余地」の誤読。素の public 化を推奨し、lint 警告リスクを検証計画へ加えよ。

（番外・事実誤認のまとめ: ansi の props 21→実測 18 / form のテスト 451→実測 459 行 / shell の「P2 承認済み @internal」→実測 0 件。いずれも軽微で骨子には影響しない。良好だった実測: connections の kill→reload・herdr 流れ・damaged key、ansi のテスト固定 13 カテゴリ、form の TextFormField index、markdown の static key/MarkdownCodeBlock、shell のデッドコード断定と download_flow_test 非依存指摘。）