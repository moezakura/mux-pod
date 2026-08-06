import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_muxpod/providers/tmux_provider.dart';
import 'package:flutter_muxpod/services/tmux/tmux_models.dart';
import 'package:flutter_muxpod/services/tmux/tmux_parser_adapter.dart';

import '../fixtures/tmux/tmux_parser_fixtures.dart';

void main() {
  group('TmuxProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('initial state is empty', () {
      final state = container.read(tmuxProvider);
      expect(state.sessions, isEmpty);
      expect(state.activeSession, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('updateSessions sets sessions and clears error', () {
      final notifier = container.read(tmuxProvider.notifier);
      final sessions = TmuxParser.parseSessions(kSessionOutput);
      notifier.updateSessions(sessions);
      expect(container.read(tmuxProvider).sessions, hasLength(2));
      expect(container.read(tmuxProvider).error, isNull);
    });

    test('parseAndUpdateSessions parses raw output', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateSessions(kSessionOutput);
      expect(container.read(tmuxProvider).sessions, hasLength(2));
      expect(container.read(tmuxProvider).sessions[0].name, 'mysession');
    });

    test('parseAndUpdateFullTree parses full tree', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      final state = container.read(tmuxProvider);
      expect(state.sessions, hasLength(2));
      expect(state.sessions[0].windows, hasLength(1));
    });

    test('setActiveSession selects active window and pane', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');
      final state = container.read(tmuxProvider);
      expect(state.activeSessionName, 'mysession');
      expect(state.activeWindowIndex, 0);
      expect(state.activePaneId, '%0');
    });

    test('setActiveSession on unknown session clears active pane', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('missing');
      final state = container.read(tmuxProvider);
      expect(state.activeSessionName, 'missing');
      expect(state.activeWindowIndex, isNull);
      expect(state.activePaneId, isNull);
    });

    test('setActiveWindow updates active pane', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');
      notifier.setActiveWindow(0);
      final state = container.read(tmuxProvider);
      expect(state.activeWindowIndex, 0);
      expect(state.activePaneId, '%0');
    });

    test('setActiveWindow clears pane selection when the window is absent', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');

      notifier.setActiveWindow(99);

      final state = container.read(tmuxProvider);
      expect(state.activeWindowIndex, 99);
      expect(state.activePaneIndex, isNull);
      expect(state.activePaneId, isNull);
    });

    test('setActivePaneByIndex sets pane index and id', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.setActivePaneByIndex(1, paneId: '%1');
      final state = container.read(tmuxProvider);
      expect(state.activePaneIndex, 1);
      expect(state.activePaneId, '%1');
    });

    test('setActivePane by id updates index', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');
      notifier.setActivePane('%1');
      final state = container.read(tmuxProvider);
      expect(state.activePaneId, '%1');
      expect(state.activePaneIndex, 1);
    });

    test(
      'setActivePane retains the last index when the pane id is no longer present',
      () {
        final notifier = container.read(tmuxProvider.notifier);
        notifier.parseAndUpdateFullTree(kFullTreeOutput);
        notifier.setActiveSession('mysession');

        notifier.setActivePane('%missing');

        final state = container.read(tmuxProvider);
        expect(state.activePaneId, '%missing');
        expect(state.activePaneIndex, 0);
      },
    );

    test('updateCursorPosition updates active pane cursor', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');
      notifier.updateCursorPosition('%0', 12, 34);
      final pane = container.read(tmuxProvider).activePane;
      expect(pane?.cursorX, 12);
      expect(pane?.cursorY, 34);
    });

    test(
      'updateCursorPosition ignores inactive pane and unchanged coordinates',
      () {
        final notifier = container.read(tmuxProvider.notifier);
        notifier.parseAndUpdateFullTree(kFullTreeOutput);
        notifier.setActiveSession('mysession');
        final before = container.read(tmuxProvider);

        notifier.updateCursorPosition('%1', 12, 34);
        expect(identical(container.read(tmuxProvider), before), isTrue);

        notifier.updateCursorPosition('%0', 5, 10);
        expect(identical(container.read(tmuxProvider), before), isTrue);
      },
    );

    test('currentTarget returns pane id', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');
      expect(notifier.currentTarget, '%0');
    });

    test('currentTarget returns null when incomplete', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.setActive(sessionName: 'mysession');
      expect(notifier.currentTarget, isNull);
    });

    test('setLoading and setError', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.setLoading(true);
      expect(container.read(tmuxProvider).isLoading, isTrue);
      notifier.setError('failed');
      expect(container.read(tmuxProvider).error, 'failed');
      expect(container.read(tmuxProvider).isLoading, isTrue);
    });

    test('clear resets state', () {
      final notifier = container.read(tmuxProvider.notifier);
      notifier.parseAndUpdateFullTree(kFullTreeOutput);
      notifier.setActiveSession('mysession');
      notifier.clear();
      final state = container.read(tmuxProvider);
      expect(state.sessions, isEmpty);
      expect(state.activeSessionName, isNull);
    });

    test('copyWith supports clear flags', () {
      const state = TmuxState(
        sessions: [],
        activeSessionName: 'mysession',
        activeWindowIndex: 0,
        activePaneIndex: 0,
        activePaneId: '%0',
      );
      final cleared = state.copyWith(
        clearActiveWindowIndex: true,
        clearActivePaneIndex: true,
        clearActivePaneId: true,
      );
      expect(cleared.activeSessionName, 'mysession');
      expect(cleared.activeWindowIndex, isNull);
      expect(cleared.activePaneIndex, isNull);
      expect(cleared.activePaneId, isNull);
    });

    test('activeSession returns first matching session', () {
      const state = TmuxState(
        sessions: [
          TmuxSession(name: 'a'),
          TmuxSession(name: 'b'),
        ],
        activeSessionName: 'b',
      );
      expect(state.activeSession?.name, 'b');
    });

    test('activeWindow and activePane handle missing indices', () {
      const state = TmuxState();
      expect(state.activeWindow, isNull);
      expect(state.activePane, isNull);
    });
  });
}
