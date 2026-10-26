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

## 2026-07-28 详情日期下拉改成切换器

- `TaskDetailView.MembershipBar` 的 Days 下拉从只读改成侧栏日期切换器：点击某条 assignment 直接 `store.dayFilter = .day(a.day)`
- 下拉 label 从 `Days (N)` 改成显示"当前那天"：Day filter 时 = filter 那天；Backlog 时 = 最后一个 assignment day（空则 today）
- `WorkspaceStore.entryDayForCurrentFilter` → 公开成 `entryDay(for: agg)`，Backlog 分支从 `Day.today()` 改成 `assignments.map(\.day).max() ?? today`；`addEntry`、详情 EntriesSection、下拉 label / checkmark 都用它 —— 三处一致
- `taskerCheck` 22/22 通过
- Sidebar 行的"👀 当前"标志在 Backlog filter 下不显示（`isCurrentInContext` Backlog 分支从 `hasAnyCurrent` 改为 `false`）；"当前"是 day-relation 属性，Backlog 没有当天上下文，展示无意义

## 2026-07-28 发布

- 发布 `v0.4.9`：提交 `efec768` 已推送到 `origin/main`，tag `v0.4.9` 已推送触发 GitHub Actions Release

## 2026-07-28 状态推导忽略未来记录

- `StatusDeriver.derive(from:now:)` 在推导前过滤掉 `startAt > now` 的 entry：预排计划不算进"进行中"，纯未来 entry → notStarted，未来 done marker 也不算 done
- 无 startAt（已建未开始）保留原行为 —— 只过滤明确在未来的时间点
- 新增 check 覆盖，taskerCheck 23/23

## 2026-07-28 发布

- 发布 `v0.4.10`：提交 `3c7cede` 已推送到 `origin/main`，tag `v0.4.10` 已推送触发 GitHub Actions Release

## 2026-07-28 详情日期下拉去掉 👀 当前标

- `TaskDetailView.dayListItem` 去掉 `if a.isCurrent { parts.append("👀") }`；下拉只显示日期 + 优先级 emoji，与 sidebar 保持一致（👀 只在右侧 Current toggle 里体现）

## 2026-07-28 发布

- 发布 `v0.4.11`：提交 `52ab879` 已推送到 `origin/main`，tag `v0.4.11` 已推送触发 GitHub Actions Release

## 2026-07-28 markdown 编辑器过滤孤立 `<br>` 行

- `MarkdownWebEditor` 在 `setMarkdown` 与 `change→Swift` 两个方向都调用 `normalizeMarkdown(md)`，剥掉整行只有 `<br>` 的行
- 起因：Toast UI WYSIWYG 里的空段落会被序列化成一串 `<br>` 存进 markdown；下次以 WYSIWYG 打开这段 markdown 时不生成可放光标的实体块，光标停在 `<br>` 区域按退格会跨过它删掉上面最后一个列表项
- 加载/保存两个方向都清理，session 内再产生的 `<br>` 保存回磁盘时也会被清掉

## 2026-07-28 发布

- 发布 `v0.4.12`：提交 `0d01646` 已推送到 `origin/main`，tag `v0.4.12` 已推送触发 GitHub Actions Release

## 2026-07-28 markdown 编辑器 mid-session 也清 `<br>`

- v0.4.12 只在 setMarkdown / change→Swift 清 `<br>`；粘贴 mid-session 场景下 WYSIWYG DOM 里的 `<br>` 空段仍在，退格照样删列表项
- 改成 `change` 里检测 `normalized !== raw` 时直接 `editor.setMarkdown(normalized, false)` 立即重设 editor；`suppressChange` guard 防死循环
- 副作用：清理时光标位置丢失（只在真需要清 artifact 时触发，正常输入不会命中）

## 2026-07-28 保留光标位置

- `MarkdownWebEditor` change 里清 `<br>` 之前记 `getCursorTextOffset()`（跨 text node 累加字符偏移），`setMarkdown` 之后 `setTimeout` 里 `setCursorTextOffset(offset)` 恢复
- 用文本字符偏移而非 prosemirror position：`<br>` 空段不含文本，删掉后其后内容的字符偏移不变，光标停留在同一文本处
- 越界时钳到文档末尾

## 2026-07-28 发布

- 发布 `v0.4.13`：提交 `aaf28da` 已推送到 `origin/main`，tag `v0.4.13` 已推送触发 GitHub Actions Release

