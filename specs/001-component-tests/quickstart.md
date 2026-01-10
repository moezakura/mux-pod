# Quickstart: Component Tests

**Branch**: `001-component-tests`
**Date**: 2026-01-10

## Prerequisites

- Node.js 18+
- pnpm installed
- Project dependencies installed (`pnpm install`)

## Quick Commands

```bash
# Run all tests
pnpm test

# Run specific test file
pnpm test ConnectionCard

# Run tests in watch mode
pnpm test --watch

# Run with coverage
pnpm test --coverage
```

## Directory Structure

```
__tests__/
└── components/
    ├── ConnectionCard.test.tsx
    ├── TerminalView.test.tsx
    ├── SpecialKeys.test.tsx
    └── SessionTabs.test.tsx
```

## Test File Template

```typescript
import { render, screen, fireEvent } from '@testing-library/react-native';
import { ComponentName } from '@/components/path/ComponentName';

// Mock icons
jest.mock('@expo/vector-icons', () => ({
  MaterialCommunityIcons: 'MaterialCommunityIcons',
  MaterialIcons: 'MaterialIcons',
}));

describe('ComponentName', () => {
  // Mock data
  const mockData = { /* ... */ };

  it('renders correctly', () => {
    render(<ComponentName {...mockData} />);
    expect(screen.getByText('expected text')).toBeTruthy();
  });

  it('handles user interaction', () => {
    const onPress = jest.fn();
    render(<ComponentName onPress={onPress} />);
    fireEvent.press(screen.getByTestId('button'));
    expect(onPress).toHaveBeenCalledTimes(1);
  });
});
```

## Common Patterns

### Testing Callback Invocation
```typescript
const onPress = jest.fn();
render(<Component onPress={onPress} />);
fireEvent.press(screen.getByTestId('target'));
expect(onPress).toHaveBeenCalledWith(expectedArg);
```

### Testing Conditional Rendering
```typescript
const { rerender } = render(<Component visible={false} />);
expect(screen.queryByText('Content')).toBeNull();

rerender(<Component visible={true} />);
expect(screen.getByText('Content')).toBeTruthy();
```

### Testing State Changes
```typescript
fireEvent.press(screen.getByText('Toggle'));
expect(screen.getByText('Toggle')).toHaveStyle({
  backgroundColor: expectedColor
});
```

## Troubleshooting

### "Cannot find module" errors
- Ensure `@/` path alias is configured in jest.config.js
- Check that moduleNameMapper includes `'^@/(.*)$': '<rootDir>/src/$1'`

### Icon-related errors
- Add icon mocks to test file or jest.setup.js

### Async state updates
- Use `waitFor` for async operations:
```typescript
await waitFor(() => {
  expect(screen.getByText('Updated')).toBeTruthy();
});
```

## Next Steps

1. Create test files in `__tests__/components/`
2. Run `pnpm test` to verify setup
3. Implement tests following spec.md acceptance scenarios
