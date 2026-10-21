/// herdr 実験機能のテストで共通に使う [AppSettings]。
library;

import 'package:flutter_muxpod/providers/settings_provider.dart';

/// caret テスト共通の settings（実験フラグ ON・カーソル表示 ON）。
const caretOnSettings = AppSettings(
  keepScreenOn: false,
  experimentalHerdrCaretPositionEnabled: true,
  adjustMode: 'manual',
  fontSize: 14.0,
);

/// hyperlinks 実験フラグのみ ON（caret は既定 OFF）。
const hyperlinksOnSettings = AppSettings(
  keepScreenOn: false,
  experimentalHerdrHyperlinksEnabled: true,
  adjustMode: 'manual',
  fontSize: 14.0,
);

/// caret・hyperlinks 両方 ON。
const bothOnSettings = AppSettings(
  keepScreenOn: false,
  experimentalHerdrCaretPositionEnabled: true,
  experimentalHerdrHyperlinksEnabled: true,
  adjustMode: 'manual',
  fontSize: 14.0,
);
