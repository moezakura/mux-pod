/// HerdrCaretComposer.ensureStatus() のテスト（herdr OSC 8
/// ハイパーリンク実験機能・Herdr status の single-flight 共有）。
///
/// 手書き fake（[FakeHerdrCaretHost]）で [HerdrCaretHost] を実装し、
/// SSH 実行は [FakeSshClient] で観測する。`refreshStatus` は取得中の再接続で
/// 古い client の status を書き戻さないことを確認するため
/// `_host.ref.read(sshProvider.notifier).client` を参照する。
/// そのため `ref` は本物の [WidgetRef] を、最小限の widget を pump して得る
/// （`testWidgets` を使う。他のフィールドは手書き fake のまま）。
library;

import 'package:flutter_muxpod/providers/ssh_provider.dart';
import 'package:flutter_muxpod/screens/terminal/herdr/herdr_caret.dart';
import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_ssh_client.dart';
import '../../../helpers/fake_ssh_notifier.dart';

import '../helpers/herdr_caret_composer_fakes.dart';

// 実測: server 稼働時の `herdr status --json`（herdr_adapter_status_test.dart
// の kStatusOk と同一値）。
const _kStatusOk =
    '{"client":{"version":"0.7.5","protocol":17},"server":{"status":"running",'
    '"running":true,"version":"0.7.5","protocol":17,"compatible":true,'
    '"socket":"/tmp/herdr.sock"},"update":{}}';

