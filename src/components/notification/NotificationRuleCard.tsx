/**
 * NotificationRuleCard
 *
 * 通知ルールカードコンポーネント。
 * HTMLデザイン (notification_rules_setup.html) に完全準拠。
 */
import { memo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { colors, borderRadius, spacing, fontSize } from '@/theme';
import { NotificationToggle } from './NotificationToggle';

export type RuleType = 'regex' | 'idle' | 'success';

export interface NotificationRule {
  id: string;
  name: string;
  type: RuleType;
  pattern?: string;
  timeout?: number;
  enabled: boolean;
}

export interface NotificationRuleCardProps {
  rule: NotificationRule;
  onToggle?: (enabled: boolean) => void;
  onPress?: () => void;
}

/** ルールタイプに応じたカラーとアイコン */
const ruleTypeConfig: Record<RuleType, {
  color: string;
  bgColor: string;
  textColor: string;
  borderColor: string;
  icon: keyof typeof MaterialCommunityIcons.glyphMap;
}> = {
  regex: {
    color: colors.rose500,
    bgColor: colors.roseBg,
    textColor: colors.roseText,
    borderColor: colors.roseBorder,
    icon: 'code-tags',
  },
  idle: {
    color: colors.amber500,
    bgColor: colors.amberBg,
    textColor: colors.amberText,
    borderColor: colors.amberBorder,
    icon: 'timer-outline',
  },
  success: {
    color: colors.emerald500,
    bgColor: colors.emeraldBg,
    textColor: colors.emeraldText,
    borderColor: colors.emeraldBorder,
    icon: 'check-circle-outline',
  },
};

export const NotificationRuleCard = memo(function NotificationRuleCard({
  rule,
  onToggle,
  onPress,
}: NotificationRuleCardProps) {
  const config = ruleTypeConfig[rule.type];

  return (
    <View style={[styles.card, !rule.enabled && styles.cardDisabled]}>
      {/* Left color bar */}
      <View style={[styles.colorBar, { backgroundColor: config.color }]} />

      <View style={styles.content}>
        {/* Icon */}
        <View style={[styles.iconContainer, { backgroundColor: config.bgColor }]}>
          <MaterialCommunityIcons
            name={config.icon}
            size={20}
            color={config.color}
          />
        </View>

        {/* Content */}
        <View style={styles.textContent}>
          <View style={styles.header}>
            <Text style={styles.title}>{rule.name}</Text>
            <NotificationToggle
              value={rule.enabled}
              onValueChange={onToggle}
            />
          </View>

          {/* Pattern or timeout display */}
          {rule.type === 'idle' && rule.timeout !== undefined ? (
            <View style={styles.idleRow}>
              <Text style={styles.idleLabel}>Notify if silent for</Text>
              <View style={[styles.timeoutBadge, { backgroundColor: config.bgColor }]}>
                <Text style={[styles.timeoutText, { color: config.textColor }]}>
                  {'>'} {rule.timeout}s
                </Text>
              </View>
            </View>
          ) : rule.pattern ? (
            <View style={[styles.patternContainer, { backgroundColor: config.bgColor, borderColor: config.borderColor }]}>
              <Text style={[styles.patternText, { color: config.textColor }]} numberOfLines={1}>
                {rule.pattern}
              </Text>
            </View>
          ) : null}
        </View>
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  card: {
    position: 'relative',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
    marginBottom: spacing.sm + 4, // space-y-3 = 12px
  },
  cardDisabled: {
    opacity: 0.6,
  },
  colorBar: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: 4,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    padding: spacing.md,
    paddingLeft: spacing.md + 4, // offset for color bar
    gap: spacing.sm + 4, // gap-3
  },
  iconContainer: {
    width: 32,
    height: 32,
    borderRadius: borderRadius.sm,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 4,
  },
  textContent: {
    flex: 1,
    minWidth: 0,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 4,
  },
  title: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
    flex: 1,
    marginRight: spacing.sm,
  },
  patternContainer: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 6,
    borderRadius: borderRadius.sm,
    borderWidth: 1,
  },
  patternText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
  },
  idleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginTop: 4,
  },
  idleLabel: {
    fontSize: fontSize.sm,
    color: colors.textSecondary,
  },
  timeoutBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: borderRadius.sm,
  },
  timeoutText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
    fontWeight: '700',
  },
});
