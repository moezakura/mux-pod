# バッテリー負荷の計測

`measure.py` は、接続済みターミナルのCPU時間・端末全体のwlan0通信量・ベンチサーバーのコマンド数を計測する。**エミュレーター限定**であり、電池消費量（mAh）の測定ではない。

## 前提

- 明示したADB serialがAndroid Emulatorであること（スクリプトでも検査）。
- profile APKを導入し、対象のtmux/herdrペインへ接続済み。
- `muxpod-bench` コンテナで `while true; do date; sleep 1; done` が動作し、`/var/log/bench-cmd.log` にマルチプレクサ呼び出しが記録されること。
- 計測対象の通信設定・実効モード・APKのSHA-256を別途記録する。
- 計測中は他のアプリ操作、画面キャプチャ、インストール、並列計測を行わない。

## 実行例

```bash
python3 tool/battery/measure.py --serial EMULATOR_SERIAL \
  --out /tmp/battery-tmux-fg --phase foreground --seconds 1800
python3 tool/battery/measure.py --serial EMULATOR_SERIAL \
  --out /tmp/battery-tmux-home --phase home --seconds 1800
python3 tool/battery/measure.py --serial EMULATOR_SERIAL \
  --out /tmp/battery-tmux-off --phase screen-off --seconds 1800
```

出力先は未作成のディレクトリを指定する。計測は一台につき直列で実行する。

- `foreground`: 画面点灯・アプリを前面へ移す。
- `home`: HOMEへ移す。バランスでは最初の1分の保持を含む。
- `screen-off`: 画面を消す。すでに背景で猶予が切れていれば、計測中の新しい猶予は発生しない。

計測開始でエミュレーターを非充電扱いにし、batterystatsをリセットする。終了・例外時に充電状態をリセットする。強制終了やホスト障害で後始末できなかった場合は、対象serialを確認して `adb -s EMULATOR_SERIAL shell dumpsys battery reset` を実行する。

## 成果物と解釈

- `status.json`: completeのみ有効な計測として扱う。
- `samples.csv`: タイムスタンプ、CPU tick、通信量、コマンド累計、画面状態、deep idle状態。意図しない画面状態になれば計測を失敗として扱う。
- `threads_start.txt`, `threads_end.txt`: 計測前後のスレッド別CPU情報。
- `summary.json`: 実際の計測秒数と差分。CPU比率は1コア比。
- `batterystats.txt`, `power.txt`, `services.txt`: 保持・サービス状態。

画面取得コマンドがゼロでも、転送やkeep-aliveの通信までゼロとは限らない。wlan0は端末全体なので、他アプリの通信を本アプリに帰属させない。停止試験はSSHを切断せず、背景化後にコマンド数が増えないことと前面復帰後に再び増えることを組み合わせる。

Android実機のモバイル通信・長時間Doze、iOS、実際の電池消費量は別途検証する。

## 背景移行の反復

```bash
python3 tool/battery/home_trials.py --serial EMULATOR_SERIAL \
  --out /tmp/battery-home-trials.jsonl --trials 30
```

各試行で前面10秒のコマンド増加を確認し、HOME移行後5秒待ってから背景15秒のコマンドを数える。前面でコマンドが増えない場合も失敗とし、切断しただけの状態を「省電力成功」に数えない。短縮試験ではオプションで時間を変更できるが、標準試験と区別して記録する。
