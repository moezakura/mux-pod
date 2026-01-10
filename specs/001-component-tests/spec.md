# Feature Specification: Component Tests

**Feature Branch**: `001-component-tests`
**Created**: 2026-01-10
**Status**: Draft
**Input**: User description: "コンポーネントテスト追加。React Native Testing Library使用。ConnectionCard、TerminalView、SpecialKeys、SessionTabsのテスト。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - ConnectionCard Test Coverage (Priority: P1)

開発者として、ConnectionCardコンポーネントの動作を検証するテストが必要。接続カードは主要なナビゲーション要素であり、接続状態の表示・セッション展開・ユーザーインタラクションが正しく機能することを保証したい。

**Why this priority**: ConnectionCardはアプリの中核UIであり、ユーザーが最初に操作する要素。リグレッションを防ぐため最優先。

**Independent Test**: ConnectionCardのテストのみ実行して、カードの表示・タップ・展開・セッション選択が正しく動作することを検証可能。

**Acceptance Scenarios**:

1. **Given** 接続情報が渡された状態, **When** カードがレンダリングされる, **Then** 接続名・ホスト・ユーザー名が表示される
2. **Given** 接続状態が「connected」の状態, **When** カードを表示する, **Then** 接続中を示すステータスドットが緑色で表示される
3. **Given** セッション一覧がある状態, **When** カードをタップする, **Then** セッション一覧が展開表示される
4. **Given** セッション一覧が展開された状態, **When** セッションをタップする, **Then** onSelectSessionコールバックが呼ばれる
5. **Given** エラー状態の接続, **When** カードを表示する, **Then** エラーメッセージが表示される

---

### User Story 2 - SpecialKeys Test Coverage (Priority: P1)

開発者として、SpecialKeysコンポーネントの動作を検証するテストが必要。特殊キー入力はターミナル操作の要であり、ESC・TAB・CTRL・ALT等のキー送信が正しく機能することを保証したい。

**Why this priority**: ターミナル操作に必須の機能であり、キー入力の誤動作は致命的。

**Independent Test**: SpecialKeysのテストのみ実行して、各キーボタンのタップでコールバックが正しく呼ばれることを検証可能。

**Acceptance Scenarios**:

1. **Given** コンポーネントがレンダリングされた状態, **When** ESCボタンをタップする, **Then** onSendSpecialKeyが「Escape」で呼ばれる
2. **Given** コンポーネントがレンダリングされた状態, **When** TABボタンをタップする, **Then** onSendSpecialKeyが「Tab」で呼ばれる
3. **Given** CTRLモードがオフの状態, **When** CTRLボタンをタップする, **Then** CTRLモードがオンになりボタンがアクティブ表示になる
4. **Given** CTRLモードがオンの状態, **When** リテラルキー（例: /）をタップする, **Then** onSendCtrlが呼ばれCTRLモードがオフになる
5. **Given** disabled=trueの状態, **When** 任意のボタンをタップする, **Then** コールバックは呼ばれない

---

### User Story 3 - SessionTabs Test Coverage (Priority: P2)

開発者として、SessionTabsコンポーネントの動作を検証するテストが必要。セッションタブはナビゲーションの重要要素であり、タブ表示・選択状態・アタッチ状態が正しく機能することを保証したい。

**Why this priority**: ナビゲーション機能として重要だが、ConnectionCardより単純な構造。

**Independent Test**: SessionTabsのテストのみ実行して、タブ表示・選択・空状態の処理を検証可能。

**Acceptance Scenarios**:

1. **Given** 複数のセッションがある状態, **When** コンポーネントをレンダリングする, **Then** 全セッション名がタブとして表示される
2. **Given** セッションタブが表示された状態, **When** タブをタップする, **Then** onSelectコールバックがセッション名で呼ばれる
3. **Given** 選択中のセッションがある状態, **When** コンポーネントを表示する, **Then** 選択中タブがアクティブスタイルで表示される
4. **Given** attachedセッションがある状態, **When** コンポーネントを表示する, **Then** attachedバッジが表示される
5. **Given** セッションが0件の状態, **When** コンポーネントをレンダリングする, **Then** 「セッションがありません」メッセージが表示される

---

### User Story 4 - TerminalView Test Coverage (Priority: P2)

開発者として、TerminalViewコンポーネントの動作を検証するテストが必要。ターミナル表示はANSIカラー対応が必要であり、行・スパンの表示・スタイル適用が正しく機能することを保証したい。

**Why this priority**: コアUI機能だが、表示専用で複雑なインタラクションはない。

**Independent Test**: TerminalViewのテストのみ実行して、テキスト表示・ANSIスタイル適用・空行処理を検証可能。

**Acceptance Scenarios**:

1. **Given** テキストスパンを含む行データがある状態, **When** コンポーネントをレンダリングする, **Then** テキスト内容が表示される
2. **Given** 前景色が指定されたスパンがある状態, **When** コンポーネントをレンダリングする, **Then** 指定色でテキストが表示される
3. **Given** bold属性が指定されたスパンがある状態, **When** コンポーネントをレンダリングする, **Then** 太字でテキストが表示される
4. **Given** 空のスパン配列を持つ行がある状態, **When** コンポーネントをレンダリングする, **Then** 空行として適切な高さで表示される
5. **Given** カスタムテーマが指定された状態, **When** コンポーネントをレンダリングする, **Then** テーマの背景色が適用される

---

### Edge Cases

- ConnectionCardで長い接続名・ホスト名が渡された場合、適切に省略表示されるか？
- SpecialKeysでCTRLモードとALTモードの排他制御は正しく動作するか？
- SessionTabsで大量のセッション（10件以上）がある場合、スクロール可能か？
- TerminalViewで極端に長い行（1000文字以上）がある場合、適切にラップされるか？
- 各コンポーネントでundefined/nullのpropsが渡された場合、クラッシュしないか？

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: テストはReact Native Testing Libraryを使用して実装されること
- **FR-002**: 各コンポーネントテストは独立して実行可能であること
- **FR-003**: テストはプロジェクト既存のjest.config.jsとjest.setup.jsを使用すること
- **FR-004**: テストファイルは__tests__/components/ディレクトリに配置されること
- **FR-005**: 各テストはコンポーネントの主要機能（レンダリング・イベント処理・状態変化）をカバーすること
- **FR-006**: モックが必要な外部依存（アイコン等）は適切にモック化されること

### Key Entities

- **ConnectionCard**: 接続情報を表示するカード。接続状態・セッション一覧・エラー表示を含む
- **TerminalView**: ANSIカラー対応のターミナル表示。行とスパンで構成
- **SpecialKeys**: 特殊キー入力バー。ESC・TAB・CTRL・ALT・リテラルキーを含む
- **SessionTabs**: tmuxセッション一覧のタブ表示。選択状態・アタッチ状態を表示

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 4つのコンポーネント全てにテストファイルが存在すること
- **SC-002**: 各コンポーネントで最低5つのテストケースがパスすること
- **SC-003**: 全テストが`pnpm test`で正常に実行・完了すること
- **SC-004**: テストカバレッジがレンダリング・イベント・状態変化の主要パスを網羅していること

## Assumptions

- 既存のjest.config.jsとjest.setup.jsが正しく設定されている
- React Native Testing Libraryがプロジェクトに導入済み
- @expo/vector-iconsのモックが必要な場合は追加で設定する
- テスト実行環境はjest-expoプリセットを使用
