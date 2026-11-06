# Podcast 升级迁移与简化交接

这份文档供升级 Podcast Collection 层的开发者和 agent 使用，记录必须迁移的 API、升级后可以删除的重复代码，以及使用审查中需要继续核对的地方。后续 Parade 功能落地时，应同步补充对应的 Podcast 简化项；发布前再按最终版本核对一次。

Podcast 提供真实使用场景，Parade 仍负责定义通用的框架契约。应用现有写法是评估依据，不限制框架改进；也不能把应用业务逻辑直接当作框架应承担的职责。

## 适用版本与接入位置

基础迁移表保留 **2026-10-03 的 1.0.0 API** 说明；Store 查询与输入分类一节对应当前
**1.2.0** 变更。**2026-11-06** 已只读核对新首页 Featured / Discovery 和 Story
的相关接入代码并更新示例，其余历史迁移项仍需在应用接入时重新核对。执行迁移时确认
两边 revision，并记录实际使用的 Parade tag；本文不代表 Podcast 已完成新 API 接入。

Podcast 的 Home 代码当前导入 `XYZFoundationUI`，Collection 实现在该仓库的 `Submodules/XYZFoundationUI/Sources/XYZFoundationUI/Collection/` 中。其 Package 当前没有外部依赖。因此，单独升级 Parade 包版本不会自动迁移这份实现：应先确认继续同步源码，还是调整模块依赖，再迁移调用方。

下文路径均相对于 **Podcast-iOS 仓库根目录**。Parade 的完整 API 变更见 [CHANGELOG](../CHANGELOG.md)，框架验证范围见 [Verification](Verification.md)。本文只记录迁移方案，尚未修改或验证 Podcast 应用。

## 必须迁移的 API

| 原用法 | 1.0 用法 | 迁移要点 |
| --- | --- | --- |
| `SectionPresenter` | `SectionController` | 修改协议遵循；业务具体类和文件的 `SectionPresenter` 后缀建议同步改为 `SectionController`。Cell 和 Supplementary 仍叫 Presenter。 |
| Section 的 `updates` | `updateContext` | 同步检查 `isAttached` 等访问。 |
| `sections.presenters` / `change.presenters` | `sections.controllers` / `change.controllers` | 仅指 `SectionStore` 与它的 `Change`，不是所有名为 presenters 的数组。 |
| `orchestrator.setSections(sections, animated: flag)` | `orchestrator.compose(sections).apply(animated: flag)` | 必须执行 `apply` 才会捕获内容并提交。 |
| `orchestrator.update(sections, animated: flag)` | `orchestrator.update(sections).apply(animated: flag)` | Section 自己的 `try await update(animated:)` 保持原样，不加 `apply`。 |
| `orchestrator.setVisible(flag)` | `orchestrator.isVisible = flag` | 保留调用时机及原有可见性判断。 |
| Presenter 的 `setBehaviors(_:)` | `bind(to:)` | Cell、Supplementary 的实现和手动调用都要改。 |
| `orchestrator.logger` | `onDiagnostic` / `onDidApply` | 若其他调用方有使用，分别记录问题和成功提交；合并现有回调职责，不覆盖已有处理。成功日志的时机改为完整提交结束后。 |
| `DefaultCollectionDataSource` | `StagedCollectionDataSource` | 只影响显式类型引用；普通 `CollectionOrchestrator(collectionView:)` 构造保持不变。 |
| DataSource 工厂的 `view, cell, supplementary` 与两种 provider 参数 | `view, views` 与 `views: views` | 自研实现保留 `CollectionViews`，通过它创建视图和批量刷新兼容的 Supplementary。 |
| 泛型 helper 假定任意 Presenter 都是 `DiffableElement` | 约束相应 Presenter 协议，或显式适配算法输入 | Presenter 自己定义身份与 `Equatable`；普通业务实现的 `id`、`==`、`configure`、`bind` 保持不变。 |

业务 Section 的 `setSection(_:)`、普通 View 的 `setBehaviors(onDismiss:...)` 并不是上述框架接口，不应全局机械替换。业务方法命名可另行整理。

### 绑定迁移不能只靠编译检查

