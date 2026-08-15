import 'package:flutter/material.dart';

import '../../../theme/design_colors.dart';

/// パスバー（Breadcrumb）
///
/// 現在のパスをセグメントとして表示し、各セグメントをタップして
/// そのディレクトリにジャンプできる。長押しで直接パス入力モード。
class PathBar extends StatefulWidget {
  final String currentPath;
  final ValueChanged<String> onPathSelected;

  const PathBar({
    super.key,
    required this.currentPath,
    required this.onPathSelected,
  });

  @override
  State<PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<PathBar> {
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
  }

  @override
  void didUpdateWidget(PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath != widget.currentPath && !_isEditing) {
      _controller.text = widget.currentPath;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? DesignColors.canvasDark : DesignColors.canvasLight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: bgColor,
      child: _isEditing
          ? _buildEditMode(context, isDark)
          : _buildBreadcrumb(isDark),
    );
  }

  Widget _buildBreadcrumb(bool isDark) {
    final segments = _pathSegments(widget.currentPath);
    final textColor = isDark
        ? DesignColors.textSecondary
        : DesignColors.textSecondaryLight;
    final activeColor = isDark
        ? DesignColors.textPrimary
        : DesignColors.textPrimaryLight;

    return GestureDetector(
      onLongPress: () => setState(() => _isEditing = true),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.chevron_right, size: 16, color: textColor),
                ),
              InkWell(
                onTap: () => widget.onPathSelected(segments[i].path),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    segments[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      color: i == segments.length - 1 ? activeColor : textColor,
                      fontWeight: i == segments.length - 1
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditMode(BuildContext context, bool isDark) {
    final borderColor = isDark
        ? DesignColors.borderDark
        : DesignColors.borderLight;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? DesignColors.textPrimary
                  : DesignColors.textPrimaryLight,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: DesignColors.primary),
              ),
            ),
            onSubmitted: (value) {
              setState(() => _isEditing = false);
              if (value.isNotEmpty) {
                widget.onPathSelected(value);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () {
            setState(() => _isEditing = false);
            _controller.text = widget.currentPath;
          },
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  List<_PathSegment> _pathSegments(String path) {
    final segments = <_PathSegment>[_PathSegment(label: '/', path: '/')];

    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    for (var i = 0; i < parts.length; i++) {
      final fullPath = '/${parts.sublist(0, i + 1).join('/')}';
      segments.add(_PathSegment(label: parts[i], path: fullPath));
    }

    return segments;
  }
}

class _PathSegment {
  final String label;
  final String path;

  const _PathSegment({required this.label, required this.path});
}
