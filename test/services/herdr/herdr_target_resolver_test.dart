import 'package:flutter_muxpod/services/herdr/herdr_models.dart';
import 'package:flutter_muxpod/services/herdr/herdr_target_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2 workspace × 2 tab × 2 pane の snapshot。
///
/// - w1 (label "lab-ws1"): tab w1:t1 (pane w1:p1 focused / w1:p2), tab w1:t2 (w1:p3 / w1:p4)
/// - w2 (label "lab-ws2"): tab w2:t1 (w2:p1 / w2:p2 focused)
/// - 全体フォーカス: w2:p2（focusedPaneId）
HerdrSnapshot _multiWorkspaceSnapshot() {
  return HerdrSnapshot(
    protocol: 17,
    version: '0.7.5',
    focusedWorkspaceId: 'w2',
    focusedTabId: 'w2:t1',
    focusedPaneId: 'w2:p2',
    workspaces: const [
      HerdrWorkspace(
        id: 'w1',
        label: 'lab-ws1',
        number: 1,
        focused: false,
        activeTabId: 'w1:t1',
      ),
      HerdrWorkspace(
        id: 'w2',
        label: 'lab-ws2',
        number: 2,
        focused: true,
        activeTabId: 'w2:t1',
      ),
    ],
    tabs: const [
      HerdrTab(
        id: 'w1:t1',
        workspaceId: 'w1',
        label: '1',
        number: 1,
        focused: true,
      ),
      HerdrTab(
        id: 'w1:t2',
        workspaceId: 'w1',
        label: '2',
        number: 2,
        focused: false,
      ),
      HerdrTab(
        id: 'w2:t1',
        workspaceId: 'w2',
        label: '1',
        number: 1,
        focused: true,
      ),
    ],
    panes: const [
      HerdrPane(
        id: 'w1:p1',
        workspaceId: 'w1',
        tabId: 'w1:t1',
        focused: true,
        cwd: '/tmp',
      ),
      HerdrPane(id: 'w1:p2', workspaceId: 'w1', tabId: 'w1:t1', focused: false),
      HerdrPane(id: 'w1:p3', workspaceId: 'w1', tabId: 'w1:t2', focused: false),
      HerdrPane(id: 'w1:p4', workspaceId: 'w1', tabId: 'w1:t2', focused: false),
      HerdrPane(id: 'w2:p1', workspaceId: 'w2', tabId: 'w2:t1', focused: false),
      HerdrPane(id: 'w2:p2', workspaceId: 'w2', tabId: 'w2:t1', focused: true),
    ],
  );
}

