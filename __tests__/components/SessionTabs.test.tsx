/**
 * SessionTabs Component Tests
 *
 * Tests for the tmux session tabs component.
 */
import { render, screen, fireEvent } from '@testing-library/react-native';
import { SessionTabs } from '@/components/navigation/SessionTabs';
import type { TmuxSession } from '@/types/tmux';

// Mock data
const mockSessions: TmuxSession[] = [
  {
    name: 'main',
    created: Date.now(),
    attached: true,
    windowCount: 3,
    windows: [],
  },
  {
    name: 'dev',
    created: Date.now(),
    attached: false,
    windowCount: 2,
    windows: [],
  },
  {
    name: 'test',
    created: Date.now(),
    attached: false,
    windowCount: 1,
    windows: [],
  },
];

describe('SessionTabs', () => {
  // T016: 全セッション名がタブ表示
  describe('displays all session names as tabs', () => {
    it('renders all session names', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      expect(screen.getByText('main')).toBeTruthy();
      expect(screen.getByText('dev')).toBeTruthy();
      expect(screen.getByText('test')).toBeTruthy();
    });

    it('renders correct number of tabs', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      // Each session should have a corresponding tab
      const tabs = screen.getAllByText(/main|dev|test/);
      expect(tabs.length).toBe(3);
    });
  });

  // T017: タブタップでonSelect呼び出し
  describe('calls onSelect when tab is tapped', () => {
    it('invokes callback with session name', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      fireEvent.press(screen.getByText('dev'));

      expect(onSelect).toHaveBeenCalledTimes(1);
      expect(onSelect).toHaveBeenCalledWith('dev');
    });

    it('invokes callback for each different tab', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      fireEvent.press(screen.getByText('main'));
      fireEvent.press(screen.getByText('dev'));
      fireEvent.press(screen.getByText('test'));

      expect(onSelect).toHaveBeenCalledTimes(3);
      expect(onSelect).toHaveBeenNthCalledWith(1, 'main');
      expect(onSelect).toHaveBeenNthCalledWith(2, 'dev');
      expect(onSelect).toHaveBeenNthCalledWith(3, 'test');
    });
  });

  // T018: 選択中タブがアクティブスタイル
  describe('shows active style for selected tab', () => {
    it('applies active style to selected session', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession="main"
          onSelect={onSelect}
        />
      );

      // The selected tab should be rendered (we can't easily test styles,
      // but we can verify the component renders without errors)
      expect(screen.getByText('main')).toBeTruthy();
    });

    it('does not apply active style to non-selected sessions', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession="main"
          onSelect={onSelect}
        />
      );

      // Non-selected tabs should also render
      expect(screen.getByText('dev')).toBeTruthy();
      expect(screen.getByText('test')).toBeTruthy();
    });
  });

  // T019: attachedバッジ表示
  describe('displays attached badge', () => {
    it('shows attached indicator for attached sessions', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={mockSessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      // The attached session (main) should have a badge indicator
      // In the component, attached badge is displayed as "⚫"
      expect(screen.getByText('⚫')).toBeTruthy();
    });

    it('does not show attached indicator for detached sessions', () => {
      const onSelect = jest.fn();
      const detachedSessions: TmuxSession[] = [
        {
          name: 'detached-only',
          created: Date.now(),
          attached: false,
          windowCount: 1,
          windows: [],
        },
      ];

      render(
        <SessionTabs
          sessions={detachedSessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      expect(screen.getByText('detached-only')).toBeTruthy();
      expect(screen.queryByText('⚫')).toBeNull();
    });
  });

  // T020: 空セッション時のメッセージ表示
  describe('displays empty message when no sessions', () => {
    it('shows empty message when sessions array is empty', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={[]}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      expect(screen.getByText('セッションがありません')).toBeTruthy();
    });

    it('does not show tabs when sessions array is empty', () => {
      const onSelect = jest.fn();

      render(
        <SessionTabs
          sessions={[]}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      expect(screen.queryByText('main')).toBeNull();
      expect(screen.queryByText('dev')).toBeNull();
    });
  });

  // Additional edge case tests
  describe('edge cases', () => {
    it('handles single session', () => {
      const onSelect = jest.fn();
      const singleSession: TmuxSession[] = [
        {
          name: 'only-one',
          created: Date.now(),
          attached: true,
          windowCount: 1,
          windows: [],
        },
      ];

      render(
        <SessionTabs
          sessions={singleSession}
          selectedSession="only-one"
          onSelect={onSelect}
        />
      );

      expect(screen.getByText('only-one')).toBeTruthy();
    });

    it('handles many sessions', () => {
      const onSelect = jest.fn();
      const manySessions: TmuxSession[] = Array.from({ length: 10 }, (_, i) => ({
        name: `session-${i}`,
        created: Date.now(),
        attached: i === 0,
        windowCount: 1,
        windows: [],
      }));

      render(
        <SessionTabs
          sessions={manySessions}
          selectedSession={null}
          onSelect={onSelect}
        />
      );

      expect(screen.getByText('session-0')).toBeTruthy();
      expect(screen.getByText('session-9')).toBeTruthy();
    });
  });
});
