// Pure helpers for terminal pinch-zoom.
//
// Kept free of Flutter widget dependencies so the gesture classification and
// font-size math can be unit-tested in isolation.

/// Classification of an in-progress two-finger terminal gesture.
enum TwoFingerGesture { undetermined, zoom, pan }

/// Minimum `|scale - 1|` before a two-finger gesture counts as a pinch-zoom.
const double kZoomScaleThreshold = 0.05;

/// Minimum focal-point travel (logical px) before a two-finger gesture counts
/// as a pan / pane-swipe.
const double kPanFocalThreshold = 16.0;

/// Bounds for the persisted zoom multiplier.
const double kMinZoomFactor = 0.5;
const double kMaxZoomFactor = 5.0;

/// Upper bound for the effective render font size (matches the legible ceiling).
const double kMaxTerminalFontSize = 48.0;

/// Classifies a two-finger gesture from the scale recognizer's robust signals.
///
/// - [scale] is `ScaleUpdateDetails.scale` (1.0 = pointers unchanged distance).
/// - [focalTravel] is how far the focal point has moved since the gesture start.
///
/// Zoom is checked first: a pinch changes [scale] even when one finger is
/// stationary, which the previous finger-vector heuristic missed.
TwoFingerGesture classifyTwoFingerGesture({
  required double scale,
  required double focalTravel,
  double zoomThreshold = kZoomScaleThreshold,
  double panThreshold = kPanFocalThreshold,
}) {
  if ((scale - 1.0).abs() >= zoomThreshold) return TwoFingerGesture.zoom;
  if (focalTravel >= panThreshold) return TwoFingerGesture.pan;
  return TwoFingerGesture.undetermined;
}

/// Clamps a persisted zoom multiplier to a sane range.
double clampZoomFactor(double factor) =>
    factor.clamp(kMinZoomFactor, kMaxZoomFactor).toDouble();

/// Effective render font size = base * zoom, clamped to the legible range.
double zoomedFontSize({
  required double baseFontSize,
  required double zoomFactor,
  required double minFontSize,
  double maxFontSize = kMaxTerminalFontSize,
}) =>
    (baseFontSize * zoomFactor).clamp(minFontSize, maxFontSize).toDouble();
