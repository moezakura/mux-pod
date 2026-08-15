import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/terminal/tmux_key_display.dart';

/// キーオーバーレイの状態管理
///
/// [ValueNotifier] と異なり、同じ値でも [notifyListeners] を呼ぶため
/// 連打時のパルスアニメーションが正しくトリガーされる。
class KeyOverlayState extends ChangeNotifier {
  String? _text;
  bool _pulse = false;

  String? get text => _text;
  bool get pulse => _pulse;

  void show(String newText) {
    _pulse = _text == newText;
    _text = newText;
    notifyListeners();
  }

  void hide() {
    _text = null;
    _pulse = false;
    notifyListeners();
  }
}

/// キー送信時のオーバーレイ表示ウィジェット
class KeyOverlayWidget extends StatefulWidget {
  final KeyOverlayState overlayState;
  final KeyOverlayPosition position;

  const KeyOverlayWidget({
    super.key,
    required this.overlayState,
    this.position = KeyOverlayPosition.aboveKeyboard,
  });

  @override
  State<KeyOverlayWidget> createState() => _KeyOverlayWidgetState();
}

class _KeyOverlayWidgetState extends State<KeyOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pulseAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        );
    widget.overlayState.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(KeyOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayState != widget.overlayState) {
      oldWidget.overlayState.removeListener(_onStateChanged);
      widget.overlayState.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.overlayState.removeListener(_onStateChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (widget.overlayState.pulse) {
      _pulseController.forward(from: 0);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.overlayState.text;

    if (widget.position == KeyOverlayPosition.center) {
      return Positioned.fill(
        child: IgnorePointer(child: Center(child: _buildOverlay(text))),
      );
    }

    return Positioned(
      top: widget.position == KeyOverlayPosition.belowHeader ? 8 : null,
      bottom: widget.position == KeyOverlayPosition.aboveKeyboard ? 8 : null,
      left: 0,
      right: 0,
      child: IgnorePointer(child: Center(child: _buildOverlay(text))),
    );
  }

  Widget _buildOverlay(String? text) {
    return AnimatedOpacity(
      opacity: text != null ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: text != null
          ? ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2B35).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  text,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
