# Codex94 v0.1.6 状态语义分离升级计划

> 文档日期：2026-08-24
> 目标版本：`v0.1.6`
> 前置版本：已独立发布并验证的 `v0.1.5` 兼容修复
> 计划性质：可直接交给 Codex 执行的本地代码升级规格
> 本文不授权：合并 PR、推送远端、创建或移动 tag、创建 GitHub Release、安装或替换本机 App

---

## 0. 文档定位与冲突处理

本文基于原升级文档 `CODEX94_UPGRADE_PLAN_V0.2.md` 中的“状态语义分离”建议，结合已发布的 `v0.1.5` 源码基线重新整理。

原文档是规划参考，不是高于用户请求的执行指令。本计划对它作出以下明确修订：

1. 原定发布为 `v0.1.5` 的“额度严重度与连接/数据新鲜度分离”，整体顺延到 `v0.1.6`。
2. `v0.1.5` 只承载已经发布的 Codex 0.149 兼容、多额度桶、cache v2 和偏好迁移修复。
3. 原文中的固定参数 `-a untrusted` 已过时；`v0.1.6` 必须继承 `v0.1.5` 已修正的固定参数：

   ```text
   codex -s read-only -a never app-server --stdio
   ```

4. 原文中属于 `v0.2.0`、`v0.2.1` 或更远版本的建议，均不进入本次升级。
5. 实施时的事实优先级为：用户当前指令 > 实际仓库与工具行为 > 本计划 > 原升级文档中的历史建议。

如果实际代码已经发生变化，Codex 应先报告差异并按本文的产品语义和安全边界调整落点，不得为了机械匹配文件名而覆盖新实现。

---

## 1. 当前核验快照

以下是 2026-08-24 开始执行前重新核验的仓库快照；后续恢复执行时仍必须再次核验：

- 兼容 PR #2 已合并为 `bc86017`，GitHub CI、CodeQL、Release gate 和
  `codex-cli 0.149.0-alpha.4` live smoke test 均已通过。
- 发布 PR #3 已合并；`main`、`origin/main` 与 annotated tag `v0.1.5`
  均指向或解引用到 `b1e6899`，不得移动或重建该 tag。
- `v0.1.5` 的两个 build configuration 均为：
  - `MARKETING_VERSION = 0.1.5`；
  - `CURRENT_PROJECT_VERSION = 6`。
- `v0.1.5` 已发布以下实现：
  - 固定 `-s read-only -a never app-server --stdio` 参数；
  - 多 `QuotaBucketSnapshot` 支持；
  - `rateLimitsByLimitId` 解析；
  - 动态菜单栏额度选择；
  - cache v2 与 v1 迁移；
  - `menuBarQuotaSelection.v2` 与旧 `displayMode` 迁移；
  - Popover 固定 `500 pt` 宽度并跟随当前额度内容的自然高度，同时保护
    header 顶部间距和对应布局测试；
  - 对应模型、缓存、AppStore、客户端和布局测试。
- 已发布 tag 内的 `SECURITY.md` 稳定版本文字曾遗漏更新；本前置文档 PR
  在 `main` 上纠正该文档事实，但不会移动或重建 `v0.1.5`。
- 状态颜色问题仍存在：stale 会把额度颜色覆盖为琥珀色。

因此，`v0.1.5` 已成为不可变的发布基线。开始 `v0.1.6` 功能实现前，
仍须先合并本前置文档 PR、确认工作区干净，并完成第 3 节的全部行为门。

---

## 2. v0.1.6 的唯一目标

`v0.1.6` 只解决一个问题：

> 将额度严重度与连接/数据新鲜度拆成两个独立、可测试、可访问的视觉语义轴。

升级后的含义必须稳定：

- 绿色、琥珀色、红色只表示剩余额度等级。
- 蓝色或青色的独立图标/Badge 表示刷新、缓存或连接不可用。
- stale 不得覆盖最后已知额度的颜色。
- 没有可用额度时显示灰色 `--`，不得伪装成 `0%`。
- 所有关键状态必须同时通过图标、文字或 accessibility label 表达，不能只依赖颜色。

### 2.1 明确纳入

- 纯值语义模型 `StatusPresentation`。
- 额度等级 `QuotaLevel`。
- 独立连接状态 `ConnectionBadge`。
- `AppStore` 为菜单栏窗口和 Popover 浏览窗口提供两个只读 presentation 投影，不改变刷新状态机。
- `Codex94Palette.quotaColor` 去除 stale 职责。
- 菜单栏状态视图接入双轴语义。
- Popover header 和 state banner 接入双轴语义。
- 英文、简体中文本地化。
- VoiceOver、Help/Tooltip 和组合 accessibility label。
- 纯逻辑单元测试、现有兼容回归测试和人工 UI 矩阵。
- `v0.1.6` 版本号、变更日志和源发布文档准备。

