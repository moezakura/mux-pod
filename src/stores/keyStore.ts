/**
 * SSH鍵ストア
 *
 * SSH鍵のリアクティブな状態管理。
 */
import { create } from 'zustand';
import type { SSHKey } from '@/types/sshKey';

interface KeyStoreState {
  /** 保存されている鍵一覧 */
  keys: SSHKey[];

  /** ローディング状態 */
  isLoading: boolean;

  /** エラーメッセージ */
  error: string | null;

  /** 選択中の鍵ID */
  selectedKeyId: string | null;
}

interface KeyStoreActions {
  /** 鍵一覧を設定する */
  setKeys: (keys: SSHKey[]) => void;

  /** 鍵を追加する */
  addKey: (key: SSHKey) => void;

  /** 鍵を削除する */
  removeKey: (id: string) => void;

  /** ローディング状態を設定する */
  setLoading: (isLoading: boolean) => void;

  /** エラーを設定する */
  setError: (error: string | null) => void;

  /** 鍵を選択する */
  selectKey: (id: string | null) => void;

  /** ストアをリセットする */
  reset: () => void;
}

type KeyStore = KeyStoreState & KeyStoreActions;

const initialState: KeyStoreState = {
  keys: [],
  isLoading: false,
  error: null,
  selectedKeyId: null,
};

export const useKeyStore = create<KeyStore>((set) => ({
  ...initialState,

  setKeys: (keys) => set({ keys, error: null }),

  addKey: (key) =>
    set((state) => ({
      keys: [...state.keys, key],
      error: null,
    })),

  removeKey: (id) =>
    set((state) => ({
      keys: state.keys.filter((k) => k.id !== id),
      selectedKeyId: state.selectedKeyId === id ? null : state.selectedKeyId,
    })),

  setLoading: (isLoading) => set({ isLoading }),

  setError: (error) => set({ error, isLoading: false }),

  selectKey: (id) => set({ selectedKeyId: id }),

  reset: () => set(initialState),
}));

/**
 * 鍵をIDで取得する
 */
export const selectKeyById = (id: string) => (state: KeyStore) =>
  state.keys.find((k) => k.id === id);

/**
 * 鍵を名前で取得する
 */
export const selectKeyByName = (name: string) => (state: KeyStore) =>
  state.keys.find((k) => k.name === name);
