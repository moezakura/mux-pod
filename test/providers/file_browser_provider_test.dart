import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/file_browser_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';
import 'package:flutter_muxpod/services/ssh/ssh_connection_state.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';

import '../helpers/fake_sftp_client.dart';
import '../helpers/fake_ssh_client.dart';
import '../helpers/fake_ssh_notifier.dart';
import '../helpers/fake_tmux_notifier.dart';

class _DelayedSftpClient extends FakeSftpClient {
  final pending = <String, Completer<List<SftpName>>>{};

  @override
  Future<List<SftpName>> listdir(String path) {
    final completer = pending[path];
    return completer?.future ?? super.listdir(path);
  }
}

SftpName _file(String name) => SftpName(
  filename: name,
  longname: '-rw-r--r--',
  attr: SftpFileAttrs(mode: SftpFileMode.value(0x81A4)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({
    required FakeSshClient sshClient,
    TmuxState? tmuxState,
  }) {
    return ProviderContainer(
      overrides: [
        sshProvider.overrideWith(() => FakeSshNotifier(client: sshClient)),
        tmuxProvider.overrideWith(
          () => FakeTmuxNotifier(initialState: tmuxState ?? const TmuxState()),
        ),
      ],
    );
  }

  test('initial state uses defaults', () async {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);

    final state = container.read(fileBrowserProvider);
    expect(state.currentPath, '/');
    expect(state.entries, isEmpty);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
  });

  test('initialize loads directory from pane CWD', () async {
    final sftpClient = FakeSftpClient(
      homeDirectory: '/home/user',
      entriesByPath: {
        '/home/user/projects': [
          SftpName(
            filename: 'src',
            longname: 'drwxr-xr-x',
            attr: SftpFileAttrs(mode: SftpFileMode.value(0x41ED)),
          ),
          SftpName(
            filename: 'readme.md',
            longname: '-rw-r--r--',
            attr: SftpFileAttrs(mode: SftpFileMode.value(0x81A4), size: 1234),
          ),
        ],
      },
    );

    final sshClient = FakeSshClient();
    sshClient.sftpClient = sftpClient;

    final tmuxState = TmuxState(
      sessions: [
        TmuxSession(
          name: 'mysession',
          windows: [
            TmuxWindow(
              index: 0,
              name: 'shell',
              panes: [
                TmuxPane(
                  index: 0,
                  id: '%0',
                  active: true,
                  currentPath: '/home/user/projects',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final container = makeContainer(sshClient: sshClient, tmuxState: tmuxState);
    addTearDown(container.dispose);

    await container.read(fileBrowserProvider.notifier).initialize('%0');

    final state = container.read(fileBrowserProvider);
    expect(state.currentPath, '/home/user/projects');
    expect(state.entries, hasLength(2));
    expect(state.entries[0].name, 'src');
    expect(state.entries[0].isDirectory, isTrue);
    expect(state.entries[1].name, 'readme.md');
    expect(state.entries[1].isDirectory, isFalse);
  });

  test(
    'initialize falls back to the SFTP home directory when pane CWD is absent',
    () async {
      final sftpClient = FakeSftpClient(
        homeDirectory: '/home/user',
        entriesByPath: {'/home/user': []},
      );
      final sshClient = FakeSshClient()..sftpClient = sftpClient;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);

      await container.read(fileBrowserProvider.notifier).initialize('%missing');

      expect(container.read(fileBrowserProvider).currentPath, '/home/user');
      expect(container.read(fileBrowserProvider).error, isNull);
    },
  );

  test(
    'newer directory request wins when an older listing completes last',
    () async {
      final sftpClient = _DelayedSftpClient();
      final slow = Completer<List<SftpName>>();
      sftpClient.pending['/slow'] = slow;
      final sshClient = FakeSshClient()..sftpClient = sftpClient;
      final container = makeContainer(sshClient: sshClient);
      addTearDown(container.dispose);
      final notifier = container.read(fileBrowserProvider.notifier);

      final slowLoad = notifier.loadDirectory('/slow');
      await notifier.loadDirectory('/fast');
      slow.complete([_file('stale.txt')]);
      await slowLoad;

      final state = container.read(fileBrowserProvider);
      expect(state.currentPath, '/fast');
      expect(state.entries.map((entry) => entry.name), contains('file.txt'));
      expect(
        state.entries.map((entry) => entry.name),
        isNot(contains('stale.txt')),
      );
    },
  );

  test('connection monitoring reports disconnect after initialize', () async {
    final sshClient = FakeSshClient();
    final container = makeContainer(sshClient: sshClient);
    addTearDown(container.dispose);

    await container.read(fileBrowserProvider.notifier).initialize(null);
    sshClient.setConnected(SshConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(fileBrowserProvider);
    expect(state.error, 'SSH connection lost');
    expect(state.isLoading, isFalse);
  });

  test('navigateUp normalizes trailing slash and keeps root stable', () async {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);
    final notifier = container.read(fileBrowserProvider.notifier);

    await notifier.loadDirectory('/home/user/');
    await notifier.navigateUp();
    expect(container.read(fileBrowserProvider).currentPath, '/home');

    await notifier.loadDirectory('/');
    final atRoot = container.read(fileBrowserProvider);
    await notifier.navigateUp();
    expect(identical(container.read(fileBrowserProvider), atRoot), isTrue);
  });

  test(
    'FILE-017 navigateToDirectory loads and selects the requested path',
    () async {
      final sftpClient = FakeSftpClient(
        entriesByPath: {
          '/workspace': [_file('main.dart')],
        },
      );
      final container = makeContainer(
        sshClient: FakeSshClient()..sftpClient = sftpClient,
      );
      addTearDown(container.dispose);

      await container
          .read(fileBrowserProvider.notifier)
          .navigateToDirectory('/workspace');

      final state = container.read(fileBrowserProvider);
      expect(state.currentPath, '/workspace');
      expect(state.entries.single.name, 'main.dart');
      expect(sftpClient.listdirCalls, ['/workspace']);
    },
  );

  test(
    'FILE-022 rename emits old/new paths and refreshes current directory',
    () async {
      final sftpClient = FakeSftpClient(
        entriesByPath: {
          '/workspace': [_file('old.txt')],
        },
      );
      final container = makeContainer(
        sshClient: FakeSshClient()..sftpClient = sftpClient,
      );
      addTearDown(container.dispose);
      final notifier = container.read(fileBrowserProvider.notifier);
      await notifier.loadDirectory('/workspace');

      final renamed = await notifier.rename(
        const FileEntry(
          name: 'old.txt',
          fullPath: '/workspace/old.txt',
          isDirectory: false,
        ),
        'new.txt',
      );

      expect(renamed, isTrue);
      expect(sftpClient.renameCalls, [
        ('/workspace/old.txt', '/workspace/new.txt'),
      ]);
      expect(sftpClient.listdirCalls, ['/workspace', '/workspace']);
      expect(container.read(fileBrowserProvider).currentPath, '/workspace');
    },
  );

  test(
    'FILE-024 refresh reloads the current path without changing selection',
    () async {
      final sftpClient = FakeSftpClient(
        entriesByPath: {
          '/logs': [_file('app.log')],
        },
      );
      final container = makeContainer(
        sshClient: FakeSshClient()..sftpClient = sftpClient,
      );
      addTearDown(container.dispose);
      final notifier = container.read(fileBrowserProvider.notifier);
      await notifier.loadDirectory('/logs');

      await notifier.refresh();

      expect(sftpClient.listdirCalls, ['/logs', '/logs']);
      expect(container.read(fileBrowserProvider).currentPath, '/logs');
      expect(
        container.read(fileBrowserProvider).entries.single.name,
        'app.log',
      );
    },
  );

  test('setSort toggles direction for same option', () async {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);

    final notifier = container.read(fileBrowserProvider.notifier);
    notifier.setSort(SortOption.name);
    expect(container.read(fileBrowserProvider).sortAscending, isFalse);

    notifier.setSort(SortOption.name);
    expect(container.read(fileBrowserProvider).sortAscending, isTrue);
  });

  test('setSort changes option and resets ascending', () {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);

    final notifier = container.read(fileBrowserProvider.notifier);
    notifier.setSort(SortOption.name, ascending: false);
    expect(container.read(fileBrowserProvider).sortOption, SortOption.name);
    expect(container.read(fileBrowserProvider).sortAscending, isFalse);

    notifier.setSort(SortOption.size);
    expect(container.read(fileBrowserProvider).sortOption, SortOption.size);
    expect(container.read(fileBrowserProvider).sortAscending, isTrue);
  });

  test('toggleShowHidden', () {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);

    final notifier = container.read(fileBrowserProvider.notifier);
    expect(container.read(fileBrowserProvider).showHidden, isFalse);

    notifier.toggleShowHidden();
    expect(container.read(fileBrowserProvider).showHidden, isTrue);
  });

  test('navigateUp from /home/user goes to /home', () async {
    final container = makeContainer(sshClient: FakeSshClient());
    addTearDown(container.dispose);

    final notifier = container.read(fileBrowserProvider.notifier);
    await notifier.initialize(null);
    await notifier.navigateUp();

    expect(container.read(fileBrowserProvider).currentPath, '/home');
  });

  test('delete and create directory call sftp', () async {
    final sftpClient = FakeSftpClient(homeDirectory: '/home/user');
    final sshClient = FakeSshClient();
    sshClient.sftpClient = sftpClient;

    final tmuxState = TmuxState(
      sessions: [
        TmuxSession(
          name: 'mysession',
          windows: [
            TmuxWindow(
              index: 0,
              name: 'shell',
              panes: [
                TmuxPane(
                  index: 0,
                  id: '%0',
                  active: true,
                  currentPath: '/home/user/projects',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final container = makeContainer(sshClient: sshClient, tmuxState: tmuxState);
    addTearDown(container.dispose);

    await container.read(fileBrowserProvider.notifier).initialize('%0');

    final file = FileEntry(
      name: 'readme.md',
      fullPath: '/home/user/projects/readme.md',
      isDirectory: false,
    );
    final result = await container
        .read(fileBrowserProvider.notifier)
        .delete(file);
    expect(result, isTrue);

    final result2 = await container
        .read(fileBrowserProvider.notifier)
        .createDirectory('newdir');
    expect(result2, isTrue);
  });

  test('displayEntries filters hidden files', () {
    const state = FileBrowserState(
      showHidden: false,
      entries: [
        FileEntry(name: 'visible', fullPath: '/visible', isDirectory: false),
        FileEntry(name: '.hidden', fullPath: '/.hidden', isDirectory: false),
      ],
    );
    expect(state.displayEntries, hasLength(1));
    expect(state.displayEntries[0].name, 'visible');
  });
}