### 2.2 明确不纳入

- 菜单栏新增 compact、percent-only 或 ring-only 布局。
- 最后更新时间的全新常驻 UI；仅可复用现有 stale age。
- 睡眠/唤醒刷新策略。
- Retry、Dashboard 等新恢复操作。
- 本地通知。
- About/更新检查入口。
- ZIP、DMG、Homebrew、自动更新、GitHub Release workflow。
- Developer ID、notarization 或 stapling。
- JSON-RPC 全量强类型重构。
- cache v3 或任何 cache schema 改动。
- 新的偏好设置或 UserDefaults key。
- 直接 HTTP quota fallback、多账号、多个 `CODEX_HOME`。
- telemetry、analytics、崩溃上传或第三方运行时依赖。
- 将现有 AppDelegate/NSStatusItem/NSPopover 架构改写成新的 scene 架构。

若实施中发现上述非目标确实是完成本目标的必要条件，应先停止并说明原因，不能自行扩展范围。

---

## 3. 开工前置门：核验 v0.1.5 发布基线

### 3.1 必须满足的发布事实

在创建 `v0.1.6` 开发分支前，必须同时满足：

1. Codex 0.149 兼容修复已经过独立 PR #2 审查。
2. 兼容分支完整测试、Release build、静态安全检查和真实 Codex smoke test 均通过。
3. 兼容修复已经合并到 `main`。
4. `main` 上已形成不可变的 annotated tag `v0.1.5`。
5. `v0.1.5` 的两个 build configuration 都具有正确版本元数据：
   - `MARKETING_VERSION = 0.1.5`
   - `CURRENT_PROJECT_VERSION = 6`，或发布者实际选择的其他唯一构建号。
6. `CHANGELOG.md` 已把兼容改动从 `Unreleased` 移入有日期的 `0.1.5` 小节。
7. `README.md`、`README.zh-CN.md` 和 `SECURITY.md` 已将稳定源版本更新为 `v0.1.5`。
8. 工作区没有用户未提交改动。

已发布的 `v0.1.5` tag 中若只存在稳定版本文字遗漏，应在独立文档 PR 中
纠正 `main`，记录该历史例外，并保持 tag 不变。本前置文档 PR 合并后，
该修正可满足第 7 项，不得为修正文案移动或重建已发布 tag。

若任一条件不满足，Codex 应停止 `v0.1.6` 实现并列出缺项；不得把 `v0.1.5` 发布收尾和 `v0.1.6` 功能混入同一个提交或 PR。

### 3.2 不依赖单一 commit hash

兼容 PR 可能被 squash merge，因此不能只检查 `5e3d9a0` 是否为祖先。应同时验证行为标记：

- app-server 固定使用 `-s read-only -a never app-server --stdio`；
- `QuotaSnapshot` 支持多个额度桶；
- `rateLimitsByLimitId` 不会把独立额度合并；
- cache v2 可读写，旧 v1 cache 可迁移；
- `menuBarQuotaSelection.v2` 可从旧 `displayMode` 迁移；
- 多桶、weekly-only、quota-only 模式的既有测试通过。

### 3.3 建议只读核验命令

```bash
git status --short --branch --untracked-files=all
git log --oneline --decorate --graph -12
git tag --list --sort=-version:refname
git show --stat v0.1.5
git merge-base --is-ancestor v0.1.5 main
rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' Codex94.xcodeproj/project.pbxproj
rg -n '"-s", "read-only", "-a", "never", "app-server", "--stdio"' Codex94/Services/CodexAppServerClient.swift
rg -n 'rateLimitsByLimitId|menuBarQuotaSelection.v2|version: 2' Codex94 Codex94Tests
```

开工分支建议：

```bash
git switch main
git switch -c codex/v0.1.6-status-semantics
```

只有在前置门已满足且工作区干净时才执行建分支操作。不要自动 stash、reset 或覆盖用户改动。

---

## 4. 必须保留的 v0.1.5 边界

### 4.1 安全与隐私

`v0.1.6` 不得改变以下边界：

1. 不读取、记录或缓存 token、cookie、Keychain、认证存储、会话日志或 SQLite。
2. 不增加直接 quota HTTP endpoint。
3. 继续通过 Codex app-server 使用其现有登录状态。
4. 子进程不经过 shell，也不拼接任意用户文本。
5. 固定参数必须保持：

   ```text
   -s read-only -a never app-server --stdio
   ```

