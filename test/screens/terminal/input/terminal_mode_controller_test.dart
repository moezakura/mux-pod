/// [TerminalModeController.onModeChanged]（herdr OSC 8 ハイパー
/// リンク・スクロールモードのリンク読取のモード終了検知）のテスト。
///
/// 「変化したら常に通知し、select を抜けたかどうかの判断は呼び出し側
/// （root）に委ねる」という設計を検証する。ここでは変化検知
/// （previous/next の通知・同じモードへの遷移では発火しない）だけを見る。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_muxpod/screens/terminal/input/terminal_input_ports.dart';
import 'package:flutter_muxpod/screens/terminal/input/terminal_mode_controller.dart';
import 'package:flutter_muxpod/screens/terminal/widgets/ansi_terminal_model.dart'
    show TerminalMode;
import 'package:flutter_muxpod/services/backend/domain/pane_frame_reader.dart'
    show PaneCaret;

class _FakeScrollbackPort implements TerminalScrollbackPort {
  @override
  bool get canRead => true;
  @override
  String get displayedContent => '';
  @override
  int get displayedPaneWidth => 80;
  @override
  int get displayedPaneHeight => 24;
  @override
  PaneCaret? get displayedCaret => null;
  @override
  int get scrollbackLimit => 10000;
  @override
  Object? captureTargetIdentity() => null;
  @override
  Future<String?> readScrollbackContent() async => null;
  @override
  void setDisplayedContent(String content) {}
}

class _FakeValidator implements TerminalTargetIdentityValidator {
  @override
  bool isCurrent(Object? identity) => true;
}

typedef _ModeChangeEvent = ({TerminalMode previous, TerminalMode next});

/// [TerminalModeController] の構築に必要な実 [WidgetRef] を得る（`ref` は
/// zoom 系 getter でのみ使われ、このテストの対象（モード遷移）では未使用）。
Future<WidgetRef> _pumpRef(WidgetTester tester) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('onModeChanged はモードが変化したときにprevious/nextを通知する', (tester) async {
    final controller = TerminalModeController(
      ref: await _pumpRef(tester),
      scrollback: _FakeScrollbackPort(),
      validator: _FakeValidator(),
    );
    final events = <_ModeChangeEvent>[];
    controller.onModeChanged = (previous, next) =>
        events.add((previous: previous, next: next));

    controller.applySelectManual();

    expect(events, hasLength(1));
    expect(events.single.previous, TerminalMode.normal);
    expect(events.single.next, TerminalMode.select);

    controller.applyNormal();

    expect(events, hasLength(2));
    expect(events.last.previous, TerminalMode.select);
    expect(events.last.next, TerminalMode.normal);
  });

  testWidgets('onModeChanged は同じモードへの遷移では発火しない', (tester) async {
    final controller = TerminalModeController(
      ref: await _pumpRef(tester),
      scrollback: _FakeScrollbackPort(),
      validator: _FakeValidator(),
    );
    final events = <_ModeChangeEvent>[];
    controller.onModeChanged = (previous, next) =>
        events.add((previous: previous, next: next));

    // 初期状態は既に TerminalMode.normal のため、normal -> normal は変化なし。
    controller.applyNormal();

    expect(events, isEmpty);
  });
}
