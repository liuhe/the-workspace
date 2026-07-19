# tasker log

## 2026-07-11 决策

- 项目名：tasker
- 平台：macOS Native（默认 Swift + SwiftUI）
- 建模：跳过 DCDDP 4 视图建模，直接开搞
- Backlog 定义：未归属当天集合且未完成的任务
- 状态推导规则确认（见 overview.md）

## 2026-07-11

- 建 `projects/tasker/`，写 overview / tasks / log
- 环境探查：Swift 6.2 有，Xcode 无（只有 CLT）→ 走 SwiftPM 可执行 target + SwiftUI，`swift run` 启动，不做 `.app` bundle
- 存储目录约定：`~/Documents/tasker/` = `tasks.jsonl` + `entries.jsonl` + `descriptions/<uuid>.md`
- Backlog 精确定义：`!isInCurrent && collectionDate == nil && status != .done`（等实际用起来若不对再改）
- 领域层 + 仓储 + UI 一次落地，共 15 个源文件；用 `taskerCheck` 可执行 target 替代 `swift test`（CLT 无法链接 XCTest / Testing）
- 端到端场景全绿；踩坑：ISO8601 秒精度导致同秒记录顺序丢失、状态推导选错 last entry → 改为带 fractional seconds
- app 从 `$(swift build --show-bin-path)/tasker` 启动可正常运行，storage 目录自动初始化
- 模型重构：`WorkType`/标题下沉到 `TimeEntry`；引入 `Membership`（单一，`kind = .day(Day) | .current`），`Priority` 移到 Membership 上；`Task` 只留 title/category/description
- 决策：一个任务同一时刻只能属于一个集合（`.day` 或 `.current` 或 nil=Backlog）——通过合并成单个 `Membership` 实现
- UI 改：侧栏改下拉菜单（今天/昨天/明天/选日期/当前/Backlog）；新建任务弹标题输入 sheet；列表右键 → 优先级 + 归属 + 删除；详情标题+优先级最上，时间记录可编辑开始/结束/标题/类型/标志
- 数据格式变化，旧数据不迁移，直接清空 `~/Documents/tasker/` 重来
- 侧栏结构调整：下拉只放"日期 + Backlog"；"当前"改成独立开关（`showCurrent`），打开时下拉禁用、effective filter = .current
- 日期标签统一带星期显示（zh-CN locale，`Day.descriptionWithWeekday` → `2026-07-11 周六`）
- 详情页重构成 3 段：关联行（日期/优先级/当前 一行）→ 任务标题+分类+描述 → 时间记录列表
- 领域模型再改：`Membership` 从 `kind` 枚举回归到 `{ day: Day?, isCurrent: Bool, priority: Priority }` 三字段，日期和当前**可同时存在**、独立编辑
- TimeEntry 语义变化：`startAt` 变可选（nil = 已建但未开始）；工作流从"开始即建"改成"先建后开始"
- 新命令：`addEntry` / `startEntry(id)` / `endEntry(id)`；`marker` 与 `startEntry` 解耦（marker 由用户单独设，restart 场景保留自动填 marker）
- Backlog 定义相应更新：`!membership.isInAnyCollection && status != .done`
- 又一轮改动：
  - 状态搬到第二部分标题前（不再是关联属性）
  - 优先级加 emoji（❗️/🔶/无）；列表标题前缀 emoji、去次行、按分类分组
  - 时间记录加 workType 显示编辑、时间只显示 HH:mm、时间随时可编辑
  - `Membership.day: Day?` → `days: Set<Day>`（任务可属多日期）
  - "当前" 改成正交 filter：`showCurrent` 独立于日期，可与日期/backlog 组合过滤
  - Backlog 定义再改：`days.isEmpty && status != .done`（isCurrent 与 Backlog 判定完全解耦）
  - 右键从"归属"改成"添加到 / 从 X 移除"
  - 自制 `MiniCalendarView`：月历带任务小点，用于选日期
- 又一轮：
  - 时间记录追加到末尾（去掉 view 里的 `.reversed()`）
  - `WorkCategory` 从 enum 改成 name-based struct；`AppSettings` 保存分类和工作类型两个可编辑清单，独立 `settings.json`
  - 设置界面 `SettingsView`（gear 图标打开）：分类/类型双列表增删移
  - Marker 显示名："再开始" → "开始新阶段"（enum case 名保持 `.restart` 不动）
  - 描述改成 双栏：源码 TextEditor 左，`MarkdownRenderView` 右实时渲染（headings/列表/引用/代码块/inline markdown）；纯 SwiftUI 单栏 WYSIWYG 成本高，先做双栏
