import 'package:flutter_muxpod/services/herdr/herdr_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isHerdrProtocolSupported', () {
    test('rejects 16 (below minimum 17)', () {
      expect(isHerdrProtocolSupported(16), isFalse);
    });

    test('accepts 17 (minimum)', () {
      expect(isHerdrProtocolSupported(17), isTrue);
    });

    test('accepts 18 (above minimum)', () {
      expect(isHerdrProtocolSupported(18), isTrue);
    });
  });

  group('isHerdrCaretProtocolSupported', () {
    test('accepts 17 (allow-list member)', () {
      expect(isHerdrCaretProtocolSupported(17), isTrue);
    });

    test('rejects 18 (not in allow-list)', () {
      expect(isHerdrCaretProtocolSupported(18), isFalse);
    });

    test('accepts 20 (allow-list member)', () {
      expect(isHerdrCaretProtocolSupported(20), isTrue);
    });

    test('accepts 22 (allow-list member)', () {
      expect(isHerdrCaretProtocolSupported(22), isTrue);
    });
  });

  group('isHerdrHyperlinkProtocolSupported', () {
    test('accepts 17 (allow-list member)', () {
      expect(isHerdrHyperlinkProtocolSupported(17), isTrue);
    });

    test('accepts 20 (allow-list member)', () {
      expect(isHerdrHyperlinkProtocolSupported(20), isTrue);
    });

    test('accepts 22 (allow-list member)', () {
      expect(isHerdrHyperlinkProtocolSupported(22), isTrue);
    });

    test('rejects 18 (not in allow-list)', () {
      expect(isHerdrHyperlinkProtocolSupported(18), isFalse);
    });
  });

  group('isHerdrScrollbackLinkProtocolSupported', () {
    test('accepts 17 (allow-list member)', () {
      expect(isHerdrScrollbackLinkProtocolSupported(17), isTrue);
    });

    test('accepts 20 (allow-list member)', () {
      expect(isHerdrScrollbackLinkProtocolSupported(20), isTrue);
    });

    test('accepts 22 (allow-list member)', () {
      expect(isHerdrScrollbackLinkProtocolSupported(22), isTrue);
    });

    test('rejects 18 (not in allow-list)', () {
      expect(isHerdrScrollbackLinkProtocolSupported(18), isFalse);
    });
  });

  group('3 つの allow-list の独立性（protocol allow-list）', () {
    test('22 は caret・hyperlink・scrollback-link のいずれでも true', () {
      expect(isHerdrCaretProtocolSupported(22), isTrue);
      expect(isHerdrHyperlinkProtocolSupported(22), isTrue);
      expect(isHerdrScrollbackLinkProtocolSupported(22), isTrue);
    });

    test('caret の allow-list は [17, 20, 22]', () {
      expect(kHerdrCaretSupportedProtocols, {17, 20, 22});
    });

    test('hyperlink と scrollback-link の allow-list はそれぞれ設定どおり', () {
      expect(kHerdrHyperlinkSupportedProtocols, {17, 20, 22});
      expect(kHerdrScrollbackLinkSupportedProtocols, {17, 20, 22});
    });
  });
}
