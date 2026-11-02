#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
"""Render measured results without inventing missing timings."""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parent
RESULTS = ROOT / 'results'
cpu = json.loads((RESULTS/'cpu.json').read_text())
ui = json.loads((RESULTS/'ui.json').read_text()) if (RESULTS/'ui.json').exists() else None

def export(name, rows):
    columns = sorted({key for row in rows for key in row if key not in ('samples','samplesMs')})
    with (RESULTS/name).open('w',newline='') as f:
        writer = csv.DictWriter(f,fieldnames=columns,extrasaction='ignore')
        writer.writeheader(); writer.writerows(rows)

export('cpu.csv',cpu['records'])
if ui: export('ui.csv',ui['records'])

def value(row, key):
    return f"{row[key]:.3f}" if row and key in row else '未测'

engines = ['DifferenceKit-core','Unique-Heckel','Key-LIS','Swift-difference']
scenarios = ['no-op','append-5pct','prepend-5pct','delete-5pct','rotate-left-1','rotate-right-1',
             'update-5pct','adjacent-swap','shuffle','reverse','replace-all','mixed']
lines = ['# Parade UI diff 实测结果','',
         '这是 2026-09-17 的本机实验快照；实验合同、正确性检查、实现边界和复现方式见 [README](README.md)。',
         '', '## 当前判断', '',
         '建议优先继续验证 **Key + LIS**，保留唯一 ID 的 Heckel 实现作为计算成本对照。理由是输出操作质量，尚不是生产选型结论。',
         '', '1. **Heckel 的线性计算不保证更少 UI 工作。** 10,000 项左旋一位，DifferenceKit 与当前 Unique-Heckel 生成 9,999 个 move，LIS 与标准库只生成 1 个。反向旋转时四者都是 1 个 move；这暴露了移动选择策略的方向性。',
         '2. **LIS 的优势依赖场景。** 随机打乱时，多数项原本就必须移动，LIS 节省的操作有限。无变化、增删导致整体平移时，所有候选都避免了多余 move；不能把 index 改变直接算作移动。',
         '3. **Apple 要比较完整 backend。** 原生 snapshot 准备、内容存储更新及 apply 是可见的完整路径。自研 backend 也包含计划与 UIKit 应用；快慢不能全部归到其不可见的内部算法。',
         '4. **Section 是下一步决定性验证。** 本轮只有 Apple / DifferenceKit 跑 section 插入、重排和跨 section 场景。LIS 的数组正确性与本轮单 section UIKit 通过，都不足以证明多 section planner 正确。',
         '', '本轮不据小幅差距判断胜负；特别是无内容变化时两个 Apple 变体的差异，尚未对运行波动与空标记 API 路径做归因。',
         '',f"CPU：{cpu['os']}；{cpu['date']}；Release 优化、每组 5 次预热 / 30 次样本。",
         '',f"正确性：{cpu['verifiedEngineCases']:,} 个算法用例，通过独立操作重放、stages 重放和小规模 LCS oracle。",
         '', 'Apple 内部 diff 无公开独立计时入口，所以不出现在 CPU 表中。DifferenceKit-core 不等于其公共 staged API。',
         '', '## CPU diff：10,000 个带 section 前缀的 String ID', '',
         '单位 ms，中位数；全部包含内容检查。未测表示预算策略跳过，不代表超时。','',
         '| 场景 | DifferenceKit core | 自研 Unique-Heckel | Key + LIS | Swift 标准库 |',
         '|---|---:|---:|---:|---:|']
for scenario in scenarios:
    rows = {r['engine']:r for r in cpu['records'] if r['scenario']==scenario and r['n']==10000 and r['id']=='section-prefixed-String'}
    lines.append('| '+scenario+' | '+' | '.join(value(rows.get(e),'medianMs') for e in engines)+' |')
lines += ['', '## 相同目标下生成的 move 数', '',
          '| 10,000 项场景 | DifferenceKit core | 自研 Unique-Heckel | Key + LIS | Swift 标准库 |',
          '|---|---:|---:|---:|---:|']
