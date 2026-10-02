# 布局接入与迁移

此文描述未发布的开发 API。布局由 Section 决定；集合选择一种布局类型，Parade 将它与内容一同捕获、排队和更新。内置 Compositional、Flow 接入，自定义 `UICollectionViewLayout` 可在库外接入。

## 核心代码入口

| 文件 | 职责 |
| --- | --- |
| [SectionController](../Sources/Parade/Section/SectionController.swift) / [SectionContent](../Sources/Parade/Section/SectionContent.swift) | `Content.Layout == Layout`；不同具体 Section / Content 可以使用同一种布局类型。 |
| [SectionSnapshot](../Sources/Parade/Section/SectionSnapshot.swift) | 捕获 `content.layout`，中间更新阶段保留布局版本身份。 |
| [CollectionDataSource](../Sources/Parade/DataSource/CollectionDataSource.swift) | `sectionSnapshot(at:)` 返回当前 UIKit 阶段的捕获版本。 |
| [CollectionLayout](../Sources/Parade/Layout/CollectionLayout.swift) | 创建原生 layout 和布局 delegate；`LayoutAccess` 查询当前展示阶段。 |
| [CollectionLayoutDelegate](../Sources/Parade/Layout/CollectionLayoutDelegate.swift) | 供外部布局扩展；将既有交互、显示、滚动回调转交内部 bridge。 |
| [FlowSectionLayout](../Sources/Parade/Layout/FlowSectionLayout.swift) | 在对应 Section 的具体 Flow delegate 上调用原生尺寸与间距查询。 |
| [CollectionOrchestrator](../Sources/Parade/CollectionOrchestrator.swift) | 安装上述对象，保留既有提交队列和绑定流程。 |

`Controller → Content → Snapshot → DataSource → Orchestrator` 都携带同一个 `Layout`，`CollectionUpdate`、`SectionStore` 和更新计划也如此。具体 Controller / Content 在内部被擦除，布局类型关联仍被编译器检查。纯 `SectionedDiffAlgorithm` 不认识布局，算法协议与实现没有变化。

## Compositional：返回原生布局值

```swift
func captureContent() -> LayoutContent<CompositionalSectionLayout> {
    let columns = columns // 提交时的业务输入
    return LayoutContent(cells: cards.map(AnyCellPresenter.init)) { environment in
        makeSection(columns: columns, environment: environment)
    }
}

let collection = CollectionOrchestrator(collectionView: collectionView)
// 等价的明确选择：layout: .compositional()
```

`LayoutContent` 是便利容器。自定义 `SectionContent` 也可以实现 `@MainActor var layout: CompositionalSectionLayout`，返回 `CompositionalSectionLayout { environment in ... }`。原来的 `makeLayout(in:)` 不再是协议要求。

原生 environment 每次查询都取当前值；闭包中的列数、展示模式等业务输入属于捕获版本。不要捕获后再读活的 Section 状态。

## Flow：返回具体 delegate 工厂

```swift
func captureContent() -> LayoutContent<FlowSectionLayout> {
    let columns = columns
    return LayoutContent(
        cells: cards.map(AnyCellPresenter.init),
        layout: FlowSectionLayout { access in
            CardFlowDelegate(access: access, columns: columns)
        }
    )
}

let flow = UICollectionViewFlowLayout() // 也可以是自己的 Flow 子类
flow.minimumLineSpacing = 12
let collection = CollectionOrchestrator(collectionView: collectionView, layout: .flow(flow))
```

`CardFlowDelegate` 直接遵循 `UICollectionViewDelegateFlowLayout`。尺寸查询可以用
`access.item(at: indexPath, as: CardPresenter.self)` 取得当前阶段的具体 Presenter；类型不符或位置已不存在时返回 `nil`。不同 Section 可使用不同的具体 delegate 类，调用处无需写 `any`。

工厂在首次查询时创建对象，同一捕获版本、同一集合的后续查询复用它。每次捕获创建新的 `FlowSectionLayout`，不要在 Section 间共享它；工厂应复制业务输入，不应读取可变 Section。内部只在原生协议边界擦除 delegate 类型。遗漏的六个 Flow 布局查询会使用原生 layout 的 `itemSize`、insets、spacing 和 header/footer 默认值；启用 `estimatedItemSize` 时仍由 Cell 参与自适应尺寸计算。

这个 **Section delegate 只处理六个 Flow 布局查询**，不承担点击、显示或滚动事件。相关行为继续通过 Presenter、`eventHandler`、`scrollViewDelegate` 配置。Flow 子类若另有自定义 delegate 协议，应使用下面的自定义接入方式。

## 自定义布局：在库外组装

完整示例在 [Waterfall.swift](../Tests/LayoutSupport/Waterfall.swift)，它只 `import Parade`。这里的纯 Swift `WaterfallDelegate` 和 `WaterfallSectionLayout` 都是应用定义的类型：

