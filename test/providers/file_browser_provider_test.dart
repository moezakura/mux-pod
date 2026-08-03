import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/file_browser_provider.dart';
import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/services/sftp/file_entry.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';

import '../helpers/fake_sftp_client.dart';
import '../helpers/fake_ssh_client.dart';
import '../helpers/fake_ssh_notifier.dart';
import '../helpers/fake_tmux_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({
    required FakeSshClient sshClient,
    TmuxState? tmuxState,
  }) {
    return ProviderContainer(
      overrides: [
        sshProvider.overrideWith(
          () => FakeSshNotifier(client: sshClient),
        ),
        tmuxProvider.overrideWith(
          () => FakeTmuxNotifier(
            initialState: tmuxState ?? const TmuxState(),
          ),
        ),
      ],
    );
  }

  test('initial state uses defaults', () async {
    final container = makeContainer(
      sshClient: FakeSshClient(),
    );
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
            attr: SftpFileAttrs(
              mode: SftpFileMode.value(0x41ED),
            ),
          ),
          SftpName(
            filename: 'readme.md',
            longname: '-rw-r--r--',
            attr: SftpFileAttrs(
              mode: SftpFileMode.value(0x81A4),
              size: 1234,
            ),
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

    final container = makeContainer(
      sshClient: sshClient,
      tmuxState: tmuxState,
    );
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

  test('setSort toggles direction for same option', () async {
    final container = makeContainer(
      sshClient: FakeSshClient(),
    );
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

    final container = makeContainer(
      sshClient: sshClient,
      tmuxState: tmuxState,
    );
    addTearDown(container.dispose);

    await container.read(fileBrowserProvider.notifier).initialize('%0');

    final file = FileEntry(
      name: 'readme.md',
      fullPath: '/home/user/projects/readme.md',
      isDirectory: false,
    );
    final result = await container.read(fileBrowserProvider.notifier).delete(file);
    expect(result, isTrue);

    final result2 = await container.read(fileBrowserProvider.notifier).createDirectory('newdir');
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