for scenario in ['prepend-5pct','rotate-left-1','rotate-right-1','adjacent-swap','shuffle','reverse']:
    rows = {r['engine']:r for r in cpu['records'] if r['scenario']==scenario and r['n']==10000 and r['id']=='section-prefixed-String'}
    lines.append('| '+scenario+' | '+' | '.join(str(rows.get(e,{}).get('moves','未测')) for e in engines)+' |')

if ui:
    lines += ['', '## UIKit：模拟器上的完整 backend 更新', '',
              f"iOS {ui['os']}，{ui['device']}，{ui['date']}；关闭动画，每项 3 次预热 / 15 次样本。",
              '', '单位 ms，中位数；包含 prepare + apply completion + layout。布局和 cell 相同，collection 实际挂在 window 上。',
              '模拟器使用宿主机资源，这张表不能代表真机耗时、掉帧或电量；completion 后 layout 也不是像素呈现时刻。',
              '', '| 项数 / 场景 | Apple reload | Apple reconfigure | DifferenceKit staged | Unique-Heckel staged | Key-LIS staged |',
              '|---|---:|---:|---:|---:|---:|']
    ue = ['Apple-reload','Apple-reconfigure','DifferenceKit-staged','Unique-Heckel-staged','Key-LIS-staged']
    for n in [100,1000,10000]:
        for scenario in ['no-op','prepend-5pct','rotate-left-1','rotate-right-1','update-5pct','mixed','shuffle']:
            rows = {r['engine']:r for r in ui['records'] if r['n']==n and r['scenario']==scenario}
            lines.append(f'| {n:,} / {scenario} | '+' | '.join(value(rows.get(e),'median-totalMs') for e in ue)+' |')
    lines += ['', '## UIKit section 样本', '',
              '旧数据 10 sections × 100 items；自研候选尚无 sectioned planner，所以本表只比较已实现的两种后端。','',
              '| 场景 | Apple reload | Apple reconfigure | DifferenceKit staged |', '|---|---:|---:|---:|']
    for scenario in ['section-reorder','section-insert','cross-section-stable-ID','cross-section-new-prefixed-ID']:
        rows = {r['engine']:r for r in ui['records'] if r['scenario']==scenario}
        lines.append('| '+scenario+' | '+' | '.join(value(rows.get(e),'median-totalMs') for e in ue[:3])+' |')
    lines += ['', f"共 {len(ui['records'])} 个 UIKit 比较组合，每个样本完成 section/item 数量及可见 cell 的 ID/revision 检查；Apple 另核对完整 snapshot。",
              '', 'Apple 的内部操作数和 stage 数不可见；原始数据 operations = -1、stages = 0 表示不可观测，不能解释为没有操作或优于其他候选。',
              '', '## 10,000 项左旋一位：分段耗时', '',
              '| Backend | prepare 中位数 | apply 中位数 | layout 中位数 | total 中位数 | total p95 |',
              '|---|---:|---:|---:|---:|---:|']
    for e in ue:
        r=next(x for x in ui['records'] if x['n']==10000 and x['scenario']=='rotate-left-1' and x['engine']==e)
        lines.append('| '+e+' | '+' | '.join(value(r,k) for k in ['median-prepareMs','median-applyMs','median-layoutMs','median-totalMs','p95-totalMs'])+' |')
    lines += ['', '分段各自取中位数，三段中位数之和不一定等于 total 的中位数。']
else:
    lines += ['', 'UIKit 尚无完成的结果文件；不能报告运行成功或性能结论。']
lines += ['', '## 结果文件', '',
          '原始 JSON / CSV 由 `build/cpu`、UIKit app 和 `report.py` 写入 `results/`，不随仓库提交；这里只保留汇总表。',
          'UIKit 原始样本同样在 `results/ui.json`。' if ui else 'UIKit：尚未生成结果文件。',
          '', 'p95 仅是本轮样本的描述性统计，尤其 UIKit 只有 15 次样本，不作为稳定尾延迟保证。',
          '本轮没有测 allocation / 峰值内存、真实复杂内容 equality、动画 frame/hitch、连续提交和交互状态保留；不要从这些结果推导相关结论。']
(ROOT/'RESULTS.md').write_text('\n'.join(lines)+'\n')
print(f"Wrote RESULTS.md ({len(cpu['records'])} CPU records, {len(ui['records']) if ui else 0} UIKit records)")
