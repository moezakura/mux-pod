import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/services/image/image_converter.dart';

void main() {
  group('ImageOutputFormat', () {
    test('fromString parses known values', () {
      expect(
        ImageOutputFormat.fromString('original'),
        ImageOutputFormat.original,
      );
      expect(ImageOutputFormat.fromString('png'), ImageOutputFormat.png);
      expect(ImageOutputFormat.fromString('jpeg'), ImageOutputFormat.jpeg);
    });

    test('fromString returns original for unknown values', () {
      expect(ImageOutputFormat.fromString('bmp'), ImageOutputFormat.original);
      expect(ImageOutputFormat.fromString(''), ImageOutputFormat.original);
    });
  });

  group('ImageConverter.detectExtension', () {
    test('detects JPEG from magic bytes', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      expect(ImageConverter.detectExtension(bytes), 'jpg');
    });

    test('detects PNG from magic bytes', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      expect(ImageConverter.detectExtension(bytes), 'png');
    });

    test('detects GIF from magic bytes', () {
      final bytes = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      expect(ImageConverter.detectExtension(bytes), 'gif');
    });

    test('detects HEIC from ftyp heic brand', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x68, 0x65, 0x69, 0x63, // "heic"
        ...List.filled(20, 0),
      ]);
      expect(ImageConverter.detectExtension(bytes), 'heic');
    });

    test('detects HEIC from ftyp mif1 brand', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x1C, // box size
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x6D, 0x69, 0x66, 0x31, // "mif1"
        ...List.filled(20, 0),
      ]);
      expect(ImageConverter.detectExtension(bytes), 'heic');
    });

    test('detects HEIC from ftyp hevc brand', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x68, 0x65, 0x76, 0x63, // "hevc"
        ...List.filled(20, 0),
      ]);
      expect(ImageConverter.detectExtension(bytes), 'heic');
    });

    test('detects HEIC from ftyp heix brand', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x68, 0x65, 0x69, 0x78, // "heix"
        ...List.filled(20, 0),
      ]);
      expect(ImageConverter.detectExtension(bytes), 'heic');
    });

    test('does not detect HEIC from non-HEIF ftyp (mp41)', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x6D, 0x70, 0x34, 0x31, // "mp41"
        ...List.filled(20, 0),
      ]);
      expect(ImageConverter.detectExtension(bytes), 'png'); // デフォルト
    });

    test('does not detect HEIC from non-HEIF ftyp (isom)', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x69, 0x73, 0x6F, 0x6D, // "isom"
        ...List.filled(20, 0),
      ]);
      expect(ImageConverter.detectExtension(bytes), 'png'); // デフォルト
    });

    test('returns png for bytes too short for ftyp detection', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70,
        0x68, 0x65, 0x69, // 11 bytes, need 12
      ]);
      expect(ImageConverter.detectExtension(bytes), 'png');
    });

    test('returns png for unknown format', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      expect(ImageConverter.detectExtension(bytes), 'png');
    });

    test('returns png for empty bytes', () {
      final bytes = Uint8List.fromList([]);
      expect(ImageConverter.detectExtension(bytes), 'png');
    });
  });

  group('ImageConverter.convert', () {
    test(
      'returns original bytes when format is original and no resize',
      () async {
        final jpegHeader = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          ...List.filled(100, 0),
        ]);
        final result = await ImageConverter.convert(
          bytes: jpegHeader,
          format: ImageOutputFormat.original,
          autoResize: false,
        );
        expect(result.bytes, jpegHeader);
        expect(result.extension, 'jpg');
      },
    );
  });
}