## 2026-08-05 侧栏状态过滤下拉

- 侧栏右上"Current" 单开关 → 下拉菜单（漏斗图标，激活时填充），含 3 个独立 Toggle：只显示当前 / 隐藏已完成 / 隐藏未开始
- `TaskQueries.apply` 新增 `hideCompleted` / `hideNotStarted` 参数，按 `status(in: filter)` 过滤（循环任务在 `.day(d)` 用当日状态）
- `WorkspaceStore` 新增 `hideCompleted` / `hideNotStarted` @Published；`ContentView` 在其变化时 `pruneSelectionIfOffscreen`，navTitle 追加 `-Done` / `-NotStarted` 标签

## 2026-08-05 发布

- 发布 `v0.4.14`：提交 `d3d3dc4` 已推送到 `origin/main`，tag `v0.4.14` 已推送触发 GitHub Actions Release

## 2026-08-05 侧栏过滤菜单英化

- 新增的 3 个 Toggle + tooltip 遗漏为中文，改成 English：Current only / Hide completed / Hide not started
- overview.md 补上"UI 文案统一英文"约定，避免下次再踩

## 2026-08-05 发布

- 发布 `v0.4.15`：提交 `e7b6246` 已推送到 `origin/main`，tag `v0.4.15` 已推送触发 GitHub Actions Release

## 2026-08-05 日期下拉重构 & 星期英化

- 侧栏日期下拉：`Today/Yesterday/Tomorrow` 相对词 → 直接展示 ±3 天（共 7 天）日期，每项 `YYYY-MM-DD EEE`；今天前缀 `★`，有任务的日子后缀 `●`；选中态用 `Toggle` 原生勾选（Backlog 同）
- 触发按钮 label 也去掉相对词，直接显示日期
- 右键任务 "Add to" 同款改造：±3 天日期列表 + `Choose date…`；今天 `★`、已归属日 `●`
- `Day.weekdayLabel` 默认 locale 从 `.current`（会漂到中文短名）改成 `en_US`；`MiniCalendarView` 星期表头同步强制 `en_US`
- overview 的 "UI 文案统一英文" 约定收紧：明确覆盖星期名/日期格式化输出

## 2026-08-05 发布

- 发布 `v0.4.16`：提交 `9aaf5bb` 已推送到 `origin/main`，tag `v0.4.16` 已推送触发 GitHub Actions Release

## 2026-08-05 侧栏按开始时间排序

- `.day(d)` 视图：`sortForDisplay` 主键改为当天最早 `startAt` 升序，无 `startAt` 的排后；同档再按 priority、updatedAt desc
- `.backlog` 视图不受影响（时间维度对 backlog 无意义）
- Check 新增 2 个用例锁定行为（有/无 startAt 混合排序、backlog 保持 priority 主导）

## 2026-08-11 发布

- 发布 `v0.4.17`：提交 `abba1ef` 已推送到 `origin/main`，tag `v0.4.17` 已推送触发 GitHub Actions Release

## 2026-08-20 Stats 支持日期范围

- `StatsView` 头部新增 `DateRangePicker`（两个 `.date` DatePicker + "→"），默认起止 = today-2 → today（含今天最近 3 天）
- `StatsBuilder.build` 加 `range: ClosedRange<Day>?` 参数：非空时按 `assignment.day` 过滤；nil 保留原行为
- 起止反向时自动归正为 `min...max`；范围内无 entries 显示 "No timed entries in this range."

## 2026-08-20 发布

- 发布 `v0.4.18`：提交 `8634afb` 已推送到 `origin/main`，tag `v0.4.18` 已推送触发 GitHub Actions Release

## 2026-08-21 TimeEntry 时间读取忽略日期部分

- 背景：`TimeEntry.startAt`/`endAt` 存 `Date?`（含年月日），entry 归属由 `DayAssignment.day` 决定 → 用户编辑时分时日期部分可能漂移；Stats/排序按 raw Date 时会失真
- 策略：**存储不动**（`Date?`），**读处理时丢日期只取时分秒**，日期一律用 assignment.day 锚定
- 新 helper（`TimeEntry.swift`）：`startAt(inDay:)`, `endAt(inDay:)`, `duration(inDay:)`
- 更新读取点：
  - `TaskDayStat` 带 `day` 字段；`ranges`/`totalDuration` 走 helper
  - `StatsBuilder.build` 内部按 `startAt(inDay: day)` 排序
  - `StatsView.EntryRow`：Gantt range 和 duration 走 helper
  - `TaskQueries.sortForDisplay` day 分支：`.min()` 前先经过 helper
