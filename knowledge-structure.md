# the-workspace 知识库结构

> 本工程的目录组织方式。新增/修改任何目录需先与用户确认。修改本文件也需先确认。

## 顶级目录

工程为新建仓库，暂无业务目录。已有的仅为 AI 协作配置：

- `.claude/` — 项目级 Claude Code 配置（hooks、skills、settings）
- `.claude_global/` — 3 个软链，指向 `~/.claude/` 下的全局配置（gitignored）
- `docs/` — 文档（含 `docs/modeling/` DCDDP 系统模型；`docs/modeling/viewer/` 静态 viewer，gitignored）
- `projects/` — 项目模式下的 initiative 容器（按需创建）；只放项目文档 (overview/tasks/log/design)，**不放代码**
- `app/` — 实际应用代码根目录，每个 app 一个子目录（如 `app/tasker/`）；`projects/<name>/` 与 `app/<name>/` 通常同名，前者是项目管理产物，后者是实际交付物

（后续新增业务目录时，请先与用户对齐用途后再写入本文件。）

## projects/<name>/ 文件约定（若使用项目模式）

- `overview.md` — 项目目标
- `tasks.md` — 任务列表
- `log.md` — 日志
- `design.md` — 设计（可选）
