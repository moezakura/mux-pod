import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../l10n/app_localizations.dart';

/// 画像出力フォーマット
enum ImageOutputFormat {
  original,
  png,
  jpeg;

  static ImageOutputFormat fromString(String value) {
    switch (value) {
      case 'png':
        return ImageOutputFormat.png;
      case 'jpeg':
        return ImageOutputFormat.jpeg;
      default:
        return ImageOutputFormat.original;
    }
  }
}

/// 画像変換結果
class ImageConvertResult {
  final Uint8List bytes;
  final String extension;

  const ImageConvertResult({required this.bytes, required this.extension});
}

/// 画像フォーマット変換 + リサイズサービス
///
/// `image` パッケージを使用し、Isolate でバックグラウンド実行する。
/// HEIC/HEIF は `flutter_image_compress` でネイティブAPI経由でJPEGに事前変換する。
class ImageConverter {
  /// 画像のフォーマット変換とリサイズを行う
  ///
  /// [bytes] 元の画像バイトデータ
  /// [format] 出力フォーマット（original/png/jpeg）
  /// [jpegQuality] JPEG品質（1-100）
  /// [autoResize] リサイズを行うか
  /// [maxWidth] 最大幅（0 = 無制限）
  /// [maxHeight] 最大高さ（0 = 無制限）
  /// [l10n] は任意。null の場合は英語フォールバック（テスト互換）。
  static Future<ImageConvertResult> convert({
    required Uint8List bytes,
    required ImageOutputFormat format,
    int jpegQuality = 85,
    bool autoResize = false,
    int maxWidth = 1920,
    int maxHeight = 1080,
    AppLocalizations? l10n,
  }) async {
    final detectedExt = detectExtension(bytes);

    // HEIC/HEIF はネイティブAPIでJPEGに事前変換
    Uint8List processedBytes = bytes;
    String effectiveExt = detectedExt;
    if (detectedExt == 'heic') {
      final converted = await _preProcessHeic(bytes, l10n);
      processedBytes = converted.bytes;
      effectiveExt = converted.extension;
    }

    // 変換不要の場合はそのまま返す
    if (format == ImageOutputFormat.original && !autoResize) {
      return ImageConvertResult(bytes: processedBytes, extension: effectiveExt);
    }

    // Isolate でバックグラウンド実行（UIスレッドブロック防止）
    return await Isolate.run(
      () => _processImage(
        bytes: processedBytes,
        format: format,
        jpegQuality: jpegQuality,
        autoResize: autoResize,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        sourceExtension: effectiveExt,
        l10n: l10n,
      ),
    );
  }

  /// HEIC/HEIF をネイティブAPIでJPEGに変換
  static Future<ImageConvertResult> _preProcessHeic(
    Uint8List bytes,
    AppLocalizations? l10n,
  ) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 95,
        format: CompressFormat.jpeg,
      );
      if (result.isEmpty) {
        throw FormatException(
          l10n?.imgTransferHeicEmptyResult ??
              'Native HEIC conversion returned empty result',
        );
      }
      return ImageConvertResult(
        bytes: Uint8List.fromList(result),
        extension: 'jpg',
      );
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException(
        l10n?.imgTransferHeicConvertFailed('$e') ??
            'Failed to convert HEIC image: $e',
      );
    }
  }

  /// Isolate 内で実行される画像処理
  static ImageConvertResult _processImage({
    required Uint8List bytes,
    required ImageOutputFormat format,
    required int jpegQuality,
    required bool autoResize,
    required int maxWidth,
    required int maxHeight,
    required String sourceExtension,
    AppLocalizations? l10n,
  }) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw FormatException(
        l10n?.imgTransferDecodeFailed ?? 'Failed to decode image',
      );
    }

    var processed = image;

    // リサイズ
    if (autoResize) {
      final needsResize =
          (maxWidth > 0 && processed.width > maxWidth) ||
          (maxHeight > 0 && processed.height > maxHeight);
      if (needsResize) {
        // アスペクト比を維持してリサイズ
        final widthRatio = maxWidth > 0 ? processed.width / maxWidth : 0.0;
        final heightRatio = maxHeight > 0 ? processed.height / maxHeight : 0.0;
        final ratio = widthRatio > heightRatio ? widthRatio : heightRatio;
        if (ratio > 1.0) {
          processed = img.copyResize(
            processed,
            width: (processed.width / ratio).round(),
            height: (processed.height / ratio).round(),
          );
        }
      }
    }

    // フォーマット変換
    switch (format) {
      case ImageOutputFormat.png:
        return ImageConvertResult(
          bytes: Uint8List.fromList(img.encodePng(processed)),
          extension: 'png',
        );
      case ImageOutputFormat.jpeg:
        return ImageConvertResult(
          bytes: Uint8List.fromList(
            img.encodeJpg(processed, quality: jpegQuality),
          ),
          extension: 'jpg',
        );
      case ImageOutputFormat.original:
        // リサイズのみ（元フォーマットで再エンコード）
        final ext = sourceExtension;
        if (ext == 'jpg' || ext == 'jpeg') {
          return ImageConvertResult(
            bytes: Uint8List.fromList(
              img.encodeJpg(processed, quality: jpegQuality),
            ),
            extension: ext,
          );
        }
        return ImageConvertResult(
          bytes: Uint8List.fromList(img.encodePng(processed)),
          extension: 'png',
        );
    }
  }

  /// バイトデータのマジックバイトからファイルフォーマットを検出
  static String detectExtension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    // HEIF/HEIC: ISOBMFF ftyp box
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (const {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'hevm',
        'hevs',
        'mif1',
      }.contains(brand)) {
        return 'heic';
      }
    }
    return 'png'; // デフォルト
  }
}
