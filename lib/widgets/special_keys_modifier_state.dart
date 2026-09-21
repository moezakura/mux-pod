import 'package:flutter/foundation.dart';

/// ソフトウェア修飾子（CTRL/ALT/SHIFT）押下状態の唯一の所有者。
///
/// ChangeNotifier として状態変化を通知する。消費（1個ずつ通知）と
/// 一括リセット（1回通知）の意味論を持つ:
/// - [toggle*]: ボタンタップでの押下/解除。
/// - [consumeAll]: 送信時の消費（S→C→M の順で読み取り、全部クリア）。
/// - [clearAll]: 一括リセット（押下中の場合のみ1回通知）。
class SpecialKeysModifierState extends ChangeNotifier {
  bool _shiftPressed = false;
  bool _ctrlPressed = false;
  bool _altPressed = false;

  bool get shift => _shiftPressed;
  bool get ctrl => _ctrlPressed;
  bool get alt => _altPressed;

  /// いずれかの修飾子が押下中か。
  bool get any => _shiftPressed || _ctrlPressed || _altPressed;

  void toggleShift() {
    _shiftPressed = !_shiftPressed;
    notifyListeners();
  }

  void toggleCtrl() {
    _ctrlPressed = !_ctrlPressed;
    notifyListeners();
  }

  void toggleAlt() {
    _altPressed = !_altPressed;
    notifyListeners();
  }

  /// 押下中の修飾子を消費順 S→C→M で読み取り、すべてクリアする。
  ///
  /// 返り値は消費した修飾子のシンボル列（例: `['S', 'C']`）。
  /// 押下中でなければ空リストを返し、通知しない（現行の条件付き setState と同一）。
  List<String> consumeAll() {
    final consumed = <String>[];
    if (_shiftPressed) {
      _shiftPressed = false;
      consumed.add('S');
    }
    if (_ctrlPressed) {
      _ctrlPressed = false;
      consumed.add('C');
    }
    if (_altPressed) {
      _altPressed = false;
      consumed.add('M');
    }
    if (consumed.isNotEmpty) notifyListeners();
    return consumed;
  }

  /// 一括リセット（押下中の場合のみ1回通知）。
  void clearAll() {
    if (!any) return;
    _shiftPressed = false;
    _ctrlPressed = false;
    _altPressed = false;
    notifyListeners();
  }

  /// CTRL のみ消費する（Samsung workaround: 送信対象の文字に合わせて
  /// CTRL/ALT を個別に消費する経路）。押下中だった場合のみ通知し true を返す。
  bool consumeCtrl() {
    if (!_ctrlPressed) return false;
    _ctrlPressed = false;
    notifyListeners();
    return true;
  }

  /// ALT のみ消費する（Samsung workaround 経路）。押下中だった場合のみ
  /// 通知し true を返す。
  bool consumeAlt() {
    if (!_altPressed) return false;
    _altPressed = false;
    notifyListeners();
    return true;
  }
}
