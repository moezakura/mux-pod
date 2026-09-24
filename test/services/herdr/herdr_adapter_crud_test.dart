import 'package:flutter_muxpod/services/herdr/herdr_adapter.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_ssh_client.dart';

void main() {
  group('HerdrAdapter tab CRUD (T12)', () {
    test(
      'tabCreate builds the command and succeeds with empty stdout',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr tab create'] = '';

        final adapter = HerdrAdapter(client);
        final result = await adapter.tabCreate('w1', label: 'logs');

        expect(result.changed, isTrue);
        expect(result.layout, isNull);
        expect(
          client.execCommands,
          contains("herdr tab create --workspace w1 --label 'logs'"),
        );
      },
    );

    test('tabCreate passes cwd and focus flags', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab create'] = '';

      final adapter = HerdrAdapter(client);
      await adapter.tabCreate('w1', cwd: '/tmp/work dir', focus: true);

      expect(
        client.execCommands,
        contains(
          "herdr tab create --workspace w1 --cwd '/tmp/work dir' --focus",
        ),
      );
    });

    test(
      'tabClose throws HerdrTargetNotFoundException on tab_not_found',
      () async {
        final client = FakeSshClient();
        client.execOutputs['herdr tab close'] =
            '{"error":{"code":"tab_not_found","message":"no tab"},'
            '"id":"cli:tab:close"}';
        client.execExitCodes['herdr tab close'] = 1;

        final adapter = HerdrAdapter(client);
        await expectLater(
          adapter.tabClose('w1:t1'),
          throwsA(
            isA<HerdrTargetNotFoundException>()
                .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.tab)
                .having((e) => e.errorCode, 'errorCode', 'tab_not_found'),
          ),
        );
      },
    );

    test('tabRename passes the quoted label', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab rename'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.tabRename('w1:t1', 'my tab');

      expect(result.changed, isTrue);
      expect(client.execCommands, contains("herdr tab rename w1:t1 'my tab'"));
    });

    test('tabFocus builds the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr tab focus'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.tabFocus('w1:t1');

      expect(result.changed, isTrue);
      expect(client.execCommands, contains('herdr tab focus w1:t1'));
    });
  });
  group('HerdrAdapter workspace CRUD (T12)', () {
    test('workspaceCreate succeeds and ignores the layout-less response', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace create'] =
          '{"id":"cli:workspace:create","result":{"workspace":{'
          '"workspace_id":"w6","label":"api","number":2,"focused":true},'
          '"tab":{"tab_id":"w6:t1","workspace_id":"w6","label":"1","number":1},'
          '"root_pane":{"pane_id":"w6:p1","workspace_id":"w6","tab_id":"w6:t1",'
          '"cwd":"/tmp"}},"type":"workspace_created"}';

      final adapter = HerdrAdapter(client);
      final result = await adapter.workspaceCreate(label: 'api');

      expect(result.changed, isTrue);
      expect(result.layout, isNull);
      expect(
        client.execCommands,
        contains("herdr workspace create --label 'api'"),
      );
    });

    test('workspaceCreate passes cwd and focus flags', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace create'] = '';

      final adapter = HerdrAdapter(client);
      await adapter.workspaceCreate(cwd: '/tmp/work dir', focus: true);

      expect(
        client.execCommands,
        contains("herdr workspace create --cwd '/tmp/work dir' --focus"),
      );
    });

    test('workspaceClose throws HerdrTargetNotFoundException on '
        'workspace_not_found', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace close'] =
          '{"error":{"code":"workspace_not_found","message":"no ws"},'
          '"id":"cli:workspace:close"}';
      client.execExitCodes['herdr workspace close'] = 1;

      final adapter = HerdrAdapter(client);
      await expectLater(
        adapter.workspaceClose('w1'),
        throwsA(
          isA<HerdrTargetNotFoundException>()
              .having((e) => e.kind, 'kind', HerdrTargetNotFoundKind.workspace)
              .having((e) => e.errorCode, 'errorCode', 'workspace_not_found'),
        ),
      );
    });

    test('workspaceRename passes the quoted label', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace rename'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.workspaceRename('w1', 'my ws');

      expect(result.changed, isTrue);
      expect(
        client.execCommands,
        contains("herdr workspace rename w1 'my ws'"),
      );
    });

    test('workspaceFocus builds the command', () async {
      final client = FakeSshClient();
      client.execOutputs['herdr workspace focus'] = '';

      final adapter = HerdrAdapter(client);
      final result = await adapter.workspaceFocus('w1');

      expect(result.changed, isTrue);
      expect(client.execCommands, contains('herdr workspace focus w1'));
    });
  });
}
