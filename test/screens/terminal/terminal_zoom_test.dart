import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/terminal_zoom.dart';

void main() {
  group('classifyTwoFingerGesture', () {
    test('treats a pinch with one stationary finger as zoom', () {
      // Regression: the old heuristic required BOTH fingers to travel >=15px
      // in opposing directions, so an anchored-thumb pinch never zoomed.
      // ScaleUpdateDetails.scale changes even when the focal point barely moves.
      expect(
        classifyTwoFingerGesture(scale: 1.3, focalTravel: 2.0),
        TwoFingerGesture.zoom,
      );
    });

    test('treats pinch-in (scale < 1) as zoom', () {
      expect(
        classifyTwoFingerGesture(scale: 0.7, focalTravel: 0.0),
        TwoFingerGesture.zoom,
      );
    });

    test('treats a parallel two-finger drag as pan', () {
      expect(
        classifyTwoFingerGesture(scale: 1.0, focalTravel: 60.0),
        TwoFingerGesture.pan,
      );
    });

    test('zoom wins when both the scale and the focal point move', () {
      expect(
        classifyTwoFingerGesture(scale: 1.2, focalTravel: 80.0),
        TwoFingerGesture.zoom,
      );
    });

    test('returns undetermined while the gesture is still tiny', () {
      expect(
        classifyTwoFingerGesture(scale: 1.01, focalTravel: 3.0),
        TwoFingerGesture.undetermined,
      );
    });
  });

  group('clampZoomFactor', () {
    test('clamps below the minimum', () {
      expect(clampZoomFactor(0.1), kMinZoomFactor);
    });

    test('clamps above the maximum', () {
      expect(clampZoomFactor(9.0), kMaxZoomFactor);
    });

    test('keeps an in-range value unchanged', () {
      expect(clampZoomFactor(2.0), 2.0);
    });
  });

  group('zoomedFontSize', () {
    test('scales the base font by the zoom factor', () {
      expect(
        zoomedFontSize(baseFontSize: 14, zoomFactor: 2.0, minFontSize: 8),
        28.0,
      );
    });

    test('never drops below minFontSize', () {
      expect(
        zoomedFontSize(baseFontSize: 14, zoomFactor: 0.1, minFontSize: 8),
        8.0,
      );
    });

    test('never exceeds the max terminal font size', () {
      expect(
        zoomedFontSize(baseFontSize: 20, zoomFactor: 3.0, minFontSize: 8),
        kMaxTerminalFontSize,
      );
    });

    test('a factor of 1.0 returns the base size', () {
      expect(
        zoomedFontSize(baseFontSize: 16, zoomFactor: 1.0, minFontSize: 8),
        16.0,
      );
    });
  });

  group('fitTerminalZoomFactor', () {
    const charWidthRatio = 0.5;
    const lineHeightRatio = 1.2;

    test('returns 1.0 when width is the limiting axis', () {
      // 80 cols × 0.5 = 40px/char at fontSize 1 → base 14 needs width
      // screenWidth=560 → width fit fontSize = 560/(80*0.5)=14 → zoom 1.0
      expect(
        fitTerminalZoomFactor(
          screenWidth: 560,
          screenHeight: 2000,
          paneCharWidth: 80,
          paneHeight: 24,
          baseFontSize: 14,
          charWidthRatio: charWidthRatio,
          lineHeightRatio: lineHeightRatio,
        ),
        1.0,
      );
    });

    test('zooms out when height is the limiting axis', () {
      // Height fit fontSize = 400/(24*1.2)=13.89; width fit = 14.
      // So height drives: 13.89/14 ≈ 0.992.
      final fit = fitTerminalZoomFactor(
        screenWidth: 560,
        screenHeight: 400,
        paneCharWidth: 80,
        paneHeight: 24,
        baseFontSize: 14,
        charWidthRatio: charWidthRatio,
        lineHeightRatio: lineHeightRatio,
      );
      expect(fit, closeTo(13.8889 / 14.0, 0.001));
    });

    test('width drives the factor when width overflows', () {
      // Width fit fontSize = 300/(80*0.5)=7.5; height fit = 2000/(24*1.2)=69.4.
      // So width drives: 7.5/14 ≈ 0.536.
      final fit = fitTerminalZoomFactor(
        screenWidth: 300,
        screenHeight: 2000,
        paneCharWidth: 80,
        paneHeight: 24,
        baseFontSize: 14,
        charWidthRatio: charWidthRatio,
        lineHeightRatio: lineHeightRatio,
      );
      expect(fit, closeTo(7.5 / 14.0, 0.001));
    });

    test('clamps to the minimum zoom factor', () {
      expect(
        fitTerminalZoomFactor(
          screenWidth: 100,
          screenHeight: 100,
          paneCharWidth: 200,
          paneHeight: 200,
          baseFontSize: 14,
          charWidthRatio: charWidthRatio,
          lineHeightRatio: lineHeightRatio,
        ),
        kMinZoomFactor,
      );
    });

    test('returns 1.0 for degenerate geometry (no-op)', () {
      expect(
        fitTerminalZoomFactor(
          screenWidth: 0,
          screenHeight: 0,
          paneCharWidth: 80,
          paneHeight: 24,
          baseFontSize: 14,
          charWidthRatio: charWidthRatio,
          lineHeightRatio: lineHeightRatio,
        ),
        1.0,
      );
    });
  });
}
