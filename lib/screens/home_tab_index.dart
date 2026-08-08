/// Home screen tab indices.
///
/// Keep all cross-screen tab switches using these constants instead of
/// hard-coded integers. This avoids breakage when tabs are reordered or
/// new tabs (like Remote UI) are added.
abstract final class HomeTabIndex {
  static const int servers = 0;
  static const int keys = 1;
  static const int dashboard = 2;
  static const int remoteUi = 3;
  static const int notifications = 4;
  static const int settings = 5;
}
