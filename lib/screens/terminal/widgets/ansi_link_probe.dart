/// 選択モードの OSC 8 リンクタップ検出の補助（Issue #61・Phase 5 #15・🤝#3）。
///
/// 選択モードでは `SelectionArea` がタップを吸うため TextSpan recognizer は
/// 不活性になる。そこで gesture arena に参加しない生ポインタリスナ
/// （[AnsiSelectModeTapProbe]）でタップを検出し、行ウィジェット（#14）が
/// [AnsiLinkProbeRegistry] へ登録した解決経由でヒット位置の url を得て、
/// 通常経路と同一の起動コーディネータへ渡す（全モードタップ導線）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 選択モードのリンクタップ解決先として行ウィジェットが登録する対象。
abstract interface class AnsiLinkProbeTarget {
  /// 解決要求を受け付けられる状態か（行 State の mounted）。
  bool get isProbeValid;

  /// タップ global 位置が本行のテキスト上にあり、その位置がリンク区間なら
  /// その URL を返す。範囲外・非リンク区間・未解決は null（throw しない）。
  String? resolveLinkAt(Offset globalPosition);
}

/// 行ウィジェットの登録を保持し、タップ global 位置からリンク URL を解決する。
///
/// sync・no-throw・副作用なしの純読取（解決後のコーディネータ委譲は
/// 呼び出し側が行う）。登録 / 解除は行ウィジェット State 自身が行う
/// （initState / dispose・didUpdateWidget）。
class AnsiLinkProbeRegistry {
  final Set<AnsiLinkProbeTarget> _targets = <AnsiLinkProbeTarget>{};

  /// 行ウィジェットを登録する（同一対象の重複登録は無視）。
  void register(AnsiLinkProbeTarget target) => _targets.add(target);

  /// 行ウィジェットの登録を解除する。
  void unregister(AnsiLinkProbeTarget target) => _targets.remove(target);

  /// global 位置を含む行からリンク URL を解決する。
  ///
  /// ヒットする行が無い・位置が非リンク区間の場合は null を返す
  /// （url 未解決は throw せず null 握りつぶし・プローブ行契約）。
  String? resolveUrl(Offset globalPosition) {
    for (final target in _targets) {
      if (!target.isProbeValid) {
        continue;
      }
      final url = target.resolveLinkAt(globalPosition);
      if (url != null) {
        return url;
      }
    }
    return null;
  }
}

/// 選択モードのタップ検出プローブ（Listener・gesture arena 不参加）。
///
/// 「移動量が [kTouchSlop] 未満かつ押下時間が [kLongPressTimeout] 未満の
/// down→up」をタップと判定する。長押しによる選択開始やドラッグ選択は
/// 検出対象外で、`SelectionArea` の従来動作に干渉しない
/// （behavior: translucent で子のイベント受領を妨げない）。
///
/// 複数ポインタは**先頭 1 本のみ**追跡する（pointer id 照合）。2 本指 down が
/// 先頭ポインタの判定座標を上書きする構造的問題を排除する（Zoom 等・
/// 2 本指操作は [kTouchSlop] 超過でタップ不成立になるため従来どおり不発火）。
class AnsiSelectModeTapProbe extends StatefulWidget {
  const AnsiSelectModeTapProbe({
    super.key,
    required this.onTapUp,
    required this.child,
  });

  /// タップと判定したときの global 位置コールバック（sync・no-throw 前提）。
  final void Function(Offset globalPosition) onTapUp;

  final Widget child;

  @override
  State<AnsiSelectModeTapProbe> createState() => _AnsiSelectModeTapProbeState();
}

class _AnsiSelectModeTapProbeState extends State<AnsiSelectModeTapProbe> {
  /// タップ判定対象のポインタ（先頭 1 本のみ・pointer id 照合）。
  int? _activePointerId;
  Offset? _downPosition;
  Duration? _downTimeStamp;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_activePointerId != null) {
          // 2 本指目以降は判定対象にしない（先頭ポインタの座標を上書きしない）。
          return;
        }
        _activePointerId = event.pointer;
        _downPosition = event.position;
        _downTimeStamp = event.timeStamp;
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointerId) {
          return;
        }
        _activePointerId = null;
        final downPosition = _downPosition;
        final downTimeStamp = _downTimeStamp;
        _downPosition = null;
        _downTimeStamp = null;
        if (downPosition == null || downTimeStamp == null) {
          return;
        }
        // 長押し（選択開始）はタップとして扱わない（従来どおりの選択操作）。
        if (event.timeStamp - downTimeStamp >= kLongPressTimeout) {
          return;
        }
        // ドラッグ（選択・スクロール）はタップとして扱わない。
        if ((event.position - downPosition).distance > kTouchSlop) {
          return;
        }
        widget.onTapUp(event.position);
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointerId) {
          return;
        }
        _activePointerId = null;
        _downPosition = null;
        _downTimeStamp = null;
      },
      child: widget.child,
    );
  }
}
