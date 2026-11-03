#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Validate all runs, export complete comparison tables and descriptive figures."""
import csv
import hashlib
import json
import math
import os
import pathlib
import statistics as stats
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent
ASSETS = ROOT / 'assets'
ASSETS.mkdir(exist_ok=True)
OUT = ROOT / 'results'
EXPECTED = {'flat': 288, 'permutation': 288, 'churn': 567, 'matrix': 400}
METRICS = ['prepareMs', 'applyMs', 'layoutMs', 'totalMs']
AL, A, D, H, L, KL, KH, KR, AR, R = [
    'Apple-reloadItems', 'Apple-reconfigure', 'DifferenceKit-staged', 'Unique-Heckel-staged',
    'Key-LIS-staged', 'ListKit-LIS-exact', 'ListKit-Heckel-exact', 'ListKit-default-no-animation',
    'Apple-reloadData', 'UIKit-reloadData']
LABELS = {AL: 'Apple reloadItems', A: 'Apple reconfigure', D: 'DifferenceKit', H: '自研 Heckel',
          L: '自研 LIS', KL: 'ListKit LIS', KH: 'ListKit Heckel', KR: 'ListKit false → reload',
          AR: 'Apple reloadData', R: 'UIKit reloadData'}
FLAT = ['no-op', 'append-5pct', 'prepend-5pct', 'delete-5pct', 'update-5pct', 'adjacent-swap',
        'rotate-left-1', 'rotate-right-1', 'mixed', 'shuffle', 'reverse', 'replace-all']
NAMES = {'no-op': '无变化', 'append-5pct': '尾部新增 5%', 'prepend-5pct': '头部新增 5%',
         'delete-5pct': '删除 5%', 'update-5pct': '内容更新 5%', 'adjacent-swap': '相邻交换',
         'rotate-left-1': '左旋一项', 'rotate-right-1': '右旋一项', 'mixed': '混合更新',
         'shuffle': '随机乱序', 'reverse': '完全逆序', 'replace-all': '全部替换'}
grouped = defaultdict(list)
raw_rows = []
formal_samples = 0
warmups = 0

for suite, expected in EXPECTED.items():
    for repetition in range(1, 4):
        path = OUT / f'{suite}-{repetition}.json'
        data = json.loads(path.read_text())
        assert data['complete'] and not data['uiAnimationsEnabled']
        assert data['suite'] == suite and data['repetition'] == repetition
        assert len(data['records']) == expected, (path, len(data['records']))
        expected_sizes = {6,99,999,9999} if suite == 'matrix' else {100,1000,10000}
        assert {r['n'] for r in data['records']} == expected_sizes
        fixture_keys = {(r['n'],r['scenario']) for r in data['records']}
        assert len(fixture_keys) == {'flat':36,'permutation':36,'churn':63,'matrix':80}[suite]
        seen = set()
        for row in data['records']:
            key = (suite, row['n'], row['scenario'], row['engine'])
            assert key not in seen, (path, key)
            seen.add(key)
            assert row['runs'] == (40 if suite == 'flat' else 30)
            assert len(row['samples']) == row['runs']
            assert row['warmups'] == 5
            for sample in row['samples']:
                assert all(sample[m] >= 0 and math.isfinite(sample[m]) for m in METRICS)
                assert abs(sum(sample[m] for m in METRICS[:3]) - sample['totalMs']) < 1e-7
                if row['callsObservable']:
                    assert sample['calls'] == row['calls'], (path, key, 'varying operation count')
            for metric in METRICS:
                values = sorted(s[metric] for s in row['samples'])
                assert abs(stats.median(values) - row[f'median-{metric}']) < 1e-9
                assert abs(values[math.ceil(len(values)*.95)-1] - row[f'p95-{metric}']) < 1e-9
            grouped[key].append(row)
            formal_samples += row['runs']
            warmups += row['warmups']
            flat = {k: v for k, v in row.items() if k not in ['samples', 'calls']}
            flat.update({'suite': suite, 'repetition': repetition})
            if row['callsObservable']:
                flat.update(row['calls'])
            raw_rows.append(flat)

def csv_write(path, rows):
    columns = sorted({k for row in rows for k in row})
    with path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

