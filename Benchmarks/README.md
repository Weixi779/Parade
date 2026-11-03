# Benchmarks

这个目录保留 Parade 的研究型 benchmark：实验源码、复现脚本、结果报告和汇总图放在一起。原始 JSON、CSV、日志、依赖 checkout 与二进制不提交。

这些实验直接编译固定版本的参考库源码，不挂进 `Package.swift`，没有 `swift run` 入口；各轮 README 说明依赖与构建方式。

## DiffBenchmark

2026-09-17 的三轮 Diff / UIKit 实验及后续诊断。建议先读[调查总览](DiffBenchmark/OVERVIEW.md)，它区分算法计算、完整更新、后续修正以及与 Parade 当前实现的关系。

| 内容 | 报告 | 方法与复现 |
|---|---|---|
| 第一轮：一维算法与完整更新 | [结果](DiffBenchmark/RESULTS.md) | [README](DiffBenchmark/README.md) |
| 第二轮：Section、执行顺序、reload / reconfigure | [结果](DiffBenchmark/round2/RESULTS.md) | [README](DiffBenchmark/round2/README.md) |
| 第三轮：ListKit 对照与完整矩阵 | [结果](DiffBenchmark/round3/RESULTS.md) | [README](DiffBenchmark/round3/README.md) |
| 后续诊断：空调用与初始事务 | [修正](DiffBenchmark/round3/diagnostics/RESULTS.md) | [README](DiffBenchmark/round3/diagnostics/README.md) |

算法计算更快、移动更少，都不保证完整更新更快。第三轮的部分跨框架排名还受到初始化事务条件影响，引用时必须带上后续诊断。

这些是历史实验快照，不是当前 Parade 的生产性能排名，也不代表真机动画帧时。本次归档没有重新运行性能矩阵。
