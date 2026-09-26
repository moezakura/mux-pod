#!/usr/bin/env python3
"""Measure a connected benchmark terminal. Emulator only; never measures mAh.

Example: python3 tool/battery/measure.py --serial SERIAL --out /tmp/run \
  --phase screen-off --seconds 1800
The matching SSH benchmark container must already be running. This script
changes app foreground/screen state and resets emulator battery statistics.
"""
import argparse
import csv
import json
import signal
import subprocess
import time
from pathlib import Path


def run(args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--phase', choices=['foreground', 'home', 'screen-off'], required=True)
    parser.add_argument('--seconds', type=int, default=1800)
    parser.add_argument('--interval', type=int, default=30)
    parser.add_argument('--container', default='muxpod-bench')
    parser.add_argument('--package', default='si.mox.mux_pod')
    args = parser.parse_args()
    if args.seconds <= 0 or args.interval <= 0:
        parser.error('duration and interval must be positive')
    adb = ['adb', '-s', args.serial, 'shell']
    if run(adb + ['getprop', 'ro.kernel.qemu']) != '1':
        raise SystemExit('Refusing to measure a non-emulator device')
    args.out.mkdir(parents=True, exist_ok=False)
    status_path = args.out / 'status.json'
    status_path.write_text(json.dumps({'status': 'running'}) + '\n')

    def interrupted(signum, frame):
        raise InterruptedError(f'Measurement interrupted by signal {signum}')

    signal.signal(signal.SIGTERM, interrupted)
    if args.phase == 'foreground':
        run(adb + ['input', 'keyevent', 'KEYCODE_WAKEUP'])
        run(adb + ['am', 'start', '-n', args.package + '/.MainActivity'])
    elif args.phase == 'home':
        run(adb + ['input', 'keyevent', 'KEYCODE_WAKEUP'])
        run(adb + ['input', 'keyevent', 'KEYCODE_HOME'])
    else:
        run(adb + ['input', 'keyevent', 'KEYCODE_SLEEP'])
    time.sleep(3)
    pid = run(adb + ['pidof', '-s', args.package])
    if not pid.isdigit():
        raise SystemExit('App must be running and connected before measuring')
    hz = int(run(adb + ['getconf', 'CLK_TCK']))

    def sample():
        if run(adb + ['pidof', '-s', args.package]) != pid:
            raise RuntimeError('App PID changed; measurement invalid')
        stat = run(adb + ['cat', '/proc/' + pid + '/stat']).rsplit(')', 1)[1].split()
        cpu = int(stat[11]) + int(stat[12])
        net = run(adb + ['cat', '/proc/net/dev'])
        fields = next(line.split(':', 1)[1].split() for line in net.splitlines()
                      if line.strip().startswith('wlan0:'))
        commands = int(run(['podman', 'exec', args.container, 'wc', '-l',
                            '/var/log/bench-cmd.log']).split()[0])
        power = run(adb + ['dumpsys', 'power'])
        wakefulness = next(line.strip().split('=', 1)[1] for line in power.splitlines()
                          if line.strip().startswith('mWakefulness='))
        idle = run(adb + ['dumpsys', 'deviceidle', 'get', 'deep'])
        expected = {'Dozing', 'Asleep'} if args.phase == 'screen-off' else {'Awake'}
        if wakefulness not in expected:
            raise RuntimeError(f'Unexpected screen state: {wakefulness} for {args.phase}')
        return [time.time(), cpu, int(fields[0]), int(fields[8]),
                int(fields[1]), int(fields[9]), commands, wakefulness, idle]

    run(adb + ['dumpsys', 'battery', 'unplug'])
    try:
        run(adb + ['dumpsys', 'batterystats', '--reset'])
        (args.out / 'threads_start.txt').write_text(run(adb + ['cat', f'/proc/{pid}/task/*/stat']))
        rows = [sample()]
        deadline = time.monotonic() + args.seconds
        with (args.out / 'samples.csv').open('w') as output:
            writer = csv.writer(output)
            writer.writerow(['epoch', 'cpu_ticks', 'rx_bytes', 'tx_bytes', 'rx_packets', 'tx_packets', 'commands', 'screen', 'deep_idle'])
            writer.writerow(rows[0])
            output.flush()
            while time.monotonic() < deadline:
                time.sleep(min(args.interval, max(0, deadline - time.monotonic())))
                rows.append(sample())
                writer.writerow(rows[-1])
                output.flush()
        for name, command in [
            ('threads_end', ['cat', f'/proc/{pid}/task/*/stat']),
            ('batterystats', ['dumpsys', 'batterystats', args.package]),
            ('power', ['dumpsys', 'power']),
            ('services', ['dumpsys', 'activity', 'services', args.package]),
        ]:
            (args.out / (name + '.txt')).write_text(run(adb + command))
        first, last = rows[0], rows[-1]
        duration = last[0] - first[0]
        cpu = (last[1] - first[1]) / hz
        summary = dict(phase=args.phase, seconds=duration, cpu_seconds=cpu,
                       cpu_percent_one_core=100 * cpu / duration,
                       rx_bytes=last[2]-first[2], tx_bytes=last[3]-first[3],
                       rx_packets=last[4]-first[4], tx_packets=last[5]-first[5],
                       commands=last[6]-first[6], clock_ticks_per_second=hz,
                       limitations='Emulator; wlan0 covers the whole device, not only this app; no mAh measurement.')
        (args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        status_path.write_text(json.dumps({'status': 'complete'}) + '\n')
        print(json.dumps(summary), flush=True)
    except BaseException as error:
        status_path.write_text(json.dumps({'status': 'failed', 'error': str(error)}) + '\n')
        raise
    finally:
        run(adb + ['dumpsys', 'battery', 'reset'])


if __name__ == '__main__':
    main()
