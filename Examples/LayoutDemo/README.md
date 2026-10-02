# LayoutDemo

直接用 Xcode 打开 `LayoutDemo.xcodeproj`，选择 **LayoutDemo** scheme 和 iOS 模拟器运行。项目引用仓库根目录的本地 Parade 包。

应用展示三条路径：Compositional 返回原生 Section 布局、两个具体 Flow delegate 共存、自定义瀑布流协议在库外接入。点击“运行演示”依次更新尺寸、重排 Section / item、将瀑布流从两列改为三列。scheme 中启用 `--auto-demo` 可自动执行。

- [Demo.swift](Demo.swift)：集合创建和提交更新。
- [Sections.swift](../../Tests/LayoutSupport/Sections.swift)：Compositional / Flow Section、具体 Presenter 和 delegate。
- [Waterfall.swift](../../Tests/LayoutSupport/Waterfall.swift)：自定义 layout、协议和适配层。
- [布局契约及迁移](../../Docs/LayoutIntegration.md)：核心源码入口与接入成本。

两个支持文件也被独立的测试消费者模块使用，只导入公开 Parade API。它们是可运行的接入示例，瀑布流算法不作为通用布局产品提供。

从仓库根目录构建（替换设备 ID）：

```sh
xcodebuild -project Examples/LayoutDemo/LayoutDemo.xcodeproj -scheme LayoutDemo \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_DEVICE_ID' \
  -derivedDataPath .build/LayoutDemo CODE_SIGNING_ALLOWED=NO build
```

自动运行结束后，应用数据目录 `Documents/layout-study.json` 保存六个步骤的实际 cell frame、revision 和显示回调数。该报告便于核对几何变化，不代替动画质量或性能测量。

外部类型检查可独立运行：

```sh
python3 Tests/check_layout_types.py
```

脚本针对当前正式源码构建公开消费者，验证正确调用可以编译，错误的 Section 布局类型、data source 类型、不遵循原生 Flow 协议的 delegate、覆盖保留回调都会被编译器拒绝。结果写入 `.build/LayoutAPIChecks/results.json`。
