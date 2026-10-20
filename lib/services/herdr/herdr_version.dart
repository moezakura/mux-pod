import 'herdr_protocols.g.dart';

export 'herdr_protocols.g.dart';

/// メイン preflight: client/server protocol が最小番号以上か（>= 17）。
// inventory: HERDR-VER-003
bool isHerdrProtocolSupported(int protocol) =>
    protocol >= kHerdrMinSupportedProtocol;

/// caret: 対応 protocol の allow-list に含まれるか。
// inventory: HERDR-VER-004
bool isHerdrCaretProtocolSupported(int protocol) =>
    kHerdrCaretSupportedProtocols.contains(protocol);

/// 通常表示のリンク読取（`hyperlinks`）: 対応 protocol の allow-list に
/// 含まれるか（herdr OSC 8 ハイパーリンク実験機能）。
bool isHerdrHyperlinkProtocolSupported(int protocol) =>
    kHerdrHyperlinkSupportedProtocols.contains(protocol);

/// スクロールモードのリンク読取（`scrollback-links`）: 対応 protocol の
/// allow-list に含まれるか（herdr OSC 8 ハイパーリンク実験機能）。
bool isHerdrScrollbackLinkProtocolSupported(int protocol) =>
    kHerdrScrollbackLinkSupportedProtocols.contains(protocol);
