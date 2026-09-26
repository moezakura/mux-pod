import 'dart:async';

import 'package:flutter/widgets.dart';

/// A discrete blink only while the app and terminal route are visible.
class CaretBlinkController extends ValueNotifier<bool>
    with WidgetsBindingObserver {
  CaretBlinkController() : super(true) {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _update();
  }

  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;

  void setVisible(bool visible) {
    _visible = visible;
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }

  void _update() {
    if (!_foreground || !_visible) {
      _timer?.cancel();
      _timer = null;
      value = true;
    } else {
      _timer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
        value = !value;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
