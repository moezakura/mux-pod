import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'fake_sftp_client.dart';

void main() {
  group('FakeSftpFile', () {
    test('writeBytes: 連続（offset順）で content が連結される', () async {
      final file = FakeSftpFile(
        FakeSftpClient(contentsByPath: {'/a': Uint8List(0)}),
        Uint8List(0),
      );

      final data1 = Uint8List.fromList([1, 2, 3]);
      final data2 = Uint8List.fromList([4, 5, 6, 7]);

      await file.writeBytes(data1, offset: 0);
      await file.writeBytes(data2, offset: data1.length);

      expect(file.content, [1, 2, 3, 4, 5, 6, 7]);
    });

    test('writeBytes: offset > 現在長でゼロパディング拡張される', () async {
      final file = FakeSftpFile(
        FakeSftpClient(contentsByPath: {'/a': Uint8List(0)}),
        Uint8List.fromList([10, 20]),
      );

      // offset=5 は現在長2を超える → [10, 20, 0, 0, 0, 99] になる
      await file.writeBytes(Uint8List.fromList([99]), offset: 5);

      expect(file.content, [10, 20, 0, 0, 0, 99]);
    });

    test('read: 連結後の total content を返す', () async {
      final file = FakeSftpFile(
        FakeSftpClient(contentsByPath: {'/a': Uint8List(0)}),
        Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final chunks = await file.read().toList();
      final restored = Uint8List(chunks.fold<int>(0, (s, c) => s + c.length));
      var offset = 0;
      for (final c in chunks) {
        restored.setRange(offset, offset + c.length, c);
        offset += c.length;
      }

      expect(restored, [1, 2, 3, 4, 5]);
    });

    test('read: offset/length で部分読み出し', () async {
      final file = FakeSftpFile(
        FakeSftpClient(contentsByPath: {'/a': Uint8List(0)}),
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );

      final chunks = await file.read(offset: 2, length: 3).toList();
      expect(chunks, [
        Uint8List.fromList([3, 4, 5]),
      ]);
    });

    test('close: closeCalls を毎回カウント（冪等化しない）', () async {
      final file = FakeSftpFile(
        FakeSftpClient(contentsByPath: {'/a': Uint8List(0)}),
        Uint8List(0),
      );

      await file.close();
      await file.close();
      expect(file.closeCalls, 2);
    });
  });
}
