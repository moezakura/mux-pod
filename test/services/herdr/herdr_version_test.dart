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
  });
}