/**
 * Known Host Manager Tests
 *
 * knownHostManager.ts のユニットテスト
 */
import AsyncStorage from '@react-native-async-storage/async-storage';

import {
  getAllHosts,
  getHost,
  getHostByIdentifier,
  verifyHostKey,
  trustHostKey,
  updateHostKey,
  deleteHost,
  deleteHostByAddress,
  clearAllHosts,
} from '@/services/ssh/knownHostManager';
import { KNOWN_HOSTS_STORAGE_KEY } from '@/types/sshKey';
import type { KnownHost } from '@/types/sshKey';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  getItem: jest.fn(),
  setItem: jest.fn(),
  removeItem: jest.fn(),
}));

const mockedAsyncStorage = AsyncStorage as jest.Mocked<typeof AsyncStorage>;

describe('knownHostManager', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const mockHost: KnownHost = {
    identifier: 'example.com:22',
    host: 'example.com',
    port: 22,
    keyType: 'ssh-ed25519',
    publicKey: 'AAAAC3NzaC1lZDI1NTE5AAAAITest...',
    fingerprint: 'SHA256:abcdef123456',
    addedAt: 1700000000000,
    lastVerifiedAt: 1700000000000,
  };

  describe('getAllHosts', () => {
    it('returns empty array when no hosts stored', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(null);

      const result = await getAllHosts();

      expect(result).toEqual([]);
      expect(mockedAsyncStorage.getItem).toHaveBeenCalledWith(KNOWN_HOSTS_STORAGE_KEY);
    });

    it('returns stored hosts', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await getAllHosts();

      expect(result).toEqual([mockHost]);
    });

    it('returns empty array on parse error', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue('invalid json');

      const result = await getAllHosts();

      expect(result).toEqual([]);
    });
  });

  describe('getHostByIdentifier', () => {
    it('returns host when found', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await getHostByIdentifier('example.com:22');

      expect(result).toEqual(mockHost);
    });

    it('returns null when not found', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await getHostByIdentifier('other.com:22');

      expect(result).toBeNull();
    });
  });

  describe('getHost', () => {
    it('returns host by host and port', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await getHost('example.com', 22);

      expect(result).toEqual(mockHost);
    });

    it('returns null when not found', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await getHost('example.com', 2222);

      expect(result).toBeNull();
    });
  });

  describe('verifyHostKey', () => {
    it('returns unknown status for new host', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(null);

      const result = await verifyHostKey(
        'newhost.com',
        22,
        'ssh-ed25519',
        'AAAAC3...',
        'SHA256:newfingerprint'
      );

      expect(result).toEqual({
        status: 'unknown',
        fingerprint: 'SHA256:newfingerprint',
        keyType: 'ssh-ed25519',
      });
    });

    it('returns trusted status when fingerprint matches', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));
      mockedAsyncStorage.setItem.mockResolvedValue(undefined);

      const result = await verifyHostKey(
        'example.com',
        22,
        'ssh-ed25519',
        mockHost.publicKey,
        mockHost.fingerprint
      );

      expect(result.status).toBe('trusted');
      expect(result).toHaveProperty('host');
      // Should update lastVerifiedAt
      expect(mockedAsyncStorage.setItem).toHaveBeenCalled();
    });

    it('returns changed status when fingerprint differs', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await verifyHostKey(
        'example.com',
        22,
        'ssh-ed25519',
        'differentPublicKey',
        'SHA256:differentFingerprint'
      );

      expect(result).toEqual({
        status: 'changed',
        previousFingerprint: mockHost.fingerprint,
        newFingerprint: 'SHA256:differentFingerprint',
      });
    });
  });

  describe('trustHostKey', () => {
    it('adds new host to empty list', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(null);
      mockedAsyncStorage.setItem.mockResolvedValue(undefined);

      const result = await trustHostKey(
        'newhost.com',
        22,
        'ssh-ed25519',
        'publicKey123',
        'SHA256:fingerprint123'
      );

      expect(result.identifier).toBe('newhost.com:22');
      expect(result.host).toBe('newhost.com');
      expect(result.port).toBe(22);
      expect(result.fingerprint).toBe('SHA256:fingerprint123');
      expect(mockedAsyncStorage.setItem).toHaveBeenCalled();
    });

    it('replaces existing host', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));
      mockedAsyncStorage.setItem.mockResolvedValue(undefined);

      const result = await trustHostKey(
        'example.com',
        22,
        'ssh-rsa',
        'newPublicKey',
        'SHA256:newFingerprint'
      );

      expect(result.fingerprint).toBe('SHA256:newFingerprint');
      expect(result.keyType).toBe('ssh-rsa');

      // Check that setItem was called with replaced host
      const call = mockedAsyncStorage.setItem.mock.calls[0]!;
      const savedData = JSON.parse(call[1] as string);
      expect(savedData).toHaveLength(1);
      expect(savedData[0].fingerprint).toBe('SHA256:newFingerprint');
    });
  });

  describe('updateHostKey', () => {
    it('updates existing host key', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));
      mockedAsyncStorage.setItem.mockResolvedValue(undefined);

      const result = await updateHostKey(
        'example.com:22',
        'ssh-rsa',
        'updatedPublicKey',
        'SHA256:updatedFingerprint'
      );

      expect(result).not.toBeNull();
      expect(result?.fingerprint).toBe('SHA256:updatedFingerprint');
      expect(result?.keyType).toBe('ssh-rsa');
    });

    it('returns null for non-existent host', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await updateHostKey(
        'nonexistent.com:22',
        'ssh-rsa',
        'publicKey',
        'fingerprint'
      );

      expect(result).toBeNull();
    });
  });

  describe('deleteHost', () => {
    it('deletes existing host', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));
      mockedAsyncStorage.setItem.mockResolvedValue(undefined);

      const result = await deleteHost('example.com:22');

      expect(result).toBe(true);
      const call = mockedAsyncStorage.setItem.mock.calls[0]!;
      const savedData = JSON.parse(call[1] as string);
      expect(savedData).toHaveLength(0);
    });

    it('returns false for non-existent host', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));

      const result = await deleteHost('nonexistent.com:22');

      expect(result).toBe(false);
    });
  });

  describe('deleteHostByAddress', () => {
    it('deletes host by address and port', async () => {
      mockedAsyncStorage.getItem.mockResolvedValue(JSON.stringify([mockHost]));
      mockedAsyncStorage.setItem.mockResolvedValue(undefined);

      const result = await deleteHostByAddress('example.com', 22);

      expect(result).toBe(true);
    });
  });

  describe('clearAllHosts', () => {
    it('removes all hosts', async () => {
      mockedAsyncStorage.removeItem.mockResolvedValue(undefined);

      await clearAllHosts();

      expect(mockedAsyncStorage.removeItem).toHaveBeenCalledWith(KNOWN_HOSTS_STORAGE_KEY);
    });
  });
});