void main() {
  final snapshot = _multiWorkspaceSnapshot();

  group('HerdrTargetResolver.resolve 直接 pane 指定', () {
    test('paneIds の最初に存在する pane を返す', () {
      expect(
        HerdrTargetResolver.resolve(snapshot, paneIds: ['w1:p1']),
        'w1:p1',
      );
    });

    test('paneIds が存在しないものなら次を試す（initial → last 優先順）', () {
      expect(
        HerdrTargetResolver.resolve(snapshot, paneIds: ['gone:p1', 'w2:p2']),
        'w2:p2',
      );
    });

    test('paneIds がすべて存在しなければ workspace 解決へフォールバック', () {
      expect(
        HerdrTargetResolver.resolve(
          snapshot,
          paneIds: ['gone:p1'],
          workspaceLabel: 'lab-ws2',
        ),
        'w2:p2', // w2 のフォーカス pane
      );
    });
  });

  group('HerdrTargetResolver.resolve workspace 解決', () {
    test('workspaceLabel の label 一致 → フォーカス pane', () {
      expect(
        HerdrTargetResolver.resolve(snapshot, workspaceLabel: 'lab-ws1'),
        'w1:p1',
      );
    });

    test('workspaceLabel は id 一致にもフォールバック', () {
      expect(
        HerdrTargetResolver.resolve(snapshot, workspaceLabel: 'w2'),
        'w2:p2',
      );
    });

    test('workspaceId 指定で一致 workspace を選ぶ', () {
      expect(HerdrTargetResolver.resolve(snapshot, workspaceId: 'w1'), 'w1:p1');
      expect(HerdrTargetResolver.resolve(snapshot, workspaceId: 'w2'), 'w2:p2');
    });

    test('workspace 未指定なら先頭 workspace のフォーカス pane', () {
      expect(HerdrTargetResolver.resolve(snapshot), 'w1:p1');
    });

    test('workspace 内にフォーカス pane が無ければ先頭 pane', () {
      final noFocused = HerdrSnapshot(
        focusedPaneId: null,
        workspaces: const [
          HerdrWorkspace(id: 'w1', label: 'lab-ws1', number: 1),
        ],
        tabs: const [
          HerdrTab(id: 'w1:t1', workspaceId: 'w1', label: '1', number: 1),
        ],
        panes: const [
          HerdrPane(id: 'w1:p1', workspaceId: 'w1', tabId: 'w1:t1'),
          HerdrPane(id: 'w1:p2', workspaceId: 'w1', tabId: 'w1:t1'),
        ],
      );
      expect(HerdrTargetResolver.resolve(noFocused), 'w1:p1');
    });
  });

  group('HerdrTargetResolver.resolve tab 指定', () {
    test('tabId 指定でその tab 内のフォーカス pane を返す', () {
      expect(
        HerdrTargetResolver.resolve(snapshot, tabId: 'w1:t2'),
        'w1:p3', // tab 内にフォーカス pane がないので先頭
      );
    });

    test('tabId 指定でフォーカス pane があればそれを返す', () {
      expect(HerdrTargetResolver.resolve(snapshot, tabId: 'w1:t1'), 'w1:p1');
    });

    test('workspaceId + tabId + paneId の組み合わせ', () {
      expect(
        HerdrTargetResolver.resolve(
          snapshot,
          workspaceId: 'w1',
          tabId: 'w1:t2',
          paneIds: ['w1:p4'],
        ),
        'w1:p4',
      );
    });

    test('tabId が workspace に無ければ workspace 内フォールバック', () {
      expect(
        HerdrTargetResolver.resolve(
          snapshot,
          workspaceId: 'w1',
          tabId: 'w1:no_such',
        ),
        'w1:p1', // workspace 全体のフォーカス pane
      );
    });
  });

  group('HerdrTargetResolver.resolve 全体フォールバック・空', () {
    test('workspace 内に pane が無ければ focusedPaneId へフォールバック', () {
      final emptyWorkspace = HerdrSnapshot(
        focusedPaneId: 'w2:p2',
        workspaces: const [
          HerdrWorkspace(id: 'w1', label: 'lab-ws1', number: 1),
        ],
        tabs: const <HerdrTab>[],
        panes: const [
          HerdrPane(id: 'w2:p2', workspaceId: 'w2', tabId: 'w2:t1'),
        ],
      );
      expect(HerdrTargetResolver.resolve(emptyWorkspace), 'w2:p2');
    });

    test('focusedPaneId が panes に無ければ無視して先頭 pane', () {
      final staleFocus = HerdrSnapshot(
        focusedPaneId: 'gone:p9',
        workspaces: const [
          HerdrWorkspace(id: 'w1', label: 'lab-ws1', number: 1),
        ],
        tabs: const [
          HerdrTab(id: 'w1:t1', workspaceId: 'w1', label: '1', number: 1),
        ],
        panes: const [
          HerdrPane(id: 'w1:p1', workspaceId: 'w1', tabId: 'w1:t1'),
        ],
      );
      expect(HerdrTargetResolver.resolve(staleFocus), 'w1:p1');
    });

    test('workspace が空なら null', () {
      expect(HerdrTargetResolver.resolve(const HerdrSnapshot()), isNull);
    });

    test('pane が空なら null', () {
      final noPanes = HerdrSnapshot(
        workspaces: const [
          HerdrWorkspace(id: 'w1', label: 'lab-ws1', number: 1),
        ],
        tabs: const [
          HerdrTab(id: 'w1:t1', workspaceId: 'w1', label: '1', number: 1),
        ],
        panes: const <HerdrPane>[],
      );
      expect(HerdrTargetResolver.resolve(noPanes), isNull);
    });
  });
}
