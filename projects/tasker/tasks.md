# tasker tasks

## 完成（第二轮：模型重构 + 交互调整）

- ✅ 时间记录加 title / workType（`WorkType` 从 Task 下沉到 TimeEntry）
- ✅ 优先级下沉到 Membership（关联对象），不再是 Task 属性
- ✅ 合并 `DayMembership` / `CurrentMembership` → 单个 `Membership { kind, priority }`；任务同时最多一个集合
- ✅ 侧栏改下拉菜单：今天 / 昨天 / 明天 / 选日期 / 当前 / Backlog
- ✅ 新建任务弹标题输入 sheet（Cmd+N 触发）
- ✅ 列表右键菜单：改优先级 / 归属（今天、明天、选日期、当前、Backlog）/ 删除
- ✅ 详情：标题 + 优先级放最上面（详情顶部编辑优先级也支持）
- ✅ 分类下沉到详情第二行（简化，不再是主要属性）
- ✅ 时间记录：标题 / 类型 / 开始时间 DatePicker / 结束时间 DatePicker / 结束 toggle / marker 可切
- ✅ 17 项 check 全绿

## 完成（第一轮）

- ✅ 定存储目录约定（`~/Documents/tasker/tasks.jsonl` + `entries.jsonl` + `descriptions/<uuid>.md`）
- ✅ SwiftPM 工程骨架（放弃 Xcode 依赖，用 CLT + `swift build`）
- ✅ 领域层：`TaskMeta` / `TimeEntry` / `TaskAggregate` / 值对象（Day / WorkCategory / Priority）
- ✅ 状态推导：`StatusDeriver`
- ✅ 领域查询：`TaskQueries` + `TaskFilter`（当前 / 某天 / Backlog）
- ✅ 断言 harness（`taskerCheck` 可执行 target 替代无法工作的 `swift test`）
- ✅ 仓储层：`FileRepository` + `JsonlFile` + `StorageLayout`
- ✅ 时间精度修复：ISO8601 加 fractional seconds，避免同秒记录顺序丢失
- ✅ 磁盘 mtime poll（10s 定时通过 `WorkspaceStore` 检测重载）
- ✅ UI 骨架：`ContentView` + `SidebarView`（过滤器 + 列表 + 新建按钮）+ `TaskDetailView`
- ✅ 任务详情：标题 / 分类 / 类型 / 优先级 / 集合归属 / 描述 markdown / 时间记录列表
- ✅ 打卡动作：开始 / 暂停 / 完成 / 再开始
- ✅ 端到端场景 check + app 启动烟测

## 待办 / 未做

- 🔘 UI 手动交互验证（新建、切换过滤器、编辑描述、打卡、删除，我没法在这台机上代替用户点）
- 🔘 描述编辑器：目前是纯文本 monospace，未做 markdown 预览
- 🔘 app icon / dock 图标
- 🔘 打包 `.app` bundle（需装 Xcode）
- 🔘 磁盘 mtime 冲突调解目前是 "reload 覆盖"，若同时改同一 task 会丢失最新一方；后续需三向合并或以 updatedAt 决胜
