import 'package:flutter_muxpod/services/command/command_request.dart';
import 'package:flutter_muxpod/services/command/command_result.dart';
import 'package:flutter_test/flutter_test.dart';

// CommandRequest / CommandResult の契約テスト
// （Codex 根本設計レビュー・段階2 Step 1: 型追加と不変条件）。

void main() {
  group('CommandRequest', () {
    test('defaults to ephemeralOnly + outputOnly', () {
      const request = CommandRequest(command: 'echo hi');
      expect(request.transport, CommandTransportPreference.ephemeralOnly);
      expect(request.output, CommandOutputRequirement.outputOnly);
      expect(request.timeout, isNull);
    });

    test('is valid for persistentPreferred + exitCode', () {
      const request = CommandRequest(
        command: 'herdr pane read w1:p1',
        transport: CommandTransportPreference.persistentPreferred,
        output: CommandOutputRequirement.exitCode,
      );
      expect(request.isValid, isTrue);
    });

    test('rejects persistentOnly + separatedOutput (PTY cannot separate)', () {
      const request = CommandRequest(
        command: 'cmd',
        transport: CommandTransportPreference.persistentOnly,
        output: CommandOutputRequirement.separatedOutput,
      );
      expect(
        request.isValid,
        isFalse,
        reason: 'persistent shell（PTY）は stdout/stderr を分離できないため拒否',
      );
    });

    test(
      'accepts persistentPreferred + separatedOutput by routing to ephemeral',
      () {
        const request = CommandRequest(
          command: 'cmd',
          transport: CommandTransportPreference.persistentPreferred,
          output: CommandOutputRequirement.separatedOutput,
        );
        expect(request.isValid, isTrue);
      },
    );
  });

  group('CommandResult', () {
    test(
      'separated result carries stdout/stderr and primaryOutput is stdout',
      () {
        const result = CommandResult(
          stdout: 'out',
          stderr: 'err',
          exitCode: 1,
          outputSeparation: CommandOutputSeparation.separated,
          actualTransport: CommandTransport.ephemeral,
        );
        expect(result.stdout, 'out');
        expect(result.stderr, 'err');
        expect(result.mergedOutput, isNull);
        expect(result.primaryOutput, 'out');
      },
    );

    test(
      'merged result carries only mergedOutput and primaryOutput maps to it',
      () {
        const result = CommandResult(
          mergedOutput: 'merged text',
          exitCode: 0,
          outputSeparation: CommandOutputSeparation.merged,
          actualTransport: CommandTransport.persistent,
        );
        expect(result.stdout, '');
        expect(result.stderr, '');
        expect(result.mergedOutput, 'merged text');
        expect(result.primaryOutput, 'merged text');
      },
    );
  });
}
