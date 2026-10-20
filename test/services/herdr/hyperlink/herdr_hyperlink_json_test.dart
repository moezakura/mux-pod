// inventory: HERDR-HYPERLINK-JSON-TEST-000
/// herdr_hyperlink_json.dart（`hyperlinks`/`scrollback-links` 共通の
/// フィールド検証）の単体テスト。
///
/// この関数は protocol allow-list に依存しないため、
/// herdr_hyperlink_helper_manager_test.dart / herdr_scrollback_link_helper_
/// manager_test.dart とは独立して、コア検証ロジックだけを確認できる。
library;

import 'package:flutter_muxpod/services/herdr/hyperlink/herdr_hyperlink_json.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _base({
  int frameWidth = 120,
  int frameHeight = 40,
  bool truncated = false,
  List<Map<String, Object?>> links = const [
    {
      'url': 'https://example.com/',
      'ranges': [
        [3, 10, 24],
      ],
    },
  ],
  List<List<Object?>> rowHashes = const [
    [3, '9f1c000000000000'],
  ],
}) => {
  'frameWidth': frameWidth,
  'frameHeight': frameHeight,
  'truncated': truncated,
  'links': links,
  'rowHashes': rowHashes,
};

void main() {
  group('parseHyperlinkFields 成功', () {
    test('正常な JSON を PaneHyperlinks へ変換する', () {
      final result = parseHyperlinkFields(_base());
      expect(result.frameWidth, 120);
      expect(result.frameHeight, 40);
      expect(result.truncated, isFalse);
      expect(result.links.single.url, 'https://example.com/');
      expect(result.links.single.ranges.single.row, 3);
      expect(result.links.single.ranges.single.startCol, 10);
      expect(result.links.single.ranges.single.endCol, 24);
      expect(result.rowFingerprints, {3: '9f1c000000000000'});
    });

    test('リンクが無い場合は空リスト・空マップ', () {
      final result = parseHyperlinkFields(
        _base(links: const [], rowHashes: const []),
      );
      expect(result.links, isEmpty);
      expect(result.rowFingerprints, isEmpty);
    });

    test('links / ranges / rowFingerprints は unmodifiable', () {
      final result = parseHyperlinkFields(_base());
      expect(
        () => result.links.add(result.links.first),
        throwsUnsupportedError,
      );
      expect(
        () => result.links.single.ranges.add(result.links.single.ranges.first),
        throwsUnsupportedError,
      );
      expect(() => result.rowFingerprints[99] = 'x', throwsUnsupportedError);
    });

    test('複数行・複数リンクを正しく変換する', () {
      final result = parseHyperlinkFields(
        _base(
          links: const [
            {
              'url': 'https://a.example/',
              'ranges': [
                [0, 0, 5],
              ],
            },
            {
              'url': 'https://b.example/',
              'ranges': [
                [1, 0, 3],
                [2, 0, 3],
              ],
            },
          ],
          rowHashes: const [
            [0, '0000000000000001'],
            [1, '0000000000000002'],
            [2, '0000000000000003'],
          ],
        ),
      );
      expect(result.links, hasLength(2));
      expect(result.links[1].ranges, hasLength(2));
      expect(result.rowFingerprints.length, 3);
    });
  });

  group('parseHyperlinkFields 失敗（型・寸法）', () {
    test('frameWidth が u16 でなければ FormatException', () {
      expect(
        () => parseHyperlinkFields(_base()..['frameWidth'] = -1),
        throwsFormatException,
      );
      expect(
        () => parseHyperlinkFields(_base()..['frameWidth'] = 0x10000),
        throwsFormatException,
      );
      expect(
        () => parseHyperlinkFields(_base()..['frameWidth'] = 'x'),
        throwsFormatException,
      );
    });

    test('frameHeight が u16 でなければ FormatException', () {
      expect(
        () => parseHyperlinkFields(_base()..['frameHeight'] = -1),
        throwsFormatException,
      );
    });

    test('truncated が bool でなければ FormatException', () {
      expect(
        () => parseHyperlinkFields(_base()..['truncated'] = 'yes'),
        throwsFormatException,
      );
    });

    test('links が配列でなければ FormatException', () {
      expect(
        () => parseHyperlinkFields(_base()..['links'] = 'x'),
        throwsFormatException,
      );
    });

    test('rowHashes が配列でなければ FormatException', () {
      expect(
        () => parseHyperlinkFields(_base()..['rowHashes'] = 'x'),
        throwsFormatException,
      );
    });
  });

  group('parseHyperlinkFields 失敗（範囲の境界）', () {
    test('range の row が frameHeight 以上なら FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            frameHeight: 40,
            links: const [
              {
                'url': 'https://example.com/',
                'ranges': [
                  [40, 0, 5],
                ],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('range の endCol が frameWidth 以上なら FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            frameWidth: 120,
            links: const [
              {
                'url': 'https://example.com/',
                'ranges': [
                  [3, 0, 120],
                ],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('range の startCol > endCol は FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            links: const [
              {
                'url': 'https://example.com/',
                'ranges': [
                  [3, 24, 10],
                ],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('links[].ranges が空配列は FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            links: const [
              {'url': 'https://example.com/', 'ranges': <Object?>[]},
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rowHashes の row が frameHeight 以上なら FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            frameHeight: 40,
            rowHashes: const [
              [40, '9f1c000000000000'],
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rowHashes の row が重複していれば FormatException（黙った上書き防止）', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            rowHashes: const [
              [3, '9f1c000000000000'],
              [3, '03ab000000000000'],
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('rowHashes の hex が16桁小文字hexでなければ FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            rowHashes: const [
              [3, 'ABCD'],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => parseHyperlinkFields(
          _base(
            rowHashes: const [
              [3, '9f1c00000000000'],
            ],
          ),
        ),
        throwsFormatException,
        reason: '15桁（短すぎる）も拒否する',
      );
    });
  });

  group('parseHyperlinkFields 失敗（URL 検証）', () {
    test('url が空文字列なら FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            links: const [
              {
                'url': '',
                'ranges': [
                  [3, 0, 5],
                ],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('url に C0 制御文字を含むと FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            links: const [
              {
                'url': 'https://example.com/\x07evil',
                'ranges': [
                  [3, 10, 24],
                ],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('url に DEL（0x7F）を含むと FormatException', () {
      expect(
        () => parseHyperlinkFields(
          _base(
            links: const [
              {
                'url': 'https://example.com/\x7Fevil',
                'ranges': [
                  [3, 10, 24],
                ],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('通常の URL（クエリ・アンカー含む）は許可する', () {
      final result = parseHyperlinkFields(
        _base(
          links: const [
            {
              'url': 'https://example.com/path?query=1&x=2#frag',
              'ranges': [
                [3, 10, 24],
              ],
            },
          ],
        ),
      );
      expect(
        result.links.single.url,
        'https://example.com/path?query=1&x=2#frag',
      );
    });
  });

  group('例外メッセージに URL・stdout 本文が出ないこと', () {
    test('制御文字を含む URL は message に出ない', () {
      const secretUrl = 'https://secret.example.com/token=abc123';
      try {
        parseHyperlinkFields(
          _base(
            links: [
              {
                'url': '$secretUrl\x07',
                'ranges': const [
                  [3, 10, 24],
                ],
              },
            ],
          ),
        );
        fail('FormatException のはずが成功した');
      } on FormatException catch (e) {
        expect(e.message, isNot(contains(secretUrl)));
      }
    });
  });
}