`bind(to:)` 有默认空实现。漏改的 `setBehaviors(_:)` 可能作为普通方法继续通过编译，却不再收到框架回调，导致点击、订阅或 Supplementary 行为缺失。

至少逐项检查这些入口，并继续搜索其他协议实现：

| 调用位置 | 检查内容 |
| --- | --- |
| `Podcast/App/Features/Home/Featured/Sections/Episode/Presentation/HomeFeaturedEpisodeCellPresenter.swift` | 点击、播放、长按、用户跳转和实时观察绑定。 |
| `Podcast/App/Features/Home/Featured/Sections/EditorPick/Presentation/HomeEditorPickCellPresenter.swift` | 行为绑定、播放观察及当前购买/阅读相关状态。 |
| `Podcast/App/Features/Home/Shared/Sections/Shortcut/Presentation/HomeShortcutSectionPresenter.swift` | 内部 CellPresenter 的绑定实现，具体 Section 改名不等于内部 Presenter 已完成迁移。 |
| `Podcast/App/Features/Home/Discovery/Sections/Pictorial/Presentation/HomePictorialView.swift` 的 `bind(_:to:)` | 手动调用 `presenter.setBehaviors(cell)` 改为 `presenter.bind(to: cell)`，保留随后安装的画报交互。 |
| Home 下 Banner、NewPower、EditorPick、Podcast、Episode、Pilot、Pictorial 的 Header / Supplementary Presenter | 检查全部绑定协议实现，不能只迁移 Cell。 |

绑定在视觉内容相等时也会更新。实现应覆盖或清除自己负责的回调，订阅需要沿用现有替换/清理机制；不能依赖重复绑定累加 target 或观察者。相同 ID、相同外观但新点击目标的用例需要实际验证。

## Store 接纳与交付接入方式

2026-11-06 核对的新首页和 Story 接入已使用 `compose(...).updating(...).apply(...)`。
以下替换此前面向旧首页 `setSections` / `pendingState` 的建议。示例中的业务 helper
是页面负责的步骤示意，不是 Parade 新增 API，也不表示 Podcast 产品代码已迁移。

### 查询和输入分类

Store 与 Change 都实现 `SectionControllerQuery<Layout>`：

```swift
let thread: StoryCommentThreadSectionController? = threadSections.controller(for: id)
let feed = sections.controller(for: .feed, as: HomeDiscoveryFeedSectionController.self)
let pictorials = change.controllers(ofType: HomePictorialSectionController.self)
```

Store 查询已接纳成员；async reconcile 回调内应用 Change 查询本次目标，不能用 Store
替代。两者都是活实例，输入可能已变；可见、挂载和播放有效性仍沿 Collection 当前交付
身份查询，不能从 Store 查询结果推导。

`change.inputUpdated` 是本次执行过 update 闭包的存续实例，按目标顺序返回。它可以
替换首页 `updatedIds` 与 `change.retained` 的交集；相同输入重复投递也计入。
新建、同 ID 替换以及 retaining definitions 不计入。它不是内容差异、交付回执或
跨失败保存的 dirty 集合。最终 `.updating(...)` 仍由消费者选择。

### Home：页面串行范围包住定义生成和业务结算

保留页面已有的 `submit` 入口：等待前一个任务结束，检查取消，Discovery 再等待画报
交接并再次检查取消，然后才执行操作。必须在这个操作内读取当前成员和生成定义：

```swift
try await submit {
    // 已等待前一轮和必要的画报交接；此时才读取当前成员。
    let definitions = makeDefinitions(from: sections.retainingDefinitions, page: page)
    let change = try await sections.reconcile(definitions) { change in
        // 返回由序号、Feed 位置等额外变化影响的存续实例。
        // 画报配置也在交接完成后、捕获之前进行。
        let additionalUpdates = configureTarget(change.controllers)
        let regularInputs = change.inputUpdated.filter {
            !($0 is HomeShortcutSectionController)
        }
        let regularAdditional = additionalUpdates.filter {
            !($0 is HomeShortcutSectionController)
        }
        try await orchestrator.compose(change.controllers)
            .updating(regularInputs)
            .updating(regularAdditional)
            .apply(animated: animated)
    }
    // Collection 成功、Store 已接纳；Shortcut 继续自己的准备/提交/播放流程。
    for case let shortcut as HomeShortcutSectionController in change.inputUpdated {
        try await shortcut.updateContent(animated: animated)
    }
    settleCursorAndPageState(page)
}
```

