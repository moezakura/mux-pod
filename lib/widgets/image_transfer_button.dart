import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n_ext.dart';
import '../providers/image_transfer_provider.dart';

/// 画像転送ボタン
///
/// SpecialKeysBar の横に配置される36x36のアイコンボタン。
/// タップでギャラリー/カメラ選択のBottomSheetを表示する。
class ImageTransferButton extends ConsumerWidget {
  final VoidCallback? onTransferComplete;

  const ImageTransferButton({
    super.key,
    this.onTransferComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transferState = ref.watch(imageTransferProvider);
    final isUploading = transferState.phase == ImageTransferPhase.uploading ||
        transferState.phase == ImageTransferPhase.converting;
    final isIdle = transferState.canPick;

    return SizedBox(
      width: 36,
      height: 36,
      child: isUploading
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(
                value: transferState.uploadProgress > 0
                    ? transferState.uploadProgress
                    : null,
                strokeWidth: 2.0,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : IconButton(
              onPressed: isIdle ? () => _showSourcePicker(context, ref) : null,
              icon: Icon(
                _iconForPhase(transferState.phase),
                size: 20,
                color: isIdle
                    ? Colors.white70
                    : transferState.phase == ImageTransferPhase.error
                        ? Colors.redAccent
                        : Colors.green,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              tooltip: context.l10n.imgTransferSendImage,
            ),
    );
  }

  IconData _iconForPhase(ImageTransferPhase phase) {
    switch (phase) {
      case ImageTransferPhase.completed:
        return Icons.check_circle_outline;
      case ImageTransferPhase.error:
        return Icons.error_outline;
      default:
        return Icons.image_outlined;
    }
  }

  void _showSourcePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(context.l10n.imgTransferGallery),
              onTap: () {
                Navigator.pop(context);
                ref.read(imageTransferProvider.notifier).pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(context.l10n.imgTransferCamera),
              onTap: () {
                Navigator.pop(context);
                ref.read(imageTransferProvider.notifier).pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
}
