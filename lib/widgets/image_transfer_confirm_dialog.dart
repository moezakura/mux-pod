import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../providers/settings_provider.dart';

/// リサイズプリセット
enum ImageResizePreset {
  original,
  small,
  medium,
  large,
  custom;

  String get label {
    switch (this) {
      case original:
        return 'Original';
      case small:
        return 'Small';
      case medium:
        return 'Medium';
      case large:
        return 'Large';
      case custom:
        return 'Custom';
    }
  }

  /// 長辺の最大ピクセル数（original/customは0）
  int get maxLongSide {
    switch (this) {
      case original:
        return 0;
      case small:
        return 480;
      case medium:
        return 1080;
      case large:
        return 1920;
      case custom:
        return 0;
    }
  }

  static ImageResizePreset fromString(String value) {
    switch (value) {
      case 'small':
        return small;
      case 'medium':
        return medium;
      case 'large':
        return large;
      case 'custom':
        return custom;
      default:
        return original;
    }
  }
}

/// 確認ダイアログの戻り値（全設定のオーバーライド値を含む）
class ImageTransferOptions {
  final String remotePath;
  final String outputFormat;
  final int jpegQuality;
  final ImageResizePreset resizePreset;
  final int customMaxWidth;
  final int customMaxHeight;
  final String pathFormat;
  final bool autoEnter;
  final bool bracketedPaste;

  const ImageTransferOptions({
    required this.remotePath,
    required this.outputFormat,
    required this.jpegQuality,
    required this.resizePreset,
    required this.customMaxWidth,
    required this.customMaxHeight,
    required this.pathFormat,
    required this.autoEnter,
    required this.bracketedPaste,
  });

  /// リサイズが必要か
  bool get needsResize => resizePreset != ImageResizePreset.original;

  /// 実効最大幅
  int get effectiveMaxWidth {
    if (resizePreset == ImageResizePreset.custom) return customMaxWidth;
    return resizePreset.maxLongSide;
  }

  /// 実効最大高さ
  int get effectiveMaxHeight {
    if (resizePreset == ImageResizePreset.custom) return customMaxHeight;
    return resizePreset.maxLongSide;
  }
}

/// 画像転送確認ダイアログ
///
/// 設定画面のデフォルト値を初期値として表示し、
/// 今回のアップロードだけに適用する一時的なオーバーライドが可能。
class ImageTransferConfirmDialog extends StatefulWidget {
  final String remotePath;
  final Uint8List imageBytes;
  final String? imageName;
  final AppSettings settings;

  const ImageTransferConfirmDialog({
    super.key,
    required this.remotePath,
    required this.imageBytes,
    this.imageName,
    required this.settings,
  });

  static Future<ImageTransferOptions?> show(
    BuildContext context, {
    required String remotePath,
    required Uint8List imageBytes,
    String? imageName,
    required AppSettings settings,
  }) {
    return showDialog<ImageTransferOptions>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ImageTransferConfirmDialog(
        remotePath: remotePath,
        imageBytes: imageBytes,
        imageName: imageName,
        settings: settings,
      ),
    );
  }

  @override
  State<ImageTransferConfirmDialog> createState() =>
      _ImageTransferConfirmDialogState();
}