6. 保留环境清理、响应大小上限、各阶段超时、独立进程组和终止回收。
7. 不把 email、account ID、原始 RPC payload、完整自定义路径或 opaque `limitID` 放入新 UI、日志或 accessibility label。
8. cache 仍只保存必要的额度信息，并保持 owner-only 权限。
9. 获取失败只能表示为 stale 或 unavailable，不得本地估算“官方额度”。
10. 保持 Hardened Runtime 和现有 source-only 发布政策。

### 4.2 多额度桶与持久化

以下行为必须原样保留：

- 菜单栏使用 `store.menuBarQuota?.window`，而不是退回旧的单窗口字段。
- Popover header 使用当前浏览桶的 `store.viewedWindow`。
- Auto 继续跨 displayable buckets 和 windows 选择最低剩余额度。
- 显式选择、缺失选择 fallback、default bucket、named bucket 和 weekly-only 行为不变。
- 浏览 Popover 中的另一个桶不得悄悄改变菜单栏选择。
- 不改 cache v2 结构和偏好迁移 key。

### 4.3 macOS UI 架构

现有 AppDelegate 继续拥有 NSStatusItem、NSPopover 和 Dashboard 生命周期。状态语义应保留在 SwiftUI/纯值层：

- 不为本功能增加新的 AppKit bridge。
- 不把状态源复制到 AppKit 对象。
- `AppStore` 继续是刷新与状态协调的单一事实来源。
- View 只消费统一 presentation，不在多个视图里重复推断 stale、refreshing 或 quota level。
- 保留 v0.1.5 已发布的 Popover 固定 `500 pt` 宽度、随当前额度内容变化的
  自然高度、header 顶部间距和 `QuotaPopoverLayoutTests`；状态组件必须
  适配该布局，不能恢复会在短内容下留下大块空白的固定高度。

---

## 5. 状态语义合同

### 5.1 额度轴

| `remainingPercent` | `QuotaLevel` | 圆环/百分比/额度条颜色 |
| --- | --- | --- |
| `nil` | `unknown` | secondary/灰色 |
| `50...100` | `healthy` | 绿色 |
| `20...49` | `warning` | 琥珀色 |
| `0...19` | `critical` | 红色 |

边界必须通过单元测试固定：`nil`、`0`、`19`、`20`、`49`、`50`、`100`。

颜色函数不再接受 stale：

```swift
func quotaColor(for level: QuotaLevel) -> Color
```

也可保留一个只接收百分比的薄封装，但最终必须由 `QuotaLevel` 控制额度颜色，不能把连接状态重新传入。

### 5.2 连接/新鲜度轴

| 有效状态 | 菜单栏 Badge | Popover 表示 | 建议图形语义 |
| --- | --- | --- | --- |
| idle | 无 | Ready/就绪 | 无额外颜色 |
| connected | 无 | Connected/已连接 | 无额外颜色 |
| refreshing | 蓝色/青色 Badge | spinner + Refreshing/正在刷新 | `arrow.clockwise` 或同义旋转图形 |
| stale | 蓝色/青色 Badge | Cached/缓存数据 + age | `clock.fill` |
| unavailable | 蓝色/青色 Badge | 明确错误类别；额度为灰色 `--` | 与 stale 不同的断开图形 |

图标名称允许在实现时根据小尺寸清晰度微调，但 refreshing、stale、unavailable 必须通过形状可区分。

### 5.3 刷新优先级

`AppStore` 在已有 snapshot 时开始刷新，只会设置 `isRefreshing = true`，不一定把 `connectionState` 改为 `.refreshing`。因此只读取 `ConnectionState` 会漏掉常见刷新状态。

`StatusPresentation` 至少应接收：

```swift
remainingPercent: Int?
connectionState: ConnectionState
isRefreshing: Bool
```

Badge 决策优先级：

1. `isRefreshing == true` 或 `connectionState == .refreshing` → `.refreshing`
2. 否则 `connectionState == .stale` → `.stale`
3. 否则 `connectionState == .unavailable` → `.unavailable`
4. idle/connected → `.none`

`usesCachedData` 独立记录 `.stale` 事实。这样 stale snapshot 重试中可以显示刷新 Badge，同时 accessibility 或 Popover 文案仍能说明当前数字来自缓存。

### 5.4 建议纯类型

新增 `Codex94/Support/StatusPresentation.swift`：

```swift
enum QuotaLevel: Equatable, Sendable {
    case unknown
    case healthy
    case warning
    case critical
}

enum ConnectionBadge: Equatable, Sendable {
    case none
    case refreshing
    case stale
    case unavailable
}

struct StatusPresentation: Equatable, Sendable {
    let quotaLevel: QuotaLevel
    let connectionBadge: ConnectionBadge
    let usesCachedData: Bool

    init(
        remainingPercent: Int?,
        connectionState: ConnectionState,
        isRefreshing: Bool
    )
}
```

