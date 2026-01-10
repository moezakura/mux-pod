/**
 * SSH Key Manager Tests
 *
 * TDD: これらのテストは実装前に作成され、失敗することを確認する。
 */
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import * as LocalAuthentication from 'expo-local-authentication';

import {
  generateKey,
  getAllKeys,
  getKeyById,
  deleteKey,
  getPrivateKey,
  isNameAvailable,
  validatePrivateKey,
  importKey,
} from '@/services/ssh/keyManager';
import { SSH_KEYS_STORAGE_KEY, PRIVATE_KEY_PREFIX } from '@/types/sshKey';

// Mocks
jest.mock('@react-native-async-storage/async-storage');
jest.mock('expo-secure-store');
jest.mock('expo-local-authentication');

const mockAsyncStorage = AsyncStorage as jest.Mocked<typeof AsyncStorage>;
const mockSecureStore = SecureStore as jest.Mocked<typeof SecureStore>;
const mockLocalAuth = LocalAuthentication as jest.Mocked<typeof LocalAuthentication>;

describe('keyManager', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockAsyncStorage.getItem.mockResolvedValue(null);
    mockSecureStore.getItemAsync.mockResolvedValue(null);
    mockLocalAuth.authenticateAsync.mockResolvedValue({
      success: true,
    });
  });

  describe('generateKey', () => {
    it('should generate ED25519 key pair and save to storage', async () => {
      mockAsyncStorage.setItem.mockResolvedValue(undefined);
      mockSecureStore.setItemAsync.mockResolvedValue(undefined);

      const result = await generateKey({
        name: 'Test Key',
        keyType: 'ed25519',
        requireBiometrics: false,
      });

      expect(result.key.name).toBe('Test Key');
      expect(result.key.keyType).toBe('ed25519');
      expect(result.key.imported).toBe(false);
      expect(result.publicKey).toContain('ssh-ed25519');
      expect(mockSecureStore.setItemAsync).toHaveBeenCalled();
      expect(mockAsyncStorage.setItem).toHaveBeenCalledWith(
        SSH_KEYS_STORAGE_KEY,
        expect.any(String)
      );
    });

    it('should reject duplicate key names', async () => {
      const existingKeys = [{ id: '1', name: 'Test Key', keyType: 'ed25519' }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(existingKeys));

      await expect(
        generateKey({ name: 'Test Key', keyType: 'ed25519' })
      ).rejects.toThrow('Key name already exists');
    });

    it('should generate fingerprint in SHA256 format', async () => {
      mockAsyncStorage.setItem.mockResolvedValue(undefined);
      mockSecureStore.setItemAsync.mockResolvedValue(undefined);

      const result = await generateKey({
        name: 'Fingerprint Test',
        keyType: 'ed25519',
      });

      expect(result.key.fingerprint).toMatch(/^SHA256:/);
    });
  });

  describe('getAllKeys', () => {
    it('should return empty array when no keys exist', async () => {
      mockAsyncStorage.getItem.mockResolvedValue(null);

      const keys = await getAllKeys();

      expect(keys).toEqual([]);
    });

    it('should return all stored keys', async () => {
      const storedKeys = [
        { id: '1', name: 'Key 1', keyType: 'ed25519' },
        { id: '2', name: 'Key 2', keyType: 'rsa-2048' },
      ];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));

      const keys = await getAllKeys();

      expect(keys).toHaveLength(2);
      expect(keys[0]?.name).toBe('Key 1');
      expect(keys[1]?.name).toBe('Key 2');
    });
  });

  describe('getKeyById', () => {
    it('should return null for non-existent key', async () => {
      mockAsyncStorage.getItem.mockResolvedValue(null);

      const key = await getKeyById('non-existent');

      expect(key).toBeNull();
    });

    it('should return key by ID', async () => {
      const storedKeys = [{ id: 'test-id', name: 'Test Key', keyType: 'ed25519' }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));

      const key = await getKeyById('test-id');

      expect(key?.name).toBe('Test Key');
    });
  });

  describe('deleteKey', () => {
    it('should delete key from both storages', async () => {
      const storedKeys = [{ id: 'delete-me', name: 'Delete Key', keyType: 'ed25519' }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));
      mockAsyncStorage.setItem.mockResolvedValue(undefined);
      mockSecureStore.deleteItemAsync.mockResolvedValue(undefined);

      const result = await deleteKey('delete-me');

      expect(result).toBe(true);
      expect(mockSecureStore.deleteItemAsync).toHaveBeenCalledWith(
        `${PRIVATE_KEY_PREFIX}delete-me`
      );
      expect(mockAsyncStorage.setItem).toHaveBeenCalledWith(
        SSH_KEYS_STORAGE_KEY,
        '[]'
      );
    });

    it('should return false for non-existent key', async () => {
      mockAsyncStorage.getItem.mockResolvedValue(null);

      const result = await deleteKey('non-existent');

      expect(result).toBe(false);
    });
  });

  describe('getPrivateKey', () => {
    it('should return private key from SecureStore', async () => {
      const privateKey = '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----';
      const storedKeys = [{ id: 'key-1', name: 'Key', requireBiometrics: false }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));
      mockSecureStore.getItemAsync.mockResolvedValue(privateKey);

      const result = await getPrivateKey('key-1');

      expect(result).toBe(privateKey);
    });

    it('should require biometric auth when configured', async () => {
      const storedKeys = [{ id: 'bio-key', name: 'Bio Key', requireBiometrics: true }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));
      mockSecureStore.getItemAsync.mockResolvedValue('private-key');
      mockLocalAuth.authenticateAsync.mockResolvedValue({ success: true });

      await getPrivateKey('bio-key');

      expect(mockLocalAuth.authenticateAsync).toHaveBeenCalled();
    });

    it('should throw when biometric auth fails', async () => {
      const storedKeys = [{ id: 'bio-key', name: 'Bio Key', requireBiometrics: true }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));
      mockLocalAuth.authenticateAsync.mockResolvedValue({
        success: false,
        error: 'user_cancel',
      });

      await expect(getPrivateKey('bio-key')).rejects.toThrow('Biometric authentication failed');
    });
  });

  describe('isNameAvailable', () => {
    it('should return true for available name', async () => {
      mockAsyncStorage.getItem.mockResolvedValue(null);

      const available = await isNameAvailable('New Key');

      expect(available).toBe(true);
    });

    it('should return false for existing name', async () => {
      const storedKeys = [{ id: '1', name: 'Existing Key' }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(storedKeys));

      const available = await isNameAvailable('Existing Key');

      expect(available).toBe(false);
    });
  });

  describe('validatePrivateKey', () => {
    it('should return valid for OpenSSH ED25519 key', () => {
      const ed25519Key = `-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxAAAA
-----END OPENSSH PRIVATE KEY-----`;

      const result = validatePrivateKey(ed25519Key);

      expect(result.valid).toBe(true);
      expect(result.keyType).toBe('ed25519');
      expect(result.encrypted).toBe(false);
    });

    it('should return valid for RSA key', () => {
      const rsaKey = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
-----END RSA PRIVATE KEY-----`;

      const result = validatePrivateKey(rsaKey);

      expect(result.valid).toBe(true);
      expect(result.keyType).toBe('rsa-2048');
    });

    it('should detect encrypted key', () => {
      const encryptedKey = `-----BEGIN OPENSSH PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAA
-----END OPENSSH PRIVATE KEY-----`;

      const result = validatePrivateKey(encryptedKey);

      expect(result.valid).toBe(true);
      expect(result.encrypted).toBe(true);
    });

    it('should return invalid for empty key', () => {
      const result = validatePrivateKey('');

      expect(result.valid).toBe(false);
      expect(result.error).toBe('Private key is empty');
    });

    it('should return invalid for malformed key', () => {
      const result = validatePrivateKey('not a valid key');

      expect(result.valid).toBe(false);
      expect(result.error).toBe('Invalid private key format');
    });
  });

  describe('importKey', () => {
    const validPrivateKey = `-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxAAAA
-----END OPENSSH PRIVATE KEY-----`;

    it('should import a valid private key', async () => {
      mockAsyncStorage.getItem.mockResolvedValue(null);
      mockAsyncStorage.setItem.mockResolvedValue(undefined);
      mockSecureStore.setItemAsync.mockResolvedValue(undefined);

      const result = await importKey({
        name: 'Imported Key',
        privateKey: validPrivateKey,
        requireBiometrics: true,
      });

      expect(result.key.name).toBe('Imported Key');
      expect(result.key.imported).toBe(true);
      expect(result.key.requireBiometrics).toBe(true);
      expect(mockSecureStore.setItemAsync).toHaveBeenCalled();
      expect(mockAsyncStorage.setItem).toHaveBeenCalledWith(
        SSH_KEYS_STORAGE_KEY,
        expect.any(String)
      );
    });

    it('should reject invalid private key', async () => {
      await expect(
        importKey({
          name: 'Invalid Key',
          privateKey: 'not a valid key',
        })
      ).rejects.toThrow('Invalid private key format');
    });

    it('should reject duplicate key names', async () => {
      const existingKeys = [{ id: '1', name: 'Existing Key' }];
      mockAsyncStorage.getItem.mockResolvedValue(JSON.stringify(existingKeys));

      await expect(
        importKey({
          name: 'Existing Key',
          privateKey: validPrivateKey,
        })
      ).rejects.toThrow('Key name already exists');
    });

    it('should reject empty key name', async () => {
      await expect(
        importKey({
          name: '',
          privateKey: validPrivateKey,
        })
      ).rejects.toThrow('Key name cannot be empty');
    });
  });
});
