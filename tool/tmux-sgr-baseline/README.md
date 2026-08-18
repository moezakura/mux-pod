# SGR 素通し実証ベースライン（B1〜B4）

`capture_baseline.sh` はスクロール送信モード（`PaneCapabilities.wheelSend`
フリップ・D11 ゲート）の前提となる SGR 素通し・copy-mode 挙動・連結送信を
タイムスタンプ付きディレクトリに記録する。ソース・テストファイルは変更しない。

```bash
tool/tmux-sgr-baseline/capture_baseline.sh
```

生成される結果ディレクトリ:

- `metadata.txt`: commit・作業ツリー状態・OS・tmux/herdr バージョン・
  Flutter/Dart バージョン（実行環境の固定・Open Questions #5 対応）。
- `b1-receiver.out` / `b4-receiver.out` / `b3-receiver.out`: 受信側
  `od -An -tx1` が受け取ったバイト列。
- `b1.log` / `b2.log` / `b3.log` / `b4.log`: 各実測の詳細（期待値 vs 受信値）。
- `result.summary`: `B<n>_RESULT=PASS|FAIL|SKIPPED|OBSERVED` の集約。

## 実測項目

| # | 内容 | 判定 | wheelSend への影響 |
|---|------|------|-------------------|
| B1 | tmux `send-keys -l` による SGR（`ESC[<64;1;1M`）素通し | 受信バイト列が完全一致で PASS | tmux 側 wheel 有効化 |
| B2 | herdr `send-text` による SGR / プレーンテキスト素通し（**(b) 文字キー送信の sendText 素通し確認を兼ねる**・L0-a #6） | send-text が exit 0 + stdout 空で PASS | herdr 側 wheel 有効化 |
| B3 | copy-mode 中の SGR 送信挙動（先頭 ESC が cancel になるか・残りがゴミになるか・R1 の実証） | 観測事実（OBSERVED）として記録 | —（`_isCopyModeDetected` 方式の妥当性確認資料） |
| B4 | 連結送信（8 ティック分の SGR を 1 コマンドで送信） | 受信バイト列が 8 連結分一致で PASS | 合流方式（D6・最大 8 ティック）の妥当性確認 |

**B5（1 本指ドラッグと 2 本指ピンチの競合）はスクリプト対象外**（Flutter の
gesture arena はシェルで実測不能。widget テスト / 実機で確認・Phase 0 #4）。

## SKIPPED（未実施）の扱い

tmux / herdr が存在しない・herdr サーバに到達できない場合はその項目を
**SKIPPED（未実施）** として記録し、exit 0 で完了する（環境依存のため）。
`wheelSend` フリップは **実測が PASS の backend のみ** true へ（D11 ゲート）。
未実施・未達の backend は false のまま（key フォールバック）。

## 出力ディレクトリの明示

```bash
tool/tmux-sgr-baseline/capture_baseline.sh /tmp/tmux-sgr-baseline
```

上書き防止のため、既存ディレクトリ指定時は 73 で失敗する。
