# Podcast 升级迁移与简化交接

这份文档供升级 Podcast Collection 层的开发者和 agent 使用，记录必须迁移的 API、升级后可以删除的重复代码，以及使用审查中需要继续核对的地方。后续 Parade 功能落地时，应同步补充对应的 Podcast 简化项；发布前再按最终版本核对一次。

Podcast 提供真实使用场景，Parade 仍负责定义通用的框架契约。应用现有写法是评估依据，不限制框架改进；也不能把应用业务逻辑直接当作框架应承担的职责。

## 适用版本与接入位置

Parade 契约更新至 **2026-10-03** 的 DataSource 解耦重构，包含此前 public API 整理及正式布局实现，属于未发布开发 API。Podcast 最后一次源码核对为 **2026-10-02**，对照本地 `3eaa6a714` 工作区；本轮没有重新核对或修改 Podcast。执行迁移时须重新确认两边版本，不把本文当作已发布 1.0 的能力清单。

Podcast 的 Home 代码当前导入 `XYZFoundationUI`，Collection 实现在该仓库的 `Submodules/XYZFoundationUI/Sources/XYZFoundationUI/Collection/` 中。其 Package 当前没有外部依赖。因此，单独升级 Parade 包版本不会自动迁移这份实现：应先确认继续同步源码，还是调整模块依赖，再迁移调用方。

