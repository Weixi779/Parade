# 滚动位置保持：调研与实测

研究日期：2026-09-29。基于 Parade `18a6eef` 的公开 API；本目录是独立实验，没有修改框架实现，也没有确定正式 API。

## 希望演示的效果

用户正在读第 21 条内容；列表上方插入、删除或调整模块后，第 21 条仍停留在原来的屏幕位置。这里选择一个可见内容作为参照，保持它相对于可视区域上沿的距离。

这个定义不同于保持 `contentOffset` 数值、跳回某个 IndexPath、聊天列表自动跟随底部或页面退出后的状态恢复。最终要支持哪些场景，仍需要讨论。

## 录屏与实测

录屏位于本机生成目录，不加入版本管理：

- [默认数据源，四场景完整演示，约 29 秒](../../.build/ScrollPositionStudy/default.mp4)
- [Diffable 数据源，四场景完整演示，约 29 秒](../../.build/ScrollPositionStudy/diffable.mp4)
- [Diffable 第一场景的 12 倍慢放，10.8 秒](../../.build/ScrollPositionStudy/diffable-slow-motion.mp4)
- [默认数据源坐标记录](../../.build/ScrollPositionStudy/default-measurements.json)
- [Diffable 坐标记录](../../.build/ScrollPositionStudy/diffable-measurements.json)

上下两组使用相同数据、相同 Compositional Layout 和同一种数据源。上方直接执行 Parade 的更新；下方在 `await apply()` 完成后，根据同一内容的 ID 与新布局恢复相对位置。对照组没有人为重设 offset。

每场更新前，第 21 条顶部都距离列表可视区域上沿 28 pt，橙线标记这个位置。前三个场景 `animated: false`，第四个为 `true`。两种数据源本轮的最终测量结果一致：

| 更新场景 | 对照组最终位置 | 实验组最终位置 | 观察 |
| --- | ---: | ---: | --- |
| 上方插入两条，各 64 pt | 156 pt，偏移 +128 | 28 pt，偏移 0 | offset 不变时，正在读的内容向下移动 |
| 上方模块从 192 增高到 352 pt | 28 pt，偏移 0 | 28 pt，偏移 0 | 这个更新路径下 UIKit 已经自动补偿 |
| 上方 192 pt 模块移到列表末尾 | -164 pt，偏移 -192 | 28 pt，偏移 0 | 对照组第 21 条移出可视区域 |
| 上方插入两条，开启动画 | 28 pt，偏移 0 | 28 pt，偏移 0 | 这个动画路径下 UIKit 已经自动补偿 |

不能根据这个表推导“所有尺寸更新都自动保持”或“所有无动画插入都会跳”。这些是当前系统、当前布局与当前更新实现的实测结果。

### 最终正确不代表过程正确

Diffable 第一场景中，下方实验组最终回到了 28 pt，但出现一帧先下移再回来的画面。原始视频解码结果：

- 2.695 秒的帧中，下方蓝色卡片顶部在图像 y≈2075 px；此前约为 1694 px。
- 2.706667 秒的下一帧，卡片顶部回到约 1694 px。
- 同时，CADisplayLink 的 presentation layer 采样记录到最大 128 pt 偏移。

像素差与布局点数会受圆角、压缩及像素判定阈值影响。这里同时使用视频画面和布局采样确认短暂偏移，没有把采样值直接当成屏幕呈现的证明。慢放来自原视频 2.35–3.25 秒片段，播放速度为原速的 1/12。

默认数据源在本轮实验组采样中未记录到偏移。这不构成跨系统或全部更新组合的无闪跳保证。锚点移出屏幕时，采样器无法读取其 cell；`sampledFrames == 0` 时，最大偏移为零也不表示没有偏移。

## 参考实现

研究时固定到下列提交，避免之后上游变化改变结论。

