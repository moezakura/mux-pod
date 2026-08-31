// ignore_for_file: unnecessary_brace_in_string_interps

/// tmux コマンド出力の fixture
///
/// Written with the legacy 0x1f/0x1e pair on purpose: output recorded from a
/// MuxPod that still asked tmux for the control characters has to keep
/// parsing, whatever delimiters the current call minted. The live shape —
/// printable, per-invocation — is covered in tmux_facade_test.dart.
library;

import 'package:flutter_muxpod/services/tmux/tmux_delimiters.dart';

const _fs = TmuxDelimiters.legacyField;
const _rs = TmuxDelimiters.legacyRecord;

// セッション一覧（詳細版）
const kSessionOutput =
    'mysession${_fs}1735689600${_fs}1${_fs}3${_fs}\$0${_rs}'
    'other${_fs}1735689700${_fs}0${_fs}1${_fs}\$1${_rs}';

// セッション一覧（簡易版）
const kSessionOutputSimple = r'''
mysession:3:1
other:1:0
''';

// ウィンドウ一覧（詳細版）
const kWindowOutput =
    '0${_fs}@0${_fs}shell${_fs}1${_fs}2${_fs}-${_rs}'
    '1${_fs}@1${_fs}build${_fs}0${_fs}1${_fs}*${_rs}'
    '2${_fs}@2${_fs}zoomed${_fs}0${_fs}1${_fs}*Z${_rs}';

// ウィンドウ一覧（簡易版）
const kWindowOutputSimple = r'''
0:shell:1:2
1:build:0:1
''';

// ペイン一覧（詳細版）
const kPaneOutput =
    '0${_fs}%0${_fs}1${_fs}bash${_fs}shell-title${_fs}80${_fs}24${_fs}0${_fs}0${_rs}'
    '1${_fs}%1${_fs}0${_fs}vim${_fs}vim-title${_fs}80${_fs}24${_fs}10${_fs}5${_rs}';

// ペイン一覧（簡易版）
const kPaneOutputSimple = r'''
0:%0:1:80x24
1:%1:0:80x24
''';

// 完全ツリー（list-panes -a）
const kFullTreeOutput =
    'mysession${_fs}\$0${_fs}0${_fs}@0${_fs}shell${_fs}1${_fs}0${_fs}%0${_fs}1${_fs}80${_fs}24${_fs}0${_fs}0${_fs}bash${_fs}bash${_fs}5${_fs}10${_fs}/home/user${_fs}-${_rs}'
    'mysession${_fs}\$0${_fs}0${_fs}@0${_fs}shell${_fs}1${_fs}1${_fs}%1${_fs}0${_fs}80${_fs}24${_fs}80${_fs}0${_fs}vim${_fs}vim${_fs}15${_fs}20${_fs}/home/user/projects${_fs}*${_rs}'
    'other${_fs}\$1${_fs}0${_fs}@10${_fs}logs${_fs}1${_fs}0${_fs}%10${_fs}1${_fs}80${_fs}24${_fs}0${_fs}0${_fs}tail${_fs}tail${_fs}0${_fs}0${_fs}/var/log${_fs}#${_rs}';

// ペイン内容（ANSI 付き）
const kPaneContentWithAnsi = '\x1b[32mhello\x1b[0m\nworld\n';

// ペイン内容（空行付き）
const kPaneContentWithTrailingBlank = 'line1\n\n';

// サーバー未起動
const kNoServerOutput = 'no server running';

// セッション未検出
const kSessionNotFoundOutput = 'session not found: missing';

// 不正区切り
const kMalformedTooFewFields = 'just_one_field';

// 空出力
const kEmptyOutput = '';
