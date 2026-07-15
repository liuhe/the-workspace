# tasker 存储格式

tasker 的数据全部落在本地磁盘上。默认根目录 `~/Documents/tasker/`，用户可在 app 设置里换（路径存 macOS `UserDefaults` 的 `tasker.dataRoot` 键）。以下所有路径都相对数据根目录。

## 目录布局

```
<root>/
├── settings.json              # 分类和工作类型的可编辑清单（含稳定 UUID）
├── tasks.jsonl                # 任务元信息 + 日期关联 + 时间记录，每行一个任务
├── entries.legacy.jsonl       # 旧版 entries.jsonl 迁移后的归档（如发生过迁移）
└── descriptions/
    └── <task-uuid>.md         # 每个任务的描述文本（markdown）
```

- 结构化字段用 **JSONL**（每行一个 JSON 对象）方便 diff、grep、按行追加，也方便手工编辑。
- 描述作为大字段独立存储为 `.md` 文件，路径由任务 id 决定。
- 结构化文件是原子写：先写临时文件再 `rename` 覆盖，防止半写坏文件。
- app 启动时全量加载所有 jsonl 到内存；每 10s 检查文件 mtime，外部修改会自动重载。

## `settings.json`

一整份 JSON 对象。两个数组，每个元素带稳定 UUID —— 改名字不会影响任务的引用。

```json
{
  "categories": [
    { "id": "DD0E9FC0-9037-43F6-B75E-6C4BA97F078E", "name": "Daily follow-up" },
    { "id": "3114879A-BA37-4149-88B2-AC018909E035", "name": "Meeting" }
  ],
  "workTypes": [
    { "id": "42492DAB-A3CE-4483-976D-21C2901202A5", "name": "Unspecified" },
    { "id": "54950CF8-CEF6-4C35-8CE8-961052D14952", "name": "Coding" }
  ]
}
```

- **categories**：任务的"工作分类"（每个任务通过 `categoryId` 引用一个）。
- **workTypes**：时间记录的"工作类型"（每条 entry 通过 `workTypeId` 引用一个）。
- 如果任务/记录引用了不在这里的 id（已删除），app 里会显示为 `(Unknown)`。

## `tasks.jsonl`

每行是一个 `TaskMeta` 对象。`membership.dayAssignments[]` 是任务↔某天的关联；时间记录挂在该关联的 `entries[]` 下。

```json
{
  "id": "8F3C1D0A-2E5B-4A9F-8B7C-1D2E3F4A5B6C",
  "title": "Ship v1",
  "categoryId": "3114879A-BA37-4149-88B2-AC018909E035",
  "membership": {
    "dayAssignments": [
      {
        "day": "2026-07-11",
        "priority": "todayMustReach",
        "isCurrent": true,
        "entries": [
          {
            "id": "AB123456-7890-1234-5678-9ABCDEF01234",
            "title": "Draft outline",
            "workTypeId": "54950CF8-CEF6-4C35-8CE8-961052D14952",
            "startAt": "2026-07-11T13:00:00.000Z",
            "endAt": "2026-07-11T14:30:00.000Z",
            "marker": "done"
          }
        ]
      },
      {
        "day": "2026-07-12",
        "priority": "important",
        "isCurrent": false,
        "entries": []
      }
    ]
  },
  "isRecurring": false,
  "createdAt": "2026-07-11T10:30:00.123Z",
  "updatedAt": "2026-07-11T15:45:00.456Z"
}
```

字段说明：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 任务唯一标识 |
| `title` | String | 标题 |
| `categoryId` | UUID? | 引用 `settings.categories[].id`；`null`/缺失 = 未设置 |
| `membership` | object | 任务与日期集合的关联（见下） |
| `isRecurring` | Bool | 循环任务：完成状态按天独立，且始终出现在 Backlog |
| `createdAt` | ISO8601 (ms) | 创建时间 |
| `updatedAt` | ISO8601 (ms) | 最近一次修改时间 |

