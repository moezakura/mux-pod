#!/usr/bin/env python3
"""Repeated foreground/background polling check, on an already connected emulator."""
import argparse
import json
import subprocess
import time
from pathlib import Path


def run(args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--trials', type=int, default=30)
    parser.add_argument('--warmup', type=float, default=10)
    parser.add_argument('--foreground-seconds', type=float, default=10)
    parser.add_argument('--settle', type=float, default=5)
    parser.add_argument('--background-seconds', type=float, default=15)
    parser.add_argument('--container', default='muxpod-bench')
    args = parser.parse_args()
    if min(args.trials, args.foreground_seconds, args.background_seconds) <= 0 or min(args.warmup, args.settle) < 0:
        parser.error('invalid trial count or interval')
    if args.out.exists():
        parser.error('output file already exists')
    adb = ['adb', '-s', args.serial, 'shell']
    if run(adb + ['getprop', 'ro.kernel.qemu']) != '1':
        raise SystemExit('Emulator required')
    args.out.parent.mkdir(parents=True, exist_ok=True)

    def count():
        return int(run(['podman', 'exec', args.container, 'wc', '-l', '/var/log/bench-cmd.log']).split()[0])

    failed = False
    with args.out.open('w') as output:
        for trial in range(1, args.trials + 1):
            run(adb + ['input', 'keyevent', 'KEYCODE_WAKEUP'])
            run(adb + ['am', 'start', '-n', 'si.mox.mux_pod/.MainActivity'])
            time.sleep(args.warmup)
            first = count()
            time.sleep(args.foreground_seconds)
            foreground = count() - first
            run(adb + ['input', 'keyevent', 'KEYCODE_HOME'])
            time.sleep(args.settle)
            first = count()
            time.sleep(args.background_seconds)
            background = count() - first
            passed = foreground > 0 and background == 0
            failed |= not passed
            result = dict(trial=trial, foreground_commands=foreground,
                          background_commands=background, passed=passed,
                          foreground_seconds=args.foreground_seconds,
                          background_seconds=args.background_seconds,
                          settle_seconds=args.settle)
            line = json.dumps(result)
            print(line, flush=True)
            output.write(line + '\n')
            output.flush()
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