`makeDefinitions` 必须保留页面策略：Featured 分页同 ID 原位更新；Discovery 普通
分页同 ID 忽略，Feed 分页单独更新 Feed。框架不自动 upsert、去重或重投旧输入。
`configureTarget` 负责返回额外需要捕获的实例；`.updating` 按实例去重。

不能只给提前生成的定义数组排队：后一个任务可能基于旧成员构造目标，覆盖前一个任务
新增的成员。Collection FIFO 只保证已捕获提交的交付顺序，不包括定义生成、画报等待、
Shortcut 动画和 cursor 收尾。

失败与取消仍由页面结算：

- 页面任务链等待前一个任务的 result，而不是仅等待成功；失败后下一轮仍能执行。
- 开始前或画报交接后的取消检查可阻止本轮输入修改；已进入 Collection 的提交不能因
  Task 被取消而假定撤销。当前 Collection 不提供排队取消 API。
- reconcile 回调抛错时 Store 保留旧成员，但已执行的输入更新及其他副作用不回滚。
- Collection 成功后的 Shortcut 失败不撤销 Store 接纳；cursor 是否推进取决于页面
  结算规则。示例保持现有“后续流程成功后才收尾”的顺序。
- 失败后重新投递 fresh definitions 会再次执行 update 并计入 `inputUpdated`；若
  只用 retaining definitions 重试，集合为空。页面必须明确选择待重新交付的内容。

### Story：先接纳业务与实例，再同步捕获并等待回执

Story 的 Repository 已负责接纳业务数据和分组。同步 reconcile 后处理移除实例的
回复任务及呈现清理，再与上下边界 Section 组合。使用 callback apply 保证在当前
调用内完成捕获、入队，不为等待回执另建 Store 队列：

```swift
// Repository 已接纳本轮业务结果。
let change = try threadSections.reconcile(makeThreadDefinitions(repository.groups))
for case let thread as StoryCommentThreadSectionController in change.removed {
    replyLoads.cancel(thread.id)
    thread.finishPresentation()
}
let target = composeBoundariesAndThreads(change.controllers)
let contentUpdates = selectStoryContentUpdates(change, target: target)
orchestrator.compose(target)
    .updating(contentUpdates)
    .apply(animated: animated) { result in
        finishPagePresentation(result, request: request)
        coordinateAfterSubmission()
    }
```

`selectStoryContentUpdates` 由页面选择，包括本轮线程输入、边界状态和挂载前局部变化。
仅构造 `CollectionUpdate` 不会捕获；调用 callback apply 才同步捕获。async apply
进入执行后使用相同捕获与完成边界，但不能把它放进稍后启动的 Task 后仍声称当前调用
已捕获。回执代表本次 Collection 内容、布局和绑定交付结束，不代表业务动画全部结束。

交付失败只结束本轮呈现，不撤销 Repository 的业务确认，也不把它伪装成网络失败。
移除实例的业务清理由 Story 显式执行；Store 移除和 Collection detach 都不自动等同于
业务删除。播放有效性继续查询 Collection 的当前交付身份。

### 本轮可删与必须保留

| 内容 | 迁移方式 |
| --- | --- |
| 首页 `updatedIds` 参数及来源集合 | 用 `change.inputUpdated` 替代 |
| Store 点查和 Change 类型筛选的重复转换 | 用共享查询协议替代 |
| 无障碍序号、Feed 位置、画报配置 | 保留页面计算，补充最终更新选择 |
| Shortcut 自有更新与动画 | 保留，从 `inputUpdated` 选择本轮实例 |
| 首页任务链、画报交接等待、cursor 结算 | 保留页面所有权 |
| Story 业务接纳、移除清理、播放查询 | 保留各自业务及 Collection 身份边界 |

布局和 Cell 内容必须来自同一份已捕获展示版本。不要让捕获后的 layout 闭包重新读取
可变 Section 状态。UIKit 更新中的查询可能对应中间阶段，不能拿最新 Store 下标替代。

