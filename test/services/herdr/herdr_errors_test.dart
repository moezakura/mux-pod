import 'package:flutter_muxpod/services/connection_error.dart';
import 'package:flutter_muxpod/services/herdr/herdr_commands.dart';
import 'package:flutter_muxpod/services/herdr/herdr_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isServerDownException (A1 3条件)', () {
    test('条件1: HerdrServerNotRunningException なら true', () {
      expect(isServerDownException(HerdrServerNotRunningException()), isTrue);
    });

    test('条件2a: errorCode が server 未稼働系なら true', () {
      final e = HerdrCommandException(
        'herdr command failed',
        errorCode: 'server_not_running',
      );
      expect(isServerDownException(e), isTrue);

      final refused = HerdrCommandException(
        'boom',
        errorCode: 'connection_refused',
      );
      expect(isServerDownException(refused), isTrue);

      final socket = HerdrCommandException(
        'boom',
        errorCode: 'socket_not_found',
      );
      expect(isServerDownException(socket), isTrue);
    });

    test('条件2b: message が接続拒否を示せば true', () {
      final e = HerdrCommandException(
        'herdr command failed: Error: connect ECONNREFUSED 127.0.0.1:41999',
      );
      expect(isServerDownException(e), isTrue);
    });

    test('条件2b: message が socket 不在を示せば true', () {
      final e = HerdrCommandException(
        'herdr command failed: cannot open socket: no such file or directory',
      );
      expect(isServerDownException(e), isTrue);

      final socketMissing = HerdrCommandException(
        'herdr command failed: socket /tmp/herdr.sock not found',
      );
      expect(isServerDownException(socketMissing), isTrue);
    });

    test('条件2b: message が server 停止を示せば true', () {
      final e = HerdrCommandException(
        'herdr command failed: server is not running',
      );
      expect(isServerDownException(e), isTrue);
    });

    test('条件3: SSH/transport 層の確定的接続断 (SshConnectionError) なら true', () {
      expect(
        isServerDownException(SshConnectionError('Connection lost')),
        isTrue,
      );
      expect(
        isServerDownException(SshConnectionError('Not connected')),
        isTrue,
      );
      expect(
        isServerDownException(SshConnectionError('ssh channel closed')),
        isTrue,
      );
      expect(
        isServerDownException(SshConnectionError('socket closed by peer')),
        isTrue,
      );
      // コマンド実行中の接続断（ラップされた cause が接続断を示すケース）
      expect(
        isServerDownException(SshConnectionError('Connection reset by peer')),
        isTrue,
      );
    });

    test('条件3b: 一過性エラー (SshConnectionError) は false（自動再接続に流す）', () {
      // タイムアウトは一過性。server-down にするとポーリング停止 + SnackBar で
      // 自然復旧しなくなる（M1 過検知）。
      expect(
        isServerDownException(
          SshConnectionError('Command execution timed out'),
        ),
        isFalse,
      );
      // コマンド実行失敗（例: リモートのコマンド不存在・非ゼロ終了）も一過性。
      expect(
        isServerDownException(SshConnectionError('Failed to execute command')),
        isFalse,
      );
      expect(
        isServerDownException(
          SshConnectionError('Failed to execute command: herdr: boom'),
        ),
        isFalse,
      );
      // 接続パラメータのバリデーションエラー等も server-down ではない
      expect(
        isServerDownException(SshConnectionError('Invalid port number: 0')),
        isFalse,
      );
    });

    test('target-not-found は server-down ではない', () {
      final e = HerdrCommandException('boom', errorCode: 'pane_not_found');
      expect(isServerDownException(e), isFalse);

      final typed = HerdrTargetNotFoundException(
        kind: HerdrTargetNotFoundKind.pane,
        message: 'no pane',
        errorCode: 'pane_not_found',
      );
      expect(isServerDownException(typed), isFalse);
    });

    test('非該当の例外は false', () {
      expect(isServerDownException(Exception('other')), isFalse);
      expect(
        isServerDownException(
          HerdrProtocolMismatchException(supported: 17, actual: 16),
        ),
        isFalse,
      );
      expect(
        isServerDownException(
          HerdrCommandException('boom', errorCode: 'internal_error'),
        ),
        isFalse,
      );
      expect(
        isServerDownException(
          HerdrCommandException('boom', errorCode: 'pane_not_found'),
        ),
        isFalse,
      );
    });
  });

  group('isHerdrTargetNotFound', () {
    test('HerdrTargetNotFoundException の直接インスタンスなら true', () {
      expect(
        isHerdrTargetNotFound(
          HerdrTargetNotFoundException(
            kind: HerdrTargetNotFoundKind.pane,
            message: 'no pane',
            errorCode: 'pane_not_found',
          ),
        ),
        isTrue,
      );
    });

    test('errorCode が pane/tab/workspace_not_found なら true', () {
      expect(
        isHerdrTargetNotFound(
          HerdrCommandException('boom', errorCode: 'pane_not_found'),
        ),
        isTrue,
      );
      expect(
        isHerdrTargetNotFound(
          HerdrCommandException('boom', errorCode: 'tab_not_found'),
        ),
        isTrue,
      );
      expect(
        isHerdrTargetNotFound(
          HerdrCommandException('boom', errorCode: 'workspace_not_found'),
        ),
        isTrue,
      );
    });

    test('server-down 系コード・その他は false', () {
      expect(
        isHerdrTargetNotFound(
          HerdrCommandException('boom', errorCode: 'server_not_running'),
        ),
        isFalse,
      );
      expect(
        isHerdrTargetNotFound(
          HerdrCommandException('boom', errorCode: 'internal_error'),
        ),
        isFalse,
      );
      expect(
        isHerdrTargetNotFound(HerdrCommandException('boom', exitCode: 1)),
        isFalse,
      );
      expect(isHerdrTargetNotFound(HerdrServerNotRunningException()), isFalse);
      expect(isHerdrTargetNotFound(Exception('other')), isFalse);
    });
  });

  group('herdrTargetNotFoundKindForCode', () {
    test('pane/tab/workspace_not_found を kind に変換する', () {
      expect(
        herdrTargetNotFoundKindForCode('pane_not_found'),
        HerdrTargetNotFoundKind.pane,
      );
      expect(
        herdrTargetNotFoundKindForCode('tab_not_found'),
        HerdrTargetNotFoundKind.tab,
      );
      expect(
        herdrTargetNotFoundKindForCode('workspace_not_found'),
        HerdrTargetNotFoundKind.workspace,
      );
    });

    test('未知のコード・null は null', () {
      expect(herdrTargetNotFoundKindForCode('internal_error'), isNull);
      expect(herdrTargetNotFoundKindForCode(null), isNull);
    });
  });

  group('isHerdrInvalidKey（R9 防御的分類）', () {
    test('errorCode が invalid_key なら true', () {
      expect(kHerdrInvalidKeyErrorCodes, contains('invalid_key'));
      final e = HerdrCommandException(
        'herdr command failed: unsupported key Home',
        exitCode: 1,
        errorCode: 'invalid_key',
      );
      expect(isHerdrInvalidKey(e), isTrue);
    });

    test('target-not-found / server-down / その他は false', () {
      expect(
        isHerdrInvalidKey(
          HerdrCommandException('boom', errorCode: 'pane_not_found'),
        ),
        isFalse,
      );
      expect(
        isHerdrInvalidKey(
          HerdrCommandException('boom', errorCode: 'server_not_running'),
        ),
        isFalse,
      );
      expect(
        isHerdrInvalidKey(HerdrCommandException('boom', exitCode: 1)),
        isFalse,
      );
      expect(
        isHerdrInvalidKey(
          HerdrTargetNotFoundException(
            kind: HerdrTargetNotFoundKind.pane,
            message: 'no pane',
          ),
        ),
        isFalse,
      );
      expect(isHerdrInvalidKey(Exception('other')), isFalse);
    });
  });
}
