import 'package:flutter_muxpod/services/backend/domain/multiplexer_session.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/services/tmux/tmux_to_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TmuxSession.toDomain', () {
    test('maps a tmux session tree to a MultiplexerSession', () {
      final pane = TmuxPane(
        index: 2,
        id: '%2',
        active: true,
        currentPath: '/home/user',
      );
      final window = TmuxWindow(
        index: 0,
        id: '@0',
        name: 'editor',
        active: true,
        paneCount: 1,
        panes: [pane],
      );
      final session = TmuxSession(
        name: 'work',
        id: '\$0',
        attached: true,
        windowCount: 1,
        windows: [window],
      );

      final domain = session.toDomain();

      expect(domain, isA<MultiplexerSession>());
      expect(domain.name, 'work');
      expect(domain.id, '\$0');
      expect(domain.windowCount, 1);
      expect(domain.attached, isTrue);

      expect(domain.windows, hasLength(1));
      final domainWindow = domain.windows.single;
      expect(domainWindow.index, 0);
      expect(domainWindow.id, '@0');
      expect(domainWindow.name, 'editor');
      expect(domainWindow.active, isTrue);
      expect(domainWindow.paneCount, 1);

      expect(domainWindow.panes, hasLength(1));
      final domainPane = domainWindow.panes.single;
      expect(domainPane.index, 2);
      expect(domainPane.id, '%2');
      expect(domainPane.active, isTrue);
      expect(domainPane.currentPath, '/home/user');
    });

    test('handles optional fields and empty windows', () {
      const session = TmuxSession(name: 'detached');
      final domain = session.toDomain();

      expect(domain.name, 'detached');
      expect(domain.id, isNull);
      expect(domain.attached, isFalse);
      expect(domain.windowCount, 0);
      expect(domain.windows, isEmpty);
    });
  });
}