## 后续能力落地时继续补充

| 议题 | 当前状态 | 届时要回答的 Podcast 迁移问题 |
| --- | --- | --- |
| Flow Layout / 自定义 `UICollectionViewLayout` | 1.0 API 已实现，见下方迁移说明和 [布局契约](LayoutIntegration.md)；尚未迁移 Podcast | 核对实际自建 Collection 的协议和回调，确定适配代码可删范围；每个 Section 只提供自己所属布局类型，不要求写两套。 |
| Diff 算法和 DataSource 的命名、可替换边界 | 已完成本轮职责解耦；`StagedCollectionDataSource`、`CollectionViews` 和公开模型判断已实现，仍为同一个 target | 按下方说明迁移工厂和泛型约束；实际删除范围需在 Podcast 接入时确认。 |
| 滚动位置保持 | 未来 TODO，明确不纳入 1.0；从有实际需求的具体布局验证 | 1.0 迁移继续保留业务布局中的位置记录与补偿；只有后续实现和验证成立后，才讨论删除范围。 |
| 拖拽与交互排序 | 未来 TODO，明确不纳入 1.0 | 不把布局接入或程序化移动当成交互排序支持；有真实编辑场景后再讨论同步规则。 |
| 队列空闲通知 | 1.0 不新增；保留既有 `onDidApply` | `onDidApply` 仍不是 idle 信号；迁移不能据此删除 pending render 的等待逻辑。 |

后续每落地一项变更，在本文补齐“框架契约 → Podcast 调用位置 → 必改项 / 可删除代码 → 必须保留的业务行为 → 验证结果”。未经实现和验证的讨论保持待定，不写成升级收益。

## DataSource 重构的必改项与可简化项

框架仍只有 `Parade` 一个模块，先按物理目录分离职责，没有新增包依赖或转导出层。`SectionedDiff` 与 `SectionedDiffAlgorithm` 保持名称和计算契约。普通 Home Section、Cell / Header Presenter、Store 和提交链无需因本轮重构再改一套写法。

若继续同步 `Submodules/XYZFoundationUI/Sources/XYZFoundationUI/Collection/` 中的实现，应同步本轮职责调整；不能只把默认 DataSource 文件改名。若改成外部包依赖，再按实际调用方是否自建 DataSource 区分迁移范围：

- **必改：** 显式默认实现改为 `StagedCollectionDataSource`；自定义工厂接收 `view, views`，两种内置实现都用 `views:`。自研 DataSource 的 UIKit 回调调用 `views.cell(at:presenter:)` 与 `views.supplementary(ofKind:at:presenter:)`。删除原 provider 闭包存储。
- **泛型约束：** Presenter 不再继承算法协议，具体业务实现通常无需修改。只在确实将 Presenter 交给独立算法的 helper 中补适配；不要为保持旧继承关系又给整个 Presenter 层挂回 diff 协议。
- **可合并的重复判断：** 自研 DataSource 若复制了 Cell / Header 视图类型比较、Supplementary 身份/位置兼容判断或 layout 捕获版本判断，可改用模型公开方法。兼容 Header 的视觉刷新可集中交给 `views.reconfigureSupplementaries(_:)`，无需复制内部 `configure` 与布局失效逻辑。这是接入时的检查项，尚未确认 Podcast 存在每一种重复实现。
- **必须保留：** 自研 DataSource 的阶段安装、结构差异处理、reload 决策、布局失效和完成时机；业务渲染合并、Shortcut 动画准备与失败清理也继续保留。`CollectionViews` 不负责制定更新策略，框架的最终行为重绑仍在 DataSource `apply` 返回后执行。

外部 DataSource 只能把身份、位置和视图类型均兼容的 Supplementary 交给批量刷新，使用已安装目标数据的坐标。仅行为变化不应伪装成视觉变化；最终绑定步骤会安装新的回调。`hasSameLayoutVersion(as:)` 比较一次捕获的身份，不能用业务高度恰好相等替代；`replacingCells(_:)` 才会保留原捕获版本。

