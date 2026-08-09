# Herdr mutation baseline (T0 spike)

herdr 0.7.5 の mutation 系コマンド（`pane send-keys` / `send-text` / `resize` /
`focus` / `edges` / `zoom` / `split`）の実機計測レポート。

## 成果物

| ファイル | 内容 |
|---|---|
| `mutation-baseline-report.md` | **本編**。全キー送信経路分類・エスケープ/制御文字伝送・resize ステップ換算・focus/edges 応答・layout JSON 構造 |
| `capture_mutation_baseline.sh` | 実測収集＋ローカル検証（`make analyze` / `make test`）のオーケストレータ |
| `scripts/remote_sendkeys_sweep.sh` | send-keys 受容性スイープ（リモート実行、TSV 出力） |
| `scripts/remote_transmission_sweep.sh` | エスケープシーケンス伝送スイープ（cat -v エコー、od -c） |
| `scripts/remote_controlchars_sweep.sh` | 制御文字伝送スイープ（cat -v エコー） |
| `scripts/remote_mutation_sweep.sh` | split/resize/zoom/edges/focus 応答 JSON 収集 |
| `scripts/remote_resize_precise.sh` | resize amount 換算の精密実測 |
| `results/<timestamp>/` | 実測生データ（TSV / ログ / メモ） |

## 主要な発見（要約）

1. **send-keys は最小語彙のみ**: 受理は F1-F12・Enter/Tab/Space/Backspace/BS/Escape・
   矢印 4 種・C-c の 21 種だけ。Home/End/PageUp/PageDown/Insert/Delete・全 S-*・全 M-*・
   C-c 以外の全 C-* は `invalid_key`（rc=1）で拒否。
2. **拒否キーは send-text のエスケープ/制御文字経路で送信可能**:
   `send-text` はバイナリ素通し。`\x1b[H`(Home)・`\x1b[5~`(PgUp)・`\x04`(C-d)・`\x18`(C-x)
   は cat -v エコーでバイト完全到達を確認。
3. **resize の amount は現在 ratio への加算**（絶対指定ではない）。クランプ [0.1, 0.9]、
   1 回あたり delta 最大 0.5、負値は絶対値扱い。セル換算は `round(ratio × コンテナ幅)`。
4. **mutation 応答の layout**: resize/zoom/focus/edges は layout JSON 込み、
   split は含まない（`pane_info`）。zoom は `layouts[].zoomed` フラグのみで
   `panes[].rect` は非 zoom 時の値のまま。

## 再現手順

```bash
# 1. 実機へスクリプト転送して計測（ホストは SSH 設定済み前提）
tool/herdr-mutation-baseline/capture_mutation_baseline.sh mox@192.168.10.132
```

`capture_mutation_baseline.sh` は ①実機で各スイープを実行し `results/<timestamp>/` に
生データを保存、②ローカルで `make analyze` / `make test` を実行する。
