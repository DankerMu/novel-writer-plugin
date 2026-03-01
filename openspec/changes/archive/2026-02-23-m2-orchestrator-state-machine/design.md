## Context

Orchestrator 是逻辑抽象，实际分布在 3 个入口 Skills 中：
- `/novel:start`：负责 INIT/QUICK_START/VOL_PLANNING/VOL_REVIEW 的交互与状态推进
- `/novel:continue`：负责 WRITING 循环（含门控与修订）
- `/novel:dashboard`：只读，不触发转移

系统原则为“无状态冷启动”：每次运行通过读取文件状态恢复，不依赖会话历史。

## Goals / Non-Goals

**Goals:**
- 固化 Orchestrator 状态枚举、转移条件与写入 checkpoint 的时机
- 固化冷启动恢复所需的最小读取集合与降级策略（缺文件时的提示/补救）
- 固化质量回顾与卷末回顾的触发条件与路由入口（由 `/novel:start` 承担）

**Non-Goals:**
- 不定义具体 Agents 的 prompt 细节（由 agent changes 覆盖）
- 不实现确定性校验工具（M3+ 扩展点）

## Decisions

1. **状态单写点：checkpoint**
   - 所有状态转移以 `.checkpoint.json` 为单写点；其他文件（outline/state/memory）由对应流程落盘。

2. **转移只发生在“已提交”边界**
   - WRITING 中的章节推进仅在 staging→commit 成功后更新 `last_completed_chapter` 与 `pipeline_stage="committed"`，避免半成品推进导致断链。

3. **冷启动恢复采用“文件即状态”**
   - 优先使用 summaries + state + outline，而非读取历史章节全文；缺失时按优先级降级并提示用户重建。

4. **用户审核点集中在 `/novel:start`**
   - 卷规划确认、质量回顾、卷末回顾均通过 `/novel:start` 进入，统一 AskUserQuestion 交互边界。

## Risks / Trade-offs

- [Risk] checkpoint 与 staging 产物不一致 → Mitigation：恢复逻辑严格以 `pipeline_stage` + 文件存在性共同判定；必要时重启整章。
- [Risk] 卷末/质量回顾触发过于频繁打断写作 → Mitigation：触发点可配置（例如每 5/10 章），但默认遵循 PRD。

## Integration Test Plan

见 `openspec/changes/m2-orchestrator-state-machine/integration-test-plan.md`（1 卷 30 章，至少 2 条故事线交织，覆盖冷启动恢复、修订循环与卷末回顾）。

## References

- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/10-protocols.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`
