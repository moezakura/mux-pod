import 'package:flutter_muxpod/services/agent/agent_registry.dart';
import 'package:flutter_muxpod/services/agent/agent_types.dart';
import 'package:flutter_muxpod/services/agent/claude_code_adapter.dart';
import 'package:flutter_muxpod/services/agent/codex_adapter.dart';
import 'package:flutter_muxpod/services/agent/factory_droid_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentRegistry.adapters', () {
    test('contains all three adapters', () {
      expect(AgentRegistry.adapters, hasLength(3));
      expect(
        AgentRegistry.adapters.map((a) => a.kind),
        containsAll(AgentKind.values),
      );
    });
  });

  group('AgentRegistry.detect', () {
    test('detects each agent by bare process name', () {
      expect(AgentRegistry.detect('claude'), isA<ClaudeCodeAdapter>());
      expect(AgentRegistry.detect('codex'), isA<CodexAdapter>());
      expect(AgentRegistry.detect('droid'), isA<FactoryDroidAdapter>());
    });

    test('matches absolute paths by basename', () {
      expect(AgentRegistry.detect('/usr/bin/codex'), isA<CodexAdapter>());
      expect(
        AgentRegistry.detect('/usr/local/bin/claude'),
        isA<ClaudeCodeAdapter>(),
      );
    });

    test('is case-insensitive and trims whitespace', () {
      expect(AgentRegistry.detect('Claude'), isA<ClaudeCodeAdapter>());
      expect(AgentRegistry.detect('  droid  '), isA<FactoryDroidAdapter>());
    });

    test('returns null for non-agent commands', () {
      expect(AgentRegistry.detect('bash'), isNull);
      expect(AgentRegistry.detect('vim'), isNull);
      // Substring matches must not count.
      expect(AgentRegistry.detect('claude-helper'), isNull);
    });

    test('returns null for null or empty input', () {
      expect(AgentRegistry.detect(null), isNull);
      expect(AgentRegistry.detect(''), isNull);
      expect(AgentRegistry.detect('   '), isNull);
    });
  });
}
