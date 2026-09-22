# Codex94

[English](README.md) | **简体中文**

## 产品简介

Codex94 是一款与 OpenAI Codex 兼容的非官方、独立 macOS **额度监控与 Token
统计**工具。菜单栏随时显示剩余额度和重置时间，不占用 Dock；弹出面板和 Dashboard
提供详细信息。

`0.3.0 (14)` 新增服务端汇总卡、可切换的**柱状图／折线图**，以及每日 Token 记录的
**CSV 导出**。手动检查更新可查看 GitHub 上更新的稳定 Release，下载和安装仍由用户完成。

`0.2.2 (13)` 引入的额度功能继续保留：四种菜单栏布局（含双窗口）、可选的低额度／
恢复提醒和可配置全局快捷键。鼠标左键或右键都切换同一个面板。面板和总览中的只读
**手动额度重置**卡片展示可用次数，不执行重置兑换。

Codex94 是采用 MIT 许可的源码项目，使用 Mac 上已有的 Codex 可执行文件，
并且没有第三方运行时依赖。

**本项目通过 Codex 辅助的 vibe coding 工作流构建。** 每个版本在创建标签前
仍会由维护者检查，并通过测试与安全扫描。

> Codex94 与 OpenAI 没有隶属关系，也未获得 OpenAI 的认可、背书或赞助。Codex
> `app-server` 是实验性接口，未来 Codex 版本可能会改变它。

## 3.1.1 候选版

`3.1.1 (17)` 会根据当前额度数据调整悬浮栏：只有周额度时为
**480 × 90 逻辑点**，有真实 5 小时窗口时保留 **680 × 90** 双列布局。
不再显示缺失的 5h 栏，单列保留正常字号；两种布局展开后均为 132 点高。
刷新、缓存及额度组切换会自动更新同一个窗口，适应屏幕空间，不额外请求数据。
下方稳定下载暂仍指向已发布的 `3.1.0`。

## 3.1.0 版本

`3.1.0 (16)` 已于 **2026-09-23**（Australia/Melbourne）正式发布，
下方下载与源码指令均指向本版。

- 新增目标尺寸为 **680 × 90 逻辑点**的额度横浮条，支持置顶、拖动、隐藏和展开。
  复用已有额度数据；悬停或聚焦更新时间控件时显示手动刷新。不会新增轮询或兑换
  重置次数，原全局快捷键继续切换 Popover。
- Token 统计在原三个范围之外增加**自选日期**，沿用服务端日历日期标签。展示已报告
  日均值、所选区间峰值和覆盖率，与服务端汇总卡保持区分。对比前一等长区间时展示
  其已报告合计与覆盖天数；仅两段数据完整且基期非零时计算增长百分比。
- **导出 PNG…**与**复制图表图片**使用当前范围、柱状／折线样式、语言和主题；
  图片仅含图表、日期范围、抓取时间、覆盖和旧数据说明，不含身份。复制只在用户
  点击后写入系统剪贴板，CSV 导出继续保留。
- 新增持久化偏好仅保存浮条置顶状态与位置；不增加统计历史库、系统权限、网络
  接口，也不改变签名和手动安装方式。

验证包含第四个合成 **Floating** UI 场景及统计控件／图片检查，证据分类见下文。
原生键盘焦点、跨 Spaces 与全屏应用行为须单独实测，不能仅凭图片或面板配置认定。

## 界面截图

