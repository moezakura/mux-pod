import 'package:flutter_muxpod/providers/tmux_provider.dart';

/// [TmuxNotifier] をオーバーライドし、固定の [TmuxState] を返す stub。
class FakeTmuxNotifier extends TmuxNotifier {
  final TmuxState initialState;

  FakeTmuxNotifier({required this.initialState});

  @override
  TmuxState build() => initialState;
}