- 再一轮：
  - 分类和工作类型都改成 `{id, name}` 稳定 UUID 的对象（`CategoryDef` / `WorkTypeDef`）；任务用 `categoryId`，TimeEntry 用 `workTypeId`；改名不掉关联
  - `TaskQueries.groupByCategory` 支持"改名保留"、"删除→(未知)"、"nil→(未设置)"三种展示
  - 状态推导规则改成"最后一个有标记录"权威：无 marker 的 entry 不改变已有 done 状态，但空任务里出现任何 entry 就算进行中
  - Markdown preview 之前用 HStack 布局被 TextEditor 抢空间挤没了；改成 `HSplitView`（用户可拖分隔线）
- 再改 markdown preview：`AttributedString(markdown:)` 在 macOS 上默认 `.full` 解析会用 `presentationIntent` 属性，而 SwiftUI 的 `Text(AttributedString)` **不渲染**这些块级属性 —— 所以 preview 看起来跟源码一样。改用 `Text(LocalizedStringKey(raw))` —— SwiftUI 内建 markdown 支持，`**bold**`/`*italic*`/`` `code` ``/链接都能识别；再叠加自定义的块级解析器（heading/list/quote/code）；layout 从 `HSplitView` 换回 HStack 显式 50/50 保稳
- 侧栏下拉的今天/昨天/明天条目：`daysWithTasks` 命中时后缀加 ● 提示
- markdown preview 用户误以为没生效 —— 实际是他输入了 `** sdf **`（星号内外有空格），按 CommonMark 规范不算粗体；解释后确认预览生效
- 时间记录行：工作类型 Picker 移到标题前
- 切换 filter 到空列表时自动清空选中和详情（`store.pruneSelectionIfOffscreen()` + ContentView `.onChange`）
- 侧栏下拉底部（当 filter 是 .day 时）加 "把未完成推到别一天…" —— `pushUncompleted(from:to:)` 把源日下 status ≠ done 的任务的 `days` 补上目标日
- 目录重构：`projects/tasker/app/` → `app/tasker/`；`projects/tasker/` 只留 overview/tasks/log；新增顶级 `app/` 目录写入 `knowledge-structure.md`
- 设置里加"数据目录"配置：`UserDefaults` 存路径（key = `tasker.dataRoot`，独立于数据目录本身），运行时 `WorkspaceStore.setDataRoot(url)` 热重绑 repo；未配置时默认仍是 `~/Documents/tasker/`
- Bug 修：优先级是"任务-每天关联"的独立属性，不是全局。之前 `Membership.priority` 一份共享导致 A 天改优先级 B 天跟着变
  - 模型改：`dayAssignments: [DayAssignment{day, priority}]` + `currentPriority`；Codable 保留旧格式兼容
  - `pushUncompleted` 复制源日 priority 到目标日
  - 列表、详情、右键都按 filter 上下文取 `priority(in:)`；详情第一部分改成每个 day chip 前带独立可编辑的 emoji
- Backlog 定义再放宽：**所有未完成任务**（含已归属某天的）。之前是"未归属任何天 && 未完成"，现改为"未完成"一个条件
- UI 全部改英文（domain displayName、Views、错误消息、defaults 的分类/工作类型名）；日历用系统 locale
- 写 `docs/tasker-storage.md` —— 磁盘存储格式说明（目录布局、jsonl 字段、状态推导规则、时间戳精度、旧格式兼容、手工编辑注意事项）
- 新属性 `TaskMeta.isRecurring`：循环任务
  - `statusForDay(_)`：只看 startAt 落在该天的时间记录，独立推导；`status(in filter)` 循环任务 + `.day(d)` 走 statusForDay，否则走全局 status
  - Backlog 过滤：`$0.status != .done || $0.meta.isRecurring` —— 循环任务永远在 Backlog
  - `pushUncompleted`：循环任务用 `statusForDay(sourceDay)` 判定；已在源日完成的循环任务不推
  - 详情第一部分加"循环" toggle；状态徽章 + 侧栏行状态点都改用 `status(in: dayFilter)`；徽章旁标"循环"胶囊
  - 存储向前兼容：无 `isRecurring` 字段的旧任务默认 false

