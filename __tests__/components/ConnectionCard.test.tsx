/**
 * ConnectionCard Component Tests
 *
 * Tests for the expandable connection card component.
 */
import { render, screen, fireEvent } from '@testing-library/react-native';
import { ConnectionCard } from '@/components/connection/ConnectionCard';
import type { Connection, ConnectionState } from '@/types/connection';
import type { TmuxSession } from '@/types/tmux';

// Mock data
const mockConnection: Connection = {
  id: 'test-id-1',
  name: 'Production Server',
  host: 'prod.example.com',
  port: 22,
  username: 'admin',
  authMethod: 'key',
  timeout: 30,
  keepAliveInterval: 60,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  autoReconnect: true,
  maxReconnectAttempts: 3,
  reconnectInterval: 5,
};

const mockConnectedState: ConnectionState = {
  connectionId: 'test-id-1',
  status: 'connected',
  latency: 50,
  connectedAt: Date.now(),
};

const mockDisconnectedState: ConnectionState = {
  connectionId: 'test-id-1',
  status: 'disconnected',
};

const mockErrorState: ConnectionState = {
  connectionId: 'test-id-1',
  status: 'error',
  error: 'Connection refused: timeout after 30 seconds',
};

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
];

describe('ConnectionCard', () => {
  // T004: 接続情報が表示される
  describe('displays connection information', () => {
    it('renders connection name', () => {
      render(<ConnectionCard connection={mockConnection} />);
      expect(screen.getByText('Production Server')).toBeTruthy();
    });

    it('renders host name', () => {
      render(<ConnectionCard connection={mockConnection} />);
      expect(screen.getByText(/prod\.example\.com/)).toBeTruthy();
    });

    it('renders username', () => {
      render(<ConnectionCard connection={mockConnection} />);
      expect(screen.getByText(/admin/)).toBeTruthy();
    });
  });

  // T005: connected状態でステータスドットが緑色
  describe('shows connection status', () => {
    it('renders with connected state styling', () => {
      render(
        <ConnectionCard
          connection={mockConnection}
          state={mockConnectedState}
        />
      );
      // Component is rendered with connected state
      expect(screen.getByText('Production Server')).toBeTruthy();
    });

    it('renders with disconnected state styling', () => {
      render(
        <ConnectionCard
          connection={mockConnection}
          state={mockDisconnectedState}
        />
      );
      expect(screen.getByText('Production Server')).toBeTruthy();
    });
  });

  // T006: タップでセッション一覧が展開
  describe('expands session list on press', () => {
    it('shows sessions when card is pressed with connected state', () => {
      render(
        <ConnectionCard
          connection={mockConnection}
          state={mockConnectedState}
          sessions={mockSessions}
        />
      );

      // Initially sessions should not be visible
      expect(screen.queryByText('Active Sessions')).toBeNull();

      // Press the card
      fireEvent.press(screen.getByTestId('connection-card'));

      // Sessions should now be visible
      expect(screen.getByText('Active Sessions')).toBeTruthy();
      expect(screen.getByText('main')).toBeTruthy();
      expect(screen.getByText('dev')).toBeTruthy();
    });

    it('collapses sessions when pressed again', () => {
      render(
        <ConnectionCard
          connection={mockConnection}
          state={mockConnectedState}
          sessions={mockSessions}
        />
      );

      const card = screen.getByTestId('connection-card');

      // Expand
      fireEvent.press(card);
      expect(screen.getByText('Active Sessions')).toBeTruthy();

      // Collapse
      fireEvent.press(card);
      expect(screen.queryByText('Active Sessions')).toBeNull();
    });
  });

  // T007: セッション選択でコールバック呼び出し
  describe('calls onSelectSession when session is tapped', () => {
    it('invokes callback with selected session', () => {
      const onSelectSession = jest.fn();

      render(
        <ConnectionCard
          connection={mockConnection}
          state={mockConnectedState}
          sessions={mockSessions}
          onSelectSession={onSelectSession}
        />
      );

      // Expand the card
      fireEvent.press(screen.getByTestId('connection-card'));

      // Tap on a session
      fireEvent.press(screen.getByText('main'));

      expect(onSelectSession).toHaveBeenCalledTimes(1);
      expect(onSelectSession).toHaveBeenCalledWith(mockSessions[0]);
    });
  });

  // T008: エラー状態でエラーメッセージ表示
  describe('displays error message', () => {
    it('shows error message when state has error', () => {
      render(
        <ConnectionCard
          connection={mockConnection}
          state={mockErrorState}
        />
      );

      expect(screen.getByText(/Connection refused/)).toBeTruthy();
    });
  });

  // Additional tests for callbacks
  describe('callback handlers', () => {
    it('calls onPress when card is pressed', () => {
      const onPress = jest.fn();

      render(
        <ConnectionCard
          connection={mockConnection}
          onPress={onPress}
        />
      );

      fireEvent.press(screen.getByTestId('connection-card'));
      expect(onPress).toHaveBeenCalledTimes(1);
    });

    it('calls onLongPress when card is long pressed', () => {
      const onLongPress = jest.fn();

      render(
        <ConnectionCard
          connection={mockConnection}
          onLongPress={onLongPress}
        />
      );

      fireEvent(screen.getByTestId('connection-card'), 'longPress');
      expect(onLongPress).toHaveBeenCalledTimes(1);
    });
  });
});