class _ImageTransferConfirmDialogState
    extends State<ImageTransferConfirmDialog> {
  late final TextEditingController _pathController;
  late final TextEditingController _pathFormatController;
  late final TextEditingController _maxWidthController;
  late final TextEditingController _maxHeightController;

  late String _outputFormat;
  late int _jpegQuality;
  late ImageResizePreset _resizePreset;
  late bool _autoEnter;
  late bool _bracketedPaste;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _pathController = TextEditingController(text: widget.remotePath);
    _pathFormatController = TextEditingController(text: s.imagePathFormat);
    _maxWidthController = TextEditingController(
      text: s.imageMaxWidth.toString(),
    );
    _maxHeightController = TextEditingController(
      text: s.imageMaxHeight.toString(),
    );
    _outputFormat = s.imageOutputFormat;
    _jpegQuality = s.imageJpegQuality;
    _resizePreset = ImageResizePreset.fromString(s.imageResizePreset);
    _autoEnter = s.imageAutoEnter;
    _bracketedPaste = s.imageBracketedPaste;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _pathFormatController.dispose();
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  ImageTransferOptions _buildOptions() {
    return ImageTransferOptions(
      remotePath: _pathController.text.trim(),
      outputFormat: _outputFormat,
      jpegQuality: _jpegQuality,
      resizePreset: _resizePreset,
      customMaxWidth: int.tryParse(_maxWidthController.text) ?? 1920,
      customMaxHeight: int.tryParse(_maxHeightController.text) ?? 1080,
      pathFormat: _pathFormatController.text.trim(),
      autoEnter: _autoEnter,
      bracketedPaste: _bracketedPaste,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      title: Text(context.l10n.imgTransferTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 画像プレビュー + ファイル情報
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(
                          height: 100,
                          child: Center(
                            child: Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (widget.imageName != null)
                    Expanded(
                      child: Text(
                        widget.imageName!,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Text(
                    _formatSize(widget.imageBytes.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // --- 優先度高: 常時表示 ---

              // Output Format
              _label(context.l10n.imgTransferFormatLabel),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'original',
                    label: Text(context.l10n.imgTransferFormatOriginal),
                  ),
                  const ButtonSegment(value: 'png', label: Text('PNG')),
                  const ButtonSegment(value: 'jpeg', label: Text('JPEG')),
                ],
                selected: {_outputFormat},
                onSelectionChanged: (v) =>
                    setState(() => _outputFormat = v.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(theme.textTheme.bodySmall),
                ),
              ),
              const SizedBox(height: 12),

              // Resize
              _label(context.l10n.imgTransferResizeLabel),
              const SizedBox(height: 4),
              SegmentedButton<ImageResizePreset>(
                segments: [
                  ButtonSegment(
                    value: ImageResizePreset.original,
                    label: Text(context.l10n.imgTransferFormatOriginal),
                  ),
                  ButtonSegment(
                    value: ImageResizePreset.small,
                    label: Text(context.l10n.imgTransferSizeSmall),
                  ),
                  ButtonSegment(
                    value: ImageResizePreset.medium,
                    label: Text(context.l10n.imgTransferSizeMedium),
                  ),
                  ButtonSegment(
                    value: ImageResizePreset.large,
                    label: Text(context.l10n.imgTransferSizeLarge),
                  ),
                ],
                selected: {
                  _resizePreset == ImageResizePreset.custom
                      ? ImageResizePreset.original
                      : _resizePreset,
                },
                onSelectionChanged: (v) =>
                    setState(() => _resizePreset = v.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(theme.textTheme.bodySmall),
                ),
              ),
              const SizedBox(height: 12),

              // Bracketed Paste
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  context.l10n.imgTransferBracketedPaste,
                  style: theme.textTheme.bodyMedium,
                ),
                value: _bracketedPaste,
                onChanged: (v) => setState(() => _bracketedPaste = v),
              ),

              // --- Advanced ---
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  context.l10n.imgTransferAdvanced,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                ),
                children: [
                  // Remote Path
                  _label(context.l10n.imgTransferRemotePath),
                  const SizedBox(height: 4),
                  _textField(_pathController),
                  const SizedBox(height: 12),

                  // Path Format
                  _label(context.l10n.imgTransferPathFormat),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.imgTransferPathFormatHint('path'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _textField(_pathFormatController),
                  const SizedBox(height: 12),

                  // JPEG Quality
                  if (_outputFormat == 'jpeg') ...[
                    Row(
                      children: [
                        _label(context.l10n.imgTransferJpegQuality),
                        const Spacer(),
                        Text(
                          '$_jpegQuality%',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Slider(
                      value: _jpegQuality.toDouble(),
                      min: 1,
                      max: 100,
                      onChanged: (v) =>
                          setState(() => _jpegQuality = v.round()),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Custom Size
                  _label(context.l10n.imgTransferCustomSize),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _numberField(
                          _maxWidthController,
                          context.l10n.imgTransferWidth,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('x'),
                      ),
                      Expanded(
                        child: _numberField(
                          _maxHeightController,
                          context.l10n.imgTransferHeight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(
                          () => _resizePreset = ImageResizePreset.custom,
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                          context.l10n.imgTransferApply,
                          style: TextStyle(
                            color: _resizePreset == ImageResizePreset.custom
                                ? theme.colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Auto Enter
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.l10n.imgTransferAutoEnter,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      context.l10n.imgTransferAutoEnterSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    value: _autoEnter,
                    onChanged: (v) => setState(() => _autoEnter = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(context.l10n.imgTransferCancel),
        ),
        FilledButton(
          onPressed: () {
            final path = _pathController.text.trim();
            if (path.isNotEmpty) {
              Navigator.pop(context, _buildOptions());
            }
          },
          child: Text(context.l10n.imgTransferUpload),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
    );
  }

  Widget _textField(TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        hintText: hint,
      ),
    );
  }
}
