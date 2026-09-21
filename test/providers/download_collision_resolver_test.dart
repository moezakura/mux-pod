import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/providers/download_collision_resolver.dart';
import 'package:flutter_muxpod/providers/download_state.dart';
import 'package:flutter_muxpod/services/sftp/overwrite_choice.dart';

void main() {
  const resolver = DownloadCollisionResolver();

  DownloadItemState item(String name, {bool overwrite = false}) =>
      DownloadItemState(
        remotePath: '/remote/$name',
        name: name,
        localPath: name,
        overwrite: overwrite,
      );

  group('DownloadCollisionResolver.firstAvailableName', () {
    test('保存先に存在しない場合は name_1 から採番される', () async {
      var calls = <String>[];
      Future<bool> exists(String n) async {
        calls.add(n);
        return false;
      }

      final result = await resolver.firstAvailableName(
        'data.bin',
        existsIn: exists,
      );

      expect(result, 'data_1.bin');
      expect(calls, ['data_1.bin']);
    });

    test('repo にある名前はスキップして次の番号を採番する', () async {
      final exists = <String>{'data_1.bin'};

      final result = await resolver.firstAvailableName(
        'data.bin',
        reserved: exists,
        existsIn: (_) async => false,
      );

      expect(result, 'data_2.bin');
    });

    test('destination に存在する名前はスキップして次の番号を採番する', () async {
      final exists = <String>{'data_1.bin', 'data_2.bin'};

      final result = await resolver.firstAvailableName(
        'data.bin',
        existsIn: (n) async => exists.contains(n),
      );

      expect(result, 'data_3.bin');
    });

    test('拡張子なしの名前は `_1` を末尾に付ける', () async {
      final result = await resolver.firstAvailableName(
        'README',
        existsIn: (_) async => false,
      );

      expect(result, 'README_1');
    });
  });

  group('DownloadCollisionResolver.firstAvailablePath', () {
    test('常に _1 から採番する（実ファイルが存在しなくても name_1 を返す）', () {
      final result = resolver.firstAvailablePath('/tmp/sftp_download/a.txt');

      expect(result, '/tmp/sftp_download/a_1.txt');
    });

    test('実ファイルが存在する場合は次の番号を採番する', () {
      final dir = Directory.systemTemp.createTempSync('collision_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/a_1.txt').writeAsStringSync('x');
      File('${dir.path}/a_2.txt').writeAsStringSync('x');

      final result = resolver.firstAvailablePath('${dir.path}/a.txt');

      expect(result, '${dir.path}/a_3.txt');
    });

    test('reserved に含まれる名前はスキップする', () {
      final result = resolver.firstAvailablePath(
        '/tmp/a.txt',
        reserved: {'/tmp/a_1.txt'},
      );

      expect(result, '/tmp/a_2.txt');
    });
  });

  group('DownloadCollisionResolver.preScan', () {
    test('保存先に存在する名前のアイテムのみ衝突として返す', () async {
      final exists = <String>{'b.txt'};
      final items = [item('a.txt'), item('b.txt'), item('c.txt')];

      final colliding = await resolver.preScan(
        items,
        existsIn: (n) async => exists.contains(n),
      );

      expect(colliding.map((i) => i.name), ['b.txt']);
    });
  });

  group('DownloadCollisionResolver.resolveDecisions', () {
    test('決定なし（null）はそのまま維持する', () async {
      final items = [item('a.txt')];

      final result = await resolver.resolveDecisions(
        decisions: {},
        items: items,
        reserved: {},
        existsIn: (_) async => false,
      );

      expect(result.cancelled, isFalse);
      expect(result.items.single.overwrite, isFalse);
      expect(result.items.single.isSkipped, isFalse);
    });

    test('overwrite 決定は overwrite=true にする', () async {
      final items = [item('a.txt')];

      final result = await resolver.resolveDecisions(
        decisions: {'a.txt': OverwriteChoice.overwrite},
        items: items,
        reserved: {},
        existsIn: (_) async => false,
      );

      expect(result.items.single.overwrite, isTrue);
      expect(result.items.single.name, 'a.txt');
    });

    test('rename 決定は _1 採番 + overwrite=true にする', () async {
      final items = [item('a.txt')];

      final result = await resolver.resolveDecisions(
        decisions: {'a.txt': OverwriteChoice.rename},
        items: items,
        reserved: {'a.txt'},
        existsIn: (_) async => false,
      );

      final renamed = result.items.single;
      expect(renamed.name, 'a_1.txt');
      expect(renamed.localPath, 'a_1.txt');
      expect(renamed.overwrite, isTrue);
    });

    test('skip 決定は isSkipped=true にする', () async {
      final items = [item('a.txt')];

      final result = await resolver.resolveDecisions(
        decisions: {'a.txt': OverwriteChoice.skip},
        items: items,
        reserved: {},
        existsIn: (_) async => false,
      );

      expect(result.items.single.isSkipped, isTrue);
    });

    test('cancel 決定は cancelled=true で items 空を返す', () async {
      final items = [item('a.txt'), item('b.txt')];

      final result = await resolver.resolveDecisions(
        decisions: {'a.txt': OverwriteChoice.cancel},
        items: items,
        reserved: {},
        existsIn: (_) async => false,
      );

      expect(result.cancelled, isTrue);
      expect(result.items, isEmpty);
    });

    test('rename はバッチ内の他アイテム宛先（reserved）を避けて採番する', () async {
      // バッチ内に a.txt と a_1.txt が存在（LOW#3: 他アイテム宛先も予約済み）。
      final items = [item('a.txt'), item('a_1.txt')];

      final result = await resolver.resolveDecisions(
        decisions: {'a.txt': OverwriteChoice.rename},
        items: items,
        reserved: {'a.txt', 'a_1.txt'},
        existsIn: (_) async => false,
      );

      expect(result.items.first.name, 'a_2.txt');
    });
  });
}
