import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' as xterm;

/// ターミナル表示Widget
class MuxTerminalView extends StatelessWidget {
  final xterm.Terminal terminal;
  final xterm.TerminalController? controller;
  final bool autofocus;
  final double backgroundOpacity;
  final xterm.TerminalStyle? textStyle;
  final void Function(Size size)? onResize;

  const MuxTerminalView({
    super.key,
    required this.terminal,
    this.controller,
    this.autofocus = true,
    this.backgroundOpacity = 1.0,
    this.textStyle,
    this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // サイズ変更を通知
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onResize?.call(Size(constraints.maxWidth, constraints.maxHeight));
        });

        return xterm.TerminalView(
          terminal,
          controller: controller,
          autofocus: autofocus,
          backgroundOpacity: backgroundOpacity,
          textStyle: textStyle ?? const xterm.TerminalStyle(
            fontSize: 14,
            fontFamily: 'JetBrains Mono',
          ),
        );
      },
    );
  }
}
