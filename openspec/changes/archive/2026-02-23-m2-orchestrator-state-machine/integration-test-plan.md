## Integration Test Plan (1 volume / 30 chapters)

目标：验证 Orchestrator 状态机、冷启动恢复、门控修订循环、卷末回顾与下卷规划的端到端闭环（至少 2 条故事线交织）。

### Preconditions

- 已完成并可用的 changes（至少）：
  - `m1-entry-skills-and-orchestration`
  - `m1-style-and-anti-ai`
  - `m1-world-rules-and-storylines`
  - `m1-chapter-pipeline-agents`
  - `m2-orchestrator-state-machine`
- 已存在可执行的入口 Skills：`/novel:start`、`/novel:continue`、`/novel:dashboard`
- 卷规划输出（来自 `m2-volume-planning-and-contract-propagation`）可用：`volumes/vol-{V:02d}/outline.md`、`storyline-schedule.json`（用于 `chapter_end` 与交汇事件判定）

### Scenario A: INIT → QUICK_START → VOL_PLANNING

1. 进入空目录，运行 `/novel:start`，选择“创建新项目”
2. 完成快速起步：WorldBuilder（轻量）+ CharacterWeaver（主角/配角）+ StyleAnalyzer（风格样本）+ 试写 3 章流水线

验收：
- `.checkpoint.json.orchestrator_state == "VOL_PLANNING"`
- `.checkpoint.json.current_volume == 1`
- `.checkpoint.json.last_completed_chapter == 3`
- `chapters/`、`summaries/`、`state/current-state.json`、`evaluations/`、`storylines/*/memory.md` 均有最小可用产物

### Scenario B: VOL_PLANNING → WRITING (outline confirmation)

1. 运行 `/novel:start`，在 `VOL_PLANNING` 选择“规划本卷”
2. 通过 PlotArchitect 生成并确认 `volumes/vol-01/outline.md`
3. 确保本卷章节总数为 30（例如 outline 覆盖第 4–33 章）
4. 确保至少 2 条故事线交织（`storyline-schedule.json` 中多线交替出现），并至少包含 1 个交汇事件（`is_intersection: true`）

验收：
- `.checkpoint.json.orchestrator_state == "WRITING"`
- `volumes/vol-01/outline.md` 存在且可按 `/^### 第 {C} 章/` 提取章节区块

### Scenario C: WRITING loop + 5-chapter review trigger

1. 连续运行 `/novel:continue 5`（多次也可），直到累计提交 ≥10 章

验收：
- 每章 staging→commit 后才推进 `last_completed_chapter`
- 每完成 5 章输出质量简报（均分 + 低分章节 + 主要风险），并提示可用 `/novel:start` 进入“质量回顾/调整方向”
- 仍处于写作循环：`.checkpoint.json.orchestrator_state == "WRITING"`

### Scenario D: Cold-start recovery (pipeline_stage + inflight)

1. 在 `/novel:continue 1` 运行中途人为中断（例如完成 Summarizer 后、未 commit）
2. 新 session 中进入项目目录，运行 `/novel:start`
3. 观察推荐：优先恢复中断章（提示 `/novel:continue 1`）
4. 运行 `/novel:continue 1` 完成恢复

验收：
- 中断时 `last_completed_chapter` 不前进
- 恢复后从 checkpoint 指定阶段继续（或重启整章），最终正常 commit

### Scenario E: CHAPTER_REWRITE loop (revision cap)

1. 通过故意制造 hard violation 或低分，触发门控修订（3.0–3.4 或 high-confidence violation）
2. 验证状态转移：`WRITING → CHAPTER_REWRITE → WRITING`
3. 验证最大修订次数：`revision_count <= 2`，耗尽后的 force_pass / pause 策略符合 PRD

验收：
- `.checkpoint.json.orchestrator_state` 在修订期间为 `CHAPTER_REWRITE`，提交后回到 `WRITING`
- `last_completed_chapter` 仅在 commit 成功后增加

### Scenario F: End-of-volume → VOL_REVIEW → VOL_PLANNING

1. 持续写作直到本卷最后一章（`chapter_num == chapter_end`）commit
2. 验证 `.checkpoint.json.orchestrator_state == "VOL_REVIEW"`
3. 运行 `/novel:start`，选择“卷末回顾”，产出 `volumes/vol-01/review.md`
4. 确认进入下卷规划后，进入 `VOL_PLANNING`（并推进 `current_volume += 1`）

验收：
- `VOL_REVIEW` 状态可被 `/novel:start` 识别并路由
- 回顾完成后进入下卷规划：`orchestrator_state == "VOL_PLANNING"`

### Scenario G: ERROR_RETRY pause

1. 人为制造错误（例如并发锁冲突或结构化 JSON 持续解析失败）
2. 验证自动重试一次后进入 `ERROR_RETRY` 并暂停
3. 运行 `/novel:start`，选择“重试上次操作”继续

验收：
- `.checkpoint.json.orchestrator_state == "ERROR_RETRY"` 时不会推进章节计数
- 通过 `/novel:start` 可明确路由恢复