### `membership.dayAssignments[]`

| 字段 | 类型 | 说明 |
|---|---|---|
| `day` | String `yyyy-MM-dd` | 集合日期 |
| `priority` | String | `todayMustReach` / `important` / `normal` |
| `isCurrent` | Bool | 该任务在这一天是否被标记为"当前" |
| `entries` | Array | 这一天实际发生的时间记录 |

**要点**：优先级、"当前"标和时间记录都是**任务↔某天关联属性**，不是任务全局属性。同一任务在 07-11 可以是"必达 + 当前 + 两条记录"，在 07-12 可以是"普通、非当前、无记录"，改一天不影响另一天。任务的"是否 current"从各天关联汇总（任一天为 current 即视为在当前集合里）。

有时间记录的日期关联不能直接移除，避免误删历史记录。

### `entries[]`

每个元素是一个 `TimeEntry` 对象：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 记录唯一标识 |
| `title` | String | 这段活干了什么（可空） |
| `workTypeId` | UUID? | 引用 `settings.workTypes[].id`；`null`/缺失 = 未设置 |
| `startAt` | ISO8601 (ms)? | 开始时间；`null` = 已建但未开始 |
| `endAt` | ISO8601 (ms)? | 结束时间；`null` = 还没结束（进行中） |
| `marker` | String? | `done` / `restart` / `null` |

`TimeEntry` 不再存 `taskId`：它的归属由所在的 `TaskMeta.membership.dayAssignments[].entries[]` 决定。

### 状态推导规则

任务的 `status`（未开始/进行中/完成）不独立存储，从时间记录汇总：

1. 遍历所有记录，找**最后一个带 marker** 的（按 `startAt` 升序，`null` 排最后）。
2. 如果有：`marker == done` → 完成；`marker == restart` → 进行中。
3. 如果找不到带 marker 的：**有任何记录** → 进行中；一条都没 → 未开始。

**循环任务**在"某天"视图下，只看该天 `DayAssignment.entries` 来推导 —— 完成状态就此按天独立。循环任务在 Backlog 中固定显示为未开始。

## 旧版 `entries.jsonl` 迁移

旧版把时间记录单独存在 `<root>/entries.jsonl`，每行包含 `taskId`。新版启动时如果发现非空 `entries.jsonl`，会自动迁移：

1. 有 `startAt`：迁到 `Day(startAt)` 的 `DayAssignment.entries`。
2. 无 `startAt` 但有 `endAt`：迁到 `Day(endAt)`。
3. `startAt == nil && endAt == nil`：
   - 任务只有一个 day assignment → 归那一天
   - 任务有多个 day assignment → 归最早那一天
   - 任务没有 day assignment → 归今天，并自动创建 today assignment
4. 如果目标 day assignment 不存在，迁移时自动创建，`priority = normal`、`isCurrent = false`。
5. 迁移写回新版 `tasks.jsonl` 后，旧文件会移动为 `entries.legacy.jsonl`；如果该文件已存在，则移动为 `entries.legacy-<uuid>.jsonl`。

新版不会再写 `entries.jsonl`。

## `descriptions/<uuid>.md`

任务的描述文本，纯 markdown。文件名 = 任务 id。任务被删除时对应文件也会删除。

## 时间戳格式

所有时间戳都是带毫秒精度的 ISO 8601（例：`2026-07-11T13:00:00.123Z`）。
用秒精度会导致同一秒内多条记录的顺序丢失，进而状态推导可能选错"最后一条"。

## 手工编辑

- `tasks.jsonl`、`settings.json` 和 md 都是文本，你可以直接用编辑器改。
- app 每 10s 检查文件 mtime，外部修改会被检测到并重载。
- 写盘时也会先检查磁盘 mtime，避免用旧的内存版本覆盖你的手改。
- **但同一时刻在 app 里改 + 手动改同一条**仍可能丢一方 —— last-write-wins，没做三向合并。
