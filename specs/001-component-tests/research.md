# Research: Component Tests

**Date**: 2026-01-10
**Branch**: `001-component-tests`

## Research Summary

コンポーネントテスト実装に必要な技術調査結果をまとめる。

---

## 1. React Native Testing Library Best Practices

### Decision
`@testing-library/react-native`を使用し、ユーザー視点のテストを記述する。

### Rationale
- Testing Libraryの哲学「実装詳細ではなく振る舞いをテストする」に従う
- `getByText`, `getByTestId`, `fireEvent`を活用したユーザー操作のシミュレーション
- アクセシビリティ重視のクエリ（`getByRole`, `getByLabelText`）を優先

### Alternatives Considered
| Alternative | Rejected Because |
|-------------|------------------|
| Enzyme | React 18+のサポートが不完全、メンテナンス停滞 |
| react-test-renderer | 低レベルすぎる、イベント処理が困難 |

---

## 2. @expo/vector-icons モック戦略

### Decision
`jest.mock('@expo/vector-icons')`でアイコンコンポーネントをダミーに置き換える。

### Rationale
- アイコンの表示自体はテスト対象外（視覚的要素）
- ネイティブモジュールのモック回避でテスト実行を高速化
- `MaterialCommunityIcons`と`MaterialIcons`両方をモック

### Implementation Pattern
```typescript
jest.mock('@expo/vector-icons', () => ({
  MaterialCommunityIcons: 'MaterialCommunityIcons',
  MaterialIcons: 'MaterialIcons',
}));
```

---

## 3. Pressable コンポーネントのテストパターン

### Decision
`fireEvent.press`を使用し、コールバック呼び出しを検証する。

### Rationale
- React NativeのPressableはonPressイベントで操作を受け付ける
- `fireEvent.press`が最も直接的で信頼性の高いアプローチ
- disabled状態の検証も可能

### Testing Pattern
```typescript
const onPress = jest.fn();
render(<Component onPress={onPress} />);
fireEvent.press(screen.getByTestId('button'));
expect(onPress).toHaveBeenCalledTimes(1);
```

---

## 4. FlatList/ScrollView のテストパターン

### Decision
`initialNumToRender`を考慮し、表示される要素のみをテストする。

### Rationale
- FlatListはパフォーマンス最適化のため全要素をレンダリングしない
- テストでは少量のデータ（5-10件）を使用して全要素表示を保証
- スクロール動作自体はネイティブ側の責務

### Alternatives Considered
| Alternative | Rejected Because |
|-------------|------------------|
| 全データモック | 大量データはテスト実行時間に影響 |
| スクロールイベント発火 | ネイティブ動作のシミュレーションは不安定 |

---

## 5. 状態変化のテストパターン

### Decision
`rerender`または`fireEvent`後に状態変化を確認する。

### Rationale
- SpecialKeysのCTRL/ALTモード切替はコンポーネント内部状態
- `fireEvent`後にスタイル変化（アクティブ状態）を確認
- 非同期状態更新は`waitFor`で対応

### Testing Pattern
```typescript
// CTRL mode toggle
fireEvent.press(screen.getByText('CTRL'));
// After press, button should show active state
expect(screen.getByText('CTRL')).toHaveStyle({ backgroundColor: colors.primary });
```

---

## 6. テストデータ（Fixtures）設計

### Decision
各テストファイル内にモックデータを定義し、必要に応じて共通ファイルに抽出する。

### Rationale
- 初期段階では各ファイル独立でシンプルに保つ
- 重複が3回以上発生したら共通化（Rule of Three）
- 型安全なモックデータで実際のデータ構造を反映

### Mock Data Examples
```typescript
// Connection mock
const mockConnection: Connection = {
  id: 'test-id',
  name: 'Test Server',
  host: 'example.com',
  port: 22,
  username: 'testuser',
  authMethod: 'password',
  timeout: 30,
  keepAliveInterval: 60,
  createdAt: Date.now(),
  updatedAt: Date.now(),
};

// TmuxSession mock
const mockSession: TmuxSession = {
  name: 'main',
  created: Date.now(),
  attached: true,
  windowCount: 2,
  windows: [],
};
```

---

## Unresolved Items

なし - 全ての技術的な疑問点は解決済み。
