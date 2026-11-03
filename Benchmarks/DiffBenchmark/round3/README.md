# 第三轮：ListKit 与完整 UIKit 更新

日期：2026-09-17。目标是检验：在 100 / 1,000 / 10,000 项上，减少 move 是否降低实际更新总耗时；同时重新比较 Apple DiffableDataSource、DifferenceKit、自研平面 Heckel / LIS 与 ListKit。源码、报告和图表归档在本目录，原始数据与构建输出不提交，没有引入 Parade 生产 API。

**后续计时诊断：** 本轮新建列表、初始 layout 后立即计时，未等待初始事务稳定。后续统一提交初始事务并等待 30 ms（计时外）的三个 100 项探针中，追加 / 右旋的 ListKit 明显优势消失。原始表应按该初始化条件解释，不能直接当成稳定列表的框架排名；详细证据见 [追查结果](diagnostics/RESULTS.md)。原始代码与 JSON 保留。

## 实现来源与对照

ListKit 使用 [Iron-Ham/Lists](https://github.com/Iron-Ham/Lists/tree/221e1513f2786a4e5e836c9b76092c3bd6e61575) 的固定提交 `221e1513f2786a4e5e836c9b76092c3bd6e61575`，DifferenceKit 使用 `02ca1968b10305d4d6771f4005a7ce2c507a8539`。准确来源和每份源码 SHA256 见 `results/environment-*.json`。上游 checkout 保持不变；构建过程复制 ListKit 的全部六个 Swift 源文件及 LICENSE 到独立模块。

这里的 ListKit 是上述 Lists 仓库中的 ListKit target，不是完整 Lists 高层 UI 框架，也不是 IGListDiffKit。本轮未测 IGListDiffKit。

| 后端名称 | 输入与算法 | UIKit 执行 |
|---|---|---|
| Apple-reloadItems | String ID snapshot；外部按 revision 比较内容 | apply(false)，内容 reloadItems |
| Apple-reconfigure | 相同 snapshot 与内容比较 | apply(false)，内容 reconfigureItems |
| DifferenceKit-staged | 公开 StagedChangeset；平面用 flat initializer，多节用 sectioned initializer | 内容 reload；等待每个 stage completion |
| Unique-Heckel-staged | 上轮独有 ID 专用 Swift 匹配与 next-unconsumed-source 贪心 move 选择 | 上轮 customStages，内容先 reload |
| Key-LIS-staged | 同一专用匹配，换成 LIS move 选择 | 与自研 Heckel 相同的 customStages |
| ListKit-LIS-exact | 固定版本原始 ListKit：Heckel 匹配后用 LIS 选择 stationary items | 原版精确 batch；结构后 reconfigure |
| ListKit-Heckel-exact | 只把上面 stationary/move 选择换成 next-unconsumed-source 贪心 | 与原版完全相同的 snapshot、匹配、调度、执行器 |
| ListKit-default-no-animation | 原版 ListKit，同样构建 snapshot、算 diff | apply(false)；有变化时 reloadData，无变化直接返回 |
| Apple-reloadData | Apple snapshot | applySnapshotUsingReloadData |
| UIKit-reloadData | 直接替换 model | reloadData + layout |

**ListKit-LIS-exact 与 ListKit-Heckel-exact 是控制变量对照。** `build.py` 只替换一次 `minimalMoves(from:)` 调用并插入贪心 helper；其余上游源码逐字一致。两个模块使用相同优化配置，独立链接进同一 app。辅助桥接仅暴露 benchmark 所需入口。它不是把整个 ListKit 改写成自研 unique-ID 算法，因而不能把两者差额等同于最终自研成本。

Unique-Heckel 与 Key-LIS 是另一组控制变量对照。自研平面原型与 DifferenceKit、Apple、ListKit 则是完整后端比较：数据结构、内容比较、snapshot 构建、阶段数、内容更新原语都可能不同。特别是自研 / DifferenceKit 使用 reload，ListKit 使用 reconfigure，不能把跨后端 update / mixed 的差值仅归因于 diff 算法。

## 无动画的公平性

该版本 ListKit 的 `animatingDifferences: false` 在算完 diff 后走 reloadData；Apple 普通 apply(false) 仍执行 diff。直接把两个 false 相比，会把整体重载和精确更新混在一起。

因此整个 app 都设置 `UIView.setAnimationsEnabled(false)`，ListKit 的两个 exact 后端传 `animatingDifferences: true` 以进入原版 batch 路径。Apple 仍传 false。instrumented UICollectionView 验证 ListKit exact 确实提交了 move / insert / delete，default-no-animation 列单独报告。两者只是在这次实验中关闭可视动画，参数名不能替代实际执行路径。

上游 ListKit 的 1,000 项后台 diff 阈值、Task 串行链、空变化快速返回、纯内容直接 reconfigure 路径均保留。1,000 / 10,000 的 apply 包含任务切换与等待，不能当作纯计算耗时。

## 输入、样本与计时

- 平面：100 / 1,000 / 10,000 项，每档 12 场景；no-op、尾部新增、头部新增、删除、左右旋转一项、5% 内容更新、相邻交换、shuffle、reverse、全部替换、mixed。
- 系统排列：同三档，每档 12 场景；左旋 1 / 2 / 10 / n/2 / n−1，block move / swap、interleave、odd-even、middle-to-head、不相交块交换、reverse。左旋 n−1 等价于右旋一项。
- Churn：同三档；选中重排比例 0 / 10 / 25 / 50 / 75 / 90 / 100%，每档三个固定 workload seed。选中比例不等于实际移动比例；该组不更改内容与身份集合。
- 多节：3 节，每节 2 / 33 / 333 / 3,333 项，总数 6 / 99 / 999 / 9,999；20 种 section + item 组合变化。与整百大小分开标注。
- 功能检查：200 个小规模随机多节转换 × 5 个后端；不用于性能排名。

平面 `mixed` 的定义是：每隔 20 项更新一次 revision，删除另一组每隔 20 项的身份，在约 1/3 位置插入同量新身份，最后把前 5% 的目标数组移到尾部。它同时包含内容、增删与块旋转，因此不是普通“5% 内容变化”的替代样本。`adjacent-swap` 只交换数组中部相邻两项；shuffle 使用固定种子，三个进程重复不会更换输入排列。

每个 suite 启动独立进程，全部性能 suite 独立跑三轮。每个 engine × fixture 每轮先预热 5 次，平面正式 40 次，其他性能组正式 30 次。随机打乱 fixture 和每次的 backend 顺序，串行运行，不并行竞争模拟器。三个 workload seed 与三次进程运行是两个不同的维度。

统一固定 320×36 pt label cell、flow layout、关闭 prefetch、真实 window 中的 collection。每个样本新建 host，初始数据加载和初始 layout 在计时外。输入为稳定唯一 String ID，内容为整数 revision；这是便于验证的模型，不是要求生产引入 contentVersion。

总耗时从准备目标状态开始，包含外部内容比较、需要的 model 映射与 snapshot 构建、diff、stage / task、UIKit 更新，再到 `layoutIfNeeded` 返回。需要 completion 的路径等待 completion；直接 reconfigure / reloadData 路径等待方法返回再 layout。统计校验、额外滚动、文件写入在计时外。

`prepareMs` 对 Apple / ListKit 仅表示外部 snapshot 与内容适配；它们的内部 diff 包含在 `applyMs`。对自研 / DifferenceKit，prepare 包含 changeset 生成。因此跨后端的 prepare / apply 分项不具有同样的算法边界，主表比较 `totalMs`。

表格中心值是三轮各自中位数的中位数。完整 CSV 保留每轮中位数、p95、三轮范围和每轮原始样本。p95 采用 nearest rank；40 样本对应第 38 个，30 样本对应第 29 个。三轮范围是观测波动，不是置信区间，也没有对多重比较做显著性检验。小差值只作描述，不据此稳定排名。

每个 sample 都检查 `prepare + apply + layout = total`。分别对各分项取中位数后，其和不一定等于 total 的中位数；CSV 的分项不能当作一个虚构的“中位样本”直接相加。

## 正确性与解释边界

- 对 ListKit 两种 flat matcher，穷举 n=0...7 的所有排列，再加 1,500 个包含增删的固定种子随机输入，共 14,828 次检查。独立 replay 检查 identity 结果；原版 LIS 用 O(nm) LCS oracle 验证最少 move；贪心版与既有 unique-ID 选择器核对数量。
- 所有实际 UIKit 样本检查 section/item 数、可见 cell 的 ID 与 revision、Apple / ListKit 的完整 snapshot。多节和随机组还在计时外滚动到每节首尾检查。这不等于逐个展示了所有离屏 item，也未验证动画中间状态。
- UICollectionView 子类记录 batch、逐项/整节操作、reloadData 调用与 cell 配置数。所有候选使用同一个子类；Apple 内部私有路径不保证经过这些 override，其计数不拿来推断 Apple 的 diff 算法。每次调用增加计数会有少量固定开销，多 move 场景包含这个开销。
- 这是同一宿主上的模拟器相对实验。CPU、内存、图形和帧时不能视为 iPhone 真机性能；未测呈现帧、掉帧、render server 完成、峰值内存、热状态、复杂 self-sizing cell、连续提交、selection / first responder / scroll anchor 的完整保持。其他已启动模拟器和宿主进程保留，环境文件记录设备，不声称完全隔离。
- 重载组描述吞吐成本，不自动授权生产采用 reload fallback，也不产生一个可泛化的变更比例阈值。
- 此轮继续测试之前的平面自研原型；没有重写上轮通用多阶段 section planner。多节性能组对比 Apple、DifferenceKit 与两种 ListKit。

## 复现

先按[第一轮说明](../README.md)准备固定版本 DifferenceKit，再准备 Lists：

```sh
git clone https://github.com/Iron-Ham/Lists.git Benchmarks/DiffBenchmark/.build/Lists
git -C Benchmarks/DiffBenchmark/.build/Lists checkout 221e1513f2786a4e5e836c9b76092c3bd6e61575
export LISTS_PATH="$PWD/Benchmarks/DiffBenchmark/.build/Lists"
```

`LISTS_PATH` 指向 Lists 仓库根目录；`DIFFERENCEKIT_PATH` 指向 DifferenceKit 的 `Sources`。两者默认读取第一轮目录下的 `.build/`，不依赖本机 `research/`。报告图表需要 Python 的 `matplotlib`。以下命令从仓库根目录执行；报告脚本会改写本地 `RESULTS.md` 与 `assets/listkit-ablation.png`。

```sh
python3 Benchmarks/DiffBenchmark/round3/build.py
python3 Benchmarks/DiffBenchmark/round3/run.py --suites verify random
python3 Benchmarks/DiffBenchmark/round3/run.py --suites flat permutation churn matrix --repetitions 3 --skip-install
python3 Benchmarks/DiffBenchmark/round3/report.py
```

`run.py` 发现已有 booted iOS 27 iPhone，也可通过 `PARADE_BENCH_UDID` 指定；安装前等待 boot 完成。只控制本实验的独立 bundle `dev.weixi.ParadeDiffRound3`，已有其他模拟器保持原状。结果有 `complete=true` 才算完成；已有结果默认拒绝覆盖，重跑使用 `--tag`。日志及状态写入 `logs/`，原始 JSON 在 `results/`，`results/environment-*.json` 保存源码、二进制哈希及运行环境。

构建配置：Xcode 27，Swift 6.4，所有本地 Swift 使用 `-O -whole-module-optimization -swift-version 5`，arm64 iOS simulator，最低部署 iOS 17。上游项目的常规语言模式是 Swift 6，本实验为保持既有比较条件统一使用 Swift 5 模式；两个 ListKit 对照相同。

### 复算已有测量

报告生成时还会校验环境文件记录的源码、生成模块和二进制哈希，不能拿重新编译的程序冒充旧结果的来源。默认从当前 benchmark 目录和 `build/` 读取；归档迁移后复算原有数据，可分别用 `PARADE_BENCH_SOURCE_ROOT`、`PARADE_BENCH_BUILD_ROOT` 指向测量时的源码路径基准与构建目录，`LISTS_PATH` 指向对应版本的 Lists。路径可以变化，哈希必须匹配。迁移前的源文件路径基准为本地研究目录，迁移后的构建以 `Benchmarks/DiffBenchmark` 为基准。
