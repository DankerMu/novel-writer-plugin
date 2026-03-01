## Why

M4 的目标是“完整体验”：新用户必须能在 30 分钟内跑通从设定到 3 章输出的全流程，并且有清晰的文档指导后续的卷制循环与常用维护操作。没有完善的快速起步与文档，系统会停留在“能跑但难用”的状态，难以进入 100 章尺度的真实使用。

## What Changes

- 快速起步流程打磨：最少输入集 + 清晰交互（AskUserQuestion 约束）+ 可中断恢复
- 默认产物对齐：L1 轻量规则（≤3 条）+ 初始主线 storylines.json + 风格提取与降级方案
- 状态与下一步提示优化：`/novel:start` 推荐动作更明确，`/novel:dashboard` 展示关键指标
- 用户文档补全：快速入门、常用操作、Spec 体系、多线叙事说明（以 final 文档为准）

## Capabilities

### New Capabilities

- `quick-start-polish-and-docs`: 快速起步 UX/输出对齐 + 用户文档体系化交付。

### Modified Capabilities

- (none)

## Impact

- 影响范围：`/novel:start`（QUICK_START 路由与交互）、模板与默认输出、文档目录
- 依赖关系：依赖 M1/M2 的核心 pipeline 与数据结构（rules.json、storylines.json、style-profile 等）
- 兼容性：以 UX/文档为主，不改变核心文件 schema

## Milestone Mapping

- Milestone 4: 4.1（快速起步流程）、4.6（用户文档）。参见 `docs/dr-workflow/novel-writer-tool/final/milestones.md`。

## References

- `docs/dr-workflow/novel-writer-tool/final/milestones.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/01-product.md`（三命令 UX、AskUserQuestion 约束）
- `docs/dr-workflow/novel-writer-tool/final/prd/04-workflow.md`（Layer 1 快速起步）
- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md`（QUICK_START 状态）
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`（项目目录结构）

