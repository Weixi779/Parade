# 从差异计算到 UIKit 更新

这组实验始于 2026-09-17。问题从「哪种 Diff 算法适合列表」逐步变成「怎样完成一次正确、成本可控的 UIKit 更新」。这里按调查顺序整理证据；各轮报告保留当时的测量值，后续修正单独标明。

实验中的自研 Heckel、LIS 和 section planner 都是研究原型，不是当前 Parade 发布版本的性能数据。支持一种更新方式、默认选择一种实现，以及它在某个场景中最快，是三个不同的判断。

## 从哪里读

| 轮次 | 要回答的问题 | 结果与复现 |
|---|---|---|
| 第一轮 | 计算多久、生成多少操作、完整 UIKit 更新多久？ | [结果](RESULTS.md) · [方法与源码入口](README.md) |
| 第二轮 | 加入 Section、跨组移动和内容更新以后，怎样分阶段？reload 与 reconfigure 有什么差别？ | [结果](round2/RESULTS.md) · [方法](round2/README.md) |
| 第三轮 | 同一执行器只换移动策略会怎样？不同完整更新实现又有何差别？ | [结果](round3/RESULTS.md) · [方法](round3/README.md) |
| 后续诊断 | 第三轮的差距来自空 UIKit 调用，还是初始事务条件？ | [修正与数据](round3/diagnostics/RESULTS.md) · [复现](round3/diagnostics/README.md) |

若要引用第三轮的排名，必须同时阅读后续诊断。不要把不同轮次的绝对耗时拼起来计算优化收益。

## 先算出来，再执行出来

第一轮在相同的一维输入下比较 DifferenceKit、唯一 ID 的 Heckel 式贪心、LIS 和 Swift 标准库 `CollectionDifference`。后者是序列差异计算接口，不是 Apple 的 `UICollectionViewDiffableDataSource`。

10,000 项左旋一位，贪心计算约 0.794 ms，LIS 约 1.018 ms；交给相同的实验执行器以后，完整更新分别约 15.691 ms、2.618 ms。两者分别交出了 9,999 次和 1 次移动。随机打乱时，完整更新又接近：约 21.362 ms 与 21.415 ms。

这说明计算开销与输出操作的执行成本要一起看。它不说明 LIS 永远更快，也不说明 10,000 项旋转应该主导百项左右的产品选择。[第一轮表格](RESULTS.md)

Apple 没有公开可单独返回 changeset 的内部 Diff 接口，因此只参加完整更新对比。Snapshot 构造时间不能冒充系统算法时间。

## 内容更新不是一种固定操作

第二轮把 Section 与 Item 联合变化纳入实验，也比较了更新顺序和 UIKit 原语：

| 路径 | 先做什么 | 后做什么 |
|---|---|---|
| before-reload | 在旧位置 reload 内容 | 执行结构变化 |
| after-reload | 执行结构变化 | 在新位置 reload 内容 |
| after-reconfigure | 执行结构变化 | 在新位置 reconfigure 内容 |

3,000 项的 move-and-update 样本中，三者分别约 3.977、3.625、2.716 ms；但在其他组合里没有统一赢家。更新发生时 Cell 是否可见、是否刚进入视口，会改变实际配置工作。reconfigure 的语义是重配现有 Cell，不能仅凭名称推断每个场景都更快。[第二轮表格](round2/RESULTS.md)

Section 的变化也会影响执行方式。保留一条从待删除 Section 转移出去的 Item，需要协调中间数据与操作；若所有 Section 都被替换，逐项保留移动与删除后重建容器又有不同成本。只比较显式 move 数，不能完整评价这些方案。

## 第三轮比较的是哪些东西

第三轮有两组控制变量比较：自研平面 Heckel / LIS 共用执行器；ListKit 的两个版本共用 snapshot、匹配、任务调度和执行器，只改变移动选择。这里的 ListKit 来自 Iron-Ham/Lists，不是 IGListKit。

跨框架的整列比较则会同时涉及数据准备、调度、分阶段执行和内容更新方式：

