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
