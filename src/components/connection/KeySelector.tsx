/**
 * KeySelector
 *
 * SSH鍵を選択するためのボトムシート形式のセレクタ。
 */
import { memo, useCallback, useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  Modal,
  FlatList,
  ActivityIndicator,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';

import type { SSHKey } from '@/types/sshKey';
import { getAllKeys } from '@/services/ssh/keyManager';
import { colors, spacing, fontSize, borderRadius } from '@/theme';

export interface KeySelectorProps {
  /** 選択中の鍵ID */
  selectedKeyId: string | null;
  /** 鍵が選択されたときのコールバック */
  onSelect: (key: SSHKey | null) => void;
  /** 無効化するか */
  disabled?: boolean;
}

interface KeyItemProps {
  sshKey: SSHKey;
  selected: boolean;
  onPress: () => void;
}

const KeyItem = memo(function KeyItem({ sshKey, selected, onPress }: KeyItemProps) {
  return (
    <Pressable
      style={[styles.keyItem, selected && styles.keyItemSelected]}
      onPress={onPress}
    >
      <View style={styles.keyItemIcon}>
        <MaterialCommunityIcons
          name="key-variant"
          size={20}
          color={selected ? colors.primary : colors.textMuted}
        />
      </View>
      <View style={styles.keyItemInfo}>
        <Text style={[styles.keyItemName, selected && styles.keyItemNameSelected]}>
          {sshKey.name}
        </Text>
        <Text style={styles.keyItemType}>{sshKey.keyType.toUpperCase()}</Text>
      </View>
      {selected && (
        <MaterialCommunityIcons
          name="check-circle"
          size={20}
          color={colors.primary}
        />
      )}
    </Pressable>
  );
});

export const KeySelector = memo(function KeySelector({
  selectedKeyId,
  onSelect,
  disabled = false,
}: KeySelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [keys, setKeys] = useState<SSHKey[]>([]);
  const [loading, setLoading] = useState(false);
  const [selectedKey, setSelectedKey] = useState<SSHKey | null>(null);

  useEffect(() => {
    const loadSelectedKey = async () => {
      if (selectedKeyId) {
        const allKeys = await getAllKeys();
        const key = allKeys.find((k) => k.id === selectedKeyId) ?? null;
        setSelectedKey(key);
      } else {
        setSelectedKey(null);
      }
    };
    loadSelectedKey();
  }, [selectedKeyId]);

  const handleOpen = useCallback(async () => {
    if (disabled) return;

    setIsOpen(true);
    setLoading(true);

    try {
      const allKeys = await getAllKeys();
      setKeys(allKeys);
    } catch (error) {
      console.error('Failed to load keys:', error);
    } finally {
      setLoading(false);
    }
  }, [disabled]);

  const handleSelect = useCallback(
    (key: SSHKey) => {
      onSelect(key);
      setSelectedKey(key);
      setIsOpen(false);
    },
    [onSelect]
  );

  const handleClear = useCallback(() => {
    onSelect(null);
    setSelectedKey(null);
    setIsOpen(false);
  }, [onSelect]);

  return (
    <>
      <Pressable
        style={[styles.trigger, disabled && styles.triggerDisabled]}
        onPress={handleOpen}
        disabled={disabled}
      >
        <View style={styles.triggerIcon}>
          <MaterialCommunityIcons
            name="key-variant"
            size={20}
            color={selectedKey ? colors.primary : colors.textMuted}
          />
        </View>
        <Text
          style={[
            styles.triggerText,
            selectedKey && styles.triggerTextSelected,
          ]}
          numberOfLines={1}
        >
          {selectedKey ? selectedKey.name : 'Select SSH Key'}
        </Text>
        <MaterialCommunityIcons
          name="chevron-down"
          size={20}
          color={colors.textMuted}
        />
      </Pressable>

      <Modal
        visible={isOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setIsOpen(false)}
      >
        <View style={styles.modalOverlay}>
          <Pressable
            style={styles.modalBackdrop}
            onPress={() => setIsOpen(false)}
          />
          <View style={styles.modalContent}>
            {/* Header */}
            <View style={styles.modalHeader}>
              <View style={styles.modalHandle} />
              <Text style={styles.modalTitle}>Select SSH Key</Text>
            </View>

            {/* Content */}
            {loading ? (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={colors.primary} />
              </View>
            ) : keys.length === 0 ? (
              <View style={styles.emptyContainer}>
                <MaterialCommunityIcons
                  name="key-outline"
                  size={48}
                  color={colors.textMuted}
                />
                <Text style={styles.emptyTitle}>No SSH Keys</Text>
                <Text style={styles.emptySubtitle}>
                  Generate or import a key first.
                </Text>
              </View>
            ) : (
              <FlatList
                data={keys}
                keyExtractor={(item) => item.id}
                renderItem={({ item }) => (
                  <KeyItem
                    sshKey={item}
                    selected={item.id === selectedKeyId}
                    onPress={() => handleSelect(item)}
                  />
                )}
                contentContainerStyle={styles.keyList}
                showsVerticalScrollIndicator={false}
              />
            )}

            {/* Footer */}
            <View style={styles.modalFooter}>
              {selectedKeyId && (
                <Pressable style={styles.clearButton} onPress={handleClear}>
                  <MaterialCommunityIcons
                    name="close-circle"
                    size={18}
                    color={colors.textMuted}
                  />
                  <Text style={styles.clearButtonText}>Clear Selection</Text>
                </Pressable>
              )}
              <Pressable
                style={styles.cancelButton}
                onPress={() => setIsOpen(false)}
              >
                <Text style={styles.cancelButtonText}>Cancel</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </>
  );
});

const styles = StyleSheet.create({
  // Trigger
  trigger: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0b0f13',
    borderRadius: borderRadius.lg,
    paddingVertical: 14,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },
  triggerDisabled: {
    opacity: 0.5,
  },
  triggerIcon: {
    width: 24,
    alignItems: 'center',
  },
  triggerText: {
    flex: 1,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  triggerTextSelected: {
    color: colors.primary,
    fontWeight: '500',
  },
  // Modal
  modalOverlay: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  modalBackdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
  },
  modalContent: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: borderRadius.xl,
    borderTopRightRadius: borderRadius.xl,
    maxHeight: '70%',
  },
  modalHeader: {
    alignItems: 'center',
    paddingTop: spacing.sm,
    paddingBottom: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  modalHandle: {
    width: 40,
    height: 4,
    backgroundColor: colors.textMuted,
    borderRadius: 2,
    marginBottom: spacing.md,
  },
  modalTitle: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.text,
  },
  loadingContainer: {
    padding: spacing.xxl,
    alignItems: 'center',
  },
  emptyContainer: {
    padding: spacing.xxl,
    alignItems: 'center',
    gap: spacing.sm,
  },
  emptyTitle: {
    fontSize: fontSize.lg,
    fontWeight: '600',
    color: colors.text,
  },
  emptySubtitle: {
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  keyList: {
    padding: spacing.md,
    gap: spacing.sm,
  },
  // Key Item
  keyItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.background,
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    gap: spacing.md,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  keyItemSelected: {
    borderColor: colors.primary,
    backgroundColor: 'rgba(0, 192, 209, 0.05)',
  },
  keyItemIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  keyItemInfo: {
    flex: 1,
  },
  keyItemName: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 2,
  },
  keyItemNameSelected: {
    color: colors.primary,
  },
  keyItemType: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    fontWeight: '500',
  },
  // Footer
  modalFooter: {
    flexDirection: 'row',
    padding: spacing.md,
    gap: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  clearButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    gap: spacing.xs,
  },
  clearButtonText: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.textMuted,
  },
  cancelButton: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.primary,
  },
  cancelButtonText: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.background,
  },
});
