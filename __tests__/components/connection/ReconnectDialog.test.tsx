/**
 * ReconnectDialog Unit Tests
 */
import React from 'react';
import { render, fireEvent } from '@testing-library/react-native';
import { ReconnectDialog } from '@/components/connection/ReconnectDialog';
import type { Connection, ConnectionState } from '@/types/connection';
import { DEFAULT_RECONNECT_SETTINGS } from '@/types/connection';

describe('ReconnectDialog', () => {
  const mockConnection: Connection = {
    id: 'test-id',
    name: 'Test Server',
    host: '192.168.1.1',
    port: 22,
    username: 'testuser',
    authMethod: 'password',
    timeout: 30,
    keepAliveInterval: 60,
    ...DEFAULT_RECONNECT_SETTINGS,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };

  const mockConnectionState: ConnectionState = {
    connectionId: 'test-id',
    status: 'disconnected',
    disconnectReason: 'network_error',
  };

  const defaultProps = {
    visible: true,
    connection: mockConnection,
    connectionState: mockConnectionState,
    onReconnect: jest.fn(),
    onCancel: jest.fn(),
    onDismiss: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('visibility', () => {
    it('should render when visible is true', () => {
      const { getByTestId } = render(<ReconnectDialog {...defaultProps} />);
      expect(getByTestId('reconnect-dialog')).toBeTruthy();
    });

    it('should not render when visible is false', () => {
      const { queryByTestId } = render(
        <ReconnectDialog {...defaultProps} visible={false} />
      );
      expect(queryByTestId('reconnect-dialog')).toBeNull();
    });
  });

  describe('confirm state', () => {
    it('should show reconnect and cancel buttons', () => {
      const { getByText } = render(<ReconnectDialog {...defaultProps} />);
      expect(getByText('再接続')).toBeTruthy();
      expect(getByText('キャンセル')).toBeTruthy();
    });

    it('should call onReconnect when reconnect button is pressed', () => {
      const { getByText } = render(<ReconnectDialog {...defaultProps} />);
      fireEvent.press(getByText('再接続'));
      expect(defaultProps.onReconnect).toHaveBeenCalledTimes(1);
    });

    it('should call onCancel when cancel button is pressed', () => {
      const { getByText } = render(<ReconnectDialog {...defaultProps} />);
      fireEvent.press(getByText('キャンセル'));
      expect(defaultProps.onCancel).toHaveBeenCalledTimes(1);
    });

    it('should display connection name', () => {
      const { getByText } = render(<ReconnectDialog {...defaultProps} />);
      expect(getByText(/Test Server/)).toBeTruthy();
    });

    it('should display disconnect reason', () => {
      const { getByText } = render(<ReconnectDialog {...defaultProps} />);
      expect(getByText(/ネットワークエラー/)).toBeTruthy();
    });
  });

  describe('connecting state', () => {
    it('should show spinner when connecting', () => {
      const connectingState: ConnectionState = {
        ...mockConnectionState,
        status: 'reconnecting',
        reconnectAttempt: {
          startedAt: Date.now(),
          attemptNumber: 1,
          maxAttempts: 3,
          history: [],
        },
      };

      const { getByTestId } = render(
        <ReconnectDialog
          {...defaultProps}
          connectionState={connectingState}
        />
      );
      expect(getByTestId('connecting-spinner')).toBeTruthy();
    });

    it('should show attempt count when connecting', () => {
      const connectingState: ConnectionState = {
        ...mockConnectionState,
        status: 'reconnecting',
        reconnectAttempt: {
          startedAt: Date.now(),
          attemptNumber: 2,
          maxAttempts: 3,
          history: [],
        },
      };

      const { getByText } = render(
        <ReconnectDialog
          {...defaultProps}
          connectionState={connectingState}
        />
      );
      expect(getByText(/2.*\/.*3/)).toBeTruthy();
    });
  });

  describe('error state', () => {
    it('should show error message', () => {
      const errorState: ConnectionState = {
        ...mockConnectionState,
        status: 'error',
        error: 'Connection refused',
      };

      const { getByText } = render(
        <ReconnectDialog
          {...defaultProps}
          connectionState={errorState}
        />
      );
      expect(getByText(/Connection refused/)).toBeTruthy();
    });

    it('should show retry button on error', () => {
      const errorState: ConnectionState = {
        ...mockConnectionState,
        status: 'error',
        error: 'Connection refused',
      };

      const onRetry = jest.fn();
      const { getByText } = render(
        <ReconnectDialog
          {...defaultProps}
          connectionState={errorState}
          onRetry={onRetry}
        />
      );

      fireEvent.press(getByText('再試行'));
      expect(onRetry).toHaveBeenCalledTimes(1);
    });
  });

  describe('success state', () => {
    it('should show success message', () => {
      const successState: ConnectionState = {
        ...mockConnectionState,
        status: 'connected',
      };

      const { getByText } = render(
        <ReconnectDialog
          {...defaultProps}
          connectionState={successState}
        />
      );
      // タイトルとメッセージ両方に「接続しました」が含まれるため、タイトルのみを確認
      expect(getByText('接続しました')).toBeTruthy();
    });
  });
});
