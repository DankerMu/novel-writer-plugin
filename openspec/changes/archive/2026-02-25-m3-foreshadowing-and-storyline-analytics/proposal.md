## Why

跨 30-100+ 章的卷制续写中，“伏笔遗忘/失控”与“故事线节奏失衡”会显著降低读者粘性：伏笔埋了不推、推了不回收，副线长期休眠或切换节奏混乱都会快速累积体验损失。M3 需要把伏笔与故事线从“写作时记得就好”升级为“可追踪、可盘点、可回归”的质量保证能力。

## What Changes

- 增加伏笔追踪：基于 `foreshadow` ops 维护 `foreshadowing/global.json`（跨卷），并支持卷内 `volumes/vol-{V:02d}/foreshadowing.json` 的计划与盘点
- 增加跨故事线伏笔桥梁检查：校验 `storylines/storylines.json.relationships[].bridges.shared_foreshadowing[]` 引用的伏笔 ID 可追溯
- 增加故事线节奏分析：出场频率、休眠时长、交汇事件达成率统计，并输出可读报告
- 在“每 10 章定期检查 / 卷末回顾”中汇总展示：伏笔完成度 + 风险清单 + 节奏简报
- 预留确定性工具扩展点：`scripts/query-foreshadow.sh`（存在则调用，不存在回退 LLM/规则路径）

## Capabilities

### New Capabilities

- `foreshadowing-and-storyline-analytics`: 伏笔跨卷追踪、跨线桥梁检查、故事线节奏统计与报告输出。

### Modified Capabilities

- (none)

## Impact

- 影响范围：定期检查（每 10 章）、卷末回顾、`/novel:dashboard` 伏笔与故事线汇总展示、可选确定性脚本扩展点
- 依赖关系：依赖 `staging/state/*-delta.json` 中的 `foreshadow` ops、`storylines/*` 与 `volumes/vol-*/storyline-schedule.json`、`summaries/*` 的 `storyline_id`
- 兼容性：新增报告与索引；不改变章节正文/摘要的主格式

## Milestone Mapping

- Milestone 3: 3.2（伏笔追踪：卷内 + 跨卷 global.json + 跨故事线伏笔桥梁检查）、3.6（故事线节奏分析）。参见 `docs/dr-workflow/novel-writer-tool/final/milestones.md`。

## References

- `docs/dr-workflow/novel-writer-tool/final/milestones.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/04-workflow.md`（每 10 章检查 + 卷末回顾）
- `docs/dr-workflow/novel-writer-tool/final/prd/06-storylines.md`（bridges.shared_foreshadowing、convergence）
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`（foreshadowing/global.json、foreshadow ops、volumes/vol-*/foreshadowing.json）
- `docs/dr-workflow/novel-writer-tool/final/prd/10-protocols.md`（commit 更新 global.json）
- `docs/dr-workflow/novel-writer-tool/final/spec/agents/plot-architect.md`（卷级 foreshadowing.json 输出）
- `docs/dr-workflow/novel-writer-tool/final/spec/agents/summarizer.md`（foreshadow ops 权威提取）
- `docs/dr-workflow/novel-writer-tool/final/spec/06-extensions.md`（query-foreshadow.sh 扩展点）

