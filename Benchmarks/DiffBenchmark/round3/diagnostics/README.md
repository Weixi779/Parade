# 第三轮后的计时诊断

这是 2026-09-17 的后续实验，解释第三轮的完整更新差距。先读[结果与修正](RESULTS.md)，再读[第三轮方法](../README.md)。两套探针只改实验 harness，不修改 Parade 或参考库 checkout。

- `empty-ui-calls/probe.py`：只跳过六类空 UIKit 调用，保留算法、阶段、内容原语和完成等待。
- `settled-initial-state/probe.py`：在上述对照上，让所有候选于初始布局后提交事务并等待 30 ms，等待在计时外。只测百项追加、右旋和混合更新。
- `report.py`：复核原始样本的分项总和、median、p95 和覆盖数量，再生成本目录的 `RESULTS.md`。

## 复现

先完成第三轮 README 中的依赖准备与 `build.py`，探针复用其两个 ListKit 模块。选择已启动的模拟器；默认寻找 iOS 27 iPhone，也可设置 `PARADE_BENCH_UDID`。以下命令从仓库根目录执行：

```sh
python3 Benchmarks/DiffBenchmark/round3/build.py
python3 Benchmarks/DiffBenchmark/round3/diagnostics/empty-ui-calls/probe.py build
python3 Benchmarks/DiffBenchmark/round3/diagnostics/empty-ui-calls/probe.py run
python3 Benchmarks/DiffBenchmark/round3/diagnostics/settled-initial-state/probe.py build
python3 Benchmarks/DiffBenchmark/round3/diagnostics/settled-initial-state/probe.py run
python3 Benchmarks/DiffBenchmark/round3/diagnostics/report.py
```

两组各运行三个进程，正式样本分别为 7,200 与 900。原始 `probe-1/2/3.json`、日志、环境文件写入各探针目录；已有结果会拒绝覆盖，重跑前请另存旧结果。构建输出放在各自 `build/`。这些输出不提交；源码、说明与历史汇总报告保留。

探针读取相同的 `DIFFERENCEKIT_PATH`。第三轮构建后如更换依赖 checkout，应先重新构建第三轮模块，避免把不同版本混进对照。

30 ms 只用于此次诊断，不建议将这个等待加入产品；它也不能证明屏幕已经呈现某一帧。本轮没有重跑第三轮全量矩阵。