void main() {
  group('HerdrCaretComposer.ensureStatus', () {
    testWidgets('既に caretStatus が取得済みなら即時返却する（SSH 実行なし）', (tester) async {
      final ssh = FakeSshClient();
      ssh.execOutputs['herdr status --json'] = _kStatusOk;
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      host.caretStatusValue = const HerdrStatus(serverProtocol: 17);
      final composer = HerdrCaretComposer(host);

      final status = await composer.ensureStatus(ssh);

      expect(status.serverProtocol, 17);
      expect(
        ssh.execCommands.any((c) => c.contains('herdr status')),
        isFalse,
        reason: '既取得済みなら status 取得の SSH は 0 回であること',
      );
    });

    testWidgets('未取得なら1回だけ SSH で取得し、host.caretStatus へ反映する', (tester) async {
      final ssh = FakeSshClient();
      ssh.execOutputs['herdr status --json'] = _kStatusOk;
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      final status = await composer.ensureStatus(ssh);

      expect(status.serverProtocol, 17);
      expect(host.caretStatusValue?.serverProtocol, 17);
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        1,
      );
    });

    testWidgets('同時に呼ばれた ensureStatus は single-flight で1回に合流する', (
      tester,
    ) async {
      final ssh = FakeSshClient();
      ssh.execOutputs['herdr status --json'] = _kStatusOk;
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      final futures = [
        composer.ensureStatus(ssh),
        composer.ensureStatus(ssh),
        composer.ensureStatus(ssh),
      ];
      final results = await Future.wait(futures);

      for (final status in results) {
        expect(status.serverProtocol, 17);
      }
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        1,
        reason: '同時呼び出しは single-flight で1回の SSH 実行に合流すること',
      );
    });

    testWidgets('取得失敗時は既定値（const HerdrStatus()）を返す（throw しない）', (tester) async {
      final ssh = FakeSshClient();
      ssh.execExceptions['herdr status --json'] = Exception('boom');
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      final status = await composer.ensureStatus(ssh);

      expect(status, const HerdrStatus());
      expect(host.caretStatusValue, isNull);
    });

    testWidgets('取得完了後は in-flight フィールドが自己クリアされ、次回はまた1回実行する', (tester) async {
      final ssh = FakeSshClient();
      ssh.execExceptions['herdr status --json'] = Exception('boom');
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);

      // 1回目: 失敗して既定値。host.caretStatus は未設定のまま。
      await composer.ensureStatus(ssh);
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        1,
      );

      // in-flight が自己クリアされているため、2回目も新たに SSH を実行する
      // （直前の future に合流して 0 回になってはいけない）。
      await composer.ensureStatus(ssh);
      expect(
        ssh.execCommands.where((c) => c.contains('herdr status')).length,
        2,
      );
    });

    testWidgets('再接続で client が差し替わった後に完了した取得は、古い client の status を'
        '書き戻さない', (tester) async {
      final oldClient = FakeSshClient();
      oldClient.execOutputs['herdr status --json'] = _kStatusOk;
      final ref = await pumpRefFor(tester, oldClient);
      final host = FakeHerdrCaretHost(ref: ref);
      final composer = HerdrCaretComposer(host);

      // refreshStatus が oldClient で fetch している間に、"現在の" client が
      // 別の client へ差し替わったのと同じ状態を作る（sshProvider.notifier の
      // client を直接書き換える。fetch 自体は oldClient 引数で行われる）。
      final notifier = ref.read(sshProvider.notifier) as FakeSshNotifier;
      final newClient = FakeSshClient();
      notifier.client = newClient;

      // oldClient を引数に渡して fetch する（内部で fetch 完了後に
      // 「現在の client」= newClient と照合し、不一致なら書き戻さない）。
      await composer.ensureStatus(oldClient);

      expect(
        host.caretStatusValue,
        isNull,
        reason: '取得完了時に現在の client と不一致なら caretStatus を書き戻さないこと',
      );
    });
  });

  group('HerdrCaretComposer.ensureInstaller（helper installer '
      'の共有）', () {
    testWidgets('1回目は installer を構築して返し、2回目は同じインスタンスを返す（memo）', (tester) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);
      final manifest = testManifest();

      final installer1 = await composer.ensureInstaller(ssh, manifest);
      final installer2 = await composer.ensureInstaller(ssh, manifest);

      expect(
        identical(installer1, installer2),
        isTrue,
        reason: 'caret と hyperlink 読取で同じ installer インスタンスを共有すること',
      );
    });

    testWidgets('同時に呼ばれた ensureInstaller は single-flight で1つの構築に合流する', (
      tester,
    ) async {
      final ssh = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh));
      final composer = HerdrCaretComposer(host);
      final manifest = testManifest();

      final futures = [
        composer.ensureInstaller(ssh, manifest),
        composer.ensureInstaller(ssh, manifest),
        composer.ensureInstaller(ssh, manifest),
      ];
      final results = await Future.wait(futures);

      expect(identical(results[0], results[1]), isTrue);
      expect(identical(results[0], results[2]), isTrue);
    });

    testWidgets('別の SshClient（再接続相当）では memo を使い回さず新しい installer を構築する（'
        '接続単位で memoize する）', (tester) async {
      final ssh1 = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh1));
      final composer = HerdrCaretComposer(host);
      final manifest = testManifest();

      final installer1 = await composer.ensureInstaller(ssh1, manifest);

      // 再接続相当: 新しい SshClient で呼ぶ。
      final ssh2 = FakeSshClient();
      final installer2 = await composer.ensureInstaller(ssh2, manifest);

      expect(
        identical(installer1, installer2),
        isFalse,
        reason: '古い client に結びついた installer を使い回さないこと',
      );

      // 単一 slot の memo なので、client を ssh1 に戻すとまた作り直される
      // （ssh1 用の installer をキャッシュし続けているわけではない）。
      final installer1Again = await composer.ensureInstaller(ssh1, manifest);
      expect(identical(installer1Again, installer1), isFalse);
      expect(identical(installer1Again, installer2), isFalse);
    });

    testWidgets('再接続後は古い installer が caret 用・hyperlink 用のどちらにも返らない（'
        'caret（setupProduction）と hyperlink（setupHyperlinkProduction）'
        'は共に本メソッド 1 つだけを経由するため（herdr_caret.dart の '
        'setupProduction/setupHyperlinkProduction）、ここで「同一 client なら共有・'
        '別 client なら作り直し」を検証すれば両方の呼び出し元に伝播することを示す）', (tester) async {
      final ssh1 = FakeSshClient();
      final host = FakeHerdrCaretHost(ref: await pumpRefFor(tester, ssh1));
      final composer = HerdrCaretComposer(host);
      final manifest = testManifest();

      // caret 側・hyperlink 側それぞれの呼び出しを模す（同じ client）。
      final caretSideBefore = await composer.ensureInstaller(ssh1, manifest);
      final hyperlinkSideBefore = await composer.ensureInstaller(
        ssh1,
        manifest,
      );
      expect(
        identical(caretSideBefore, hyperlinkSideBefore),
        isTrue,
        reason: '再接続前は caret/hyperlink で共有される',
      );

      // 再接続相当。
      final ssh2 = FakeSshClient();
      final caretSideAfter = await composer.ensureInstaller(ssh2, manifest);
      final hyperlinkSideAfter = await composer.ensureInstaller(ssh2, manifest);

      expect(
        identical(caretSideAfter, hyperlinkSideAfter),
        isTrue,
        reason: '再接続後も caret/hyperlink で新しい installer を共有する',
      );
      expect(
        identical(caretSideAfter, caretSideBefore),
        isFalse,
        reason: '古い installer が caret 側に返らないこと',
      );
      expect(
        identical(hyperlinkSideAfter, caretSideBefore),
        isFalse,
        reason: '古い installer が hyperlink 側に返らないこと',
      );
    });
  });
}
