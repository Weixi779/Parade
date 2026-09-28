# Section 布局组装验证

2026-10-02。**这是可运行的设计实验，不是 Parade 已发布或已合入的 API。**

先看代码可从 [核心源码导航与真实 diff](Review.md) 开始；[生成的 Swift Package](../../.build/LayoutCompositionStudy/Package/Package.swift) 可直接用 Xcode 打开。

## 结论

“Section 返回明确的布局值”和“Section 提供符合特定 delegate 协议的具体对象”可以共存于同一套 Section / capture / update 模型中。每个 Section 只实现所选布局需要的那一种形式。

实验把 `Layout` 作为 `SectionContent` 的关联类型，并在集合组装处约束相同类型。调用方不用写 `any`，也不用对 layout payload 做 `as?`。混入不匹配的 Section、data source 或 delegate 会编译失败。

**这不等于消灭内部的类型擦除。** 异构 Section 仍以受 `Layout` 约束的 existential 存储；Flow 接入层通过泛型构造函数捕获具体 delegate，再用本布局协议对应的查询闭包保存它。UIKit 原生协议参数也仍有 existential 语义。闭包捕获是另一种擦除方式，不能把它宣传成“全链路没有擦除”。

| 路径 | Section 提交什么 | 接入层负责什么 | 运行结果 |
| --- | --- | --- | --- |
| Compositional | 返回原生 `NSCollectionLayoutSection` 的具体 builder 值 | 用当前 section 索引取出捕获版本并调用 builder | 92 → 140 pt 布局更新正常 |
| Flow | 工厂返回具体 `NSObject + UICollectionViewDelegateFlowLayout` | 按当前 section 路由原生 sizing / spacing / supplementary 回调 | 两种 Section、两种 delegate 混合，重排和尺寸更新正常 |
| 自定义瀑布流 | 工厂返回符合库外 `WaterfallDelegate` 的具体对象 | 库外 adapter 把自定义协议连接到 Section 的捕获版本 | 双列 → 三列正常，不需修改 Parade 核心来认识该协议 |

统一的是**带类型的组装和捕获边界**。具体几何协议仍属于相应 layout，不强行设计一个能描述所有布局的参数表或枚举。

这里 `Layout` 绑定的是 `FlowSectionLayout` 这样的布局接入类型，**不是** `CardFlowDelegate` 或 `BannerFlowDelegate` 各自的具体类。否则不同 delegate 的 Section 又无法放到同一个集合。具体类由泛型工厂接收，必要的擦除只发生在相应布局协议的接入处。

## 实际调用形式

下面的组合已从独立 consumer module 编译，并在模拟器上运行。`FlowCards` 和 `FlowBanner` 是两个不同的 SectionController 类型，使用不同的具体 delegate 类型。

```swift
let collection = CollectionOrchestrator(
    collectionView: collectionView,
    layout: .flow()
)

try await collection
    .compose([banner, cards])
    .updating([cards])
    .apply(animated: true)
```

Section 的输出为 `LayoutContent<FlowSectionLayout>`，内部保留原生协议写法：

```swift
let scale = scale
let columns = columns

return LayoutContent(
    cells: cards.map(AnyCellPresenter.init),
    layout: FlowSectionLayout { access in
        CardFlowDelegate(
            access: access,
            columns: columns,
            scale: scale,
            log: log
        )
    }
)
```

`CardFlowDelegate` 直接遵循 `UICollectionViewDelegateFlowLayout`。Section 决定列数、比例和布局行为，adapter 只路由协议，不拥有这些业务规则。

原来的 `section.update()`、`compose(...).updating(...).apply()` 调用流程不需要改变。类型出现在 Section 的输出、集合的存储属性以及自研 data source / store 的声明上。

源码入口：

- [SectionContent 关联类型](Overlay/SectionContent.swift)
- [组装、Compositional 和 Flow 接入](Overlay/CollectionLayout.swift)
- [具体 Section 与原生 Flow delegate](Support/Sections.swift)
- [完全定义在库外的自定义 layout、协议和接入](Support/Waterfall.swift)
- [运行测试](Tests/LayoutTests.swift)

## 必须保留的两个语义

**布局配置在提交时捕获。** 不能让延迟构建 delegate 的闭包再去读 Section 的实时 `scale` / `columns`。实验先复制这些值。队列测试提交 2 倍、3 倍尺寸后立刻把业务状态改为 99 倍，两个完成点仍分别得到 160、240 pt。

**item 查询与 data source 的当前 UIKit 阶段一致。** 有了固定的布局配置，也不能再用捕获的旧数组按当前 `indexPath.item` 取 item。手工 data source 会产生中间快照；实验通过 `LayoutAccess.item(at:as:)` 取当前阶段的具体 presenter，类型转换在查询边界内部完成。Section 和 item 同时重排、跨 Section 移动时，最终坐标与尺寸正确。