为避免 Popover 再次解析底层枚举，presentation 也可以附带只读的 `lastSuccess: Date?` 和 `issue: ConnectionIssue?`。这些字段只承载显示上下文，不改变 `AppStore` 状态机。

这段只是职责合同，不要求逐字复制。硬要求是：

- 类型不依赖 SwiftUI 或 AppKit；
- 输入相同必定输出相同；
- View 不复制阈值和状态优先级；
- quota level 不受 connection state 影响；
- refreshing 判定包含独立的 `isRefreshing`；
- 测试比较枚举语义，不直接比较 SwiftUI `Color`。

---

## 6. 计划文件落点

### 6.1 建议新增

- `Codex94/Support/StatusPresentation.swift`
- `Codex94/Views/Components/ConnectionBadgeView.swift`
- `Codex94Tests/StatusPresentationTests.swift`

### 6.2 必须修改

- `Codex94/Stores/AppStore.swift`，仅增加只读 presentation 投影
- `Codex94/Support/Theme.swift`
- `Codex94/Views/MenuBar/MenuBarStatusView.swift`
- `Codex94/Views/MenuBar/QuotaPopoverView.swift`
- `Codex94/Localizable.xcstrings`
- `Codex94.xcodeproj/project.pbxproj`
- `Codex94Tests/AppStoreTests.swift`
- `CHANGELOG.md`
- `README.md`
- `README.zh-CN.md`
- `SECURITY.md`

### 6.3 仅在确有可见变化时更新

- `docs/images/readme/menu-bar.png`
- `docs/images/readme/popover-en.png`
- `docs/images/readme/popover-zh-Hans.png`

截图必须使用脱敏、非真实账号和非真实 quota 数据。若不更新截图，应在 PR 说明中解释现有截图为什么仍准确。

### 6.4 不应修改

除非编译或测试证明确有必要，以下文件不属于本功能：

- `Codex94/Services/CodexAppServerClient.swift`
- `Codex94/Services/SnapshotCache.swift`
- `Codex94/Stores/PreferencesStore.swift`
- app-server parser 与 quota bucket model
- 安装、打包、发布 workflow

`AppStore.swift` 只允许增加基于现有 `menuBarQuota?.window` 和 `viewedWindow` 的只读 presentation 计算属性；不得借机改写刷新、失败、选择 fallback 或隐私状态机。上述其他文件若出现在 diff 中，Codex 必须逐项说明必要性；无法说明则回退该无关改动。

### 6.5 Xcode project membership

当前工程手工枚举源码，没有自动同步文件夹。每个新增 Swift 文件都必须加入：

1. `PBXFileReference`
2. `PBXBuildFile`
3. 正确的 production 或 test group
4. 对应 target 的 `PBXSourcesBuildPhase`

特别要确认 `StatusPresentationTests.swift` 真正加入 `Codex94Tests` target。仅仅把文件放进目录并不能保证测试会被运行。

---

## 7. 分阶段实施计划

每个阶段结束后都要：

1. 检查 `git status --short` 和本阶段 diff。
2. 确认没有覆盖用户改动或引入计划外文件。
3. 运行本阶段相关的最小测试。
4. 记录已完成、测试结果、剩余风险和下一检查点。

### 阶段 0：冻结 v0.1.5 基线

目标：证明 `v0.1.6` 建立在真实的 `v0.1.5` 之上。

执行：

1. 完成第 3 节全部前置检查。
2. 阅读：
   - `docs/PROJECT_ARCHITECTURE.md`
   - `docs/RELEASING.md`
   - `SECURITY.md`
   - `PRIVACY.md`
   - `Codex94/Stores/AppStore.swift`
   - `Codex94/Models/QuotaModels.swift`
   - `Codex94/Support/Theme.swift`
   - 两个 MenuBar view
   - `Codex94Tests/QuotaPopoverLayoutTests.swift`
   - 现有 tests
3. 从已发布的 `v0.1.5` 主线创建 `codex/v0.1.6-status-semantics`。
4. 记录基线测试数量，但不要把数量写成永久 gate；以后以实际发现数量为准。

完成标准：

- v0.1.5 tag、版本、行为标记和完整 gate 一致。
- 分支基于 v0.1.5 后的 main。
- 工作区无未知改动。

### 阶段 1：先写纯语义与单元测试

目标：在不触碰 UI 的情况下固定全部状态合同。

执行：