- 未改（本次范围外）：`StatusDeriver`（future 过滤跨天语义）、`Task.entrySortComparator`（DayAssignment 内同日排序）、`TaskDetailView` DatePicker 写入路径
- Check 新增 2 个用例锁定 helper 行为；总计 27/27 通过

## 2026-08-21 发布

- 发布 `v0.4.19`：提交 `016d6b5` 已推送到 `origin/main`，tag `v0.4.19` 已推送触发 GitHub Actions Release

## 2026-08-25 重复任务自动带上一次的时间

- 场景：重复任务在新的一天新建首条 entry 时，用户几乎总会填相同的时分；手动填是重复劳动
- `TaskAggregate.entryTimeToCarry(to day:)`：仅重复任务；往前找最近一天里第一条已完成（start+end 都非 nil）的 entry；时分锚定到 `day` 返回
- `WorkspaceStore.addEntry`：add 前记 `wasEmpty = entries(inDay: day).isEmpty`；add 后若 wasEmpty 且 helper 有值就 updateEntry 填上
- Check 加 4 个用例：正常复制、非重复返回 nil、跳过只有 in-progress 的日子、无更早数据返回 nil；总 31/31

## 2026-08-25 发布

- 发布 `v0.4.21`：提交 `1238158` 已推送到 `origin/main`，tag `v0.4.21` 已推送触发 GitHub Actions Release（v0.4.20 已被之前的 markdown-lib 编辑器工作占用）

## 2026-08-26 markdown editor 切到 markdown-lib

- 读 `https://github.com/liuhe/markdown-lib/blob/main/INTEGRATING_MARKDOWNEDITOR.md` 后，`tasker` target 新增 `markdown-lib` package 依赖和 `MarkdownEditor` product
- 本地 `MarkdownWebEditor.swift` 不再维护内联 Toast UI / WKWebView 实现，改成 `TaskMarkdownEditor` 薄包装：内部使用 `DocumentStore` + `EditorBridge` + `MarkdownEditor.MarkdownWebEditor`，外部仍暴露 `Binding<String>` 给 `WorkspaceStore.currentDescription`
- 传入描述文件 URL 和 data root：link/open/drop 交给 `NSWorkspace`，`Cmd+Shift+K` 用 `NSOpenPanel` 插入相对文件链接，图片粘贴写入 `<description>.assets/paste-yyyymmdd-HHmmss.ext`
- 验证：`swift build --package-path app/tasker` 通过；`swift run --package-path app/tasker taskerCheck` 27/27 通过

## 2026-08-26 发布

- 发布 `v0.4.20`：提交 `8fa0ccb` 已推送到 `origin/main`，tag `v0.4.20` 已推送触发 GitHub Actions Release

## 2026-09-09 日期完成标记

- 模型补充：某天集合可被用户标记完成；后续有任务新加入该日期集合时自动清除该日期完成标记
- 存储新增 `day-completions.json`，由 `FileRepository.loadCompletedDays/saveCompletedDays` 读写，mtime poll 纳入外部变更检测
- `WorkspaceStore.completedDays` 驱动 UI；`createTask`、`addToDay`、`pushUncompleted`、Backlog 下 `addEntry` 造成新日期关联时会清掉目标日期完成标记
- 日期下拉、选日期日历、Add to 日期菜单、详情日期下拉、窗口标题都显示完成日 `✓`；当前日期下拉里新增 `Day completed` toggle
- 验证：`swift build --package-path app/tasker` 通过；`swift run --package-path app/tasker taskerCheck` 32/32 通过

## 2026-09-10 发布

- 发布 `v0.4.22`：提交 `da62d1a` 已推送到 `origin/main`，tag `v0.4.22` 已推送触发 GitHub Actions Release

## 2026-10-25 本机启动

- `swift build --package-path app/tasker --product tasker` 后直接跑 debug 产物 `app/tasker/.build/x86_64-apple-macosx/debug/tasker`（nohup 后台，日志 `/tmp/tasker.log`）

