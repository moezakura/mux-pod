/**
 * SSHClient Unit Tests
 */
import { SSHClient, SSHConnectionError, SSHAuthenticationError } from '@/services/ssh/client';
import type { Connection } from '@/types/connection';
import { DEFAULT_RECONNECT_SETTINGS } from '@/types/connection';

describe('SSHClient', () => {
  let client: SSHClient;
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

  beforeEach(() => {
    client = new SSHClient();
    jest.clearAllMocks();
  });

  afterEach(async () => {
    if (client.isConnected()) {
      await client.disconnect();
    }
  });

  describe('constructor', () => {
    it('should create an instance', () => {
      expect(client).toBeInstanceOf(SSHClient);
    });

    it('should start in disconnected state', () => {
      expect(client.isConnected()).toBe(false);
    });
  });

  describe('connect', () => {
    it('should require password for password auth', async () => {
      await expect(client.connect(mockConnection, {})).rejects.toThrow(
        SSHAuthenticationError
      );
    });

    it('should require privateKey for key auth', async () => {
      const keyConnection: Connection = {
        ...mockConnection,
        authMethod: 'key',
      };
      await expect(client.connect(keyConnection, {})).rejects.toThrow(
        SSHAuthenticationError
      );
    });

    it('should validate connection parameters', async () => {
      const invalidConnection: Connection = {
        ...mockConnection,
        host: '',
      };
      await expect(
        client.connect(invalidConnection, { password: 'pass' })
      ).rejects.toThrow(SSHConnectionError);
    });
  });

  describe('disconnect', () => {
    it('should not throw when already disconnected', async () => {
      await expect(client.disconnect()).resolves.not.toThrow();
    });
  });

  describe('exec', () => {
    it('should throw when not connected', async () => {
      await expect(client.exec('ls')).rejects.toThrow(SSHConnectionError);
    });
  });

  describe('event handlers', () => {
    it('should set event handlers', () => {
      const onData = jest.fn();
      const onClose = jest.fn();
      const onError = jest.fn();

      expect(() => {
        client.setEventHandlers({ onData, onClose, onError });
      }).not.toThrow();
    });
  });
});
