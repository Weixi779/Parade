# 布局实验：从哪里读代码

这是上一轮已运行实验的源码导航。**当前正式工作区源码 → 生成实验副本** 的真实差异保存在 [Experiment.diff](Experiment.diff)。基线包含工作区已有的 public API 修改；不要把它误认为相对 HEAD 的改动。

该 diff 包含原型选择（如公开 bridge、闭包形式的 delegate 擦除），用于阅读比较，尚不是最终合入方案。本次只补充可阅读入口，未调整原型行为。

## 用 Xcode 阅读

直接打开 [实验 Package.swift](../../.build/LayoutCompositionStudy/Package/Package.swift)。它包含 `Parade`、独立消费者 `StudySupport` 和 `StudyTests`，可索引、跳转定义和运行包测试。

应用入口 [Demo.swift](Demo.swift) 仍由脚本独立编译，不在这个包的应用 target 中。讨论核心设计先看包内的库与消费者即可。

若生成目录不存在，先从仓库根目录运行 `python3 Demos/LayoutCompositionStudy/prepare.py`。阅读文件位于 `.build`，修改原型请改 `Overlay` / `Support` 或生成规则，再重新生成；下次生成会覆盖副本。

## 按这个顺序读

| 位置 | 实验源码 | 对应 diff | 重点 |
| --- | --- | --- | --- |
| 1. Controller / Content 的类型关联 | [SectionController.swift](/Users/sunshiwei/Develop/Parade/.build/LayoutCompositionStudy/Package/Sources/Parade/Section/SectionController.swift:8) | [查看差异](/Users/sunshiwei/Develop/Parade/Demos/LayoutCompositionStudy/Experiment.diff:1) | `Content.Layout == Layout`：具体 Content 可以不同，但布局类型必须匹配。 |
| 2. 两种布局的共同承载位置 | [SectionContent.swift](/Users/sunshiwei/Develop/Parade/.build/LayoutCompositionStudy/Package/Sources/Parade/Section/SectionContent.swift:5) | [查看差异](/Users/sunshiwei/Develop/Parade/Demos/LayoutCompositionStudy/Experiment.diff:17) | 原来的 `makeLayout(in:)` 变成 `associatedtype Layout` 和 `var layout: Layout`。 |
| 3. 捕获边界 | [SectionSnapshot.swift](/Users/sunshiwei/Develop/Parade/.build/LayoutCompositionStudy/Package/Sources/Parade/Section/SectionSnapshot.swift:38) | [查看差异](/Users/sunshiwei/Develop/Parade/Demos/LayoutCompositionStudy/Experiment.diff:85) | 捕获 `content.layout`；`replacingCells` 继续保留同一份布局身份。 |
| 4. DataSource 查询边界 | [CollectionDataSource.swift](/Users/sunshiwei/Develop/Parade/.build/LayoutCompositionStudy/Package/Sources/Parade/DataSource/CollectionDataSource.swift:27) | [查看差异](/Users/sunshiwei/Develop/Parade/Demos/LayoutCompositionStudy/Experiment.diff:144) | 返回当前阶段的 `SectionSnapshot<Layout>`，不再直接返回 Compositional section。 |
| 5. 布局组装与读取 | [CollectionLayout.swift](/Users/sunshiwei/Develop/Parade/.build/LayoutCompositionStudy/Package/Sources/Parade/CollectionLayout.swift:7) | [查看差异](/Users/sunshiwei/Develop/Parade/Demos/LayoutCompositionStudy/Experiment.diff:307) | `CollectionLayout` 安装原生 layout 与 bridge；`LayoutAccess` 把查询接到当前 data source。 |
| 6. Orchestrator 接线 | [CollectionOrchestrator.swift](/Users/sunshiwei/Develop/Parade/.build/LayoutCompositionStudy/Package/Sources/Parade/CollectionOrchestrator.swift:102) | [查看差异](/Users/sunshiwei/Develop/Parade/Demos/LayoutCompositionStudy/Experiment.diff:467) | 同一个 `Layout` 串起 data source、layout 与 delegate，更新队列保持原来的职责。 |

## 最关键的三处

第一处是 `SectionContent` 的布局关联。下面省略与布局无关的成员：

```diff
 public protocol SectionContent {
-    func makeLayout(in environment: any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
+    associatedtype Layout
+    var layout: Layout { get }
 }
```

第二处是 data source 只返回当前阶段的捕获版本。它保存布局信息，不解释 Flow 或 Compositional 的具体协议：

```swift
func sectionSnapshot(at index: Int) -> SectionSnapshot<Layout>?
```

第三处是接入层如何消费它。Compositional 的真实核心调用是：

```swift
UICollectionViewCompositionalLayout { index, environment in
    access.section(at: index)?.layoutValue.build(environment)
}
```

Flow 的核心调用是：

```swift
access.section(at: path.section)?
    .layoutValue.queries(access).size(view, layout, path)
    ?? layout.itemSize
```

两条路径使用同一个查询边界；各自保留原生布局的表达方式。

## 从业务 Section 跟到 UIKit

1. [FlowCards.captureContent](Support/Sections.swift:75) 复制当前 `scale` / `columns`，返回构建具体 delegate 的工厂。
2. [FlowSectionLayout.init](Overlay/CollectionLayout.swift:64) 接收 `D: UICollectionViewDelegateFlowLayout`，在本布局内部保存查询能力；这里是具体 delegate 被擦除的位置。
3. [FlowBridge 的 sizeForItemAt](Overlay/CollectionLayout.swift:126) 根据当前 section 索引找捕获的布局，再调用对应 delegate。
4. [CardFlowDelegate.sizeForItemAt](Support/Sections.swift:115) 通过 `access.item(at:as:)` 取得当前阶段的 Card，用捕获的参数计算尺寸。

原生返回值路径看 [CompositionalCards.captureContent](Support/Sections.swift:135) 和 [compositional 接入](Overlay/CollectionLayout.swift:46)。库外自定义协议路径看 [Waterfall.swift](Support/Waterfall.swift:8)。

## diff 算法到底改了什么

`Sources/Parade/Diff/` 下的纯算法文件与当前工作区逐字相同。`SectionedDiffAlgorithm` 仍然接收 `DiffableSection` 并返回差异坐标。

改变的是 `CollectionUpdatePlan<Layout>`、`CollectionBatch<Layout>` 等更新管道的承载类型：每个中间阶段携带 `SectionSnapshot<Layout>`，已有 staging 继续通过 `replacingCells` 保留布局身份。这里没有另写一套差分或 batch 规划算法。

## 阅读时区分原型与已确定方向

- 已验证：带类型的组装、内容和布局共同捕获、当前阶段查询、两种 data source 下的更新与核心回调。
- 原型选择：把整个 bridge 公开继承；Flow 使用六组闭包进行擦除；泛型传播到所有内部更新类型。这些代码能运行，但尚未作为最终 public API 定案。
- 对应行为测试见 [LayoutTests.swift](Tests/LayoutTests.swift)，实际结果和局限见 [实验报告](README.md)。

重新导出阅读 diff：从仓库根目录运行 `python3 Demos/LayoutCompositionStudy/export_review.py`。脚本会先检查正式源码是否仍匹配生成副本记录的基线，避免误把后续修改算进布局实验。
