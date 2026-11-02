# Benchmarks

这个目录放 Parade 的 benchmark。代码和说明放在一起；结果表可读，原始数据不提交。

这里的 benchmark 是研究型 harness：它们直接编译固定版本的参考库源码，不挂进 `Package.swift`，所以没有 `swift run` 入口；每轮 README 会写清构建方式。

## DiffBenchmark

第一轮：UI diff 的算法与 UIKit backend 对比（2026-09-17）。

- [README](DiffBenchmark/README.md)：问题、比较口径、复现步骤、验证方法
- [RESULTS](DiffBenchmark/RESULTS.md)：原始结果表

最短的结论：同样一次“首项移到末尾”，DifferenceKit / Unique-Heckel 生成 9,999 个 move，Key-LIS / Swift 标准库只生成 1 个；反向旋转又都是 1 个。移动选择策略会显著改变 UI 操作数，但这不等于哪种算法整体更好。

这轮是历史快照，不是 Parade 的生产选型结论。原始 `results/` 和 `build/` 不提交，按 README 重跑即可生成。

后续的 sectioned planner / adapter 轮次会按同样结构补进来。
