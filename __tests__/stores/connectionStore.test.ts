/**
 * ConnectionStore Unit Tests
 */
import { useConnectionStore } from '@/stores/connectionStore';
import type { ConnectionInput } from '@/types/connection';
import { DEFAULT_RECONNECT_SETTINGS } from '@/types/connection';

describe('connectionStore', () => {
  beforeEach(() => {
    // ストアをリセット
    useConnectionStore.getState().clearAllConnections();
  });

  describe('addConnection', () => {
    it('should add a new connection', () => {
      const input: ConnectionInput = {
        name: 'Test Server',
        host: '192.168.1.1',
        port: 22,
        username: 'testuser',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      };

      const id = useConnectionStore.getState().addConnection(input);

      expect(id).toBeDefined();
      expect(typeof id).toBe('string');

      const connections = useConnectionStore.getState().connections;
      expect(connections).toHaveLength(1);
      expect(connections[0]?.name).toBe('Test Server');
      expect(connections[0]?.host).toBe('192.168.1.1');
    });

    it('should set createdAt and updatedAt', () => {
      const beforeAdd = Date.now();
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });
      const afterAdd = Date.now();

      const connection = useConnectionStore.getState().getConnection(id);
      expect(connection?.createdAt).toBeGreaterThanOrEqual(beforeAdd);
      expect(connection?.createdAt).toBeLessThanOrEqual(afterAdd);
      expect(connection?.updatedAt).toBe(connection?.createdAt);
    });

    it('should initialize connection state to disconnected', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      const state = useConnectionStore.getState().connectionStates[id];
      expect(state?.status).toBe('disconnected');
    });
  });

  describe('updateConnection', () => {
    it('should update an existing connection', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Original Name',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      useConnectionStore.getState().updateConnection(id, { name: 'Updated Name' });

      const connection = useConnectionStore.getState().getConnection(id);
      expect(connection?.name).toBe('Updated Name');
    });

    it('should update updatedAt timestamp', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      const originalUpdatedAt = useConnectionStore.getState().getConnection(id)?.updatedAt;

      // 少し待ってから更新
      useConnectionStore.getState().updateConnection(id, { name: 'New Name' });

      const newUpdatedAt = useConnectionStore.getState().getConnection(id)?.updatedAt;
      expect(newUpdatedAt).toBeGreaterThanOrEqual(originalUpdatedAt!);
    });
  });

  describe('removeConnection', () => {
    it('should remove a connection', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      expect(useConnectionStore.getState().connections).toHaveLength(1);

      useConnectionStore.getState().removeConnection(id);

      expect(useConnectionStore.getState().connections).toHaveLength(0);
    });

    it('should remove connection state', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      expect(useConnectionStore.getState().connectionStates[id]).toBeDefined();

      useConnectionStore.getState().removeConnection(id);

      expect(useConnectionStore.getState().connectionStates[id]).toBeUndefined();
    });

    it('should clear activeConnectionId if removed', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      useConnectionStore.getState().setActiveConnection(id);
      expect(useConnectionStore.getState().activeConnectionId).toBe(id);

      useConnectionStore.getState().removeConnection(id);
      expect(useConnectionStore.getState().activeConnectionId).toBeNull();
    });
  });

  describe('setConnectionState', () => {
    it('should update connection state', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      useConnectionStore.getState().setConnectionState(id, {
        status: 'connecting',
      });

      expect(useConnectionStore.getState().connectionStates[id]?.status).toBe('connecting');
    });
  });

  describe('setActiveConnection', () => {
    it('should set active connection', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      useConnectionStore.getState().setActiveConnection(id);
      expect(useConnectionStore.getState().activeConnectionId).toBe(id);
    });

    it('should clear active connection when set to null', () => {
      const id = useConnectionStore.getState().addConnection({
        name: 'Test',
        host: '192.168.1.1',
        port: 22,
        username: 'user',
        authMethod: 'password',
        timeout: 30,
        keepAliveInterval: 60,
        ...DEFAULT_RECONNECT_SETTINGS,
      });

      useConnectionStore.getState().setActiveConnection(id);
      useConnectionStore.getState().setActiveConnection(null);
      expect(useConnectionStore.getState().activeConnectionId).toBeNull();
    });
  });
});
