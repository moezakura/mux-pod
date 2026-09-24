// G5/G6: 画像転送・ダウンロードのリスナー単一所有（terminal-transfer-flow・
// 移設元 L7558-7722）。表示仕様は ui の純関数（SessionEnv 経由）を import し、
// SnackBar 多重抑止は追加しない（HEAD 同等・H4）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../providers/download_provider.dart';
import '../../../../providers/image_transfer_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../providers/tmux_provider.dart';
import '../../../../services/backend/domain/pane_writer.dart';
import '../../../../services/backend/domain/tmux_pane_writer.dart';
import '../../../../widgets/image_transfer_confirm_dialog.dart';
import '../../../l10n/l10n_ext.dart';
import '../../file_browser/file_browser_screen.dart';
import 'session_env.dart';
import 'session_runtime.dart';

/// G5/G6: 画像転送・ダウンロードのフロー（リスナー単一所有・1 回登録ガード）。
class TerminalTransferFlow {
  TerminalTransferFlow(this.env, this.runtime);

  final SessionEnv env;
  final SessionRuntimeController runtime;

  ProviderSubscription? _downloadSub;
  ProviderSubscription? _imageTransferSub;

  /// リスナー 2 本の単一登録（`ensureListeners`・P3 で破棄）。
  Future<void> ensureListeners() async {
    _ensureDownloadListener();
    await _ensureImageTransferListener();
  }

  // ---------------------------------------------------------------------------
  // G6: ダウンロード SnackBar（`_ensureDownloadListener`・移設元 L7558-7578）
  // ---------------------------------------------------------------------------

  void _ensureDownloadListener() {
    if (_downloadSub != null) return;
    _downloadSub = env.ref.listenManual<DownloadState>(downloadProvider, (
      prev,
      next,
    ) {
      if (!env.transferHost.isMounted || env.transferHost.isDisposed) return;
      final display = env.downloadSnackBarDisplay?.call(
        env.host.context.l10n,
        next,
        prev?.phase,
      );
      if (display == null) return;
      ScaffoldMessenger.of(env.transferHost.context).showSnackBar(
        SnackBar(
          content: Text(display.message),
          backgroundColor: display.backgroundColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // G5: 画像転送（`_ensureImageTransferListener`・移設元 L7579-7637）
  // ---------------------------------------------------------------------------

  Future<void> _ensureImageTransferListener() async {
    if (_imageTransferSub != null) return;
    _imageTransferSub = env.ref.listenManual<ImageTransferState>(
      imageTransferProvider,
      (prev, next) async {
        if (next.phase == ImageTransferPhase.confirming &&
            next.pickedImageBytes != null &&
            next.pendingRemotePath != null &&
            (prev?.phase == ImageTransferPhase.picking)) {
          if (!env.transferHost.isMounted) return;
          final settings = env.ref.read(settingsProvider);
          final options = await ImageTransferConfirmDialog.show(
            env.transferHost.context,
            remotePath: next.pendingRemotePath!,
            imageBytes: next.pickedImageBytes!,
            imageName: next.pickedImageName,
            settings: settings,
          );

          if (options != null) {
            final uploadedPath = await env.ref
                .read(imageTransferProvider.notifier)
                .confirmAndUpload(options: options);

            if (uploadedPath != null && env.transferHost.isMounted) {
              await injectImagePath(uploadedPath, options);
            }
          } else {
            env.ref.read(imageTransferProvider.notifier).cancel();
          }
        }

        if (next.phase == ImageTransferPhase.error &&
            env.transferHost.isMounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(env.transferHost.context).showSnackBar(
            SnackBar(
              content: Text(
                next.errorMessage ??
                    env.transferHost.context.l10n.termImageTransferFailed,
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }

        if (next.phase == ImageTransferPhase.completed &&
            next.lastUploadedPath != null &&
            env.transferHost.isMounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(env.transferHost.context).showSnackBar(
            SnackBar(
              content: Text(
                env.transferHost.context.l10n.termUploaded(
                  next.lastUploadedPath!,
                ),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
    );
  }

  /// ファイルブラウザを開く（`_handleFileBrowser`・移設元 L7638-7651）。
  void handleFileBrowser() {
    final activePaneId = env.ref.read(tmuxProvider).activePaneId;
    Navigator.push(
      env.host.context,
      MaterialPageRoute(
        builder: (context) => FileBrowserScreen(
          connectionId: env.host.connectionId,
          paneId: activePaneId,
        ),
      ),
    );
  }

  /// 画像転送フローを開始（`_handleImageTransfer`・移設元 L7652-7691）。
  void handleImageTransfer() {
    ensureListeners();

    showModalBottomSheet(
      context: env.host.context,
      backgroundColor: Theme.of(env.host.context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(env.host.context.l10n.termGallery),
              onTap: () {
                Navigator.pop(ctx);
                env.ref
                    .read(imageTransferProvider.notifier)
                    .pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(env.host.context.l10n.termCamera),
              onTap: () {
                Navigator.pop(ctx);
                env.ref
                    .read(imageTransferProvider.notifier)
                    .pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// アップロード済み画像のパスをターミナルに注入（`_injectImagePath`・移設元 L7692-7722）。
  Future<void> injectImagePath(String remotePath, Object optionsObject) async {
    if (!runtime.can(const PaneCapabilities(imageTransfer: true))) return;

    final writer = runtime.paneWriter;
    final paneId = runtime.targetSource?.currentPaneId;
    if (writer == null || paneId == null) return;

    final options = optionsObject as ImageTransferOptions;
    final formattedPath = options.pathFormat.replaceAll('{path}', remotePath);

    if (writer is TmuxPaneWriter) {
      await writer.sendBracketedPaste(
        paneId: paneId,
        path: formattedPath,
        bracketedPaste: options.bracketedPaste,
        autoEnter: options.autoEnter,
      );
    } else {
      await writer.pasteText(paneId, formattedPath);
    }

    runtime.boostPolling();
  }

  /// P3: subscription 破棄（`disposeSubscriptions`）。
  void disposeSubscriptions() {
    _downloadSub?.close();
    _downloadSub = null;
    _imageTransferSub?.close();
    _imageTransferSub = null;
  }
}