Parade 的公开消费者测试已验证局部内容更新、兼容视图保留、Cell / Header 类型替换、仅布局变化、等内容重绑，以及 Source / `CollectionViews` 释放。它没有迁移或构建 Podcast；接入时须对真实自研实现逐项核对，不能把测试中的简化 DataSource 当作完整结构更新算法复制。

## 布局 API 的必改项与可简化项

- 现有 Compositional Section 将 `DefaultSectionContent` 改为 `LayoutContent<CompositionalSectionLayout>`；若自己实现 Content，则把 `makeLayout(in:)` 改为返回 `CompositionalSectionLayout` 的 `layout` 属性。原生 Section 构造逻辑可保留。
- Home 中显式声明的 orchestrator、store、definition、snapshot、data source 类型加上 `<CompositionalSectionLayout>`。共同子协议用 `where Layout == CompositionalSectionLayout` 约束；如果保存 `[any HomeSection]`，通过应用侧 `collectionSection` 出口逐元素转换，写法见 [布局迁移](LayoutIntegration.md#升级现有代码)。本轮发现直接转换带关联类型的子协议数组可编译却运行崩溃，不能只以编译通过为迁移验收。具体 Section 直接构造的数组无需改动。
- `CollectionOrchestrator(collectionView:)`、`compose/updating/apply`、Section 的 `update()` 保留。无需为了这次布局迁移再包一层提交方法。
- Flow / 自定义布局可以通过 `LayoutAccess.item(at:as:)` 读取当前阶段的具体 Presenter，按已捕获的 Section 布局设置计算尺寸。以此替代仅为布局复制的“Section 下标 → 最新业务数组 → Presenter”路由；删除前须确认没有承载业务状态或跨快照缓存。
- 公共 Flow 接入已经处理六个原生 sizing/inset/spacing/header/footer 查询，若应用已有相同的转发表，可以替换为 `FlowSectionLayout` 的具体 delegate 工厂。自定义 Flow 协议仍需库外 `CollectionLayout` 适配，不会自动转发任意 delegate 方法。
- 继续保留业务布局算法、bounds 失效规则、Cell 内部布局、自适应尺寸和滚动补偿。布局接入不提供通用滚动位置保持；也不应把捕获后的 delegate 工厂改为读取活的 Section。

目前这些收益已在 Parade 的独立公开消费者和两种内置 data source 上验证。本文没有证明 Podcast 中某个自建 Collection 已适配，也没有执行其项目构建；接入 agent 应先重新核对实际代码，再按具体调用处删除重复逻辑。

## Podcast 迁移验收

以下均为待执行项。Parade 的单元测试及示例通过，不代表 Podcast 已完成集成验证。

- [ ] 记录实际升级到的 Parade revision/tag，以及 Podcast 的同步方式和 revision；确认内嵌实现包含新的 reconcile 语义。
- [ ] 搜索旧协议、属性、提交入口和绑定方法，逐项区分框架调用与同名业务方法；所有目标平台通过编译。
- [ ] 若使用自研 DataSource，核对 `CollectionViews` 接入、泛型约束和当前阶段查询；覆盖兼容视图内容刷新、同 ID 更换视图类型、Header 结构变化、仅布局更新与释放。
- [ ] 两个首页验证首次加载、仅内容变化、增删/重排、空数据、刷新和加载更多；没有漏更新或重复提交同一批普通内容。
- [ ] 验证同 ID、同外观但回调变化；点击、播放、长按、Header / Supplementary 操作及画报手动绑定均使用新行为。
- [ ] Shortcut 覆盖未变化、可见内容变化、离屏更新、减少动态效果和 Socket 局部更新；检查引导、失败清理、移除后的订阅清理。
- [ ] Discovery 覆盖开屏交接中刷新、画报关闭与等待中的刷新；解锁后仍能呈现最新状态，画报交互和曝光没有丢失。
- [ ] 连续刷新、内容提交失败及重试期间，SectionStore 不重入；保留实例的业务状态和可见性回调符合预期。
- [ ] 回填实际删除了哪些代码、确认并修复了哪些误用、尚存哪些限制；记录测试环境，未验证项保持未勾选。

应用路径的基础记录来自 2026-10-02；Home / Story 的 Store 接入于 2026-11-06 重新静态核对。未运行 Podcast 构建、测试或 UI 验证。
