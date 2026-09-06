// inventory: HERDR-VER-001
/// サポートする herdr protocol の最小番号（メイン preflight 用の最小ゲート）。
/// G6 合意#2・#6: protocol は最小 17（17 以上）に対応。
const int kHerdrMinSupportedProtocol = 17;

// inventory: HERDR-VER-002
/// caret helper が対応する protocol 番号（allow-list。17 / 20 のみ）。
const Set<int> kHerdrCaretSupportedProtocols = {17, 20};

/// メイン preflight: client/server protocol が最小番号以上か（>= 17）。
// inventory: HERDR-VER-003
bool isHerdrProtocolSupported(int protocol) =>
    protocol >= kHerdrMinSupportedProtocol;

/// caret: 対応 protocol の allow-list に含まれるか。
// inventory: HERDR-VER-004
bool isHerdrCaretProtocolSupported(int protocol) =>
    kHerdrCaretSupportedProtocols.contains(protocol);
