# Parade UI diff 实测结果

这是 2026-09-17 的本机实验快照；实验合同、正确性检查、实现边界和复现方式见 [README](README.md)。

## 当前判断

建议优先继续验证 **Key + LIS**，保留唯一 ID 的 Heckel 实现作为计算成本对照。理由是输出操作质量，尚不是生产选型结论。

1. **Heckel 的线性计算不保证更少 UI 工作。** 10,000 项左旋一位，DifferenceKit 与当前 Unique-Heckel 生成 9,999 个 move，LIS 与标准库只生成 1 个。反向旋转时四者都是 1 个 move；这暴露了移动选择策略的方向性。
2. **LIS 的优势依赖场景。** 随机打乱时，多数项原本就必须移动，LIS 节省的操作有限。无变化、增删导致整体平移时，所有候选都避免了多余 move；不能把 index 改变直接算作移动。
3. **Apple 要比较完整 backend。** 原生 snapshot 准备、内容存储更新及 apply 是可见的完整路径。自研 backend 也包含计划与 UIKit 应用；快慢不能全部归到其不可见的内部算法。
4. **Section 是下一步决定性验证。** 本轮只有 Apple / DifferenceKit 跑 section 插入、重排和跨 section 场景。LIS 的数组正确性与本轮单 section UIKit 通过，都不足以证明多 section planner 正确。

本轮不据小幅差距判断胜负；特别是无内容变化时两个 Apple 变体的差异，尚未对运行波动与空标记 API 路径做归因。

CPU：Version 27.0 (Build 26A428)；2026-09-17T01:58:04Z；Release 优化、每组 5 次预热 / 30 次样本。

正确性：29,656 个算法用例，通过独立操作重放、stages 重放和小规模 LCS oracle。

Apple 内部 diff 无公开独立计时入口，所以不出现在 CPU 表中。DifferenceKit-core 不等于其公共 staged API。

## CPU diff：10,000 个带 section 前缀的 String ID

单位 ms，中位数；全部包含内容检查。未测表示预算策略跳过，不代表超时。

| 场景 | DifferenceKit core | 自研 Unique-Heckel | Key + LIS | Swift 标准库 |
|---|---:|---:|---:|---:|
| no-op | 1.137 | 0.788 | 0.780 | 1.019 |
| append-5pct | 1.157 | 0.822 | 0.791 | 2.346 |
| prepend-5pct | 1.159 | 0.807 | 0.789 | 2.366 |
| delete-5pct | 1.120 | 0.769 | 0.753 | 5.518 |
| rotate-left-1 | 1.156 | 0.794 | 1.018 | 1.214 |
| rotate-right-1 | 1.114 | 0.793 | 1.017 | 1.209 |
| update-5pct | 1.113 | 0.796 | 0.772 | 1.017 |
| adjacent-swap | 1.117 | 0.781 | 1.016 | 1.034 |
| shuffle | 1.173 | 0.818 | 0.986 | 未测 |
| reverse | 1.150 | 0.794 | 0.821 | 未测 |
| replace-all | 1.133 | 0.812 | 0.808 | 未测 |
| mixed | 1.143 | 0.784 | 0.989 | 未测 |

## 相同目标下生成的 move 数

| 10,000 项场景 | DifferenceKit core | 自研 Unique-Heckel | Key + LIS | Swift 标准库 |
|---|---:|---:|---:|---:|
| prepend-5pct | 0 | 0 | 0 | 0 |
| rotate-left-1 | 9999 | 9999 | 1 | 1 |
| rotate-right-1 | 1 | 1 | 1 | 1 |
| adjacent-swap | 1 | 1 | 1 | 1 |
| shuffle | 9994 | 9994 | 9815 | 未测 |
| reverse | 9999 | 9999 | 9999 | 未测 |

## UIKit：模拟器上的完整 backend 更新

iOS 27.0，iPhone19,2，2026-09-17T02:00:22Z；关闭动画，每项 3 次预热 / 15 次样本。

单位 ms，中位数；包含 prepare + apply completion + layout。布局和 cell 相同，collection 实际挂在 window 上。
模拟器使用宿主机资源，这张表不能代表真机耗时、掉帧或电量；completion 后 layout 也不是像素呈现时刻。

