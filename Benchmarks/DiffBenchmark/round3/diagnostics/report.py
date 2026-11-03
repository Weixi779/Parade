#!/usr/bin/env python3
# Created by weixi on 2026/09/17.
import hashlib
import json
import math
import pathlib
import statistics as stats

ROOT=pathlib.Path(__file__).resolve().parent
engines=['Unique-Heckel-staged','Unique-Heckel-no-empty-calls','DifferenceKit-staged','DifferenceKit-no-empty-calls','ListKit-Heckel-exact']
labels=['自研旧适配器','自研跳过空调用','DifferenceKit旧适配器','DifferenceKit跳过空调用','ListKit Heckel']
collected={}
counts={}
for name,expected,runs in [('empty-ui-calls',60,40),('settled-initial-state',15,20)]:
    values=[]
    for rep in [1,2,3]:
        data=json.loads((ROOT/name/f'probe-{rep}.json').read_text())
        assert data['complete'] and len(data['records'])==expected
        for r in data['records']:
            assert r['n']==100 and len(r['samples'])==runs
            for m in ['prepareMs','applyMs','layoutMs','totalMs']:
                xs=sorted(s[m] for s in r['samples'])
                assert abs(stats.median(xs)-r[f'median-{m}'])<1e-9
                assert abs(xs[math.ceil(runs*.95)-1]-r[f'p95-{m}'])<1e-9
            for sample in r['samples']:
                assert abs(sample['prepareMs']+sample['applyMs']+sample['layoutMs']-sample['totalMs'])<1e-8
            values.append(r)
    counts[name]=sum(len(r['samples']) for r in values)
    collected[name]=values

def rows(probe,scenario,engine):
    rs=[r for r in collected[probe] if r['scenario']==scenario and r['engine']==engine]
    assert len(rs)==3
    return rs
def ms(probe,scenario,engine):
    return stats.median(r['median-totalMs'] for r in rows(probe,scenario,engine))
def table(probe,scenarios):
    out=['| 场景 | '+' | '.join(labels)+' |','|---|'+'---:|'*5]
    for scenario in scenarios:
        out.append('| '+scenario+' | '+' | '.join(f'{ms(probe,scenario,e):.3f}' for e in engines)+' |')
    return out

lines=['# 追查：ListKit Heckel 的优势从哪里来', '',
    '**需要修正第三轮跨后端排名的解读：它对初始视图和事务所处状态敏感。让初始事务提交、在计时外等待 30 ms 后，ListKit 在 100 项追加和右旋的明显领先消失；混合更新仍有优势。**', '',
    '日期：2026-09-17。两个诊断均使用独立 app，不覆盖第三轮原始源码、二进制或结果。所有新数字是本诊断内三轮中位数的中位数，单位 ms；不与上一批绝对数拼接计算收益。', '',
    '## 对照一：空 UIKit 调用是不是主因', '',
    '仅给 benchmark 适配器的六类 delete / insert / reload 调用加非空判断。匹配算法、输出计划、stage、数据源切换时机、内容 reload 与 completion 等待均相同。原版 ListKit Heckel 作为同批对照。100 项全部 12 种平面输入，各候选每轮预热 5 次、正式 40 次，三轮共 7,200 次正式样本。', '']
lines+=table('empty-ui-calls',['append-5pct','prepend-5pct','update-5pct','rotate-right-1','mixed','shuffle'])
lines+=['', '**结果不支持“空调用是主要来源”。** 差距仍然存在，个别变化落在波动中；旧表里每次 batch 少约 0.2 ms 的现象不能主要归因于这些空调用。', '',
    '## 对照二：初始状态与事务边界', '',
    '在所有候选共同的 reset 中，初始 layout 之后增加 `CATransaction.flush()`，再 `Task.sleep(30 ms)`，最后清零计数并开始计时。30 ms 不算入 total。其作用是给初始事务提交和 run loop 推进的机会，不是通过图像或 display callback 证明某一帧已经呈现。', '',
    '只测 100 项追加、右旋和混合三种输入；每轮预热 3 次、正式 20 次，三轮共 900 次正式样本。执行器和差异计划与对照一相同。', '']