所有截图均采用隔离的合成数据，不包含真实账号或实时用量。以下**柱状图**与**折线图**
采集于 `0.3.0 (14)` 候选测试阶段，两者使用相同的七天日记录。原始合成截图保持不变，
这些英文界面截图来自
[CI run 35521556558](https://github.com/DEFY-AN94/codex94/actions/runs/35521556558)，
未编辑媒体内容。统计日期固定在 **2033 年**；5 月 15 日的零是夹具明确返回的数值，
不是为缺失日期补零。

<p align="center">
  <a href="docs/images/readme/token-usage-bar-0.3.0-en.png"><img src="docs/images/readme/token-usage-bar-0.3.0-en.png" alt="Codex94 0.3.0 候选的七天柱状图，使用 2033 年 5 月合成 Token 日记录" width="440"></a>
  <a href="docs/images/readme/token-usage-line-0.3.0-en.png"><img src="docs/images/readme/token-usage-line-0.3.0-en.png" alt="Codex94 0.3.0 候选将相同七天合成日记录显示为折线图" width="440"></a>
</p>
<p align="center"><strong>Token 统计：自由切换柱状图与折线图</strong></p>

[查看简体中文汇总卡截图](docs/images/readme/token-usage-overview-0.3.0-zh-Hans.png)，
或查看[精确的截图来源记录](docs/images/readme/PROVENANCE.md)。

<details>
<summary>既有额度界面——历史版本截图</summary>

保留的菜单栏示例来自 `v0.1.7`，Popover 图片来自 `0.1.8`，Dashboard 总览图片来自
`0.1.9` 的 GitHub-hosted CI。图中固定的未来 Reset 日期均为合成测试值。原文件保持
不变，只展示各自版本的界面，不代表 `0.2.2` 新增功能或 `0.3.0` 的统计与更新界面。

<p align="center">
  <img src="docs/images/readme/menu-bar.png" alt="Codex94 菜单栏圆环显示剩余 79%" width="144">
</p>
<p align="center"><strong>紧凑菜单栏状态</strong></p>

<p align="center">
  <img src="docs/images/readme/popover-zh-Hans.png" alt="Codex94 简体中文 CLI 风格额度面板" width="500">
</p>
<p align="center"><strong>CLI 风格额度面板</strong></p>

<p align="center">
  <img src="docs/images/readme/dashboard-zh-Hans.png" alt="Codex94 Terminal Dark 简体中文总览展示合成额度桶" width="900">
</p>
<p align="center"><strong>额度总览</strong></p>

</details>

## 当前分发状态

- 已发布的稳定版为
  [`v3.1.0 (16)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.0)，
  于 **2026-09-23**（Australia/Melbourne）发布，提供 Universal 2 DMG 与来自同一个
  annotated 标签的源码。
- 下方下载和源码 clone 指令均指向该正式版本。后续文档提交不会移动其标签，
  也不会重新生成已发布的资产。
- `3.0.1 (15)` 是维护版本，修正请求上下文处理，并局部复用解析、图表准备和
  清理逻辑；保留 `0.3.0` 引入的功能，不包含大范围架构重写。
- 仓库已公开，无需 GitHub 认证即可 clone。
- `0.2.2` 没有检查更新入口，其用户需手动安装 `0.3.0` 或之后的正式版本才能获得该入口；
  后续更新的下载与安装仍由用户手动完成。
- `script/install.sh` 构建本地 Release App，应用 ad-hoc Hardened Runtime
  签名，并安装到 `~/Applications/Codex94.app`。
- 安装脚本要求先退出所有 Codex94 副本，使用安装锁并验证独立的暂存副本，
  替换成功前保留旧 App 以便回滚。回滚失败时保留恢复文件，但不维护各版本归档。

已发布的 `3.1.0` DMG 外层本身完全未签名，没有 Apple Developer ID 签名，也未经过 Apple
公证。其中的 `Codex94.app` 只有 ad-hoc 签名。SHA-256 与 GitHub artifact
attestation 都不会改变这一 Apple 信任状态。

## 系统要求

- macOS 14 或更高版本。
- 一个兼容的 Codex 可执行文件，以及用于读取实时额度的当前 Codex 登录状态。

使用 DMG 安装不需要 Xcode。源码安装还需要完整版 Xcode 16.4 或更高版本
（仅有 Command Line Tools 不够），以及安装脚本静态安全检查使用的
`ripgrep`（`rg`）。

Codex94 可以使用 ChatGPT App 内置的 Codex 可执行文件；只要该内置版本兼容，
就不需要额外安装独立 Codex CLI。它也可以检测 Homebrew 与常见 CLI 路径，
或使用用户手动选择的可执行文件。

## 安装 Universal DMG

请从 [`v3.1.0` Release 页面](https://github.com/DEFY-AN94/codex94/releases/tag/v3.1.0)
下载以下两个正式资产：

- `Codex94-3.1.0-macos-universal-unnotarized.dmg`
- `Codex94-3.1.0-SHA256SUMS.txt`

DMG 支持 Apple Silicon（`arm64`）与 Intel（`x86_64`），最低系统为 macOS 14。
打开前先验证 checksum：

```bash
shasum -a 256 -c Codex94-3.1.0-SHA256SUMS.txt
```

如已安装 GitHub CLI，还可验证该 DMG 来自本仓库的 GitHub workflow 与提交：

```bash
gh attestation verify Codex94-3.1.0-macos-universal-unnotarized.dmg -R DEFY-AN94/codex94
```

Attestation 只证明构建来源，不代表 Apple 签名、公证、恶意软件审查或 Gatekeeper 认可。

先退出所有正在运行的 Codex94，再打开 DMG，把 `Codex94.app` 拖到其中的
`Applications` 快捷方式，安装位置是 `/Applications/Codex94.app`。不要同时运行
这里的副本和 `~/Applications` 中的副本；两者共用同一个 bundle identifier、
偏好、缓存与登录项注册。

由于此技术用户 DMG 未签名且未公证，macOS 可能阻止打开 DMG 或首次启动 App。
若你信任已经精确核验的该版本，请遵循 Apple 官方的
[“隐私与安全性 → 仍要打开”](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/26/mac/26)
流程。不要删除 quarantine 属性，也不要关闭 Gatekeeper。

## 从源码安装

Clone 当前已发布的稳定源码标签：

```bash
git clone --branch v3.1.0 --depth 1 https://github.com/DEFY-AN94/codex94.git
```

然后构建所选标签：

```bash
cd codex94
brew install ripgrep

sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch

./script/install.sh
```

安装前请先退出所有 Codex94 副本。安装脚本会构建、签名、安装并打开
`~/Applications/Codex94.app`。如需安装后不自动打开：

```bash
./script/install.sh --no-launch
```

首次启动时，可以选择允许 Codex94 请求 **额度 + 账号信息** 或 **仅额度**。
登录时启动精确接受 `/Applications/Codex94.app` 与
`~/Applications/Codex94.app` 两个稳定位置。源码安装脚本不会迁移或删除 DMG
安装的副本。

## 主要行为

### Token 统计与手动检查更新

- Dashboard → **Token 统计**在首次进入或手动刷新统计时，通过
  `account/usage/read` 加载服务端数据，与额度轮询独立。统计读取失败不会让
  正常工作的菜单栏额度变成连接错误。
- 汇总卡展示返回的累计 Token、单日 Token 峰值、当前和最长连续使用天数、
  最长单次运行时长；未提供的数值保持未知。服务端汇总可能与日记录覆盖范围不同，
  不推测按模型、项目、输入／输出、费用或小时划分的数据。
- 可自由切换**柱状图／折线图**并记住选择；选中日期的虚线对齐柱体中心或折线数据点，
  折线在未返回数据的日期处断开。
- 每日图表与明细表提供 **7 天／30 天／全部返回／自选日期**。三个预设范围截至最新
  返回统计日，不代表截至今天；自选范围包含所选起止日。图中保留真实日期缺口，
  缺失日期不按零用量处理。悬停或点击可
  查看精确数值。服务端分日时区与完整历史覆盖范围尚无说明。
- **导出 CSV…**仅把当前范围内已返回的日记录保存到用户选择的文件，保留原始
  服务端日期和精确 Token 数。除主动导出 CSV／PNG 或复制图表外，统计只存在于
  内存；刷新替换原快照，不会重复累加同一份使用量。
- Dashboard → **关于 → 检查新版本**仅在点击后请求 GitHub 上本仓库最新的公开稳定
  Release，显示版本和纯文本发布说明，并可通过系统浏览器打开已验证的 GitHub
  Release 页面。下载与安装仍由用户手动完成；App 不轮询更新、不下载或安装 App，
  也不会为更新自行重启。固定接口、首次迁移及未来自动安装前提见
  [更新检查与发布维护说明](docs/updating.md)。

### 既有额度行为

以下行为继承自 `0.2.2 (13)`。**既有额度界面**折叠区保留历史截图；上方新增的
Token 统计预览另有独立的来源记录。

- 新建 Dashboard 窗口默认打开**总览**，复用当前连接状态、数据新鲜度文案和菜单栏
  额度选择器，再按既有显示顺序展示所有可显示额度桶，以及服务实际返回的 5 小时或 Weekly
  窗口。缺失数据会显示明确空状态，不伪造 `0%`。打开、浏览或滚动总览不会刷新或
  写额度缓存；页面不显示邮箱、可执行文件路径或原始额度桶标识，刷新仍使用
  Dashboard 现有工具栏入口。
- 在 Dashboard → 显示中选择四种布局：**圆环 + 百分比**、**仅百分比**、
  **仅圆环**和新增的**双窗口**。原三种布局保留已有行为。
  正在运行的菜单栏状态项会立即改变布局与宽度，并且不会被删除或
  重建；状态标记位于圆环中央，或在“仅百分比”模式下占用固定尾部位置。
- `0.2.2` 增加第四种**双窗口**布局，同时显示所选额度桶的 5 小时与 Weekly
  数值。它的选桶偏好独立于原三种布局的额度选择，切换布局会保留原有选择；
  不伪造缺失窗口，也不合并不同窗口的额度。
- 鼠标左键或右键点击菜单栏状态项，都会切换同一个 Popover 的开关状态；
  打开后仍沿用正常的展开刷新路径。可配置的全局快捷键也切换同一个面板，
  **默认未设置**。组合必须包含 Control 或 Option，也可另外添加 Command 和 Shift。
- 本地额度通知**默认关闭**，只有显式启用时才请求 macOS 通知权限。剩余比例
  默认在 **20% 和 10%** 两档提醒，均可调整或关闭；默认监测默认额度桶，
  也可选择额外额度桶及恢复提醒。只有新的成功快照参与判断，通知基线与每个
  窗口周期的去重状态只保存在内存。消息仅含额度桶名称、窗口和百分比，不含邮箱；
  已送达通知由 macOS 通知中心管理和保存。
- Popover 与总览提供独立的只读**手动额度重置**卡片，突出显示可用次数。
  卡片仅用于展示信息，没有执行重置的按钮；数值来源为现有额度响应中的权威总数
  `rateLimitResetCredits.availableCount`。`0` 表示零次，缺失或 `null` 不当作零次；
  首次实时结果前显示“尚未获取”，刷新失败后保留的旧值标为缓存。次数只在内存中
  保存，不写入额度缓存；Codex94 不提供兑换操作，也不发送消费重置次数的请求。
- 分别自定义充足（50–100%）、偏低（20–49%）、紧张（0–19%）
  和无可用数据时连接不可用的四种颜色；这些颜色阈值不可调整，与可配置的通知阈值
  相互独立。颜色即时生效，按不透明
  sRGB 的规范化六位大写 `RRGGBB` 保存，不含透明度。紧张色和错误色彼此独立，
  即使两者默认都是主题红色也不会联动。**恢复默认颜色**只移除这四项覆盖，
  不改变布局、主题、语言、额度选择、可执行文件路径或窗口尺寸。
- 额度行下方独立显示绝对**重置时间**，包含完整日期、小时/分钟及
  重置时刻的 UTC 偏移，正确区分夏令时。原倒计时保留；没有日期则显示不可用，
  过去日期仍显示原时间，倒计时不低于零。日期遵循 App 语言的 locale 和当前时区。
  Dashboard → 连接显示菜单栏实际解析的额度桶与窗口，
  而不是 Popover 中单独浏览的模型。
- 错误横幅提供**打开连接设置**或**打开诊断**，复用同一个 Dashboard
  窗口；普通打开 Dashboard 会保留当前页面。这些按钮只负责导航，重试仍使用
  原有**刷新**。未登录时会提示先在 Codex 中登录、再回来刷新；Codex94 不代为登录。
- 修改布局/颜色、呈现总览、渲染重置时间文案以及恢复导航本身不会请求额度、写入
  额度缓存或改变连接状态；打开 Popover 和独立的 post-reset 调度仍按下述行为刷新。
- App 启动、每次展开菜单栏面板，以及按所选的 1、5、15 或 30 分钟间隔刷新。
- Mac 唤醒后，如果没有成功快照，或上次成功已过去至少 60 秒，则刷新一次；
  更鲜的快照保持不变。唤醒、后台、手动和展开面板触发的请求共用同一条单飞
  刷新路径。
- 每次成功快照后，会从所有可显示窗口中选择最早的未来 Reset，仅在
  `resetsAt + 5` 秒或更晚安排一次内存中的刷新。相同目标会去重，相邻请求复用同一
  单飞路径，已消费目标不会进行 Reset 专属重试。仅保存在本次运行中的已消费时间
  水位防止时钟回拨后重新安排旧 Reset。唤醒与系统时钟变化会重新协调这项一次性
  计划；不新增持久化 Reset 账本或后台刷新周期。
- 使用 `account/rateLimits/read` 读取实时额度；在 **额度 + 账号信息** 模式下，
  还会调用 `account/read`，并固定使用 `refreshToken: false`。
- 将 Codex 返回的标准/默认额度桶与额外命名的模型额度桶分开处理。默认额度桶显示
  为 **Codex**；其他额度桶使用服务端提供的名称，不写死模型可用性或下架日期。
  历史合成截图可能仍包含旧模型名称。
- Popover 中的模型选择器每次浏览一个额度桶，与菜单栏选择相互独立；浏览模型
  不会改变菜单栏圆环。正在浏览的额度桶消失时，优先使用有窗口的默认额度桶；
  默认桶无可用窗口时使用首个可显示桶。选择菜单仍能区分较长的额度桶名称。
- 动态的菜单栏额度菜单提供 `自动` 以及每个可用额度桶与窗口；`自动` 会在所有
  可显示额度桶和窗口中选择剩余比例最低的一项。新的成功快照确认固定选项已消失后，
  已保存偏好改为 `自动`；该选项重新出现时也保持自动。加载缓存或刷新失败不会
  改写这项偏好。
- 仅支持服务实际返回的 5 小时和 Weekly 窗口。仅有 Weekly 是有效数据；缺失
  窗口的额度行和选择项会隐藏，不根据套餐名称推断权限，不估算额度，也不合并
  彼此独立的窗口。
- 将额度严重度与连接/数据新鲜度分开：额度圆环、百分比和进度条使用同一套解析后
  的充足/偏低/紧张颜色，默认依次为绿色、琥珀色和红色。刷新中与缓存标记保持
  蓝色/青色连接强调色。在没有可用数据且连接不可用时，标记、横幅和
  Dashboard 错误状态点使用独立错误色，默认取应用紧张色覆盖前的主题红色。
- 刷新失败时保留最后一次成功的额度并标记为缓存数据；没有可用额度快照时显示
  灰色 `--`，不会伪装成 `0%`。
- Popover 标题区域会显示最后一次成功额度数据的相对时间。已有快照时刷新会明确
  显示“上次成功”，刷新中或不可用且没有快照时则使用不同的“暂无成功数据”语义；
  菜单栏和 Popover 的辅助功能描述也包含相同的新鲜度信息。
- 点击面板以外区域会收起临时面板，不会吞掉原始点击，也不需要辅助功能权限。
- Codex 检测顺序为：手动路径、ChatGPT App 内置文件、Homebrew、
  `/usr/local/bin`、`~/.local/bin`，最后是 `PATH` 中的绝对路径。
- Dashboard 提供 900x600、1280x720、1440x810 和 1920x1080 逻辑点窗口预设；
  超出当前屏幕时会按比例适配，并保留用户选择的预设；用户主动拖动调整窗口时
  仍更新预设。
- Dashboard → 启动在返回 App 时重新读取登录启动状态，修改失败会显示本地化提示；
  自动测试使用模拟服务，不操作真实登录项。
- 可执行文件选择面板跟随 App 中选择的语言。
- Dashboard → 关于显示正在运行的 App 精确版本与 build，由用户触发的复制结果
  与之完全一致；
  项目链接指向 `https://github.com/DEFY-AN94/codex94`，通过系统浏览器打开；
  独立的手动检查更新流程见上文。
- 支持跟随系统、Terminal Dark、Terminal Light 主题，以及 English 和简体中文。
- 只使用当前 Codex 登录；不管理多账号或其他 `CODEX_HOME` 目录，不收集本地额度历史账本。

## 安全与隐私

```mermaid
flowchart LR
    A["Codex94"] <-->|"本地 stdio JSON-RPC"| B["Codex app-server"]
    B -->|"Codex 自己管理的登录"| C["OpenAI 账号服务"]
    A --> D["仅含额度的本地缓存"]
    A -->|"自愿启用的本地提醒"| E["macOS 通知中心"]
    A -->|"0.3.0：用户手动检查更新"| F["GitHub 公开 latest-release API"]
```

Codex94 使用固定参数启动已验证的可执行文件：

```text
codex -s read-only -a never app-server --stdio
```

身份验证由 Codex 自己管理，Codex 可能会访问 OpenAI 服务。Codex94 不实现
OAuth，不接收 access token 或 refresh token，不直接发送额度 HTTP 请求，也不
读取认证文件、浏览器 cookie、Keychain、Codex session 日志或 SQLite 数据库。

带版本的本地缓存仅保存额度桶标识与可选名称、套餐类型、窗口时长与类型、百分比、
重置时间和获取时间，并使用仅限当前用户的文件权限。**额度 + 账号信息** 模式下
的邮箱只存在于内存；切换为 **仅额度** 后会从内存快照移除。UserDefaults 保存
界面选项（包括菜单栏额度偏好）和用户手动选择的可执行文件路径。版本 0.1.8 引入
`menuBarLayout.v1` 与 `statusAccentOverrides.v1`，分别保存布局和四种颜色覆盖；
后续版本继续复用这些 key 和迁移。0.2.1 仅在新的成功快照确认固定额度选项
消失后，使用已有偏好 key 将选择改为自动。重置时间文案和内存中的
post-reset 调度只使用现有重置时间戳，不新增缓存字段或持久化账本。总览复用现有
快照，不存储新的身份数据。Popover 中浏览的模型和 Dashboard 当前页面只在本次
运行中保存；窗口 frame autosave 行为保持不变。
`0.2.2` 增加 `dualWindowBucketSelection.v1`、`globalHotKey.v1` 与
`notifications.v1` 偏好，分别保存独立的双窗口选桶、快捷键和通知设置。通知基线、
去重状态及可用重置次数仅在内存中保存，缓存 schema v2 保持不变。快捷键通过系统
热键注册实现，不记录键入内容。自愿启用的通知使用 macOS 本地通知服务，系统可以
在通知中心保存包含额度桶、窗口与百分比的已送达消息；这是明确新增的权限与本地
系统数据流，不是远程遥测。
`0.3.0` 的统计只在内存保存，用户主动导出的 CSV 除外。独立的更新检查仅在用户
操作后直接请求 GitHub 固定的公开 latest-release API，不发送账号或用量数据；
检查结果只保存在内存。Codex94 没有分析、广告、遥测上传、崩溃上报 SDK、系统信息
统计或项目自营服务器。打开 Release 页面时，导航交由系统浏览器处理。

0.2.0 增加了分发打包和第二个稳定安装路径；0.2.1 保持相同的数据与权限边界。
DMG、checksum 与 CI artifact
包含 App，不包含账号数据、凭证、偏好、缓存、日志或真实额度。浏览器下载与
Gatekeeper quarantine 处理属于 macOS 分发流程。`0.3.0` 明确新增更新网络路径，
但不改变 Codex 凭证与额度数据的访问方式。

App Sandbox 被有意关闭，因为 Codex 子进程需要访问它自己的登录状态。
Hardened Runtime 仍然启用；子进程参数固定、环境变量最小化、输出有大小限制、
请求有超时，并且每次刷新后或 App 退出时都会在有界时间内终止并回收完整进程组。
版本验证只检查协议兼容性，不验证发布者身份，因此用户必须信任自己的
ChatGPT/Codex 安装以及手动选择的可执行文件。

诊断与关于页面的复制按钮只会在用户操作后写入剪贴板。复制诊断时，Codex94 会先
规范化可执行文件路径与版本；关于页面复制与显示完全一致的版本和 build。分享诊断
前仍应由用户再次检查内容；Codex94 不读取或上传剪贴板内容及诊断信息。

完整边界请参阅 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)
（英文）。

## 开发与构建

贡献与发布检查还需要 `jq`：

```bash
brew install ripgrep jq
```

构建并运行 Debug App：

```bash
./script/build_and_run.sh
```

`build_and_run.sh` 会在构建前关闭现有的匹配名称 Codex94 进程，然后启动 Debug
App。`install.sh` 会要求用户自行退出正在运行的副本，仅替换自身安装路径，
并且可能启动安装后的 App。这些脚本并非只读检查；
本机运行的 App 可能使用与已安装 App 相同的偏好和缓存。

自动测试和文档截图应使用合成数据、注入 fetcher 或显式指定的 fake executable。
不要在共享夹具或产物中包含真实账号凭证、身份、额度或私人路径。测试偏好与缓存
应与日常 App 数据分开；详见 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。

运行单元测试与 fake app-server 集成测试：

```bash
DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer \
  xcodebuild -project Codex94.xcodeproj -scheme Codex94 \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

运行完整发布检查，包括隔离的 metadata/installer 脚本测试、hosted tests、一次
Universal Release 构建和 DMG create/verify。`script/release_metadata.py` 统一读取
App target 的版本与 build，CI 与 UI fixture 使用 committed 值；完整 App 签名与
payload 验证由打包脚本负责：

```bash
./script/release_check.sh
```

版本 0.1.8 已通过完整 GitHub 测试/发布任务、合成 Display 与点击功能 Recovery UI
任务，以及 Actions/Swift CodeQL。对于 `0.1.9 (10)`，PR #11 仍是精确 head 测试、
Display/Recovery UI、Actions/Python/Swift CodeQL 与最终 App 人工验收状态的历史
记录；上方嵌入的合成总览截图已经完成布局与隐私审查。键盘激活、AXPress 与托管
运行器 tooltip 暴露仍不声明为已通过。
[`0.3.0 (14)`](https://github.com/DEFY-AN94/codex94/releases/tag/v0.3.0)
已于 2026-09-21（Australia/Melbourne）正式发布，其源码与分发资产仍绑定该发布标签。
后续文档变更不会替代已记录的验收证据，未来版本仍需独立验证。

[`3.0.1 (15)`](https://github.com/DEFY-AN94/codex94/releases/tag/v3.0.1) 的新验证包含
**315 项 hosted tests**、Display／Recovery／Token usage 三个 CI 场景、
Actions／Python／Swift CodeQL，以及本版最终 main 的 Universal App 与 DMG 核验。
这些是本维护版本自己的验证结果；未修改的 `0.3.0` 截图与维护者人工交互记录保留
原始来源，不改称为重新执行的 `3.0.1` 人工验收。最终 CI 安装包验收在本版发布记录中
单独说明。

`3.1.0 (16)` 的本地单元测试套件记录为 **340 项执行、1 项跳过、0 项失败**。
被跳过的是 hosted 键盘焦点检查，原因是测试进程无法建立 key window，不计作通过。
PNG 检查包含实际图片的新鲜／旧数据文本识别与隔离剪贴板验证。本版发布记录另行
列出 Display／Recovery／Token usage／Floating 四个外部 UI 场景、
Actions／Python／Swift CodeQL，以及最终源码和安装包验收。历史截图与人工交互
记录保留原始来源，不转作本版的新证据。

SwiftUI 负责视图与状态呈现；AppKit 负责菜单栏状态项、Popover、App 外观和
Dashboard 窗口生命周期。组件职责与复用约束见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)；
贡献与发布流程见 [CONTRIBUTING.md](CONTRIBUTING.md) 和
[docs/RELEASING.md](docs/RELEASING.md)（英文）。

## 卸载

先在 Dashboard 中关闭 **登录时启动**，然后退出所有 Codex94 副本。只删除你实际
安装过的位置；两种安装方式都不会自动删除另一个副本：

```bash
rm -rf "/Applications/Codex94.app"
rm -rf "$HOME/Applications/Codex94.app"
```

删除 App 不会删除本地数据。如需同时移除本地缓存与偏好，请再单独执行：

```bash
rm -rf "$HOME/Library/Application Support/Codex94"
defaults delete com.defyan94.codex94
```

## 许可

Codex94 使用 [MIT License](LICENSE)。设计与实现参考见
[ATTRIBUTIONS.md](ATTRIBUTIONS.md)（英文）。

Codex 和 ChatGPT 是 OpenAI 的商标。Codex94 是独立的非官方项目，不使用
OpenAI Logo。