## 2026-10-25 侧栏“所有日期”模式

- 模型：任务集合新增“所有日期（虚拟视图）”——天升序 → 分类 → 任务，Backlog 为最后一组；每行状态 / 优先级 / 当前标按该行所属天的上下文计算；状态开关逐天应用，过滤后为空的天不显示
- 领域层 `TaskQueries`：新增 `ListScope { day, backlog, allDays }`（侧栏范围）与 `TaskFilter { day, backlog }`（行上下文）分离；`DayGroup` + `groupAllDays` 产出 天 → 分类 → 任务
- `WorkspaceStore`：`dayFilter: TaskFilter` 改名 `scope: ListScope`；新增 `selectedContext`（所有日期模式下选中行所属上下文）和 `contextFilter`（详情页 / 命令统一使用）；`setPriorityInFilterContext` 改为 `setPriority(id:in:priority:)` 显式传上下文；`pruneSelectionIfOffscreen` 在所有日期模式下按 (任务, 上下文) 判断
- `SidebarView`：过滤菜单加 `All days`；列表选中类型改为 `RowRef { taskId, context }`，同一任务在多天下各自独立选中；`TaskRow` / `TaskContextMenu` 不再读 store 范围，改为接收所在行上下文；所有日期模式下分类名作为不可选的小标题行，天标题带 ★ / ✓
- `TaskDetailView` / `ContentView`：改用 `contextFilter` / `scope`；窗口标题 `All days`
- Check 新增 4 个用例（天排序 + Backlog 殿后、完成任务留天不进 Backlog + 空组丢弃、currentOnly 逐天、`ListScope.filter`）；总 36/36 通过
- 已用新构建重启本机 app；未提交

## 2026-10-25 所有日期模式：日期标题醒目 + 可折叠

- 用户反馈：日期标题不够明显；希望按日期折叠，并能一键全折叠
- 天分组改用 `Section(isExpanded:content:header:)`，自定义标题 `DayGroupHeader`（headline 粗体 + 任务数胶囊，今天用 accent 色）；分类小标题和任务行左缩进 8pt
- `WorkspaceStore.collapsedGroups: Set<TaskFilter>`（内存态，不落盘）+ `toggleCollapseAllGroups()`：有展开的就全折叠，全折叠了就全展开；顶栏在 All days 模式下显示 `CollapseAllButton`
- 验证：build 通过，check 36/36；已重启本机 app

## 2026-10-25 天分组标题整行可点击折叠

- 用户反馈：只能点最右边的小 chevron 折叠，希望点整行
- `DayGroupHeader` 加 `onToggle`，整行 `contentShape(Rectangle())` + `onTapGesture`，调用 `store.setGroupCollapsed` 取反；右侧原生 chevron 保留
- build 通过；已重启本机 app

## 2026-10-25 甘特图窗口

- 需求：统计按钮旁加按钮，弹独立窗口，选某一天 → 按分类分组的任务 + 带时间刻度的甘特图，可在图上直接点击 / 拖动改时间段，最小刻度 5 分钟
- 模型：overview.md UI 布局补"甘特图窗口"小节及直接编辑规则
- 领域层新增 `TimelineGrid`（`Sources/Domain/TimelineGrid.swift`）：以"距当天 0:00 的秒数"表达，`snap` / `move` / `resizeStart` / `resizeEnd` / `newRange` + Date 互转；与时区、UI 解耦
- `WorkspaceStore` 新增 `setEntryRange(taskId:entryId:inDay:start:end:)`、`addTimedEntry(taskId:inDay:start:end:)`（优先填该天未开始的占位记录，否则新建一条）
- `GanttView.swift`：`Window("Gantt", id: "gantt")`；分类色用 dataviz 默认 8 槽位分类色（按设置里分类顺序固定分配，不循环，超出归灰，深浅色各一套）；条身 / 左右 7pt 手柄各挂 `DragGesture(minimumDistance: 0)`，拖动中显示起止时间气泡，松手才写盘；空白处拖出新记录；底部 inspector 的 DatePicker 也吸附到 5 分钟
- 侧栏底部统计按钮右侧加 `calendar.day.timeline.left` 按钮
- 验证：build 通过；check 新增 5 个 TimelineGrid 用例，41/41 通过；已重启本机 app。甘特图拖动交互本机无法替用户点，待用户验证；未提交