回看此前关于 Section 生命周期和 presenter 能力的讨论后，保留了两个约束：业务布局属于 Section；新布局协议由它自己的接入层识别，核心不累加各家协议的分支。

## 代价与未定接口

这条方向可行，但本原型不能直接当成最终 public API 合入。

1. **泛型传播范围较大。** 为直接验证编译期约束，本实验让 `Layout` 贯穿 Controller、Content、Snapshot、DataSource、Update、Store，生成副本触及 17 个现有文件并增加一个布局接入文件。这是当前原型的实现成本，不是这些内部类型在最终版都必须公开泛型的证明。正式方案应审视是否把内部擦除收在更窄的位置；改写自研 data source 的迁移成本必须计入。
2. **接入层需要明确 delegate 所有权。** Flow 和这里的自定义 layout 都从 `collectionView.delegate` 查询；实验用 bridge 子类添加布局协议，继承原来的交互、绑定和显示处理。把整个 `CollectionViewBridge` 公开为可继承类过宽，正式接口需要收窄到布局扩展真正依赖的能力。
3. **每种布局协议需要自己的接入代码。** Swift 不能凭空把任意未知协议转发给对应 Section。Flow 接入覆盖它的六个原生尺寸/间距方法；新协议的 adapter 放在库外或独立 target 即可，但不会自动获得支持。
4. **delegate 应是捕获版本的查询对象。** 直接把可变 Section 本身作为 delegate，虽然可能编译，也会重新引入队列串读。Flow 原型按捕获版本缓存 delegate；瀑布流演示使用廉价的查询对象工厂。正式方案还要固定工厂调用次数、缓存范围、复用和释放约定。

这里验证了通过 `collectionView.delegate` 扩展布局协议的模式；没有验证另设 `layout.delegate` 属性的第三方库接入。没有验证第三方 layout 的所有可选回调、Flow estimated self-sizing、旋转、拖拽、复杂 decoration/pinning、滚动位置保持、性能或 iOS 16 运行表现。自定义瀑布流只是最小算法示例，动画和失效策略仍归 layout 自己负责。

Swift 6.4 的实验编译还遇到两个实现细节：泛型类的 Objective-C 方法需放在类体内；一个 constrained existential key path 触发编译器断言，改成等价闭包后通过。这些修正只存在于生成副本。

## 验证结果

- Xcode 27.0 / Swift 6.4，iPhone 18 Pro 模拟器，iOS 27.0；编译最低目标 iOS 16。
- Swift Testing：**10 个参数化测试、20 组运行全部通过**。两种 data source 分别执行相同测试，零失败、零跳过。
- 覆盖：异构 Section / delegate 组装、header、布局单独更新、保留捕获版本、FIFO 捕获、Section 和 item 重排、跨 Section 移动、增删、Flow 原生默认值、SectionStore 复用、自定义瀑布流、delegate 释放。
- 点击路径由测试显式调用已安装的 UIKit delegate 后核对 presenter 回调；显示回调来自实际窗口和 collection view。没有用手指点击的 UI 自动化测试，不将两者混称。
- 编译检查：正确业务调用通过；错误布局 Section、不符合协议的 delegate、错误布局 data source 均按预期失败。
- 独立 demo 完成 6 个状态，记录 22 次显示回调；逐项核对高度、重排后坐标和瀑布流列数。
- 本轮不重跑生产包原有 133 个测试；运行的是生成实验包的 20 组用例。生产 `Sources/Parade` 的 39 个文件未由本实验修改，保留工作区此前的 public API 调整。

机器记录： [测试摘要](Results/tests.json)、[编译检查](Results/typechecks.json)、[demo 的实际 frame](Results/demo.json)。

本机完整测试 bundle：`/private/tmp/ParadeLayoutStudy-02.xcresult`。
22.5 秒演示：`/Users/sunshiwei/.codex/visualizations/2026/09/28/01a0e551-37ad-72c2-b838-879828715ca4/layout-composition-demo.mp4`。

## 复现

实验以当前工作区源文件为输入，只把修改写入 `.build/LayoutCompositionStudy/Package`。不要把生成副本直接覆盖回正式源码。

在 Parade 根目录运行：

```sh
python3 Demos/LayoutCompositionStudy/build.py --app
python3 Demos/LayoutCompositionStudy/check_types.py
```

在 `.build/LayoutCompositionStudy/Package` 运行（将设备 ID 换为实际设备）：

```sh
xcodebuild test \
  -scheme LayoutCompositionStudy-Package \
  -destination 'platform=iOS Simulator,id=7A2982CC-60E7-4462-9EF1-7A5DB0FBA20B' \
  -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/ParadeLayoutStudyDerived
```

demo 应用产物：`.build/LayoutCompositionStudy/LayoutCompositionStudy.app`；Bundle ID：`dev.weixi.parade.layout-study`。安装后使用 `--auto-demo` 启动会播放六步过程，也可以点击“重播验证过程”。运行结果写在该应用 Documents 目录的 `layout-study.json`。
