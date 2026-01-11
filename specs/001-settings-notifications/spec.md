# Feature Specification: Settings and Notifications Implementation

**Feature Branch**: `001-settings-notifications`
**Created**: 2026-01-11
**Status**: Draft
**Input**: 設定と通知機能を実装。settings_screen.dartのTODOコメント解決とnotification_rules_screenのルール保存実装。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Terminal Font Configuration (Priority: P1)

ユーザーはターミナルのフォントサイズとフォントファミリーを変更して、読みやすさを向上させたい。

**Why this priority**: ターミナル操作において視認性は最重要。ユーザーの環境や好みに合わせたカスタマイズは基本機能。

**Independent Test**: 設定画面でフォントサイズを変更し、アプリを再起動後も設定が保持されていることを確認できる。

**Acceptance Scenarios**:

1. **Given** 設定画面を開いている状態, **When** Font Sizeをタップ, **Then** フォントサイズ選択ダイアログが表示される
2. **Given** フォントサイズダイアログが表示されている状態, **When** サイズを選択して確定, **Then** 設定が保存され画面に反映される
3. **Given** 設定画面を開いている状態, **When** Font Familyをタップ, **Then** フォントファミリー選択ダイアログが表示される
4. **Given** フォントファミリーダイアログが表示されている状態, **When** フォントを選択して確定, **Then** 設定が保存され画面に反映される

---

### User Story 2 - Notification Rule Management (Priority: P1)

ユーザーはターミナル出力に対するパターンマッチ通知ルールを作成・保存し、重要なイベントを見逃さないようにしたい。

**Why this priority**: 通知機能はMuxPodの差別化要素であり、リモートサーバー監視のコア機能。

**Independent Test**: 新しい通知ルールを作成してアプリを再起動後、ルールが保持されていることを確認できる。

**Acceptance Scenarios**:

1. **Given** 通知ルール画面を開いている状態, **When** FABをタップ, **Then** ルール作成ダイアログが表示される
2. **Given** ルール作成ダイアログでフォームを入力した状態, **When** Saveをタップ, **Then** ルールが保存されリストに表示される
3. **Given** ルールが1つ以上存在する状態, **When** 画面を開く, **Then** 保存されたルールがリストに表示される
4. **Given** ルールリストが表示されている状態, **When** ルールをタップ, **Then** 編集ダイアログが表示される
5. **Given** ルールリストが表示されている状態, **When** ルールを左スワイプ, **Then** 削除確認後にルールが削除される

---

### User Story 3 - Behavior Settings Persistence (Priority: P2)

ユーザーはHaptic FeedbackやKeep Screen Onなどの動作設定を変更し、好みに合わせた操作感を得たい。

**Why this priority**: UXに直接影響するが、デフォルト値でも使用可能。

**Independent Test**: Haptic Feedbackをオフにしてアプリを再起動後、オフのままであることを確認できる。

**Acceptance Scenarios**:

1. **Given** 設定画面を開いている状態, **When** Haptic Feedbackトグルを切り替え, **Then** 設定が即座に保存される
2. **Given** 設定画面を開いている状態, **When** Keep Screen Onトグルを切り替え, **Then** 設定が即座に保存される
3. **Given** 設定を変更した状態, **When** アプリを再起動, **Then** 変更した設定が保持されている

---

### User Story 4 - Theme Selection (Priority: P2)

ユーザーはアプリのテーマ（ダーク/ライト）を変更して、好みや環境に合わせた表示にしたい。

**Why this priority**: 視認性とUXに影響するが、デフォルト（ダーク）で多くのユーザーに対応可能。

**Independent Test**: テーマをライトに変更し、アプリ全体の表示が切り替わることを確認できる。

**Acceptance Scenarios**:

1. **Given** 設定画面を開いている状態, **When** Themeをタップ, **Then** テーマ選択ダイアログが表示される
2. **Given** テーマ選択ダイアログが表示されている状態, **When** テーマを選択して確定, **Then** アプリ全体のテーマが即座に切り替わる

---

### User Story 5 - External Links (Priority: P3)

ユーザーはアプリのソースコードリンクをタップして、外部ブラウザでGitHubリポジトリを開きたい。

**Why this priority**: 補助的な機能であり、コア機能ではない。

**Independent Test**: Source Codeをタップして外部ブラウザでGitHubが開くことを確認できる。

**Acceptance Scenarios**:

1. **Given** 設定画面のAboutセクションが表示されている状態, **When** Source Codeをタップ, **Then** 外部ブラウザでGitHubリポジトリが開く

---

### Edge Cases

- フォントサイズが極端に小さい/大きい場合のターミナル表示は正常か？
- 正規表現として不正なパターンが入力された場合のバリデーションは機能するか？
- 通知ルールの名前やパターンが空の場合のエラーハンドリングは適切か？
- 大量のルール（50件以上）が存在する場合のリスト表示パフォーマンスは問題ないか？
- オフライン状態でGitHubリンクをタップした場合の挙動は適切か？

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムは設定画面からフォントサイズを変更できなければならない（選択肢: 10, 12, 14, 16, 18, 20pt）
- **FR-002**: システムは設定画面からフォントファミリーを変更できなければならない（選択肢: JetBrains Mono, Fira Code, Source Code Pro, Roboto Mono）
- **FR-003**: システムはHaptic Feedbackのオン/オフ設定を永続化しなければならない
- **FR-004**: システムはKeep Screen Onのオン/オフ設定を永続化しなければならない
- **FR-005**: システムは設定画面からテーマ（Dark/Light/System）を変更できなければならない
- **FR-006**: システムはSource Codeリンクタップ時に外部ブラウザでURLを開かなければならない
- **FR-007**: システムは通知ルールの作成・編集・削除ができなければならない
- **FR-008**: システムは通知ルールを永続化し、アプリ再起動後も保持しなければならない
- **FR-009**: システムは通知ルールフォームで正規表現の有効性を検証しなければならない
- **FR-010**: システムは通知ルールの一覧を表示し、各ルールの有効/無効を切り替えられなければならない

### Key Entities

- **AppSettings**: アプリ全体の設定（フォントサイズ、フォントファミリー、ダークモード、バイブレーション有効、画面オン維持など）
- **NotificationRule**: 通知ルール（ID、名前、パターン、正規表現フラグ、有効フラグ、バイブレーションフラグなど）

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: ユーザーは3タップ以内でフォントサイズまたはフォントファミリーを変更できる
- **SC-002**: 設定変更は即座に（1秒以内に）保存され、アプリ再起動後も100%保持される
- **SC-003**: 通知ルールの作成は30秒以内に完了できる
- **SC-004**: 50件のルールを持つリストでも、画面表示に2秒以上かからない
- **SC-005**: すべてのフォーム入力にバリデーションエラーが即座に表示される

## Assumptions

- フォントサイズの選択肢は10-20ptの範囲で6段階とする（業界標準）
- フォントファミリーの選択肢は一般的なプログラミングフォント4種類とする
- テーマ選択にはSystem（OS設定に従う）オプションを含める
- GitHubのURLは現在のリポジトリURL（https://github.com/muxpod）を使用する
- 通知ルールの最大数に制限は設けない（パフォーマンスが問題になった場合は再検討）