## 2026-10-25 甘特图：底部选中条可改标题

- 用户已打开甘特图窗口验证渲染正常；问及同一行两个条 = 该任务当天两条时间记录，小条疑为空白处拖动误建
- 用户要求底部选中条支持直接编辑标题（时间 DatePicker 原本就可编辑）：标题改为 TextField，沿用详情页逐键 `store.updateEntry` 写盘的模式
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图：窄条标题外置

- 用户反馈：条太短时标题不显示；要求始终显示，超出条也没关系
- 条宽 ≤ 56pt 时标题改为用 primary 色画在条右侧（`fixedSize` + offset，不参与命中测试），否则仍白字写在条内
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图：窄条标题改为从条左边缘起写

- 用户反馈：外置标题希望从短条最左边开始，而不是从条右侧外面开始
- 外置标题 offset 由 `bw + 4` 改为 `4`，仍 primary 色、不参与命中测试
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图：选中任务模式

- 用户要求：点任务本身进入选中任务模式，底部变成任务编辑条（标题、分类、该天优先级）
- `GanttSelection` 由 struct 改为 enum `{ task(UUID), entry(taskId:entryId:) }`；任务行左侧标签整块可点，选中时行底高亮 + 标题加粗
- `GanttInspector` 拆为 `taskEditor`（标题 TextField、分类 Picker、优先级 Picker，复用详情页同样的 store 命令）和 `entryEditor`（原有记录编辑）
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图优先级前缀 + 新建任务按钮上移

- 甘特图任务标题前加该天优先级 emoji 前缀（`priority(in: .day(day)).titlePrefix`），与侧栏一致
- 侧栏 "New task" 从底栏移到顶栏范围下拉右侧，改为 `plus` 图标按钮，Cmd+N 保留
- 甘特图日期右侧加 `plus` 按钮；`WorkspaceStore.createTask(title:inDay:isCurrent:)` 新增显式归属日版本，原 `createTask(title:)` 改为按侧栏范围委托；`NewTaskSheet` 改为非 private 并接受 `targetDay`
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图：新建后自动选中

- `createTask(title:inDay:isCurrent:)` 改为返回新任务 id；`NewTaskSheet` 加 `onCreated` 回调；甘特图在回调里 `selection = .task(id)`
- build 通过；已重启本机 app；未提交

## 2026-10-25 分类颜色可在设置里指定

- 用户问甘特图色条颜色如何决定，并要求在设置页可配置
- 模型：`CategoryDef` 新增可选 `colorHex`；领域层 `CategoryPalette` 持有 8 槽位浅 / 深色表与解析规则（显式 > 槽位自动 > 灰）；`settings.json` 文档同步
- App 层 `CategoryColor`（hex ↔ Color、按外观解析）替代 GanttView 内的私有 GanttPalette
- 设置页 Categories 列表每行前加色块按钮，popover 内有 8 槽位色、Custom 取色器、Auto 复位；自定义色在浅 / 深色外观下用同一个值
- Check：settings roundtrip 加 colorHex 断言，新增 CategoryPalette 解析用例；42/42 通过
- build 通过；已重启本机 app；未提交

## 2026-10-25 提交

- 今天甘特图相关全部改动（窗口、TimelineGrid、选中 / 编辑、新建按钮上移、分类颜色设置）合为一个 commit 提交到 main；本机未提交的两处 `.claude/skills/aie-*` 删除不属于本次工作，未纳入

## 2026-10-25 时间记录"实际占用"

- 模型：`TimeEntry.actualMinutes: Int?`；`effectiveDuration` / `effectiveDuration(inDay:)` = 手动分钟数优先，否则起止差；只填分钟数没填起止也算占用
- 甘特图：任务行右侧合计、标题行最右 Total 都按实际占用；色块标题前 `(45m)` 括号前缀；选中记录的底部编辑条加 Actual 分钟输入（占位显示按起止算出的分钟数，清空 = 回退计算）
- 详情页记录行加同一个 `ActualMinutesField`，右侧时长改显示实际占用；统计窗口的任务 / 天合计与记录时长也改为实际占用（保持三处一致）
- 存储文档加 `actualMinutes` 字段；Check 新增 2 个用例（优先级规则、JSON 往返 + 旧数据缺字段），44/44 通过
- build 通过；已重启本机 app；未提交

## 2026-10-25 统计加分类层级 + 甘特图连续"现在"线

