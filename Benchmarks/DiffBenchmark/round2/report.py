#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
import csv, hashlib, json, os, pathlib, statistics

ROOT=pathlib.Path(__file__).resolve().parent
ASSETS = ROOT / 'assets'
ASSETS.mkdir(exist_ok=True)
OUT=ROOT/'results'
verification=json.loads((OUT/'verification.json').read_text())
suites={name:json.loads((OUT/f'round2-{name}.json').read_text()) for name in ['random','matrix','permutation','churn']}
assert all(value['complete'] for value in suites.values())
for name,suite in suites.items():
    rows=[]
    for r in suite['records']:
        row={k:v for k,v in r.items() if k not in ['samples','counts']}
        if r['countsObservable']: row.update(r['counts'])
        rows.append(row)
    columns=sorted({k for row in rows for k in row})
    with (OUT/f'{name}.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=columns); writer.writeheader(); writer.writerows(rows)

def find(suite,name,engine,n):
    return next(r for r in suites[suite]['records'] if r['scenario']==name and r['engine']==engine and r['n']==n)

def ms(suite,name,engine,n,key='median-totalMs'):
    return f'{find(suite,name,engine,n)[key]:.3f}'

CHURN=['Apple-diff-reconfigure','DifferenceKit-staged','LIS-after-reconfigure','UIKit-reloadData','Apple-reloadData','LIS-then-reloadData']
PCTS=[0,.1,.25,.5,.75,.9,1.]
def churn_rows(n,pct,engine):
    return [r for r in suites['churn']['records'] if r['n']==n and r['requestedFraction']==pct and r['engine']==engine]
def churn(n,pct,engine):
    return statistics.median(r['median-totalMs'] for r in churn_rows(n,pct,engine))

os.environ.setdefault('MPLCONFIGDIR',str(ROOT/'build'/'matplotlib'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
colors=['#61688b','#df8556','#078c86','#1c74ce','#b397b9','#c5346a']
labels=['Apple diff','DifferenceKit','Hierarchical LIS','UIKit reload','Apple reload','LIS then reload']
fig,axes=plt.subplots(1,3,figsize=(15,5),sharex=True)
for ax,n in zip(axes,[100,1000,10000]):
    for engine,color,label in zip(CHURN,colors,labels):
        centers=[churn(n,p,engine) for p in PCTS]
        lows=[min(r['median-totalMs'] for r in churn_rows(n,p,engine)) for p in PCTS]
        highs=[max(r['median-totalMs'] for r in churn_rows(n,p,engine)) for p in PCTS]
        xs=[p*100 for p in PCTS]
        ax.plot(xs,centers,marker='o',ms=3,lw=1.6,color=color,label=label)
        ax.fill_between(xs,lows,highs,color=color,alpha=.09)
    ax.set_yscale('log'); ax.set_title(f'{n:,} items')
    ax.set_xlabel('Items selected for shuffle (%)')
    ax.grid(True,alpha=.2); ax.spines[['top','right']].set_visible(False)
axes[0].set_ylabel('Total CPU-side update time (ms, log scale)')
handles,legend=axes[0].get_legend_handles_labels()
fig.legend(handles,legend,ncol=3,loc='lower center',frameon=False,bbox_to_anchor=(.5,-.025))
fig.suptitle('Diff vs reload — iOS 27 Simulator, fixed-size cells, animations off',fontsize=14)
fig.text(.5,.865,'Median of three workload-seed medians; shaded range is seed variation, not a confidence interval.',ha='center',fontsize=9,color='#555555')
fig.subplots_adjust(top=.8,bottom=.2,wspace=.23)
fig.savefig(ASSETS/'churn.png',dpi=180,bbox_inches='tight')
fig.savefig(OUT/'churn.svg',bbox_inches='tight')
plt.close(fig)

lines=['# Parade UI diff 第二轮结果','',
    '**四项实验都已完成。LIS 的最少移动性质保留到了 section 内部，但没有自动变成最快的完整后端；高变更量时，reload 的收益远大于继续压低 move 数。**',
    '', '详细输入、planner 阶段、复现命令及验证限制见 [实验说明](README.md)。第一轮源码和结果保持原样。',
    '', '## Section 与 item 联合变化', '',
    '下面是 3 节 × 每节 1,000 项。S 表示显式 section move，I 表示显式 item move。下表来自计划的独立重放，不是从耗时反推操作数。', '',
    '| 场景 | DifferenceKit | 分层 LIS |', '|---|---:|---:|']
for scenario in ['section-rotate-left','section-rotate-right','section-move-and-local-reorder','section-move-cross-section-move-update']:
    rows={r['engine']:r for r in verification['matrix'] if r['n']==3000 and r['scenario']==scenario}
    values=[]
    for engine in ['DifferenceKit','LIS-after']:
        c=rows[engine]['counts']; values.append(f"{c['sectionMoves']} S + {c['itemMoves']} I + {c['updates']} update")
    lines.append('| '+scenario+' | '+' | '.join(values)+' |')
lines += ['',
    '整个 section 移动不会制造 item move；这一点 DifferenceKit 同样满足。区别出现在 section 或 section 内 item 的重排选择。',
    '', '**容器替换暴露了另一种取舍。** 从待删除 section 逃出的幸存 item，自研 planner 先转移再删容器；移入新 section 时先建容器再转移。两种 staging 在 UIKit 中通过了检查。',
    '但是替换全部 section、仍保留 3,000 个 item ID 时，自研 planner 为维持显式移动产生 3,000 次跨 section move；DifferenceKit 通过旧容器删除与新容器插入完成重建，不产生显式 item move。',
    f"该样本的完整更新中位数：DifferenceKit **{ms('matrix','replace-all-sections-preserve-items','DifferenceKit-staged',3000)} ms**，LIS-after-reconfigure **{ms('matrix','replace-all-sections-preserve-items','LIS-after-reconfigure',3000)} ms**。操作语义不同，不能只数显式操作就宣布谁更优；交互状态连续性仍未全面验证。",
    '', '## Move + update：三种 staging 均通过本轮用例，尚无统一性能赢家', '',
    '单位 ms，完整更新中位数，3,000 项。before/after 对照执行顺序，after-reload/after-reconfigure 对照更新原语。', '',
    '| 场景 | 更新后移动 / reload | 移动后 reload | 移动后 reconfigure | DifferenceKit | Apple |',
    '|---|---:|---:|---:|---:|---:|']
for scenario in ['move-and-update','cross-section-move-update','section-move-and-item-update','enter-inserted-section-update','deleted-to-inserted-section-update']:
    lines.append('| '+scenario+' | '+' | '.join(ms('matrix',scenario,e,3000) for e in ['LIS-before-reload','LIS-after-reload','LIS-after-reconfigure','DifferenceKit-staged','Apple-diff-reconfigure'])+' |')
lines += ['',
    '例如 move-and-update 中，LIS-before 只配置 1 个 cell，两个 LIS-after 变体配置 2 个：旧位置离屏、移动后进入视口，会改变“在哪一阶段更新”所触发的工作。reconfigure 保留现有 cell 的能力值得用，但不能从名称推导每种场景都更快。',
    '小差距不做稳定排名。这里关闭动画，只验证最终内容；不同阶段间旧内容是否可见、是否闪烁、第一响应者等仍没有验证。',
    '', '## 系统化 permutation 与数学下界', '',
    '10,000 项；下界为 `n − LIS`，由独立 Fenwick-tree 实现计算，小样本再与动态规划 LCS 交叉验证。', '',
    '| 排列 | 最少 move | DifferenceKit / 自研 Heckel | Key + LIS |', '|---|---:|---:|---:|']
names=[]
for r in verification['permutations']:
    if r['n']==10000 and r['scenario'] not in names: names.append(r['scenario'])
for name in names:
    rows={r['engine']:r for r in verification['permutations'] if r['n']==10000 and r['scenario']==name}
    lines.append(f"| {name} | {rows['Key-LIS']['lowerBound']} | {rows['DifferenceKit-core']['moves']} / {rows['Unique-Heckel']['moves']} | {rows['Key-LIS']['moves']} |")
lines += ['',
    '**最少 move 没有直接保证最短总耗时。** 本轮通用 section planner 重建了多份身份映射和阶段数据，尚未优化：', '',
    '| 10,000 项 | DifferenceKit 总耗时 | LIS 总耗时 | LIS prepare | Apple 总耗时 |', '|---|---:|---:|---:|---:|']
for name in ['rotate-1','rotate-10','block-swap','reverse']:
    lines.append('| '+name+' | '+' | '.join([ms('permutation',name,'DifferenceKit-staged',10000),
        ms('permutation',name,'LIS-after-reconfigure',10000),ms('permutation',name,'LIS-after-reconfigure',10000,'median-prepareMs'),
        ms('permutation',name,'Apple-diff-reconfigure',10000)])+' |')
lines += ['',
    'block-swap 的 LIS move 从 7,500 降到 5,000，但额外准备成本抵消了应用收益。第一轮平面 LIS 的数字不能拿来替代这一版 section planner 的成本；“CPU 暂时不卷”可以是本轮工作优先级，不能变成永远忽略 prepare 的结论。',
    '', '## Diff 与 reload：交叉点已经落在最初的采样区间', '',
    f'![Diff and reload curves](assets/churn.png)', '',
    '纵轴为对数坐标，单位 ms。每条线是三个 workload seed 各自中位数再取中位数；阴影是 seed 之间的范围，不是置信区间。横轴是选中参与 shuffle 的比例，不是实际 move 比例。',
    '', '10,000 项的汇总：', '',
    '| 选中重排比例 | 实际最少 move 比例范围 | Apple diff | DifferenceKit | LIS 精确更新 | 直接 reloadData | Apple 显式 reload | 先算 LIS 再 reload |',
    '|---|---:|---:|---:|---:|---:|---:|---:|']
for p in PCTS:
    rs=churn_rows(10000,p,'LIS-after-reconfigure')
    bounds=[r['minimumMoveFraction']*100 for r in rs]
    lines.append(f'| {p*100:g}% | {min(bounds):.2f}–{max(bounds):.2f}% | '+' | '.join(f'{churn(10000,p,e):.3f}' for e in CHURN)+' |')
lines += ['',
    '**扣除“免费知道是否该 reload”的假设后，收益仍存在。** `LIS-then-reloadData` 先完整生成计划，再把计划丢弃后 reload；其 prepare 成本包含在表内。',
    '', '| 项数 | 0% 时：LIS / 先算再 reload | 10% 时：LIS / 先算再 reload | 首次观察到的交叉区间 |', '|---|---:|---:|---|']
for n in [100,1000,10000]:
    lines.append(f"| {n:,} | {churn(n,0,'LIS-after-reconfigure'):.3f} / {churn(n,0,'LIS-then-reloadData'):.3f} | {churn(n,.1,'LIS-after-reconfigure'):.3f} / {churn(n,.1,'LIS-then-reloadData'):.3f} | 0% 与 10% 选中重排之间 |")
lines += ['',
    '这是离散采样的区间，不是测出了精确阈值，更不是建议在生产里设 10%。简单固定尺寸 cell、关闭动画、有限可见窗口，都有利于 reload；它不保持哪些交互状态、真实尺寸重测代价多大，本轮尚未回答。100 / 1,000 / 10,000 项完整数据都在 CSV/JSON 中。',
    '当前数据已经足以说明：应将精确更新与重载看成需要产品语义约束的两种执行策略。是否允许重载、是否保留 anchor/selection/first responder，应先成为明确合同，再用真机与真实 cell 成本定阈值。',
    '', '## 验证范围与产物', '',
    '- 34,992 份 section 计划的独立逐阶段重放；98 个微型状态的全部 9,604 个转换，另有 2,000 个随机转换。',
    '- 132 组 permutation 操作数量比较，LIS 在这些样本中达到独立 oracle 下界。',
    '- 300 组 UIKit 组合矩阵、72 组 UIKit permutation、378 组 diff/reload 对照；每组 3 次预热与 12 次正式样本，共 9,000 次计时更新。',
    '- 额外 200 个随机 fixture × 5 个 backend，共 1,000 次 UIKit 功能验证。所有结果文件 complete=true；未观察到 invalid update 或内容核对失败。',
    '- 模拟器 iPhone 18 Pro / iOS 27.0，宿主 Apple M4 Max；这不是 CPU/图形/内存/帧时的真机性能结论，也未证明动画连续性。',
    '', '[实验代码与方法](README.md) · 组合矩阵 CSV（`results/matrix.csv`，本地生成） · Permutation CSV（`results/permutation.csv`，本地生成） · Churn CSV（`results/churn.csv`，本地生成） · 独立验证结果（`results/verification.json`，本地生成） · 曲线 SVG（`results/churn.svg`，本地生成）',
    '', '原始 JSON、每个样本的 prepare/apply/layout/total、各阶段操作数量和执行日志均保存在 results/。']
(ROOT/'RESULTS.md').write_text('\n'.join(lines)+'\n')
validation = {'complete': True, 'analysisSHA256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
    'inputSHA256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [OUT/'verification.json'] + [OUT/f'round2-{name}.json' for name in suites]}}
(OUT/'report-validation.json').write_text(json.dumps(validation,indent=2)+'\n')
print('Wrote round2 RESULTS.md, four CSVs, charts and report-validation.json.')