```swift
extension CollectionLayout where Layout == WaterfallSectionLayout {
    static func waterfall() -> Self {
        Self(
            makeLayout: { _ in WaterfallLayout() },
            makeDelegate: { access in WaterfallBridge(access: access) }
        )
    }
}

final class WaterfallBridge: CollectionLayoutDelegate, WaterfallDelegate {
    let access: LayoutAccess<WaterfallSectionLayout>

    init(access: LayoutAccess<WaterfallSectionLayout>) {
        self.access = access
        super.init()
    }

    func columns(in section: Int) -> Int {
        access.section(at: section)?.layoutValue.delegate(in: access)
            .columns(in: section) ?? 1
    }

    // height(at:width:) 同样按当前位置路由到对应 Section 的 delegate。
}
```

原生 layout 可以通过 `collectionView.delegate as? WaterfallDelegate` 调用自己的协议，Parade 不做动态 selector 代理，也不需要增加布局类别枚举。若 layout 有独立的 delegate 属性，可在 `makeLayout` 内建立自己的适配对象并由 layout 持有。

`CollectionLayoutDelegate` 是受限扩展入口，不是公开的内部 bridge。它已有的选择、高亮、菜单、显示和滚动方法不可覆盖，以保留视图绑定及生命周期处理。它是具体基类的代价也明确：已有第三方 delegate 若必须继承另一基类，需通过组合转发其布局查询，不能直接多继承。

原生 layout 和集合级 delegate 每个集合各创建一个。`LayoutAccess` 弱引用 orchestrator，延长 access 生命周期不会留住集合；owner 释放后查询返回 `nil`。自定义工厂和 delegate 仍应避免强引用业务 owner 形成自己的循环。

## 当前阶段与更新

- `LayoutAccess.section(at:)`、`item(at:as:)` 和 `indexPath(for:)` 读取 data source 当前阶段，不能用最新 Store 下标替代。
- 手动分阶段更新期间，保留 Section 使用源布局，新增 Section 使用目标布局；最后内容阶段安装目标布局。`replacingCells` 保留同一布局身份。
- Data source 在安装新版本后使布局失效；仅布局变化也会触发更新。布局版本不通过闭包或 delegate 相等性比较。
- 自定义 layout 自己负责 attributes、bounds 变化、invalidation 和布局动画；必须接受空 Section、中间 item 数量和位置缺失。框架不提供通用滚动锚点恢复。
- `compose(...).updating(...).apply()`、`section.update()` 和 Store reconciliation 的时机及语义不变。

一个集合选择一个 `Layout`。直接把 Flow Section 放入 Compositional 集合会编译失败；同一集合混合不同布局家族，需要应用自行定义能表达它们的统一布局契约，不会自动混用两个原生 layout。

## 升级现有代码

| 原用法 | 新用法 |
| --- | --- |
| `DefaultSectionContent` | `LayoutContent<CompositionalSectionLayout>`，原有 trailing closure 保留 |
| 自定义 Content 的 `makeLayout(in:)` | `@MainActor var layout: CompositionalSectionLayout` |
| 显式 `CollectionOrchestrator` / `SectionStore` 类型 | 增加 `<CompositionalSectionLayout>`，Flow 则使用 `<FlowSectionLayout>` |
| 显式 Snapshot、Update、Definition、DataSource 类型 | 同样增加布局类型参数；能推断的构造处无需重复写 |
| 应用子协议 `protocol HomeSection: SectionController` | 若统一使用 Compositional，增加 `where Layout == CompositionalSectionLayout` |
| 自研 data source 的 `layoutSection(at:environment:)` | `sectionSnapshot(at:) -> SectionSnapshot<Layout>?`，与其他查询保持同一阶段 |

若应用保存 `[any HomeSection]` 子协议数组，在应用侧提供一个逐元素打开具体遵循的出口：

```swift
protocol HomeSection: SectionController where Layout == CompositionalSectionLayout {}

extension HomeSection {
    var collectionSection: any SectionController<CompositionalSectionLayout> { self }
}

try await collection.compose(sections.map { $0.collectionSection }).apply()
```

仅给子协议添加 `where` 后直接传数组，或使用 `.map { $0 }`，本轮工具链无法编译。把子协议也声明为 primary-associated-type 再直接传整个数组虽然可以编译，却在 Xcode 27.0 / Swift 6.4 的运行检查中进入 `_arrayForceCast` 并崩溃。因此迁移示例采用上面的逐元素出口，并有运行测试覆盖。具体 Section 直接组成的 `[header, feed]` 不需要这些转换。


`CollectionOrchestrator(collectionView:)` 和不传 layout 的自研 data source 初始化仍推断为 Compositional。改名不增加兼容别名。

运行、类型检查及阅读示例见 [LayoutDemo](../Examples/LayoutDemo/README.md)。Podcast 专项迁移见 [交接文档](PodcastMigration.md)。