csv_write(OUT / 'all-runs.csv', raw_rows)
aggregated = []
for key, rows in sorted(grouped.items()):
    assert len(rows) == 3, key
    suite, n, scenario, engine = key
    if rows[0]['callsObservable']:
        assert all(r['calls'] == rows[0]['calls'] for r in rows), key
    out = {'suite': suite, 'n': n, 'scenario': scenario, 'engine': engine,
           'targetN': rows[0]['targetN'], 'sections': rows[0]['sections'],
           'requestedFraction': rows[0]['requestedFraction'], 'seed': rows[0]['seed'],
           'samplesAcrossRuns': sum(r['runs'] for r in rows)}
    for metric in METRICS:
        medians = [r[f'median-{metric}'] for r in rows]
        out[metric] = stats.median(medians)
        out[f'minRunMedian-{metric}'] = min(medians)
        out[f'maxRunMedian-{metric}'] = max(medians)
        out[f'medianRunP95-{metric}'] = stats.median(r[f'p95-{metric}'] for r in rows)
        for i, r in enumerate(rows, 1):
            out[f'run{i}Median-{metric}'] = r[f'median-{metric}']
    if rows[0]['callsObservable']:
        out.update(rows[0]['calls'])
    out['configuredCells'] = stats.median(r['median-configuredCells'] for r in rows)
    aggregated.append(out)
for suite in EXPECTED:
    csv_write(OUT / f'{suite}.csv', [r for r in aggregated if r['suite'] == suite])

lookup = {(r['suite'], r['n'], r['scenario'], r['engine']): r for r in aggregated}
def row(suite, n, scenario, engine):
    return lookup[(suite, n, scenario, engine)]
def value(suite, n, scenario, engine, metric='totalMs'):
    return row(suite, n, scenario, engine)[metric]
def ms(suite, n, scenario, engine):
    return f'{value(suite, n, scenario, engine):.3f}'
def table(suite, n, scenarios, engines):
    lines = ['| 场景 | ' + ' | '.join(LABELS[e] for e in engines) + ' |',
             '|---|' + '---:|'*len(engines)]
    for scenario in scenarios:
        lines.append('| '+NAMES.get(scenario, scenario)+' | '+' | '.join(ms(suite, n, scenario, e) for e in engines)+' |')
    return lines