1. 新增 `QuotaLevel`、`ConnectionBadge`、`StatusPresentation`。
2. 新增 `StatusPresentationTests`。
3. 在 `AppStore` 增加两个只读投影：
   - `menuBarStatusPresentation` 基于实际解析出的 `menuBarQuota?.window`；
   - `viewedStatusPresentation` 基于 `viewedWindow`。
4. 在 `AppStoreTests` 固定 Auto、显式选择、运行时 fallback 和 viewed bucket 分离行为。
5. 覆盖额度阈值、连接状态和刷新优先级。
6. 将新增文件加入 Xcode project 和正确 target。
7. 先运行聚焦测试，再检查编译。

完成标准：

- 纯模型不 import SwiftUI/AppKit。
- `80/40/10 + stale` 分别仍为 healthy/warning/critical。
- stale 重试中 Badge 为 refreshing，`usesCachedData` 仍为 true。
- unavailable + nil 为 unknown，不会生成 critical 或 `0%`。

### 阶段 2：拆开 palette 与独立 Badge 组件

目标：让编译器帮助发现任何仍将 stale 传入 quota color 的旧调用。

执行：

1. 修改 `Codex94Palette`：
   - `quotaColor` 只接收 `QuotaLevel` 或百分比；
   - 增加独立 connection/freshness accent token；
   - 保持 System、Terminal Dark、Terminal Light 自适应。
2. 删除所有 `quotaColor(..., stale:)` 调用。
3. 新增小型 `ConnectionBadgeView`：
   - 只消费 `ConnectionBadge`；
   - none 不占用额外视觉元素；
   - 三个可见状态图形不同；
   - accessibility label 由调用者提供或按本地化 key 注入；
   - 不持有 AppStore 或重复推断状态。
4. 不增加 AppKit bridge。

完成标准：

- 全仓库没有 `quotaColor` 的 stale 参数。
- 连接色不复用 `terminalGreen`、`terminalAmber` 或 `terminalRed`。
- Badge 在浅色、深色和终端主题下有足够对比度。

### 阶段 3：接入菜单栏

目标：菜单栏在固定宽度内同时正确表达额度和连接状态。

执行：

1. 使用 `store.menuBarStatusPresentation`；该投影必须来自当前实际的 `store.menuBarQuota?.window`，而不是只读取保存的 preference。
2. 由统一 presentation 取得 quota level 和 badge。
3. Ring 与百分比只按 quota level 着色。
4. 用 `ConnectionBadgeView` 替换旧的 amber stale 圆点。
5. 保持现有 status item 总体尺寸和点击区域，不引入新布局设置。
6. 组合 accessibility label，至少包含：
   - bucket 的安全 display name；
   - 5h/Weekly 窗口；
   - 剩余百分比或 unavailable；
   - refreshing/cached/unavailable 状态；
   - stale 时的最后成功时间描述（若当前上下文可取得）。
7. 不把 opaque `limitID` 暴露给 VoiceOver。

完成标准：

- stale + 80%：绿色环 + 蓝色/青色时钟。
- stale + 40%：琥珀色环 + 蓝色/青色时钟。
- stale + 10%：红色环 + 蓝色/青色时钟。
- connected + 40%：只有琥珀色 quota，无连接警示。
- 无 snapshot + unavailable：灰色 `--` + 独立断开图形。
- 有 snapshot 刷新中：保留 quota 色 + refreshing Badge。

### 阶段 4：接入 Popover header 与 state banner

目标：Popover 和菜单栏使用相同的语义源，但保留各自信息密度。

执行：

1. Header 使用 `store.viewedStatusPresentation`；该投影必须来自 `store.viewedWindow`。
2. Header ring 只按 quota level 着色。
3. 将现有 ProgressView/状态文字与 `ConnectionBadge` 对齐，避免同一状态重复或冲突。
4. stale banner 使用独立 connection accent 和时钟语义，不再借用 quota amber。
5. unavailable banner 使用独立连接图形和连接强调色；缺失 quota 保持灰色 `--`。
6. 保留现有 stale age 和错误分类，不新增“最后更新时间”产品功能。
7. quota rows 继续只按各自 window 百分比着色。
8. 浏览另一个 bucket 时，Popover header 使用 viewed bucket；菜单栏仍使用 menu bar selection。

完成标准：

- 同一输入在菜单栏和 Popover 中得到同一 quota level/connection badge。
- 不再出现 stale 把健康额度染成琥珀色的情况。
- state banner 与 quota 色不共享含义。
- 多桶浏览和菜单栏选择互不串线。

### 阶段 5：本地化与 Accessibility