- 统计：`DayStat.categories: [CategoryDayStat]`，`StatsBuilder.build` 接收设置里的分类，复用 `TaskQueries.groupByCategory`；新增 `CategoryBlock` 行（缩进 24，任务 48、记录 72），分类行颜色走 `CategoryColor`
- 甘特图：原来"现在"线是每行 Canvas 各画一段（分类标题处断开，且 22 点时自动范围只到记录末尾所以看不见）。改为 `GanttNowLine` 覆盖层，从刻度底部贯穿整个列表区域，列几何与行布局常量一致；今天的自动可见范围包含"现在"
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图 Row per entry 模式

- 标题行加 `Row per entry` 开关（`@AppStorage("tasker.gantt.rowPerEntry")`）
- `GanttTrack` 增加 `items` 参数（这一行画哪些记录）；`GanttTaskRowView` 透传；新增 `GanttEntryRowView`（左侧起止时间、只画一条、右侧该条实际占用）
- 列表渲染：开关开且 `row.timed.count > 1` → 任务行 `items: []` + 每条记录一行；否则原样。新建 / 拖动 / 选中逻辑不变，新记录由数据驱动自然成为新行
- build 通过；已重启本机 app；未提交

## 2026-10-25 甘特图 Detail pane 模式

- `TaskDetailView` 改为接收显式 `context: TaskFilter`（Membership / Info / Entries 三段透传），不再直接读 `store.contextFilter`；`ContentView` 传 `store.contextFilter`
- Store：`addEntry(taskId:in:...)` 与 `entryDay(for:in:)` 增加显式上下文版本，原签名委托
- 甘特图：`Detail pane` 开关 + `detailPaneFraction`（默认 1/3，夹在 0.15–0.8，AppStorage 记忆）；选中任务且开关开 → 底部 `PaneDivider`（可拖、resizeUpDown 光标）+ `ScrollView { TaskDetailView(context: .day(day)) }`；选中同步调用 `store.selectTask(id:context:)` 以加载描述
- 过程：第一轮脚本在 TaskInfoSection 匹配失败中断（该 struct 多一个 `@State debounce` 行），分段重跑后通过
- build 通过；已重启本机 app；未提交

## 2026-10-25 提交（第二批）

- 实际占用、统计分类层级、连续"现在"线、Row per entry、Detail pane 合为一个 commit 提交到 main；`.claude/skills/aie-*` 删除仍未纳入

## 2026-10-25 发布 v0.5.0

- `git push origin main`（de113ff..0a0e2e6），tag `v0.5.0` 已推送触发 GitHub Actions Release：https://github.com/liuhe/the-workspace/actions/runs/40200847267
- 版本号从 v0.4.22 跳到 v0.5.0：甘特图整套功能属于新增特性，升次版本号
- 本机 `gh` 未登录，运行状态用公开 API 查看
- Release 工作流成功，产物 `tasker-0.5.0.zip` 已挂在 https://github.com/liuhe/the-workspace/releases/tag/v0.5.0

## 2026-10-26 甘特图加号菜单 + 从 Backlog 加入当天

- 领域层新增 `TaskQueries.backlogCandidates(forDay:matching:in:)`：Backlog 过滤结果中去掉已关联那天的任务，关键词去首尾空白后按标题 `localizedCaseInsensitiveContains` 匹配
- Store：`addToDay(id:day:from:)` 增加显式上下文参数（缺省仍用侧栏 `contextFilter`），从 Backlog 挑选时传 `.backlog`，优先级沿用 Backlog 上下文规则（最后一天关联的优先级）
- 甘特图标题行：原 plus 按钮改为 `Menu`（`borderlessButton` + 隐藏指示器），两项 New task… / Add from Backlog…；第二个 sheet 挂在 `.background(Color.clear.sheet)` 上避免同一视图两个 sheet
- 新文件 `Views/BacklogPickerSheet.swift`：TextField 过滤 + 多选 List + 空态提示 + 选中计数；回车 / Add / 双击三种加入方式；关键词变化时剔除已不可见的选中项
- 新增 check 1 项（45 全绿）；build 通过；已重启本机 app；未提交


## 2026-10-26 发布 v0.5.1

