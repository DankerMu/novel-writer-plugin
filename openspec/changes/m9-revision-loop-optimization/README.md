# M9.2 修订回环优化（Revision Loop Optimization）

## Status: Accepted

## Summary

优化质量门控 revise 后的回环策略，将全量回环（~90K tokens）按严重程度分级为 targeted（~35-45K）和 full（~90K）两档，通过定向修改 + 增量摘要 + 维度复检将大部分 revise 场景的 token 消耗降低 50-60%。

## Files Changed

- `openspec/changes/m9-revision-loop-optimization/proposal.md` — 提案
- `skills/continue/references/gate-decision.md` — 门控输出 + 分级回环逻辑
- `skills/continue/SKILL.md` — 修订子流水线分支
- `agents/quality-judge.md` — recheck_mode 支持
- `agents/content-critic.md` — recheck_mode 支持
- `agents/summarizer.md` — patch_mode 支持
- `agents/style-refiner.md` — lite_mode 支持
- `CLAUDE.md` — 架构文档更新