目标：状态分离不仅在视觉上成立，也能被 VoiceOver 和中英文用户理解。

执行：

1. 在 `Localizable.xcstrings` 增加或调整：
   - refreshing Badge/Help；
   - cached/stale Badge/Help；
   - unavailable Badge/Help；
   - 组合 accessibility 文案；
   - 无 quota 的 `--` 语义。
2. 英文和简体中文同时标记为已翻译。
3. 不把完整动态文案硬编码在 View 中。
4. accessibility label 不只说 warning，也不只说 connected；应表达额度值和连接状态两个维度。
5. 验证图标有可访问名称，纯装饰图形不造成重复朗读。
6. 用 VoiceOver 和 Increase Contrast 手工检查。

示例语义：

```text
Weekly quota, 18 percent remaining. Cached data, last updated 12 minutes ago.
每周额度，剩余 18%。当前为缓存数据，最后更新于 12 分钟前。
```

完成标准：

- 两种语言都不会只依赖颜色。
- refreshing、stale、unavailable 可由图标形状和朗读区分。
- 本地化 catalog 可通过 JSON 校验与构建。

### 阶段 6：回归、版本与源发布准备

目标：形成可审查、可发布为 `v0.1.6` 的本地变更，但不自行发布。

执行：

1. 跑聚焦测试、完整 XCTest 和 `./script/release_check.sh`。
2. 完成第 8 节人工矩阵。
3. 两个 build configuration 同步更新：
   - `MARKETING_VERSION = 0.1.6`
   - `CURRENT_PROJECT_VERSION = v0.1.5 实际构建号 + 1`
   - 若 v0.1.5 为 build 6，则 v0.1.6 应为 build 7。
4. 更新 `CHANGELOG.md`，让 v0.1.5 兼容修复和 v0.1.6 状态修复分属不同版本。
5. 同步 README 中英文版本、行为说明和稳定 tag。
6. 更新 `SECURITY.md` supported version。
7. 必要时更新脱敏截图。
8. 生成最终变更摘要、测试证据、风险和回滚说明。

完成标准：

- Release gate 通过。
- 文档、bundle version 和变更日志一致为 v0.1.6。
- diff 中没有 v0.2 功能或无关重构。
- 没有新增敏感数据、真实账号信息或机器绝对路径。
- 没有执行 push、merge、tag、GitHub Release 或安装操作。

---

## 8. 测试与验收矩阵

### 8.1 纯逻辑单元测试

额度边界：

| 输入 | 预期 |
| --- | --- |
| `nil` | unknown |
| `0`、`19` | critical |
| `20`、`49` | warning |
| `50`、`100` | healthy |

连接状态：

| `connectionState` | `isRefreshing` | 预期 Badge | `usesCachedData` |
| --- | --- | --- | --- |
| idle | false | none | false |
| refreshing | true/false | refreshing | false |
| connected | false | none | false |
| connected | true | refreshing | false |
| stale | false | stale | true |
| stale | true | refreshing | true |
| unavailable | false | unavailable | false |
| unavailable | true | refreshing | false |

交叉状态：

| quota | 状态 | 预期 quota level | 预期 Badge |
| --- | --- | --- | --- |
| 80% | connected | healthy | none |
| 40% | connected | warning | none |
| 10% | connected | critical | none |
| 80% | stale | healthy | stale |
| 40% | stale | warning | stale |
| 10% | stale | critical | stale |
| nil | unavailable | unknown | unavailable |
| 80% | refreshing | healthy | refreshing |

### 8.2 v0.1.5 兼容回归

至少覆盖：

- default bucket 5h + Weekly。
- weekly-only。
- 多 named model buckets。
- Auto 跨 bucket 选择最低 remaining percentage。
- 显式选择 default/named bucket 和窗口。
- 保存选择暂时缺失时 fallback 到 Auto。
- Popover viewed bucket 与 menu bar selected bucket 不同。
- quota-only 模式不泄漏身份数据。
- Popover 保持 v0.1.5 固定 `500 pt` 宽度、自然高度及 header 顶部间距；
  weekly-only 与双窗口内容切换时均不得出现压缩或大块底部空白。
- cache v2 round trip。
- legacy cache v1 迁移。
- legacy display preference 迁移到 `menuBarQuotaSelection.v2`。
- Codex 0.149 固定 `-a never` 参数安全检查。

### 8.3 聚焦与完整命令

实现阶段可先运行：

```bash
xcodebuild \
  -project Codex94.xcodeproj \
  -scheme Codex94 \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData-v0.1.6 \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:Codex94Tests/StatusPresentationTests
```

最终必须运行：

```bash
git diff --check
jq empty Codex94/Localizable.xcstrings
./script/security_check.sh
./script/release_check.sh
```