- Apple 分别测 `reloadItems`、`reconfigureItems`，不把它们混成一列。
- 实验自研平面原型和 DifferenceKit 适配器仍使用内容 reload；不等于当前 Parade 只用 reload。
- ListKit 精确更新路径在结构变化后 reconfigure，纯内容变化有单独路径。
- DifferenceKit 这一列使用实验自写的逐阶段等待 completion 适配器，不是其官方便利方法的默认性能。
- 固定版本 ListKit 的无动画默认路径会整体 reloadData，Apple 的普通无动画 apply 仍执行差量更新。因此精确更新与整体重载分开测。

第三轮共 147,510 次正式计时更新。次数增加有助于观察波动，但不会自动消除实验条件的问题。[第三轮方法](round3/README.md)

## 后来修正了什么

最初 ListKit 在百项规模的多个场景看起来明显领先。补测分成两步：先只跳过空 UIKit 调用，再让所有候选在初始布局后提交事务、于计时外等待 30 ms。

第一步没有支持「空调用是主要差额来源」。第二步中，100 项追加与右旋的明显领先消失；混合更新仍有优势。因此旧表只能描述「新建列表后立即更新」的条件，不能直接外推为稳定显示中的列表排名。

这次诊断覆盖 8,100 次正式样本；事务条件的对照只有三个场景。没有 Instruments 栈证据把差额归给某个具体 UIKit 私有函数，也没有在新的初始化条件下重跑整张矩阵。30 ms 是诊断条件，不是框架应加入的等待。[诊断结果](round3/diagnostics/RESULTS.md)

## 与 Parade 当前实现的关系

整理时的发布基线为 [1.1.1 对应源码](https://github.com/Weixi779/Parade/tree/8e8202fc274643dd96d483df9dd99444c625a35d)：

- 默认入口使用自研分阶段 DataSource，算法采用稳定唯一 ID 的 Heckel 式贪心，不保证最少移动。百项左右的实际规模和没有极端旋转需求，是这一取舍的背景。
- 结构更新完成后，普通内容变化在视图兼容时 reconfigure，需要替换视图时 reload；Header/Footer 的兼容性和内容另外处理。不能把早期原型的 reload 表直接当成这一实现的成绩。
- 同时提供系统 Diffable Data Source 适配。更换完整更新实现与只更换 Diff 算法是两个入口。
- 本组实验没有证明当前 Parade 普遍快于系统实现，也没有从测量中确定生产用 reloadData 降级阈值。

源码：[默认入口](../../Sources/Parade/DataSource/Staged/CollectionOrchestrator+Staged.swift)、[执行](../../Sources/Parade/DataSource/Staged/StagedCollectionDataSource.swift)、[内容判断](../../Sources/Parade/DataSource/CollectionContentUpdates.swift)、[系统适配](../../Sources/Parade/DataSource/Diffable/DiffableCollectionDataSource.swift)。

[固定版本的内容更新判断](https://github.com/Weixi779/Parade/blob/8e8202fc274643dd96d483df9dd99444c625a35d/Sources/Parade/DataSource/CollectionContentUpdates.swift)。

## 引用和复现范围

- 报告记录 2026-09-17 的历史实验；本次归档不表示重新运行了 UIKit 性能测试。
- 全部是同一宿主上的模拟器实验，使用简单固定尺寸 Cell；没有测真机帧时、动画中间状态、峰值内存或连续提交。
- 第一轮每组 30 次 CPU、15 次 UIKit 样本；第二轮每组 12 次 UIKit 样本；第三轮独立运行三轮。统计口径见各轮说明。
- 源码、脚本、报告和汇总图提交；原始 JSON、CSV、日志、依赖 checkout 和二进制留在本地。报告中的这些文件名表示复现输出，不是仓库中遗漏的附件。
- 归档保持 Swift 实验源码不变。Python 脚本调整依赖路径和报告资源路径，图表改成相对链接；原始测量值不因整理而改变。
