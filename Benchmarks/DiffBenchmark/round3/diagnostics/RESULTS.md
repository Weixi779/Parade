# 追查：ListKit Heckel 的优势从哪里来

**需要修正第三轮跨后端排名的解读：它对初始视图和事务所处状态敏感。让初始事务提交、在计时外等待 30 ms 后，ListKit 在 100 项追加和右旋的明显领先消失；混合更新仍有优势。**

日期：2026-09-17。两个诊断均使用独立 app，不覆盖第三轮原始源码、二进制或结果。所有新数字是本诊断内三轮中位数的中位数，单位 ms；不与上一批绝对数拼接计算收益。

## 对照一：空 UIKit 调用是不是主因

仅给 benchmark 适配器的六类 delete / insert / reload 调用加非空判断。匹配算法、输出计划、stage、数据源切换时机、内容 reload 与 completion 等待均相同。原版 ListKit Heckel 作为同批对照。100 项全部 12 种平面输入，各候选每轮预热 5 次、正式 40 次，三轮共 7,200 次正式样本。

| 场景 | 自研旧适配器 | 自研跳过空调用 | DifferenceKit旧适配器 | DifferenceKit跳过空调用 | ListKit Heckel |
|---|---:|---:|---:|---:|---:|
| append-5pct | 0.539 | 0.515 | 0.550 | 0.526 | 0.287 |
| prepend-5pct | 0.742 | 0.719 | 0.723 | 0.746 | 0.491 |
| update-5pct | 0.666 | 0.637 | 0.620 | 0.665 | 0.267 |
| rotate-right-1 | 0.613 | 0.634 | 0.644 | 0.708 | 0.411 |
| mixed | 1.419 | 1.348 | 1.364 | 1.359 | 0.776 |
| shuffle | 1.164 | 1.204 | 1.174 | 1.136 | 0.901 |

**结果不支持“空调用是主要来源”。** 差距仍然存在，个别变化落在波动中；旧表里每次 batch 少约 0.2 ms 的现象不能主要归因于这些空调用。

## 对照二：初始状态与事务边界

在所有候选共同的 reset 中，初始 layout 之后增加 `CATransaction.flush()`，再 `Task.sleep(30 ms)`，最后清零计数并开始计时。30 ms 不算入 total。其作用是给初始事务提交和 run loop 推进的机会，不是通过图像或 display callback 证明某一帧已经呈现。

只测 100 项追加、右旋和混合三种输入；每轮预热 3 次、正式 20 次，三轮共 900 次正式样本。执行器和差异计划与对照一相同。

| 场景 | 自研旧适配器 | 自研跳过空调用 | DifferenceKit旧适配器 | DifferenceKit跳过空调用 | ListKit Heckel |
|---|---:|---:|---:|---:|---:|
| append-5pct | 0.594 | 0.560 | 0.587 | 0.579 | 0.645 |
| rotate-right-1 | 0.788 | 0.739 | 0.731 | 0.768 | 0.791 |
| mixed | 1.999 | 2.022 | 1.864 | 1.950 | 1.597 |

追加和右旋的跨后端排名改变了；混合更新里 ListKit 依然更快。不能把这个三场景探针推广成所有大小、所有场景的新版完整排名，但它足以否定旧表“100 项全面领先且可直接外推至已稳定展示的列表”的解读。

三轮中位数范围：

| 场景 / 后端 | 三轮范围 ms |
|---|---:|
| append-5pct / 自研旧适配器 | 0.476–0.724 |
| append-5pct / 自研跳过空调用 | 0.475–0.681 |
| append-5pct / DifferenceKit旧适配器 | 0.490–0.623 |
| append-5pct / DifferenceKit跳过空调用 | 0.471–0.683 |
| append-5pct / ListKit Heckel | 0.560–0.700 |
| rotate-right-1 / 自研旧适配器 | 0.637–0.803 |
| rotate-right-1 / 自研跳过空调用 | 0.631–0.851 |
| rotate-right-1 / DifferenceKit旧适配器 | 0.637–0.880 |
| rotate-right-1 / DifferenceKit跳过空调用 | 0.636–0.852 |
| rotate-right-1 / ListKit Heckel | 0.700–0.985 |
| mixed / 自研旧适配器 | 1.971–2.098 |
| mixed / 自研跳过空调用 | 1.951–2.107 |
| mixed / DifferenceKit旧适配器 | 1.846–2.131 |
| mixed / DifferenceKit跳过空调用 | 1.936–1.974 |
| mixed / ListKit Heckel | 1.553–1.993 |

## 源码确认 ListKit 做了什么

- 按 surviving section 比较 item ID 数组；顺序与 ID 不变时跳过该节 item diff。纯内容更新仍由外部适配器按 revision 比较并显式标记，不是把内容比较免费省掉。
- 空变化直接返回。纯内容直接 reload / reconfigure；本 benchmark 的 ListKit 使用 reconfigure，不创建结构 batch。
- 有结构变化时合成一个 batch；在 block 内同步推进 snapshot，completion 后按新坐标 reconfigure。旧自研 / DifferenceKit 适配器对 mixed 使用三个 stage，逐个等待 completion。
- Swift value snapshot 使用 section ID 数组、每节 item 数组、section 索引和按需构建的反向索引。其性能贡献未在此次诊断中单独分摊。
- apply 通过 MainActor Task 链串行化，1,000 项起内部 diff 使用 detached task。100 项探针没有触发后台 diff，但仍有 Task 链。这些路径与直接调用旧适配器的任务 / run loop 上下文不同。

观察到的是计时对初始事务条件的敏感性；目前没有 Instruments 栈证据把差额归因于某个具体 UIKit 私有函数、特定事务合并或某次 executor hop。Task 调度影响是待进一步拆分的解释，不应当作已经定位到的唯一根因。

还有一个基线定义：`DifferenceKit-staged` 测的是公开 Changeset 加 benchmark 自写的逐 stage 等待适配器。DifferenceKit 自带的 `UICollectionView.reload(using:)` 在循环中提交 batch，不在每段之间 await completion；不能把当前列称为库自带 UIKit helper 的默认性能。

## 对第三轮报告的影响

- 原始数字是真实测得的“新建 host → reset → 立即更新”结果，但不足以作为稳定列表的通用框架排名；尤其不能把 100 项的跨后端差距都解释为 ListKit 算法或存储结构的收益。
- 第三轮同一个 ListKit 内的 LIS / Heckel 对照仍控制了执行器，但只证明原始初始化条件下的差异；新事务条件下的全量复验尚未进行。
- ListKit 的纯内容分流、结构与内容的处理顺序、多节匹配方式仍是可核查的设计参考。对它们的成本，需要使用统一初始状态与完成边界继续比较。
- 本轮不自动将 30 ms 定成未来 benchmark 的最终等待策略。真机、实际 cell 和呈现帧仍未验证。

所有 8,100 次正式诊断样本均通过 UIKit 内容检查及统计复算；源文件和模块 hash 记录在各子目录 environment.json。原始 JSON 和日志保留。
