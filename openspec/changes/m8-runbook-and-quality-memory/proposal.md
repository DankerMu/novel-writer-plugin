## Why

博文 Memory Layer 核心论点：不要让 AGENTS.md 膨胀成巨型手册，把权威事实拆进 docs 树。当前仓库的 `CLAUDE.md` 做了索引，agent prompt 里写了异常处理逻辑，但两类关键事实没有沉到 repo 内：

1. **故障处理手册缺失**：QJ 评分 < 3.0 时的修订策略、滑窗校验发现矛盾时的修复流程、checkpoint 损坏时的恢复路径——这些知识散落在 skill 和 agent prompt 里。agent 每次遇到异常都要重新"理解"该怎么处理，这就是博文定义的**上下文熵**：关键事实不在 repo 内，每次都要重新拼图。
2. **质量趋势不可见**：QJ 产出的评分只进 `evaluations/chapter-XXX-eval.json`，没有聚合视图。写到第 30 章时，无法快速回答"哪个维度在持续走低""哪类问题反复出现"。

## What Changes

- 新增 `docs/runbooks/` 目录，包含 3-5 个初始 runbook（质量门控处理、滑窗校验修复、checkpoint 恢复、伏笔回收、跨卷衔接）
- 新增 `QUALITY.md`，由 `/novel:dashboard` 按需刷新，聚合评分趋势、维度短板、清扫优先级
- `CLAUDE.md` 增加 runbook 索引条目

## Capabilities

### New Capabilities

- `runbook-system`: 结构化故障处理手册，agent 遇到异常时直接查阅 repo 内的权威路径，而非依赖 prompt 里的内联指令
- `quality-aggregation`: 质量趋势聚合视图，支持 dashboard 展示和 agent 决策参考

### Modified Capabilities

- `/novel:dashboard` 增加 QUALITY.md 刷新逻辑
- agent prompt 中的内联异常处理指令改为 runbook 引用（manifest mode）

## Impact

- 影响范围：`docs/runbooks/`（新目录）、`QUALITY.md`（新文件）、`CLAUDE.md`（索引更新）、`skills/dashboard/SKILL.md`（聚合逻辑）
- 依赖关系：依赖 `evaluations/` 目录的评分产物
- 兼容性：纯增量，不改变既有 schema 或管道行为

## Milestone Mapping

- M8.1: Runbook 体系与质量聚合

## References

- 博文 §七 Memory Layer：事实住在哪里
- 博文 §十四 指标体系：Legibility Coverage / Cleanup Half-life
- 当前 `CLAUDE.md` 索引结构
- 当前 `evaluations/` 评分产物格式