不要预先声明固定的最终测试数量；记录实际发现和实际通过的测试数。特别确认新测试文件确实被 Xcode target 执行。

### 8.4 人工 UI 矩阵

至少验证：

- connected 80/40/10。
- stale 80/40/10。
- unavailable no snapshot。
- connected snapshot 正在后台刷新。
- stale snapshot 手动重试中。
- 5h + Weekly。
- weekly-only。
- default bucket、named bucket、Auto 和选择 fallback。
- English、简体中文。
- System Light、System Dark、Terminal Light、Terminal Dark。
- Increase Contrast。
- VoiceOver 朗读菜单栏与 Popover header。
- 固定菜单栏宽度没有裁切或点击区域退化。

没有现成 UI test target 或 snapshot 库时，不为本版本引入第三方依赖。以纯状态测试、可重复 Preview/fixture 和人工截图矩阵完成验收。

---

## 9. 版本、PR 与发布边界

### 9.1 建议分支和 PR

- 功能分支：`codex/v0.1.6-status-semantics`
- 建议一个聚焦 PR，不与 v0.1.5 兼容 PR 混合。
- 建议 PR 标题：`fix: separate quota and connection status semantics`

PR 说明至少包含：

- 问题和双轴语义合同；
- 主要文件；
- 状态矩阵截图或描述；
- 自动测试和人工验证；
- v0.1.5 多桶/cache/安全边界回归结果；
- 明确的非目标；
- 回滚方式。

### 9.2 源发布流程

本计划只准备发布内容，不授权执行外部发布。维护者另行确认后，才按 `docs/RELEASING.md`：

1. 将功能 PR 合并到 main。
2. 等待 main CI 通过。
3. 在 main 的已验证 merge commit 上创建新的 annotated `v0.1.6` tag。
4. 只推送目标 tag，不使用 `git push --tags`。

不得移动、复用或重建已发布的 `v0.1.5` tag。

### 9.3 仍为 source-only

`v0.1.6` 不附带公开 `.app`、ZIP 或 DMG。Release build 的 ad-hoc Hardened Runtime 签名只适用于当前源构建流程，不等同于 Developer ID 或 Apple notarization。

---

## 10. 风险与回滚

| 风险 | 预防 | 回滚 |
| --- | --- | --- |
| v0.1.5 未真正落地主线 | 阶段 0 硬门 | 停止，不把两个版本混合 |
| 只读 ConnectionState，漏掉已有 snapshot 的刷新 | presentation 同时接收 `isRefreshing` | 回退到纯模型检查点修正 |
| 多个 View 重复推断状态 | 单一 `StatusPresentation` | 删除 View 内重复分支 |
| stale 再次污染 quota 色 | 删除 stale 参数并用编译/rg 检查 | 回退 palette 接入提交 |
| 新文件未加入 target | 人工审查 pbxproj + 聚焦测试 | 修复 project membership |
| Badge 在固定宽度中裁切 | 保持 overlay/小组件并做 UI 矩阵 | 恢复原尺寸，调整组件而非扩展布局功能 |
| accessibility 暴露 opaque ID | 只使用安全 display name | 删除动态 ID 文案 |
| v0.1.5 多桶或 cache 回归 | 完整兼容回归和 release gate | revert v0.1.6 PR，不移动 v0.1.5 tag |
| 版本和 build 不一致 | 从实际 v0.1.5 build 加一 | 修正 release-prep commit 后再 tag |
| 范围蔓延到 v0.2 | 文件白名单和每阶段 diff 审查 | 回退无关改动，另开计划 |

推荐按阶段形成小而可回滚的本地提交；若用户没有授权提交，则只保持清晰的工作区 diff。任何回滚都不得使用会丢失用户数据的 `git reset --hard`。

---

## 11. Codex 执行协议

将本文交给 Codex 后，要求它遵守：

1. 先读完整计划和所列关键文件，再改代码。
2. 先核验 v0.1.5，不满足就停止并报告。
3. 先纯逻辑和测试，后 UI。
4. 每个阶段只做该阶段范围，完成后检查 diff 和测试。
5. 遇到用户已有修改时保留它们，不 stash、不 reset、不覆盖。
6. 遇到代码与计划不同，依据实际架构实现同等职责并说明差异。
7. 不因某个测试暂时难写而跳过状态矩阵。
8. 不修改安全参数、cache schema、偏好迁移或发布政策。
9. 不 push、merge、tag、发布、安装或替换应用，除非用户另行明确授权。
10. 最终交付：
    - 变更摘要；
    - 文件清单；
    - 测试命令和结果；
    - 人工矩阵结果；
    - 未解决风险；
    - 回滚说明；
    - 明确说明哪些外部发布动作没有执行。

