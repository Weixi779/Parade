#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Repeat the empty-call diagnostic after allowing initial UI transactions to settle."""
import pathlib

ROOT=pathlib.Path(__file__).resolve().parent
base=ROOT.parent/'empty-ui-calls'/'probe.py'
code=base.read_text().replace("BUNDLE = 'dev.weixi.ParadeDiffEmptyCallsProbe'", "BUNDLE = 'dev.weixi.ParadeDiffSettledProbe'")
needle="    generated = BUILD / 'ProbeMain.swift'"
assert code.count(needle)==1
code=code.replace(needle,'''    # Same initial-state settle for all candidates, entirely outside timing.
    source=source.replace('        configured = 0; collection.resetCounters()',
        '        CATransaction.flush()\\n        try! await Task.sleep(nanoseconds: 30_000_000)\\n        configured = 0; collection.resetCounters()')
    source=source.replace('        if !only.isEmpty { all = all.filter { $0.name == only } }',
        '        all = all.filter { ["append-5pct", "rotate-right-1", "mixed"].contains($0.name) }\\n        if !only.isEmpty { all = all.filter { $0.name == only } }')
    source=source.replace('let warmups = suite == "random" ? 0 : 5', 'let warmups = suite == "random" ? 0 : 3')
    source=source.replace('suite == "flat" ? 40 : 30', 'suite == "flat" ? 20 : 30')
'''+needle)
code=code.replace("len(data['records'])==60", "len(data['records'])==15")
code=code.replace('60 combinations, 2400 formal samples', '15 combinations, 300 formal samples')
code=code.replace('Only guard six empty UIKit calls; same diff, stages, content primitive, completion and layout boundary.',
    'Same empty-call variants; all candidates flush initial transaction and wait 30 ms before timing; 3 fixtures at 100 items.')
exec(compile(code,str(base),'exec'),globals())
