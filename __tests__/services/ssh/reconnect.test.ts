/**
 * ReconnectService Unit Tests
 */
import { ReconnectService } from '@/services/ssh/reconnect';
import type { Connection, ConnectionState } from '@/types/connection';
import { DEFAULT_RECONNECT_SETTINGS } from '@/types/connection';
import type { ReconnectEvents } from '@/services/ssh/reconnect';

// モックSSHクライアント
const mockSSHClient = {
  connect: jest.fn(),
  disconnect: jest.fn(),
  isConnected: jest.fn(),
};

// テスト用接続設定
const createMockConnection = (overrides?: Partial<Connection>): Connection => ({
  id: 'test-connection-id',
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
  ...overrides,
});

// テスト用接続状態
const createMockConnectionState = (overrides?: Partial<ConnectionState>): ConnectionState => ({
  connectionId: 'test-connection-id',
  status: 'disconnected',
  ...overrides,
});

describe('ReconnectService', () => {
  let service: ReconnectService;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
    service = new ReconnectService(mockSSHClient);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('handleDisconnection', () => {
    it('should return true when autoReconnect is enabled', () => {
      const connection = createMockConnection({ autoReconnect: true });
      const state = createMockConnectionState();

      const result = service.handleDisconnection(connection, state);

      expect(result).toBe(true);
    });

    it('should return false when autoReconnect is disabled', () => {
      const connection = createMockConnection({ autoReconnect: false });
      const state = createMockConnectionState();

      const result = service.handleDisconnection(connection, state);

      expect(result).toBe(false);
    });

    it('should return false when disconnected by user', () => {
      const connection = createMockConnection({ autoReconnect: true });
      const state = createMockConnectionState({ disconnectReason: 'user_disconnect' });

      const result = service.handleDisconnection(connection, state);

      expect(result).toBe(false);
    });

    it('should return false when auth failed', () => {
      const connection = createMockConnection({ autoReconnect: true });
      const state = createMockConnectionState({ disconnectReason: 'auth_failed' });

      const result = service.handleDisconnection(connection, state);

      expect(result).toBe(false);
    });
  });

  describe('startReconnect', () => {
    it('should return success=true when connection succeeds', async () => {
      const connection = createMockConnection();
      mockSSHClient.connect.mockResolvedValueOnce(undefined);

      const resultPromise = service.startReconnect(connection, { password: 'test' });
      await jest.runAllTimersAsync();
      const result = await resultPromise;

      expect(result.success).toBe(true);
      expect(result.attemptCount).toBe(1);
      expect(mockSSHClient.connect).toHaveBeenCalledTimes(1);
    });

    it('should retry on connection failure', async () => {
      const connection = createMockConnection({ maxReconnectAttempts: 3 });
      mockSSHClient.connect
        .mockRejectedValueOnce(new Error('Network error'))
        .mockRejectedValueOnce(new Error('Network error'))
        .mockResolvedValueOnce(undefined);

      const resultPromise = service.startReconnect(connection, { password: 'test' });
      await jest.runAllTimersAsync();
      const result = await resultPromise;

      expect(result.success).toBe(true);
      expect(result.attemptCount).toBe(3);
      expect(mockSSHClient.connect).toHaveBeenCalledTimes(3);
    });

    it('should fire giveUp event after max attempts', async () => {
      const connection = createMockConnection({
        maxReconnectAttempts: 2,
        reconnectInterval: 1000,
      });
      mockSSHClient.connect.mockRejectedValue(new Error('Network error'));

      const onGiveUp = jest.fn();
      service.setEventHandlers(connection.id, { onGiveUp });

      const resultPromise = service.startReconnect(connection, { password: 'test' });
      await jest.runAllTimersAsync();
      const result = await resultPromise;

      expect(result.success).toBe(false);
      expect(result.attemptCount).toBe(2);
      expect(onGiveUp).toHaveBeenCalledWith(2, 'Network error');
    });

    it('should fire onAttemptStart event for each attempt', async () => {
      const connection = createMockConnection({ maxReconnectAttempts: 2 });
      mockSSHClient.connect
        .mockRejectedValueOnce(new Error('Network error'))
        .mockResolvedValueOnce(undefined);

      const onAttemptStart = jest.fn();
      service.setEventHandlers(connection.id, { onAttemptStart });

      const resultPromise = service.startReconnect(connection, { password: 'test' });
      await jest.runAllTimersAsync();
      await resultPromise;

      expect(onAttemptStart).toHaveBeenCalledTimes(2);
      expect(onAttemptStart).toHaveBeenNthCalledWith(1, 1, 2);
      expect(onAttemptStart).toHaveBeenNthCalledWith(2, 2, 2);
    });

    it('should fire onAttemptFailed event on each failure', async () => {
      const connection = createMockConnection({ maxReconnectAttempts: 2 });
      mockSSHClient.connect.mockRejectedValue(new Error('Connection refused'));

      const onAttemptFailed = jest.fn();
      service.setEventHandlers(connection.id, { onAttemptFailed });

      const resultPromise = service.startReconnect(connection, { password: 'test' });
      await jest.runAllTimersAsync();
      await resultPromise;

      expect(onAttemptFailed).toHaveBeenCalledTimes(2);
      expect(onAttemptFailed).toHaveBeenNthCalledWith(1, 1, 'Connection refused');
      expect(onAttemptFailed).toHaveBeenNthCalledWith(2, 2, 'Connection refused');
    });

    it('should fire onSuccess event when connected', async () => {
      const connection = createMockConnection();
      mockSSHClient.connect.mockResolvedValueOnce(undefined);

      const onSuccess = jest.fn();
      service.setEventHandlers(connection.id, { onSuccess });

      const resultPromise = service.startReconnect(connection, { password: 'test' });
      await jest.runAllTimersAsync();
      await resultPromise;

      expect(onSuccess).toHaveBeenCalledTimes(1);
    });
  });

  describe('cancelReconnect', () => {
    it('should cancel ongoing reconnection', async () => {
      jest.useRealTimers();

      const connection = createMockConnection({
        maxReconnectAttempts: 5,
        reconnectInterval: 50, // 短い間隔
      });

      mockSSHClient.connect.mockRejectedValue(new Error('Network error'));

      const onCancelled = jest.fn();
      service.setEventHandlers(connection.id, { onCancelled });

      // 再接続を開始
      const resultPromise = service.startReconnect(connection, { password: 'test' });

      // 少し待ってからキャンセル
      await new Promise((r) => setTimeout(r, 20));

      // この時点でisReconnectingはtrue
      expect(service.isReconnecting(connection.id)).toBe(true);

      // キャンセル
      service.cancelReconnect(connection.id);

      const result = await resultPromise;

      expect(result.cancelled).toBe(true);
      expect(result.success).toBe(false);
      expect(onCancelled).toHaveBeenCalledTimes(1);

      jest.useFakeTimers();
    }, 10000);

    it('should not throw when cancelling non-existent reconnection', () => {
      expect(() => {
        service.cancelReconnect('non-existent-id');
      }).not.toThrow();
    });
  });

  describe('isReconnecting', () => {
    it('should return true during reconnection', async () => {
      const connection = createMockConnection({ reconnectInterval: 5000 });
      mockSSHClient.connect.mockImplementation(
        () => new Promise((_, reject) => setTimeout(() => reject(new Error('error')), 100))
      );

      const resultPromise = service.startReconnect(connection, { password: 'test' });

      expect(service.isReconnecting(connection.id)).toBe(true);

      service.cancelReconnect(connection.id);
      await jest.runAllTimersAsync();
      await resultPromise;

      expect(service.isReconnecting(connection.id)).toBe(false);
    });

    it('should return false when not reconnecting', () => {
      expect(service.isReconnecting('some-id')).toBe(false);
    });
  });

  describe('event handlers', () => {
    it('should set and remove event handlers', () => {
      const connectionId = 'test-id';
      const handlers: Partial<ReconnectEvents> = {
        onSuccess: jest.fn(),
        onGiveUp: jest.fn(),
      };

      expect(() => {
        service.setEventHandlers(connectionId, handlers);
      }).not.toThrow();

      expect(() => {
        service.removeEventHandlers(connectionId);
      }).not.toThrow();
    });
  });
});
