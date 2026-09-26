import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/caret_blink_controller.dart';

void main() {
  testWidgets('blink stops in background and hidden routes; resumes once', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final blink = CaretBlinkController();
    await tester.pump(const Duration(milliseconds: 500));
    expect(blink.value, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(blink.value, true);
    await tester.pump(const Duration(seconds: 3));
    expect(blink.value, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(blink.value, false);
    blink.setVisible(false);
    await tester.pump(const Duration(seconds: 3));
    expect(blink.value, true);
    blink.setVisible(true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(blink.value, false);
    blink.dispose();
    await tester.pump(const Duration(seconds: 3));
  });
}