| 实现 | 具体做法 | 对 Parade 的启发与边界 |
| --- | --- | --- |
| [Texture ASTableView](https://github.com/TextureGroup/Texture/blob/d8aa8c796dd7770ea177989253ef1cf8878cd50a/Source/ASTableView.mm#L855-L891) | 保存首个可见 node 和其相对位置，更新后按 node 找回新 IndexPath，再补偿差值 | 直接、有明确限制：这条路径跳过动画更新和已删除的锚点。这是 TableView 实现，不能当作 ASCollectionView 的能力声明 |
| [React Native Fabric ScrollView](https://github.com/facebook/react-native/blob/d194d8b5c62a39af0f44648f3fe3b140c7fa90cc/packages/react-native/React/Fabric/Mounting/ComponentViews/ScrollView/RCTScrollViewComponentView.mm#L1060-L1155) | mount 前记录第一个可见子视图，mount 后检查复用、删除，再补偿 frame 差值 | 需要身份与生命周期校验；[公开文档](https://reactnative.dev/docs/scrollview#maintainvisiblecontentposition)明确提示重排存在跳动问题，不能直接推广为任意 reorder 保证 |
| [MagazineLayout 的锚点状态](https://github.com/airbnb/MagazineLayout/blob/a45a664a68ee81f3961416615ef738d72b99e02f/MagazineLayout/LayoutCore/LayoutState.swift)及[布局实现](https://github.com/airbnb/MagazineLayout/blob/a45a664a68ee81f3961416615ef738d72b99e02f/MagazineLayout/Public/MagazineLayout.swift) | 保存内部 item ID、边缘和相对距离，优先选择已完成尺寸测量的完整可见内容；在 batch、目标 offset、尺寸失效阶段协调补偿 | 实现位于自定义 layout 内，持有更新前后几何信息。它不只是一个更新完成回调 |
| [ChatLayout](https://github.com/ekazaev/ChatLayout/blob/dd4cb5c8f91623331ba023d0ab64d844f8436204/ChatLayout/Classes/Core/CollectionViewChatLayout.swift) | 提供位置 snapshot/restore，通过 invalidation 恢复；布局内部也处理 batch、动态尺寸及底部保持 | 同样依赖自定义 layout。公开位置 snapshot 保存 IndexPath、边缘和距离，不能把它描述成天然按业务 ID 跨任意重排恢复 |
| [IGListKit IGListAdapter](https://github.com/Instagram/IGListKit/blob/23650fad95a99fa89bbe763250b75770dcd43bcf/Source/IGListKit/IGListAdapter.m) | 提供查找可见项、获取偏移、滚到对象并增加偏移的接口 | 可参考基础操作与命名，但这些方法本身不是自动贯穿更新事务的位置保持 |

UIKit 提供 [`targetContentOffset(forProposedContentOffset:)`](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/targetcontentoffset(forproposedcontentoffset:)) 和 invalidation context 的 [`contentOffsetAdjustment`](https://developer.apple.com/documentation/uikit/uicollectionviewlayoutinvalidationcontext/contentoffsetadjustment)。后者表达增量，不是绝对目标 offset。它们是布局参与补偿的入口，不能仅凭 API 存在就推导 Compositional Layout 在所有更新阶段都能无缝配合。

## 与 Parade 当前结构的关系

已经确认的代码事实：

- `CollectionOrchestrator.execute` 串行执行提交；一次提交完成后才同步显示状态并通知调用方。
- 默认数据源的一次 `apply` 可能包含多个结构 batch，之后再执行内容/布局更新。
- Diffable 数据源等待原生 snapshot apply，随后更新 supplementary、invalidate layout 并执行布局。
- 框架已有稳定的 presenter ID、ID 到 IndexPath 的查询，以及当前布局几何信息。

因此，候选方向是由 orchestrator 管理一次提交的位置保持意图和锚点身份，让实际更新/布局阶段参与补偿。只在 data source 添加一个完成回调，尚不足以解决中间帧问题。是否需要修改数据源协议，取决于下一步 Compositional Layout 时序实验，当前不作结论。

### 几何计算

实验采用以下计算；只讨论纵向主列表：

```text
distance = oldFrame.minY - oldContentOffset.y - oldAdjustedContentInset.top
desiredOffset.y = newFrame.minY - newAdjustedContentInset.top - distance
```

将目标 offset 限制在合法范围，再相对于系统更新后的实际状态进行补偿。不能直接累加插入内容的高度或 `contentSize` 差值：变化可能发生在锚点之后，UIKit 也可能已经完成了补偿。

作为候选设计，锚点应在提交真正轮到执行、即将改变 UIKit 状态时采集。业务数据在 `.apply()` 时捕获与视口位置在队首执行时捕获，是不同的时机：排队期间，用户可能继续滚动，前一个提交也可能改变了视口。该判断来自现有 FIFO 结构，尚未实现于框架。

## 下一步需要讨论的边界

首要区别是：保证更新结束后的相对位置，还是保证更新期间的阅读内容没有可见跳动。完成后补偿已经在这四组场景中展示了前一种效果，也暴露了后一种效果的不足。

建议先讨论“普通纵向列表，更新发生在正在读的内容之前”的连续阅读目标。若确认需要作为正式框架能力，应先验证 Compositional Layout 下的布局阶段补偿时机，再决定 API 和实现成本，避免先发布一个暗示全面保证的开关。

以下仍是未决定的行为，不自动纳入 1.0：

- 锚点被删除、替换或自身参与重排时，选择邻居、维持 offset，还是放弃恢复。
- 更新时用户正在拖动或减速时，是否以及如何介入。
- 动态高度在提交完成之后再次变化时，是否继续保持。
- 键盘、安全区、顶部/底部边界和内容不足一屏时的优先级。
- 页面状态恢复、底部跟随、横向 orthogonal section 的独立滚动状态。

上述未知项不影响当前录屏的有效性，也不能被当前录屏视为已经支持。

## 复现

本次环境：Xcode 27、iOS 27 Simulator，设备 `SectionPresenter Demo`，UDID `7A2982CC-60E7-4462-9EF1-7A5DB0FBA20B`。源码目标最低 iOS 16，但本次没有在 iOS 16 或真机上运行。

从仓库根目录构建：

```sh
python3 Demos/ScrollPositionStudy/build.py
```

脚本直接编译当前 Parade 源码和独立 UIKit app，不修改 Package.swift。生成位置：`.build/ScrollPositionStudy/ScrollPositionStudy.app`。

将下列 `SIMULATOR_UDID` 替换为明确选定的模拟器；不要在多个设备启动时使用模糊的 `booted`：

```sh
xcrun simctl install SIMULATOR_UDID .build/ScrollPositionStudy/ScrollPositionStudy.app
xcrun simctl launch --terminate-running-process SIMULATOR_UDID dev.weixi.parade.scroll-study --autoplay
```

增加 `--native` 切换到 Diffable 数据源；不传 `--autoplay` 时点击“播放四个场景”。运行完成后，app 数据目录的 `Documents/measurements.json` 保存当前这一轮的八条坐标记录；再次运行会覆盖它。

可在启动前另开终端录屏，完成后按 Ctrl-C 正常结束编码：

```sh
xcrun simctl io SIMULATOR_UDID recordVideo --codec=h264 .build/ScrollPositionStudy/recording.mp4
```

验证范围：两个数据源、四个固定高度场景、真实 UIKit 布局、最终坐标与 presentation layer 采样、原始录屏帧解码。没有为这次调研运行框架完整测试；没有验证动态自适应高度、锚点删除、用户拖动、键盘或其他系统版本。
