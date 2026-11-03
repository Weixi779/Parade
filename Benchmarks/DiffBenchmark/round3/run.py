#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Run serially on a discovered booted simulator and retain raw output/checkpoints."""
import argparse
import datetime
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--suites', nargs='+', default=['verify', 'random', 'flat', 'permutation', 'churn', 'matrix'])
parser.add_argument('--repetitions', type=int, default=1)
parser.add_argument('--start-repetition', type=int, default=1)
parser.add_argument('--engine', default='')
parser.add_argument('--scenario', default='')
parser.add_argument('--n', type=int, default=0)
parser.add_argument('--tag', default='')
parser.add_argument('--skip-install', action='store_true')
args = parser.parse_args()
results = ROOT / 'results'
logs = ROOT / 'logs'
results.mkdir(exist_ok=True)
logs.mkdir(exist_ok=True)
inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', '-j', 'devices', 'available']))
booted = [(runtime, d) for runtime, devices in inventory['devices'].items() for d in devices if d['state'] == 'Booted']
preferred = [x for x in booted if 'iOS-27' in x[0] and 'iPhone' in x[1]['name']]
udid = os.environ.get('PARADE_BENCH_UDID')
if udid:
    selected = next(x for x in booted if x[1]['udid'] == udid)
else:
    if not preferred:
        sys.exit('Boot an iOS 27 iPhone simulator or set PARADE_BENCH_UDID to a booted simulator.')
    selected = preferred[0]
    udid = selected[1]['udid']
subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True)
bundle = 'dev.weixi.ParadeDiffRound3'
if not args.skip_install:
    subprocess.run(['xcrun', 'simctl', 'install', udid, str(ROOT / 'build' / 'ParadeDiffRound3.app')], check=True)
container = pathlib.Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, bundle, 'data'], text=True).strip())
cpu = subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True, capture_output=True)
environment = {'started': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'selected': selected, 'otherBootedDevices': [x for x in booted if x != selected],
               'cpu': cpu.stdout.strip(), 'arguments': vars(args),
               'build': json.loads((ROOT / 'build' / 'environment.json').read_text())}
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
(results / f'environment-{stamp}.json').write_text(json.dumps(environment, indent=2) + '\n')
failures = []
for repetition in range(args.start_repetition, args.start_repetition + args.repetitions):
    for suite in args.suites:
        suffix = f'-{args.tag}' if args.tag else ''
        name = f'{suite}-{repetition}{suffix}'
        filename = f'round3-{name}.json'
        destination = results / f'{name}.json'
        if destination.exists():
            sys.exit(f'Refusing to overwrite existing results: {destination}')
        command = ['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process', udid, bundle,
                   '--suite', suite, '--repetition', str(repetition), '--output', filename]
        for key, value in [('engine', args.engine), ('scenario', args.scenario), ('n', args.n)]:
            if value:
                command += [f'--{key}', str(value)]
        print(f'RUN {name} on {selected[1]["name"]} ({selected[0]})', flush=True)
        begin = time.monotonic()
        with (logs / f'{name}.log').open('w') as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            try:
                code = process.wait(timeout=2700)
            except subprocess.TimeoutExpired:
                subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], capture_output=True)
                process.terminate()
                code = process.wait(timeout=15)
        data = None
        source = container / 'Documents' / filename
        if source.exists():
            shutil.copy2(source, destination)
            data = json.loads(destination.read_text())
        complete = bool(data and data.get('complete'))
        summary = {'name': name, 'complete': complete, 'launchExitCode': code,
                   'elapsedSeconds': time.monotonic()-begin, 'rows': len(data.get('records', [])) if data else 0}
        (logs / f'{name}-status.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary), flush=True)
        if not complete:
            failures.append(summary)
            print('\n'.join((logs / f'{name}.log').read_text().splitlines()[-12:]), flush=True)
if failures:
    sys.exit(f'{len(failures)} suite(s) did not complete; checkpoints and logs retained.')