---

## 12. 可复制的 `/goal` 目标

在 Codex94 仓库作为当前工作区时复制以下整段：

```text
/goal 在当前 Codex94 仓库中完成 v0.1.6 状态语义分离升级，并持续推进到可验证的本地完成状态。严格阅读并遵循 docs/CODEX94_UPGRADE_PLAN_V0.1.6.md：先确认兼容修复已经作为独立、通过完整 gate 的 v0.1.5 合并到 main、打好不可变 tag，且工作区没有用户未提交改动；否则停止实现并准确列出缺项。满足前置后，从 v0.1.5 后的 main 创建 codex/v0.1.6-status-semantics，只实现额度严重度与连接/数据新鲜度的双轴语义：新增纯 StatusPresentation、独立 ConnectionBadge，以及基于实际 menuBarQuota 和 viewedWindow 的两个 AppStore 只读展示投影，确保绿色/琥珀色/红色只表示 quota，蓝色/青色图形表示 refreshing/stale/unavailable，stale 不覆盖最后已知 quota 色，无 snapshot 显示灰色 -- 而不是 0%。必须保留 v0.1.5 的多额度桶、Auto/显式选择/fallback、weekly-only、固定 500pt 宽度并跟随内容自然高度的 Popover、cache v2、旧偏好迁移、quota-only 隐私行为，以及固定 codex -s read-only -a never app-server --stdio、无直接 HTTP、无凭据读取、无 telemetry 的安全边界；不得扩展到 compact layout、唤醒刷新、通知、RPC 重构、ZIP/DMG 或其他 v0.2 功能。按计划检查点完成纯逻辑与 StatusPresentationTests、AppStore 投影回归、palette/Badge、菜单栏、Popover、本地化、Accessibility、兼容回归、版本和文档；新增 Swift 文件必须加入正确 Xcode target。每个检查点检查 diff 并运行相关测试，最终停止条件是：完整状态矩阵和多桶回归满足，英文/简体中文与主题/VoiceOver 人工矩阵完成，git diff --check、静态安全检查和 ./script/release_check.sh 全部通过，MARKETING_VERSION 为 0.1.6、build 为实际 v0.1.5 build 加一，CHANGELOG/README/SECURITY 一致，且交付变更、测试、风险和回滚清单。不得覆盖用户改动，也不得自行 push、merge、tag、创建 GitHub Release、安装或替换 App；这些动作必须等待另行授权。
```

`/goal` 适合这类具有明确停止条件的长任务。可用 `/goal` 查看状态，使用 `/goal pause` 和 `/goal resume` 暂停或继续。若当前 Codex 没有 Goal 功能，先按官方说明启用 goals feature。

官方说明：[Follow a goal](https://learn.chatgpt.com/use-cases/follow-goals)

---

## 13. 最终 Definition of Done

- [ ] v0.1.5 已独立发布并成为 v0.1.6 的真实基线。
- [ ] v0.1.6 分支不包含 v0.1.5 发布收尾或 v0.2 功能。
- [ ] `StatusPresentation` 为纯值、可单测的唯一状态映射。
- [ ] `quotaColor` 不再接受 stale/connection 状态。
- [ ] refreshing 同时考虑 `ConnectionState` 和 `isRefreshing`。
- [ ] stale 80/40/10 保持绿色/琥珀色/红色 quota 色，并显示独立 stale Badge。
- [ ] unavailable no snapshot 显示灰色 `--`，不是 `0%`。
- [ ] 菜单栏使用实际 `menuBarQuota`，Popover 使用实际 `viewedWindow`。
- [ ] 多 bucket、Auto、显式选择、fallback、weekly-only 无回归。
- [ ] cache v2、旧 cache 和旧偏好迁移无回归。
- [ ] 固定 `-a never`、read-only 和其他安全边界无变化。
- [ ] 中英文、本地化 catalog、VoiceOver 和 Increase Contrast 验证完成。
- [ ] 新增 Swift 文件均在正确 Xcode target 中。
- [ ] 聚焦测试、完整 XCTest 和 `./script/release_check.sh` 通过。
- [ ] `MARKETING_VERSION = 0.1.6`，build 是实际 v0.1.5 build 加一。
- [ ] CHANGELOG、README 中英文、SECURITY 和必要截图一致。
- [ ] diff 无敏感信息、机器路径、无关重构或第三方依赖。
- [ ] 最终报告包含变更、测试、人工验证、风险与回滚。
- [ ] 未经授权没有 push、merge、tag、发布或安装。