下文路径均相对于 **Podcast-iOS 仓库根目录**。Parade 的完整 API 变更见 [CHANGELOG](../CHANGELOG.md#unreleased)，框架验证范围见 [Verification](Verification.md)。本文只记录迁移方案，尚未修改或验证 Podcast 应用。

## 必须迁移的 API

| 原用法 | 开发版用法 | 迁移要点 |
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

## 升级后可以合并的提交

新 `SectionStore.reconcile(_:apply:)` 对每次有效 reconciliation 都执行回调，包括仅内容变化、顺序不变和空目标。Podcast 当前副本只在结构变化时执行回调。**同步这项语义变化后，才能把 retained 内容更新全部移入回调。**

`compose` 提供完整目标顺序，新实例捕获当前内容；保留实例的内容只有被 `updating` 选中才会更新。因此，只将 `setSections` 改名而删除后续内容更新，会漏掉 retained 的内容变化。

### Discovery 首页

位置：`Podcast/App/Features/Home/Discovery/Controller/HomeDiscoveryViewController.swift` 的 `render(_:animated:)`。

原有流程是 `reconcile → setSections`，返回后再判断 `retained` 非空并调用 `orchestrator.update`。升级后可替换为：

```swift
try await sections.reconcile(makeSectionDefinitions(from: state.sections)) { change in
    try await orchestrator
        .compose(change.controllers)
        .updating(change.retained)
        .apply(animated: animated)
}
```

可删除外层 `let change`、`retained.isEmpty` 判断和第二次内容提交。后面的取消检查、加载状态、占位内容和阅读状态通知保持原有顺序。

这是合并为一次逻辑提交和完成边界；数据源内部仍可能分阶段更新 UIKit，不承诺只有一个 batch。原写法适配旧契约，属于升级后的简化点，不能据此认定原来使用错误。

### Featured 首页

位置：`Podcast/App/Features/Home/Featured/Controller/HomeFeaturedViewController.swift` 的 `renderContent(_:)`。

普通 retained Section 可以与结构一起提交。Shortcut 当前还有自有的更新过程，先保留它的独立入口。下例假定业务具体类也已改为 Controller 后缀：

```swift
let change = try await sections.reconcile(makeSectionDefinitions(for: state)) { change in
    let contentUpdates = change.retained.filter {
        !($0 is HomeFeaturedShortcutSectionController)
    }
    try await orchestrator
        .compose(change.controllers)
        .updating(contentUpdates)
        .apply(animated: state.hasLoaded)
}
for case let shortcut as HomeFeaturedShortcutSectionController in change.retained {
    try await shortcut.updateContent(animated: state.hasLoaded)
}
```

可删除普通内容的第二次 `orchestrator.update` 及其非空判断。Episode / Pilot 的 `contentDidUpdate()`、页面占位及阅读状态通知继续放在相关提交完成之后；尚无证据表明这些业务通知可由框架自动替代。

Shortcut 的实现位于 `Podcast/App/Features/Home/Featured/Sections/Shortcut/Presentation/HomeFeaturedShortcutSectionPresenter.swift`。`updateContent(animated:)` 除了调用 Section 更新，还维护 `submittedSection`，准备发生视觉变化的可见 Cell，处理动画失败清理、页面可见性和引导调度。没有内容变化时直接返回；没有合适的可见 Cell、页面不可见或开启减少动态效果时，也可能不播放动画。不能把它理解为“每次更新都要动画”。

把 Shortcut 也合入同一次提交，是后续可评估的简化方向：需要先确定如何保留“准备 → 提交 → 成功后播放 / 失败后清理”的职责，以及 Socket 触发的 Section 自主更新。本次链式 API 没有新增这组业务钩子，不应仅为减少一次调用而绕过现有过程。

## 使用审查与仍需保留的职责

以下区分当前确认的契约和待核实的应用问题，避免把所有可疑写法都升级为缺陷结论。

| 位置或现象 | 当前判断 | 后续处理 |
| --- | --- | --- |
| 两个首页的结构、普通 retained 内容分两次提交 | 已确认可在新契约下简化 | 按上面的示例合并；不要在合并后保留同一批内容的旧提交。 |
| 旧 `setBehaviors` 留在新协议实现中 | 已确认的迁移风险 | 核对方法实现及手动调用，验证真实交互；编译成功不足以验收。 |
| Discovery `schedulePendingRender()` 等待下一轮再检查 `isApplying` | 当前契约下不能据此判定多余 | `onDidApply` 和提交 completion 内仍可能是 `isApplying == true`；它们不是队列空闲通知。本批没有改变这个契约，不删等待逻辑。 |
| Featured `pendingState` / `renderTask` | 承担业务输入合并和串行 reconciliation | 保留。框架 FIFO 排队的是已捕获的提交，不能替代提交之前的业务状态管理。 |
| Discovery `lockedPictorial`、`isRendering`、`needsRender` | 包含开屏交接和应用渲染协调 | 保留。逐项追踪职责后再判断能否简化，不因链式 API 直接删除。 |
| Shortcut 的绑定和 `willDisplay` 都调用 `onCellUpdate` | 待核实，不能仅凭重复调用认定误用 | 当前用于登记 Cell 和引导锚点；检查重复登记/调度是否幂等。曝光周期与等内容重绑定并不等价。 |
| EditorPick 在行为绑定里设置购买/阅读相关状态 | 待核实职责归属 | 追踪字段如何影响 UI、相等性和实时观察，再判断归 `configure` 还是绑定；改名时先保持行为。 |

`SectionStore` 接受新成员关系要等待回调成功，但已经写入 retained Controller 的业务输入不会自动回滚。合并提交不等于业务状态事务；失败重试和串行 reconciliation 仍需遵守 [实现契约](ImplementationContract.md)。

同样，布局和 Cell 内容必须来自同一份已捕获展示版本。不能为减少模型复制，让捕获后的 layout 闭包重新读取可变 Section 状态。UIKit 更新中的查询可能对应中间阶段，不能直接拿应用最新 Store 下标替代。

## 后续能力落地时继续补充

| 议题 | 当前状态 | 届时要回答的 Podcast 迁移问题 |
| --- | --- | --- |
| Flow Layout / 自定义 `UICollectionViewLayout` | 正式开发 API 已实现，见下方迁移说明和 [布局契约](LayoutIntegration.md)；尚未迁移 Podcast | 核对实际自建 Collection 的协议和回调，确定适配代码可删范围；每个 Section 只提供自己所属布局类型，不要求写两套。 |
| Diff 算法和 DataSource 的命名、可替换边界 | 已完成本轮职责解耦；`StagedCollectionDataSource`、`CollectionViews` 和公开模型判断已实现，仍为同一个 target | 按下方说明迁移工厂和泛型约束；实际删除范围需在 Podcast 接入时确认。 |
| 滚动位置保持 | 尚无可交付的自动保持 API | 在实际支持的布局和更新场景中，哪些位置记录/恢复代码可删除；哪些仍由业务布局处理。 |
| 队列空闲通知 | 讨论项，尚未增加 API | 是否确实能简化 pending render，先给出已实现契约和使用证据。 |

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

## 布局开发 API 的必改项与可简化项

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

应用路径基于 2026-10-02 的源码静态核对，后续框架变更按当前实现补充；未运行 Podcast 构建、测试或 UI 验证。
