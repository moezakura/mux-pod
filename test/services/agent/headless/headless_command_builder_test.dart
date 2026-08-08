import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/headless/headless_command_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildHeadlessCommand', () {
    group('shell escaping', () {
      test('wraps the prompt in single quotes', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'hello world',
        );
        expect(command, contains("-p 'hello world'"));
      });

      test('escapes single quotes in the prompt', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: "it's a test",
        );
        expect(command, contains(r"-p 'it'\''s a test'"));
      });

      test('neutralizes dollar signs, backticks and double quotes', () {
        const prompt = 'run `rm -rf \$HOME` and say "hi"';
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: prompt,
        );
        // Inside single quotes the shell performs no expansion.
        expect(command, contains("'run `rm -rf \$HOME` and say \"hi\"'"));
      });

      test('escapes the working directory and prefixes with cd', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'x',
          workingDirectory: "/home/user's dir",
        );
        expect(
          command,
          startsWith(r"cd '/home/user'\''s dir' && droid exec"),
        );
      });

      test('omits cd when no working directory is given', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'x',
        );
        expect(command, startsWith('claude '));
      });
    });

    group('claudeCode', () {
      test('builds the documented stream-json invocation', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'summarize',
        );
        expect(
          command,
          "claude -p 'summarize' --output-format stream-json --verbose",
        );
      });

      test('passes model and effort', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'x',
          model: 'claude-sonnet-5',
          intelligence: UnifiedIntelligence.ultra,
        );
        expect(command, contains("--model 'claude-sonnet-5'"));
        expect(command, contains('--effort ultracode'));
      });

      test('maps extraHigh to xhigh', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'x',
          intelligence: UnifiedIntelligence.extraHigh,
        );
        expect(command, contains('--effort xhigh'));
      });

      test('maps permissions to permission-mode', () {
        expect(
          buildHeadlessCommand(
            kind: AgentKind.claudeCode,
            prompt: 'x',
            permission: UnifiedPermission.readOnly,
          ),
          contains('--permission-mode default'),
        );
        expect(
          buildHeadlessCommand(
            kind: AgentKind.claudeCode,
            prompt: 'x',
            permission: UnifiedPermission.defaultPermissions,
          ),
          contains('--permission-mode acceptEdits'),
        );
        expect(
          buildHeadlessCommand(
            kind: AgentKind.claudeCode,
            prompt: 'x',
            permission: UnifiedPermission.autoReview,
          ),
          contains('--permission-mode auto'),
        );
        expect(
          buildHeadlessCommand(
            kind: AgentKind.claudeCode,
            prompt: 'x',
            permission: UnifiedPermission.fullAccess,
          ),
          contains('--permission-mode bypassPermissions'),
        );
      });

      test('custom permission omits permission-mode (config file wins)', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'x',
          permission: UnifiedPermission.custom,
        );
        expect(command, isNot(contains('--permission-mode')));
      });

      test('plan mode forces permission-mode plan', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'x',
          permission: UnifiedPermission.fullAccess,
          planMode: true,
        );
        expect(command, contains('--permission-mode plan'));
        expect(command, isNot(contains('bypassPermissions')));
      });

      test('resumes with --resume', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.claudeCode,
          prompt: 'next',
          resumeSessionId: 'sess-1',
        );
        expect(command, contains("--resume 'sess-1'"));
      });
    });

    group('codex', () {
      test('builds codex exec --json with prompt last', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: 'triage',
        );
        expect(command, "codex exec --json 'triage'");
      });

      test('passes model and sandbox', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: 'x',
          model: 'gpt-5.6',
          permission: UnifiedPermission.defaultPermissions,
        );
        expect(command, contains("-m 'gpt-5.6'"));
        expect(command, contains('-s workspace-write'));
      });

      test('maps permissions to sandbox levels', () {
        expect(
          buildHeadlessCommand(
            kind: AgentKind.codex,
            prompt: 'x',
            permission: UnifiedPermission.readOnly,
          ),
          contains('-s read-only'),
        );
        expect(
          buildHeadlessCommand(
            kind: AgentKind.codex,
            prompt: 'x',
            permission: UnifiedPermission.fullAccess,
          ),
          contains('-s danger-full-access'),
        );
      });

      test('custom permission omits the sandbox flag', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: 'x',
          permission: UnifiedPermission.custom,
        );
        expect(command, isNot(contains('-s ')));
      });

      test('passes reasoning effort via config override', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: 'x',
          intelligence: UnifiedIntelligence.high,
        );
        expect(command, contains('-c \'model_reasoning_effort="high"\''));
      });

      test('clamps max effort to xhigh', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: 'x',
          intelligence: UnifiedIntelligence.max,
        );
        expect(command, contains('-c \'model_reasoning_effort="xhigh"\''));
      });

      test('resume uses the resume subcommand with config overrides', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.codex,
          prompt: 'fix it',
          model: 'gpt-5.6',
          permission: UnifiedPermission.readOnly,
          intelligence: UnifiedIntelligence.low,
          resumeSessionId: 'sess-9',
        );
        expect(
          command,
          "codex exec resume 'sess-9' --json"
          " -c 'model=\"gpt-5.6\"'"
          " -c 'sandbox_mode=\"read-only\"'"
          " -c 'model_reasoning_effort=\"low\"'"
          " 'fix it'",
        );
        // resume rejects -s/-C/-m, so they must never appear.
        expect(command, isNot(contains(' -s ')));
        expect(command, isNot(contains(' -m ')));
      });
    });

    group('droid', () {
      test('builds droid exec with stream-json output', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'analyze',
        );
        expect(command, "droid exec -o stream-json 'analyze'");
      });

      test('maps permissions to --auto levels', () {
        expect(
          buildHeadlessCommand(
            kind: AgentKind.droid,
            prompt: 'x',
            permission: UnifiedPermission.defaultPermissions,
          ),
          contains('--auto low'),
        );
        expect(
          buildHeadlessCommand(
            kind: AgentKind.droid,
            prompt: 'x',
            permission: UnifiedPermission.autoReview,
          ),
          contains('--auto medium'),
        );
        expect(
          buildHeadlessCommand(
            kind: AgentKind.droid,
            prompt: 'x',
            permission: UnifiedPermission.fullAccess,
          ),
          contains('--auto high'),
        );
      });

      test('readOnly adds no autonomy flag (read-only is the default)', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'x',
          permission: UnifiedPermission.readOnly,
        );
        expect(command, isNot(contains('--auto')));
      });

      test('never emits --skip-permissions-unsafe', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'x',
          permission: UnifiedPermission.fullAccess,
        );
        expect(command, isNot(contains('--skip-permissions-unsafe')));
      });

      test('plan mode maps to --use-spec', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'x',
          planMode: true,
        );
        expect(command, contains('--use-spec'));
      });

      test('resumes with --session-id', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'continue',
          resumeSessionId: 'sess-7',
        );
        expect(command, contains("--session-id 'sess-7'"));
      });

      test('clamps effort above high to high', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'x',
          intelligence: UnifiedIntelligence.max,
        );
        expect(command, contains('-r high'));
      });

      test('passes model', () {
        final command = buildHeadlessCommand(
          kind: AgentKind.droid,
          prompt: 'x',
          model: 'claude-opus-4-7',
        );
        expect(command, contains("-m 'claude-opus-4-7'"));
      });
    });
  });
}