def permutations(n):
    return [f'rotate-{k}' for k in [1, 2, 10, n//2, n-1]] + ['block-move', 'block-swap', 'interleave',
           'odd-even', 'middle-to-head', 'disjoint-block-swaps', 'reverse']
def churn(n, pct, engine):
    return stats.median(r['totalMs'] for r in aggregated if r['suite']=='churn' and r['n']==n
                        and abs(r['requestedFraction'] - pct/100) < 1e-8 and r['engine']==engine)
def range_ms(suite, n, scenario, engine):
    r = row(suite, n, scenario, engine)
    return f"{r['minRunMedian-totalMs']:.3f}–{r['maxRunMedian-totalMs']:.3f}"

verify = json.loads((OUT / 'verify-1.json').read_text())
random = json.loads((OUT / 'random-1.json').read_text())
assert verify['complete'] and verify['verifiedMatcherCases']==14828
assert random['complete'] and len(random['records'])==1000
environment_paths = sorted(OUT.glob('environment-*.json'))
env = json.loads(environment_paths[-1].read_text())
source_root = pathlib.Path(os.environ.get('PARADE_BENCH_SOURCE_ROOT', ROOT.parent)).resolve()
build_root = pathlib.Path(os.environ.get('PARADE_BENCH_BUILD_ROOT', ROOT / 'build')).resolve()
lists_root = pathlib.Path(os.environ.get('LISTS_PATH', ROOT.parent / '.build' / 'Lists')).resolve()
for relative, expected in env['build']['harnessHashes'].items():
    assert hashlib.sha256((source_root / relative).read_bytes()).hexdigest()==expected, relative
for module, entries in env['build']['modules'].items():
    for relative, hashes in entries.items():
        upstream=lists_root/'Sources'/'ListKit'/relative
        compiled=build_root/'generated'/module/relative
        assert hashlib.sha256(upstream.read_bytes()).hexdigest()==hashes['upstream'], relative
        assert hashlib.sha256(compiled.read_bytes()).hexdigest()==hashes['compiled'], relative
binary = build_root / 'ParadeDiffRound3.app' / 'ParadeDiffRound3'
assert hashlib.sha256(binary.read_bytes()).hexdigest()==env['build']['binarySHA256']

# Use plots only after all timing work has finished.
os.environ.setdefault('MPLCONFIGDIR', str(ROOT / 'build' / 'matplotlib'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig, axes = plt.subplots(1, 3, figsize=(14.5, 4.7))
chart_cases = ['rotate-left-1', 'rotate-right-1', 'mixed', 'shuffle', 'reverse']
for ax, n in zip(axes, [100, 1000, 10000]):
    xs = list(range(len(chart_cases)))
    for engine, color, offset, label in [(KH, '#cf7733', -.19, 'ListKit + greedy Heckel'),
                                         (KL, '#168b86', .19, 'ListKit + LIS')]:
        centers = [value('flat', n, s, engine) for s in chart_cases]
        errors = [[v-row('flat', n, s, engine)['minRunMedian-totalMs'] for s,v in zip(chart_cases,centers)],
                  [row('flat', n, s, engine)['maxRunMedian-totalMs']-v for s,v in zip(chart_cases,centers)]]
        ax.bar([x+offset for x in xs], centers, .36, color=color, label=label, yerr=errors, capsize=2)
    ax.set_title(f'{n:,} items')
    ax.set_xticks(xs, ['Left\nrotate 1', 'Right\nrotate 1', 'Mixed', 'Shuffle', 'Reverse'])
    ax.set_ylim(bottom=0)
    ax.spines[['top','right']].set_visible(False)
    ax.grid(axis='y', alpha=.16)
axes[0].set_ylabel('Total elapsed update time (ms)')
fig.suptitle('Same ListKit backend; only move selection changes', fontsize=14)
fig.text(.5, .88, 'Median of 3 run medians; whiskers = observed run range, not confidence intervals. iOS 27 Simulator, animations off.',
         ha='center', fontsize=9, color='#555')
handles, labels = axes[0].get_legend_handles_labels()
fig.legend(handles, labels, loc='lower center', ncol=2, frameon=False)
fig.subplots_adjust(top=.79, bottom=.21, wspace=.26)
fig.savefig(ASSETS/'listkit-ablation.png', dpi=170, bbox_inches='tight')
fig.savefig(OUT/'listkit-ablation.svg', bbox_inches='tight')
plt.close(fig)

lines = ['# 第三轮完整结果：ListKit、Heckel、LIS 与 UIKit', '',
    '**后续诊断修正：本轮采用新建列表后立即更新的采样方式。统一提交初始事务并在计时外等待 30 ms 后，100 项追加 / 右旋中 ListKit 的明显优势消失。以下保留原始结果，不应直接用作稳定展示中的列表性能排名。空 UIKit 调用也未被补测确认为主要差额来源。见 [追查结果](diagnostics/RESULTS.md)。**', '',
    '**完整性能矩阵已串行跑完三轮。结论是有条件的：LIS 不保证完整后端更快，但当它把数百 / 数千个多余 move 压到很少时，收益能直接体现在实际 UIKit 更新总耗时。**', '',
    '本轮不复用旧轮耗时；所有表来自同一个新 harness 的重新测量。[方法、版本与复现](README.md)。', '',
    f"- 平面 / 排列 / churn / 多节：每轮共 {sum(EXPECTED.values()):,} 个组合，三轮共 {len(raw_rows):,} 行结果、{formal_samples:,} 次正式更新，另有 {warmups:,} 次预热。",
    '- 14,828 次 matcher 检查；200 组随机多节 × 5 个后端，共 1,000 次额外 UIKit 检查。全部 complete=true。',
    f"- {env['cpu']}；iPhone 18 Pro / iOS 27.0 模拟器；Xcode 27 / Swift 6.4；-O + whole-module-optimization。", '',
    '**单位统一为 ms。** 主表是三轮各自中位数的中位数；不是最快值。总耗时包括准备、内部 diff / 任务等待、UIKit 更新到 completion 或直接调用返回，再完成 layout。未测像素呈现或动画帧时间。', '',
    '## 1. 首先看常见边界：100 项', '',
    '以下均为精确更新路径。ListKit 两列只有 move 选择不同。Apple 分开 reloadItems 与 reconfigure；自研 / DifferenceKit 的内容使用 reload，因此 update / mixed 跨列差异不能只归因于 LIS。', '']
lines += table('flat', 100, FLAT, [AL,A,D,H,L,KL,KH])
lines += ['', '100 项时的阶段与内容更新对照：', '',
          '| 场景 | 自研 Heckel batch / cell 配置 | DifferenceKit batch / cell 配置 | ListKit Heckel batch / cell 配置 | ListKit LIS batch / cell 配置 |',
          '|---|---:|---:|---:|---:|']
for s in ['prepend-5pct','update-5pct','mixed']:
    lines.append('| '+NAMES[s]+' | '+' | '.join(
        f"{row('flat',100,s,e)['batches']} / {row('flat',100,s,e)['configuredCells']:g}" for e in [H,D,KH,KL])+' |')
lines += ['',
    '这里应优先看无变化、追加 / 前插、内容更新与 mixed 的绝对时间；不能把 10,000 项旋转的倍数直接用作日常需求的架构权重。', '',
    'ListKit 两种算法在无变化和纯内容更新时走相同快速路径；跨框架的源码差异还包括 snapshot 表示、空操作省略、阶段数和 reconfigure 的执行方式。各项差异不等于已经测出了各自的收益，后续诊断也未发现空调用是主要差额来源。', '',
    '本轮自研 / DifferenceKit 的 UIKit 适配器沿用逐 stage 的执行方式，并仍会调用空数组的 UIKit 方法；ListKit 原版会跳过这些调用。两者的完整后端差距不是“自研 Heckel 的性能上限”。阶段数、内容原语、空调用的各自贡献没有单独分摊，本轮最干净的算法因果对照仍是 ListKit 内部两个版本。', '',
    '## 2. 同一个 ListKit：LIS 是否仅让结果漂亮？', '',
    f'![ListKit controlled comparison](assets/listkit-ablation.png)', '',
    '| 项数 / 场景 | Heckel move | LIS move | Heckel 总耗时 | LIS 总耗时 | LIS 节省 ms | Heckel / LIS |',
    '|---|---:|---:|---:|---:|---:|---:|']
for n in [100,1000,10000]:
    for scenario in ['rotate-left-1','rotate-right-1','mixed','shuffle','reverse']:
        h,l = row('flat',n,scenario,KH),row('flat',n,scenario,KL)
        lines.append(f"| {n:,} / {NAMES[scenario]} | {h['itemMoves']:,} | {l['itemMoves']:,} | {h['totalMs']:.3f} | {l['totalMs']:.3f} | {h['totalMs']-l['totalMs']:+.3f} | {h['totalMs']/l['totalMs']:.2f}× |")
lines += ['',
    '读法：节省为正表示 LIS 更快；倍数是 Heckel 耗时除以 LIS 耗时。旋转和 mixed 可大幅减少操作；shuffle 往往只能少一小部分；reverse 两边仍然都需要 n−1 个 move。', '',
    '**三种情况必须分开：**', '',
    '1. 少报大量 move：额外 LIS 计算可能被 UIKit 侧节省覆盖，左旋是明确检验点。',
    '2. 只少报少量 move：总耗时可能接近，shuffle 应结合三轮波动阅读。',
    '3. move 完全相同：LIS 不提供操作数量收益，有时额外计算反而更贵，例如右旋一项。', '',
    '更准确的成本模型是 `总时间 = 内容/snapshot准备 + 匹配与move选择 + 调度等待 + UIKit批次工作 + 最终layout`。LIS 最小化单位 item move 的数量，并未最小化这整个式子。不同 move 涉及的可见 cell、更新内容、section 与布局范围也不同，不能给每个 move 统一标一个恒定价格。', '',
    '因此，即使同样少了 25 次 move，在 100 项、复杂 self-sizing cell、或者全部离屏的情况下，收益也可能不同。本轮使用简单固定高度 cell；真实内容和提交频率需要单独赋予权重，绝对差 0.1 ms 也不能无条件当成零。', '',
    '三轮重复的范围如下，避免把很小的差值当稳定结论：', '',
    '| 项数 / 场景 | Heckel 各轮中位数范围 | LIS 各轮中位数范围 |', '|---|---:|---:|']
for n in [100,1000,10000]:
    for s in ['rotate-left-1','rotate-right-1','shuffle']:
        lines.append(f'| {n:,} / {NAMES[s]} | {range_ms("flat",n,s,KH)} | {range_ms("flat",n,s,KL)} |')
lines += ['', '## 3. 完整平面大规模数据', '']
for n in [1000,10000]:
    lines += [f'### {n:,} 项', ''] + table('flat',n,FLAT,[AL,A,D,H,L,KL,KH]) + ['']
lines += ['**跨后端排名不是算法排名。** 例如自研平面原型比 ListKit 少了通用 snapshot / 调度能力；ListKit 两种版本都保留 1,000 项起的后台 diff。相同 move 数下仍会出现存储、适配、调度和执行器成本差异。', '',
    '## 4. Systematic permutation：所有排列都跑了', '',
    'rotate-k 表示左旋 k 项，rotate-(n−1) 等价于右旋一项。每表保留原始场景名称，便于定位 CSV。', '']
for n in [100,1000,10000]:
    lines += [f'### {n:,} 项', ''] + table('permutation',n,permutations(n),[A,D,H,L,KL,KH]) + ['']
lines += ['### 10,000 项实际提交的 move 数', '',
          '| 场景 | DifferenceKit | 自研 Heckel | 自研 LIS | ListKit LIS | ListKit Heckel |', '|---|---:|---:|---:|---:|---:|']
for s in permutations(10000):
    lines.append('| '+s+' | '+' | '.join(str(row('permutation',10000,s,e)['itemMoves']) for e in [D,H,L,KL,KH])+' |')
lines += ['', '## 5. Churn 与 reload 对照', '',
    '**ListKit 的 false 不等于 Apple 的 false。** 该版本 ListKit 在 diff 后只要有变化就 reloadData；下面才把它放在重载对照中。0% 无变化仍走快速返回。不能拿这一列冒充精确更新胜出。', '',
    '每档值先按每个 seed 汇总三轮，再对三个 seed 取中位数。比例是被选中参与重排的 item 占比，不是最少 move 比例，也不是已测出的生产 fallback 阈值。', '']
for n in [100,1000,10000]:
    engines=[A,D,H,L,KL,KH,KR,AR,R]
    lines += [f'### {n:,} 项', '', '| 选中重排 | '+' | '.join(LABELS[e] for e in engines)+' |', '|---|'+'---:|'*len(engines)]
    for pct in [0,10,25,50,75,90,100]:
        lines.append(f'| {pct}% | '+' | '.join(f'{churn(n,pct,e):.3f}' for e in engines)+' |')
    lines += ['']
lines += ['### 局部重排也可能放大贪心 move 数', '',
          '| 项数 / 被选中重排 | Heckel 实际 move 范围 | LIS 实际 move 范围 | Heckel 总耗时 | LIS 总耗时 |',
          '|---|---:|---:|---:|---:|']
for n in [100,1000,10000]:
    for pct in [10,50,100]:
        ranges=[]
        for engine in [KH,KL]:
            counts=[r['itemMoves'] for r in aggregated if r['suite']=='churn' and r['n']==n
                    and abs(r['requestedFraction']-pct/100)<1e-8 and r['engine']==engine]
            assert len(counts)==3
            ranges.append(f'{min(counts):,}–{max(counts):,}')
        lines.append(f'| {n:,} / {pct}% | '+' | '.join(ranges)+f' | {churn(n,pct,KH):.3f} | {churn(n,pct,KL):.3f} |')
lines += ['',
    '贪心扫描以“下一个尚未消耗的旧位置”为保留基准；少数 item 提前 / 推后就可能让不少原本相对有序的 item 被显式移动。因此少量位置被选中参与 shuffle，并不保证 Heckel 只提交少量 move。是否属于业务常见输入应由真实更新模式判断，不能只用“整体没怎么变”代替测量。', '']
lines += ['ListKit false 列包含完整 diff 决策成本，UIKit reloadData 列不算 diff，也不建 ID snapshot。后者描述已决定重载时的成本。重载是否允许仍取决于状态保持与真实 cell 成本，本轮没有验证完整交互合同。', '',
    '## 6. Section + item 联合变化', '',
    '三节合计 6 / 99 / 999 / 9,999 项；20 场景 × 5 后端 × 3 轮全部通过。这里测公开 sectioned DifferenceKit 和 ListKit；自研平面原型不冒充多节实现。', '']
matrix_scenarios=sorted({r['scenario'] for r in aggregated if r['suite']=='matrix'})
for n in [6,99,999,9999]:
    lines += [f'### 合计 {n:,} 项', ''] + table('matrix',n,matrix_scenarios,[AL,A,D,KL,KH]) + ['']
lines += ['### 多节里更关键的操作差异', '',
          '合计 9,999 项。S 为显式 section move，I 为显式 item move；下列均为实际提交计数。', '',
          '| 场景 | DifferenceKit | ListKit Heckel | ListKit LIS |', '|---|---:|---:|---:|']
for scenario in ['section-rotate-left','section-move-and-local-reorder','section-move-cross-section-move-update']:
    cells=[]
    for engine in [D,KH,KL]:
        r=row('matrix',9999,scenario,engine)
        cells.append(f"{r['sectionMoves']} S + {r['itemMoves']:,} I；{r['totalMs']:.3f} ms")
    lines.append('| '+scenario+' | '+' | '.join(cells)+' |')
lines += ['',
    '纯 section 左旋只把 2 次 section move 减为 1 次，不能因为它承载近万 items 就认为少了近万次操作。section 内部左旋则确实减少大量 item move。跨节组合中，两种 ListKit 可能同时比 DifferenceKit 少报很多 item move：这说明按 surviving section 匹配、再协调跨节移动的组织方式也影响结果，收益并不全来自 LIS。', '']
lines += ['section 被删 / 插入时，容器本身可以隐含 item 的消失 / 出现。各库可能重建容器内 item；本轮检查最终内容，不把身份状态连续性视作已证明，也不主张 section + item 全局最少操作。', '',
    '## 7. 执行策略的含义', '',
    '- 以约 100 项为主要边界，自研 Swift Heckel 仍是合理方向：稳定唯一 ID、快的无变化路径、内容适配和 UIKit 执行器足以提供实际价值。无需因为压测左旋漂亮就扩大产品需求。',
    '- 同时，数据不能支持“LIS 只是好看，总耗时没有收益”的普遍说法。大幅减少多余 move 时它确实能获益；收益必须同时抵扣计算和适配成本。',
    '- ListKit 的参考价值还在执行器：纯内容快速路径、结构 batch 后再 reconfigure、跳过空 UIKit 调用、减少不必要 stage。不能把其 100 项结果全记到 LIS 名下。',
    '- 先明确精确更新与整体重载的产品语义，再决定是否需要 fallback；不从本实验直接导出 10%、100 或 1,000 的生产阈值。',
    '- 若目前确定不需要旋转 / 大规模重排，以 Heckel 为基线不会被这组压测否定。让 move 选择保持可局部替换即可；是否引入 LIS 留给真实 workload 和真机数据。', '',
    '## 8. 原始数据、统计与限制', '',
    f'- {formal_samples:,} 次正式样本都校验了 prepare + apply + layout = total，重新计算每行 median / p95，并核对三轮完整覆盖与操作数一致。',
    '- 每轮完整统计（`results/all-runs.csv`，本地生成） · 平面（`results/flat.csv`，本地生成） · 排列（`results/permutation.csv`，本地生成） · Churn（`results/churn.csv`，本地生成） · 多节（`results/matrix.csv`，本地生成）。',
    '- 原始 `flat/permutation/churn/matrix-1/2/3.json` 保存每次 sample；CSV 同时有三轮中位数、范围、p95、分项耗时和可观测 UIKit 操作数。',
    '- Apple 的内部私有调用不保证经过 instrumentation，CSV 不把其计数作为算法证据。其他后端的计数有少量调用开销，已对所有候选统一使用相同 collection 子类。',
    '- 无真机、无动画呈现帧、无峰值内存和持续提交测量。模拟器的 CPU / 内存 / 图形 / 帧时不可外推为 iPhone 真机绝对性能。',
    '- 外部 prepare 与内部 apply 的算法边界因后端而异；跨后端分析优先比较 total。三轮范围只描述这台宿主的波动，不是统计显著性或多设备复现。',
    '- 各轮原始测量保留；本目录归档实验源码、报告和图表，不修改 Parade 生产代码。原始 JSON、日志及本地生成的 CSV 不提交。', '']
(ROOT/'RESULTS.md').write_text('\n'.join(lines))
summary = {'complete': True, 'performanceRows': len(raw_rows), 'formalSamples': formal_samples,
           'warmupUpdates': warmups, 'randomUIKitChecks': len(random['records']),
           'matcherChecks': verify['verifiedMatcherCases'], 'sourceHashesVerified': True,
           'expectedRowsPerRepetition': EXPECTED,
           'analysisSHA256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
           'runnerSHA256': hashlib.sha256((ROOT/'run.py').read_bytes()).hexdigest(),
           'resultSHA256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for suite in EXPECTED for p in sorted(OUT.glob(f'{suite}-[123].json'))}}
(OUT/'validation.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