## 2026-07-15 10:48

- 修复 Backlog 里“Add to Today/Tomorrow/Choose date”时优先级丢失：新增 day assignment 时继承当前 filter 中显示的优先级
- 调整重复任务在 Backlog 中的上下文状态展示：即使全局 status 是 done，Backlog 里显示为 notStarted
- `swift run --package-path app/tasker taskerCheck` 通过（21/21）；`swift build --package-path app/tasker` 通过

## 2026-07-15 11:02

- 发布 `v0.4.4`：提交 `20d43e9` 已推送到 `origin/main`，tag `v0.4.4` 已推送触发 GitHub Actions Release
- 本机 `gh` 未登录，无法从 CLI 查询 workflow 状态；需到 GitHub Actions / Releases 页面确认完成

## 2026-07-15 11:18

- 模型修正：`TimeEntry` 不再直接挂在 Task 全局下，改为挂在 `DayAssignment.entries`（任务↔某天关联）下；`priority`、`isCurrent`、`entries` 都是某天关联属性
- 数据迁移：启动时读取旧 `entries.jsonl`，按 `startAt` / `endAt` / 最早 assignment / today 规则迁入对应 `DayAssignment.entries`，再把旧文件归档为 `entries.legacy.jsonl`（或 `entries.legacy-<uuid>.jsonl`）
- UI/统计同步：详情页按当前日期（Backlog 默认 today）展示和新增 entries；Stats 直接按 DayAssignment 汇总，不再靠 `startAt` 反推归属
- 防误删：有时间记录的 day assignment 不允许直接移除或清空，避免删除历史记录

## 2026-07-15 12:30

- 发布 `v0.4.5`：提交 `205e149` 已推送到 `origin/main`，tag `v0.4.5` 已推送触发 GitHub Actions Release
- 本地 release 验证通过：`cd app/tasker && swift build && swift run taskerCheck`（22/22）

## 2026-07-16

- Stats 视图加两处交互：
  - 行选中：Day / Task / Entry 三种行都可点击高亮（背景色，再点一次取消）；用 `StatsRowID` 枚举做唯一 id，`StatsView` 持有单选状态
  - 顶部时间刻度：`HourRulerHeader` + `HourRuler`，0-24 小时，每 3 小时一大刻度带 `HH` 数字标签；用与行相同的 260/200/flex/70 列宽和 4px 横向 padding 保持和下方 Gantt 严格对齐
- `swift build` + `taskerCheck`（22/22）通过

## 2026-07-16 10:29

- 发布 `v0.4.6`：提交 `14274e0` 已推送到 `origin/main`，tag `v0.4.6` 已推送触发 GitHub Actions Release

## 2026-07-16 后续

- Stats 时间刻度太高，压缩：`tickHeight` 12→5、`labelHeight` 11→10（字号 9→8）、header 顶部 padding 6→2；总高度从 ~33 降到 ~17

## 2026-07-16 13:05

- 发布 `v0.4.7`：提交 `7cbc21b` 已推送到 `origin/main`，tag `v0.4.7` 已推送触发 GitHub Actions Release

## 2026-07-19 Stats

- HourRuler 从 `GeometryReader + ZStack + ForEach` 换成 `Canvas` 一次性绘制刻度和标签；`tickHeight` / `labelHeight` / `totalHeight` 提为 static，header 用 `Spacer` 替 `Color.clear` 并显式 `.frame(height:)` 与刻度对齐；StatsView 主体加 `.frame(maxWidth: .infinity, alignment: .topLeading)`

## 2026-07-19 Sidebar

- 侧栏任务右键菜单新增两项：`Copy description path`（复制描述 `.md` 全路径到剪贴板）和 `Show in Finder`（`NSWorkspace.activateFileViewerSelecting`）。`WorkspaceStore` 暴露 `descriptionURL(for:)`，实际路径由 `repo.layout.descriptionURL` 提供，避免视图直接依赖 `StorageLayout`

## 2026-07-19 发布

- 发布 `v0.4.8`：提交 `c54580a` 已推送到 `origin/main`，tag `v0.4.8` 已推送触发 GitHub Actions Release
