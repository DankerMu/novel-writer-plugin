## Why

用户体验与可操作性依赖稳定的入口命令：作者需要一个“状态感知的主入口”与两个高频快捷命令，才能在无会话历史（冷启动）条件下持续续写、查看状态并做关键审核决策。

## What Changes

- 定义并实现 3 个入口 Skills 的行为与边界：
  - `/novel:start`：状态检测 → 推荐下一步 → AskUserQuestion → 派发对应 Agent/流程
  - `/novel:continue [N]`：高频续写循环（调度 ChapterWriter→…→QualityJudge），默认 1 章
  - `/novel:dashboard`：只读状态展示（进度、评分、伏笔、成本/耗时）
- 明确交互边界：AskUserQuestion 仅允许在 `/novel:start` 中调用，子代理/Agents 禁止直接向用户提问
- 固化项目初始化的“最小可运行文件集”（checkpoint/state/global foreshadow/storyline spec 等）与目录创建规则

## Capabilities

### New Capabilities

- `entry-skills-orchestration`: 提供 3 个入口命令的确定性流程与边界，形成可持续的冷启动写作调度入口。

### Modified Capabilities

- (none)

## Impact

- 影响范围：`skills/start|continue|dashboard/SKILL.md` 的提示词/流程与其读写文件契约（不涉及 Agents 的具体 prompt 内容）
- 依赖关系：依赖 `m1-plugin-skeleton` 提供的插件骨架；依赖 `m1-chapter-pipeline-agents` 与其他 agent changes 才能完成端到端试写
- 兼容性：新增能力；不改变现有 API（仓库尚无实现）

## Milestone Mapping

- Milestone 1: 任务 1.0（3 个用户可调用 skills）、1.1（项目目录/最小文件初始化）、1.8（checkpoint 写入/读取）、1.12（试写 3 章的入口编排）。参见 `docs/dr-workflow/novel-writer-tool/final/milestones.md`。

## References

- `docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md`（3 个入口 Skill 的完整定义）
- `docs/dr-workflow/novel-writer-tool/final/prd/01-product.md`（三命令混合模式与 UX 约束）
- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md`（状态机与 Skill→状态映射）
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`（项目目录结构与 `.checkpoint.json`）
- `docs/dr-workflow/novel-writer-tool/final/prd/10-protocols.md`（交互边界、锁、事务写入与注入安全）
- `docs/dr-workflow/novel-writer-tool/final/milestones.md`（M1/M2 对入口技能的职责拆分）