| 项数 / 场景 | Apple reload | Apple reconfigure | DifferenceKit staged | Unique-Heckel staged | Key-LIS staged |
|---|---:|---:|---:|---:|---:|
| 100 / no-op | 0.666 | 1.144 | 0.030 | 0.025 | 0.026 |
| 100 / prepend-5pct | 0.807 | 0.811 | 0.837 | 0.712 | 0.800 |
| 100 / rotate-left-1 | 0.647 | 0.707 | 0.729 | 0.706 | 0.518 |
| 100 / rotate-right-1 | 0.660 | 0.717 | 0.611 | 0.654 | 0.754 |
| 100 / update-5pct | 0.741 | 0.735 | 0.609 | 0.582 | 0.641 |
| 100 / mixed | 0.991 | 1.123 | 1.261 | 1.218 | 1.113 |
| 100 / shuffle | 1.529 | 1.310 | 1.030 | 1.054 | 0.978 |
| 1,000 / no-op | 1.220 | 1.099 | 0.156 | 0.146 | 0.143 |
| 1,000 / prepend-5pct | 1.655 | 1.552 | 1.270 | 1.185 | 1.212 |
| 1,000 / rotate-left-1 | 1.107 | 1.212 | 1.832 | 1.962 | 0.777 |
| 1,000 / rotate-right-1 | 1.119 | 1.147 | 0.697 | 0.845 | 0.702 |
| 1,000 / update-5pct | 1.351 | 1.091 | 0.771 | 0.694 | 0.720 |
| 1,000 / mixed | 2.310 | 2.178 | 2.699 | 2.885 | 2.034 |
| 1,000 / shuffle | 6.675 | 6.553 | 2.924 | 2.633 | 2.462 |
| 10,000 / no-op | 5.651 | 5.824 | 1.420 | 1.477 | 1.441 |
| 10,000 / prepend-5pct | 7.370 | 7.407 | 3.066 | 3.430 | 3.165 |
| 10,000 / rotate-left-1 | 6.030 | 4.959 | 15.445 | 15.691 | 2.618 |
| 10,000 / rotate-right-1 | 6.074 | 6.144 | 2.498 | 3.363 | 2.650 |
| 10,000 / update-5pct | 6.281 | 5.755 | 3.665 | 2.956 | 2.693 |
| 10,000 / mixed | 10.897 | 10.748 | 17.052 | 17.066 | 5.883 |
| 10,000 / shuffle | 57.381 | 56.741 | 21.290 | 21.362 | 21.415 |

## UIKit section 样本

旧数据 10 sections × 100 items；自研候选尚无 sectioned planner，所以本表只比较已实现的两种后端。

| 场景 | Apple reload | Apple reconfigure | DifferenceKit staged |
|---|---:|---:|---:|
| section-reorder | 1.820 | 1.894 | 1.083 |
| section-insert | 1.560 | 1.682 | 1.096 |
| cross-section-stable-ID | 1.206 | 1.068 | 0.809 |
| cross-section-new-prefixed-ID | 1.248 | 1.153 | 0.933 |

共 117 个 UIKit 比较组合，每个样本完成 section/item 数量及可见 cell 的 ID/revision 检查；Apple 另核对完整 snapshot。

Apple 的内部操作数和 stage 数不可见；原始数据 operations = -1、stages = 0 表示不可观测，不能解释为没有操作或优于其他候选。

## 10,000 项左旋一位：分段耗时

| Backend | prepare 中位数 | apply 中位数 | layout 中位数 | total 中位数 | total p95 |
|---|---:|---:|---:|---:|---:|
| Apple-reload | 2.886 | 3.214 | 0.002 | 6.030 | 6.385 |
| Apple-reconfigure | 2.846 | 1.996 | 0.023 | 4.959 | 6.458 |
| DifferenceKit-staged | 1.462 | 13.959 | 0.002 | 15.445 | 15.865 |
| Unique-Heckel-staged | 1.529 | 14.119 | 0.002 | 15.691 | 16.197 |
| Key-LIS-staged | 1.784 | 0.581 | 0.171 | 2.618 | 4.086 |

分段各自取中位数，三段中位数之和不一定等于 total 的中位数。

## 结果文件

原始 JSON / CSV 由 `build/cpu`、UIKit app 和 `report.py` 写入 `results/`，不随仓库提交；这里只保留汇总表。
UIKit 原始样本同样在 `results/ui.json`。

p95 仅是本轮样本的描述性统计，尤其 UIKit 只有 15 次样本，不作为稳定尾延迟保证。
本轮没有测 allocation / 峰值内存、真实复杂内容 equality、动画 frame/hitch、连续提交和交互状态保留；不要从这些结果推导相关结论。
