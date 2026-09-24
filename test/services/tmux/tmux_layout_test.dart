// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_muxpod/services/tmux/commands/layout.dart';

void main() {
  group('SplitDirection', () {
    test('has horizontal and vertical values', () {
      expect(SplitDirection.values, contains(SplitDirection.horizontal));
      expect(SplitDirection.values, contains(SplitDirection.vertical));
    });
  });

  group('TmuxLayout', () {
    test('name returns correct tmux layout string', () {
      expect(TmuxLayout.evenHorizontal.name, 'even-horizontal');
      expect(TmuxLayout.evenVertical.name, 'even-vertical');
      expect(TmuxLayout.mainHorizontal.name, 'main-horizontal');
      expect(TmuxLayout.mainVertical.name, 'main-vertical');
      expect(TmuxLayout.tiled.name, 'tiled');
    });
  });
}