- 甘特图加号菜单 + Backlog 选择弹框提交到 main 并打 tag `v0.5.1`，推送触发 GitHub Actions Release
- 补丁号：单个窗口的交互增强，不升次版本号
- Release 工作流成功（https://github.com/liuhe/the-workspace/actions/runs/40258078778），产物 `tasker-0.5.1.zip` 已挂在 https://github.com/liuhe/the-workspace/releases/tag/v0.5.1

## 2026-10-26 侧栏加号也改为菜单

- 用户纠偏：v0.5.1 只改了甘特图，主界面侧栏的加号也要同样两项
- `SidebarView`：plus 按钮改 `Menu`（New task… 保留 Cmd+N 展示，实际由 App CommandGroup 触发 / Add from Backlog…）；目标日取 `store.contextFilter` 为 `.day` 的那天，否则第二项 disabled；复用 `BacklogPickerSheet`，加入后 `selectTask(id:context:)` 选中第一条
- build 通过；已重启本机 app；未提交、未发版


## 2026-10-26 发布 v0.5.2

- 侧栏加号菜单提交到 main 并打 tag `v0.5.2`，推送触发 GitHub Actions Release
- Release 工作流成功（https://github.com/liuhe/the-workspace/actions/runs/40259235712），产物 `tasker-0.5.2.zip` 已挂在 https://github.com/liuhe/the-workspace/releases/tag/v0.5.2

## 2026-10-26 甘特图色条无标题时回退到任务标题

- `GanttView` 新增 `entryLabel(_:)`：时间记录标题为空时色条文字和悬停提示都改用任务标题（任务也无标题才显示 `(Untitled)`），替换原 `(no title)`
- 用户追加：色条标题被 `...` 截断。原逻辑条宽 > 56 时标签放条内受 `lineLimit(1)` 截断，仅更窄的条才溢出显示
- 改为 `.overlay` 内 `ViewThatFits(in: .horizontal)`：第一候选条内白字（`fixedSize` + 两侧 handle 留白），放不下自动落到第二候选——从条左缘起 primary 色向右溢出；去掉 56 阈值；标签 `allowsHitTesting(false)` 不挡拖拽手势
- build 通过；check 45 全绿；已重启本机 app；未提交、未发版

## 2026-10-26 发布 v0.5.3

- 色条标题回退任务标题 + 不截断提交到 main 并打 tag `v0.5.3`，推送触发 GitHub Actions Release
- 补丁号：甘特图单窗口的显示修正，不升次版本号
- Release 工作流成功（https://github.com/liuhe/the-workspace/actions/runs/40261592408），产物 `tasker-0.5.3.zip` 已挂在 https://github.com/liuhe/the-workspace/releases/tag/v0.5.3

## 2026-10-26 甘特图删除时间记录

- 用例对齐主窗口记录列表：红色垃圾桶直接删、不弹确认；Store 已有 `deleteEntry(taskId:entryId:)`，领域层无改动
- `GanttView`：底部记录编辑条在实际占用字段后加垃圾桶按钮（删前清空 selection）；色条加 `.contextMenu` 一项 Delete entry（若删的正是选中记录同样清空 selection）
- overview 色条选中说明、tasks 列表已同步
- build 通过；check 45 全绿；已重启本机 app；未提交、未发版

## 2026-10-26 发布 v0.5.4

- 甘特图删除时间记录提交到 main 并打 tag `v0.5.4`，推送触发 GitHub Actions Release
- Release 工作流成功（https://github.com/liuhe/the-workspace/actions/runs/40262202714），产物 `tasker-0.5.4.zip` 已挂在 https://github.com/liuhe/the-workspace/releases/tag/v0.5.4

## 2026-10-26 色条拖动失效排查

- 用户反馈无法拖动把手改长度，怀疑是标题截断修复所致
- 分析：把手命中结构未变，标签层本就 `allowsHitTesting(false)`（与原窄条溢出标签同法）；v0.5.4 新加的色条 `.contextMenu` 在 macOS 上会吞掉 mouseDown、与 `DragGesture` 冲突，是更可能的原因
- 处理：标签 `ViewThatFits` 从 overlay 移回 ZStack 手势层之下；撤掉色条右键菜单，删除只保留底部垃圾桶；overview / tasks 同步
- 重启 app 后用户反馈"突然可以了"，时间上正好是去掉 contextMenu 的新构建；v0.5.4 发布版仍含 contextMenu，待发 v0.5.5 修正。未提交
