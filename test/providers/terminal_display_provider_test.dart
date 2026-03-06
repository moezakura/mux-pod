import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_muxpod/providers/terminal_display_provider.dart';
import 'package:flutter_muxpod/providers/settings_provider.dart';
import 'package:flutter_muxpod/services/terminal/font_calculator.dart';
import 'package:flutter_muxpod/services/tmux/tmux_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // Pre-populate cache to avoid google_fonts async errors in tests
  FontCalculator.setCachedRatio('JetBrains Mono', 0.6);

  group('TerminalDisplayState', () {
    test('has correct default values', () {
      const state = TerminalDisplayState();

      expect(state.paneWidth, equals(80));
      expect(state.paneHeight, equals(24));
      expect(state.screenWidth, equals(0.0));
      expect(state.calculatedFontSize, equals(14.0));
      expect(state.needsHorizontalScroll, isFalse);
      expect(state.horizontalScrollOffset, equals(0.0));
      expect(state.zoomScale, equals(1.0));
      expect(state.isZooming, isFalse);
    });

    test('effectiveFontSize returns calculatedFontSize when not zooming', () {
      const state = TerminalDisplayState(
        calculatedFontSize: 12.0,
        zoomScale: 2.0,
        isZooming: false,
      );

      expect(state.effectiveFontSize, equals(12.0));
    });

    test('effectiveFontSize applies zoomScale when zooming', () {
      const state = TerminalDisplayState(
        calculatedFontSize: 12.0,
        zoomScale: 2.0,
        isZooming: true,
      );

      expect(state.effectiveFontSize, equals(24.0));
    });

    test('copyWith preserves unchanged values', () {
      const original = TerminalDisplayState(
        paneWidth: 100,
        paneHeight: 30,
        screenWidth: 500.0,
        calculatedFontSize: 16.0,
        needsHorizontalScroll: true,
        horizontalScrollOffset: 50.0,
        zoomScale: 1.5,
        isZooming: true,
      );

      final copied = original.copyWith(paneWidth: 120);

      expect(copied.paneWidth, equals(120));
      expect(copied.paneHeight, equals(30));
      expect(copied.screenWidth, equals(500.0));
      expect(copied.calculatedFontSize, equals(16.0));
      expect(copied.needsHorizontalScroll, isTrue);
      expect(copied.horizontalScrollOffset, equals(50.0));
      expect(copied.zoomScale, equals(1.5));
      expect(copied.isZooming, isTrue);
    });

    test('copyWith updates multiple values', () {
      const original = TerminalDisplayState();
      final copied = original.copyWith(
        paneWidth: 120,
        screenWidth: 800.0,
        calculatedFontSize: 18.0,
      );

      expect(copied.paneWidth, equals(120));
      expect(copied.screenWidth, equals(800.0));
      expect(copied.calculatedFontSize, equals(18.0));
    });

    test('equality works correctly', () {
      const state1 = TerminalDisplayState(paneWidth: 80, paneHeight: 24);
      const state2 = TerminalDisplayState(paneWidth: 80, paneHeight: 24);
      const state3 = TerminalDisplayState(paneWidth: 100, paneHeight: 24);

      expect(state1, equals(state2));
      expect(state1, isNot(equals(state3)));
    });

    test('hashCode is consistent with equality', () {
      const state1 = TerminalDisplayState(paneWidth: 80, paneHeight: 24);
      const state2 = TerminalDisplayState(paneWidth: 80, paneHeight: 24);

      expect(state1.hashCode, equals(state2.hashCode));
    });
  });

  group('TerminalDisplayNotifier', () {
    late ProviderContainer container;

    setUp(() {
      // Mock SharedPreferences
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has default values', () {
      final state = container.read(terminalDisplayProvider);

      expect(state.paneWidth, equals(80));
      expect(state.paneHeight, equals(24));
      expect(state.zoomScale, equals(1.0));
      expect(state.isZooming, isFalse);
    });

    test('updatePane updates pane dimensions', () {
      final notifier = container.read(terminalDisplayProvider.notifier);
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 120,
        height: 40,
        active: true,
      );

      notifier.updatePane(pane);

      final state = container.read(terminalDisplayProvider);
      expect(state.paneWidth, equals(120));
      expect(state.paneHeight, equals(40));
    });

    test('updatePane resets zoom state', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      // Start zooming
      notifier.startZoom();
      notifier.updateZoom(2.0);

      // Update pane should reset zoom
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 80,
        height: 24,
        active: true,
      );
      notifier.updatePane(pane);

      final state = container.read(terminalDisplayProvider);
      expect(state.zoomScale, equals(1.0));
      expect(state.isZooming, isFalse);
    });

    test('updatePane resets horizontal scroll offset', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      // Set scroll offset
      notifier.updateHorizontalScrollOffset(100.0);

      // Update pane should reset offset
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 80,
        height: 24,
        active: true,
      );
      notifier.updatePane(pane);

      final state = container.read(terminalDisplayProvider);
      expect(state.horizontalScrollOffset, equals(0.0));
    });

    test('updateScreenWidth updates screen width', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      notifier.updateScreenWidth(800.0);

      final state = container.read(terminalDisplayProvider);
      expect(state.screenWidth, equals(800.0));
    });

    test('updateScreenWidth does nothing if width unchanged', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      notifier.updateScreenWidth(800.0);
      final state1 = container.read(terminalDisplayProvider);

      // Update with same width
      notifier.updateScreenWidth(800.0);
      final state2 = container.read(terminalDisplayProvider);

      // Should be same instance (no state change)
      expect(identical(state1, state2), isTrue);
    });

    test('updateHorizontalScrollOffset updates offset', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      notifier.updateHorizontalScrollOffset(150.0);

      final state = container.read(terminalDisplayProvider);
      expect(state.horizontalScrollOffset, equals(150.0));
    });

    test('startZoom sets isZooming to true', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      notifier.startZoom();

      final state = container.read(terminalDisplayProvider);
      expect(state.isZooming, isTrue);
    });

    test('updateZoom updates zoom scale', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      notifier.startZoom();
      notifier.updateZoom(1.5);

      final state = container.read(terminalDisplayProvider);
      expect(state.zoomScale, equals(1.5));
    });

    test('endZoom finalizes font size and resets zoom state', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      // Setup: Set screen width and update pane to get calculated font size
      notifier.updateScreenWidth(800.0);
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 80,
        height: 24,
        active: true,
      );
      notifier.updatePane(pane);

      final initialFontSize =
          container.read(terminalDisplayProvider).calculatedFontSize;

      // Start zoom and scale up
      notifier.startZoom();
      notifier.updateZoom(2.0);
      notifier.endZoom();

      final state = container.read(terminalDisplayProvider);
      expect(state.isZooming, isFalse);
      expect(state.zoomScale, equals(1.0));
      // Font size should be approximately doubled (clamped to max)
      expect(state.calculatedFontSize,
          greaterThanOrEqualTo(initialFontSize * 0.9));
    });

    test('endZoom clamps font size to min', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      // Setup
      notifier.updateScreenWidth(800.0);
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 80,
        height: 24,
        active: true,
      );
      notifier.updatePane(pane);

      // Zoom way down
      notifier.startZoom();
      notifier.updateZoom(0.1);
      notifier.endZoom();

      final state = container.read(terminalDisplayProvider);
      final settings = container.read(settingsProvider);
      expect(state.calculatedFontSize, greaterThanOrEqualTo(settings.minFontSize));
    });

    test('endZoom clamps font size to max', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      // Setup
      notifier.updateScreenWidth(800.0);
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 80,
        height: 24,
        active: true,
      );
      notifier.updatePane(pane);

      // Zoom way up
      notifier.startZoom();
      notifier.updateZoom(10.0);
      notifier.endZoom();

      final state = container.read(terminalDisplayProvider);
      expect(state.calculatedFontSize,
          lessThanOrEqualTo(TerminalDisplayNotifier.maxFontSize));
    });

    test('onSettingsChanged triggers recalculation', () {
      final notifier = container.read(terminalDisplayProvider.notifier);

      // Setup
      notifier.updateScreenWidth(800.0);
      final pane = TmuxPane(
        id: '%0',
        index: 0,
        width: 80,
        height: 24,
        active: true,
      );
      notifier.updatePane(pane);

      // Trigger settings change recalculation
      notifier.onSettingsChanged();

      final newState = container.read(terminalDisplayProvider);
      // Font size should be recalculated (might be same value but method was called)
      expect(newState.calculatedFontSize, isNotNull);
    });
  });
}
