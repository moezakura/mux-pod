/**
 * 通知ルール設定画面
 *
 * HTMLデザイン (notification_rules_setup.html) に完全準拠。
 */
import { useState, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  Pressable,
  StyleSheet,
  SafeAreaView,
} from 'react-native';
import { useRouter } from 'expo-router';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { colors, borderRadius, spacing, fontSize, header } from '@/theme';
import {
  NotificationRuleCard,
  type NotificationRule,
} from '@/components/notification/NotificationRuleCard';
import { RuleForm, type RuleFormData } from '@/components/notification/RuleForm';

/** サンプルルールデータ */
const initialRules: NotificationRule[] = [
  {
    id: '1',
    name: 'Critical Error Match',
    type: 'regex',
    pattern: '/FATAL|CRITICAL|Error 50[0-5]/',
    enabled: true,
  },
  {
    id: '2',
    name: 'Idle Timeout',
    type: 'idle',
    timeout: 300,
    enabled: true,
  },
  {
    id: '3',
    name: 'Build Success',
    type: 'success',
    pattern: '"BUILD SUCCESSFUL"',
    enabled: false,
  },
];

export default function NotificationRulesScreen() {
  const router = useRouter();
  const [rules, setRules] = useState<NotificationRule[]>(initialRules);
  const [showForm, setShowForm] = useState(true); // Show form by default like HTML

  const handleBack = useCallback(() => {
    router.back();
  }, [router]);

  const handleAddRule = useCallback(() => {
    setShowForm(true);
  }, []);

  const handleToggleRule = useCallback((id: string, enabled: boolean) => {
    setRules((prev) =>
      prev.map((rule) =>
        rule.id === id ? { ...rule, enabled } : rule
      )
    );
  }, []);

  const handleSaveRule = useCallback((data: RuleFormData) => {
    const newRule: NotificationRule = {
      id: String(Date.now()),
      name: `New ${data.type} Rule`,
      type: data.type === 'IDLE' ? 'idle' : data.type === 'REGEX' ? 'regex' : 'success',
      pattern: data.pattern,
      enabled: true,
    };
    setRules((prev) => [...prev, newRule]);
    setShowForm(false);
  }, []);

  const handleCancelForm = useCallback(() => {
    setShowForm(false);
  }, []);

  const activeCount = rules.filter((r) => r.enabled).length;

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Pressable
          style={({ pressed }) => [
            styles.headerButton,
            pressed && styles.headerButtonPressed,
          ]}
          onPress={handleBack}
        >
          <MaterialCommunityIcons
            name="chevron-left"
            size={24}
            color={colors.textSecondary}
          />
        </Pressable>

        <Text style={styles.headerTitle}>Notification Rules</Text>

        <Pressable
          style={({ pressed }) => [
            styles.addButton,
            pressed && styles.addButtonPressed,
          ]}
          onPress={handleAddRule}
        >
          <MaterialCommunityIcons
            name="plus"
            size={24}
            color={colors.primary}
          />
        </Pressable>
      </View>

      {/* Context Bar */}
      <View style={styles.contextBar}>
        <MaterialCommunityIcons
          name="console"
          size={16}
          color={colors.textMuted}
        />
        <Text style={styles.contextText}>session-0:window-1:pane-0</Text>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Active Rules Section */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Active Watchers</Text>
            <View style={styles.activeCountBadge}>
              <Text style={styles.activeCountText}>{activeCount} Active</Text>
            </View>
          </View>

          <View style={styles.rulesList}>
            {rules.map((rule) => (
              <NotificationRuleCard
                key={rule.id}
                rule={rule}
                onToggle={(enabled) => handleToggleRule(rule.id, enabled)}
              />
            ))}
          </View>
        </View>

        {/* New Rule Form Section */}
        {showForm && (
          <View style={styles.formSection}>
            <View style={styles.formDivider} />
            <RuleForm
              onSave={handleSaveRule}
              onCancel={handleCancelForm}
            />
          </View>
        )}
      </ScrollView>

      {/* Bottom gradient fade */}
      <View style={styles.bottomGradient} pointerEvents="none" />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 4,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    backgroundColor: 'rgba(16, 17, 22, 0.95)',
  },
  headerButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerButtonPressed: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
  },
  headerTitle: {
    fontSize: fontSize.lg,
    fontWeight: '700',
    color: colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  addButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
  },
  addButtonPressed: {
    backgroundColor: 'rgba(0, 192, 209, 0.2)',
  },
  contextBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg - 4,
    paddingVertical: spacing.sm,
    backgroundColor: colors.surfaceDarker,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  contextText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
    color: colors.textSecondary,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing.md,
    paddingBottom: 128, // pb-32
  },
  section: {
    marginBottom: spacing.lg,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.sm + 4,
    paddingHorizontal: 4,
  },
  sectionTitle: {
    fontSize: fontSize.md,
    fontWeight: '600',
    color: colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  activeCountBadge: {
    backgroundColor: 'rgba(0, 192, 209, 0.1)',
    paddingHorizontal: spacing.sm,
    paddingVertical: 2,
    borderRadius: borderRadius.full,
  },
  activeCountText: {
    fontFamily: 'monospace',
    fontSize: fontSize.sm,
    color: colors.primary,
  },
  rulesList: {
    gap: 0, // Gap is handled in NotificationRuleCard marginBottom
  },
  formSection: {
    marginTop: spacing.md,
  },
  formDivider: {
    borderTopWidth: 1,
    borderTopColor: colors.border,
    borderStyle: 'dashed',
    marginBottom: spacing.md,
    paddingTop: spacing.md,
  },
  bottomGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 48,
    backgroundColor: 'transparent',
    // Note: Linear gradient would need expo-linear-gradient
  },
});