lines+=table('settled-initial-state',['append-5pct','rotate-right-1','mixed'])
lines+=['',
    '追加和右旋的跨后端排名改变了；混合更新里 ListKit 依然更快。不能把这个三场景探针推广成所有大小、所有场景的新版完整排名，但它足以否定旧表“100 项全面领先且可直接外推至已稳定展示的列表”的解读。', '',
    '三轮中位数范围：', '',
    '| 场景 / 后端 | 三轮范围 ms |', '|---|---:|']
for s in ['append-5pct','rotate-right-1','mixed']:
    for e,label in zip(engines,labels):
        xs=[r['median-totalMs'] for r in rows('settled-initial-state',s,e)]
        lines.append(f'| {s} / {label} | {min(xs):.3f}–{max(xs):.3f} |')
lines+=['', '## 源码确认 ListKit 做了什么', '',
    '- 按 surviving section 比较 item ID 数组；顺序与 ID 不变时跳过该节 item diff。纯内容更新仍由外部适配器按 revision 比较并显式标记，不是把内容比较免费省掉。',
    '- 空变化直接返回。纯内容直接 reload / reconfigure；本 benchmark 的 ListKit 使用 reconfigure，不创建结构 batch。',
    '- 有结构变化时合成一个 batch；在 block 内同步推进 snapshot，completion 后按新坐标 reconfigure。旧自研 / DifferenceKit 适配器对 mixed 使用三个 stage，逐个等待 completion。',
    '- Swift value snapshot 使用 section ID 数组、每节 item 数组、section 索引和按需构建的反向索引。其性能贡献未在此次诊断中单独分摊。',
    '- apply 通过 MainActor Task 链串行化，1,000 项起内部 diff 使用 detached task。100 项探针没有触发后台 diff，但仍有 Task 链。这些路径与直接调用旧适配器的任务 / run loop 上下文不同。', '',
    '观察到的是计时对初始事务条件的敏感性；目前没有 Instruments 栈证据把差额归因于某个具体 UIKit 私有函数、特定事务合并或某次 executor hop。Task 调度影响是待进一步拆分的解释，不应当作已经定位到的唯一根因。', '',
    '还有一个基线定义：`DifferenceKit-staged` 测的是公开 Changeset 加 benchmark 自写的逐 stage 等待适配器。DifferenceKit 自带的 `UICollectionView.reload(using:)` 在循环中提交 batch，不在每段之间 await completion；不能把当前列称为库自带 UIKit helper 的默认性能。', '',
    '## 对第三轮报告的影响', '',
    '- 原始数字是真实测得的“新建 host → reset → 立即更新”结果，但不足以作为稳定列表的通用框架排名；尤其不能把 100 项的跨后端差距都解释为 ListKit 算法或存储结构的收益。',
    '- 第三轮同一个 ListKit 内的 LIS / Heckel 对照仍控制了执行器，但只证明原始初始化条件下的差异；新事务条件下的全量复验尚未进行。',
    '- ListKit 的纯内容分流、结构与内容的处理顺序、多节匹配方式仍是可核查的设计参考。对它们的成本，需要使用统一初始状态与完成边界继续比较。',
    '- 本轮不自动将 30 ms 定成未来 benchmark 的最终等待策略。真机、实际 cell 和呈现帧仍未验证。', '',
    '所有 8,100 次正式诊断样本均通过 UIKit 内容检查及统计复算；源文件和模块 hash 记录在各子目录 environment.json。原始 JSON 和日志保留。', '']
(ROOT/'RESULTS.md').write_text('\n'.join(lines))
(ROOT/'validation.json').write_text(json.dumps({'complete':True,'formalSamples':counts,
    'analysisSHA256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()},indent=2)+'\n')
print('Wrote diagnostic RESULTS.md; verified 8,100 formal samples.')
