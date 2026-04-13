# 中断恢复与错误处理

## Step 1.5: 中断恢复（pipeline_stage）

若 `.checkpoint.json` 满足以下条件：
- `pipeline_stage != "committed"` 且 `pipeline_stage != null`
- `inflight_chapter != null`

则本次 `/novel:continue` **必须先完成** `inflight_chapter` 的流水线，按以下规则幂等恢复：

- `pipeline_stage == "drafting"`：
  - 若 `staging/chapters/chapter-{C:03d}.md` 不存在 → 从 API Writer 重启整章（降级 CW）
  - 若 `staging/chapters/chapter-{C:03d}.md` 已存在且 `staging/logs/style-refiner-chapter-{C:03d}-changes.json` 不存在 → 从 StyleRefiner 恢复
  - 若两者均存在 → 从 Summarizer 恢复
- `pipeline_stage == "refining"`：
  - 若 `staging/logs/style-refiner-chapter-{C:03d}-changes.json` 不存在 → 从 StyleRefiner 重启
  - 若已存在 → 从 Summarizer 恢复
- `pipeline_stage == "refined"`:
  - 若 `revision_scope == "targeted"`（定向修订三路并行中断）：检查三路输出存在性——Sum（`staging/summaries/chapter-{C:03d}-summary.md` + `staging/state/chapter-{C:03d}-delta.json`）、QJ（`staging/evaluations/chapter-{C:03d}-eval-raw.json`）、CC（`staging/evaluations/chapter-{C:03d}-content-eval-raw.json`）；仅重跑输出缺失的 agent（并行）；三路均存在 → 跳至门控决策（`pipeline_stage = "judged"`）
  - 否则 → 从 Summarizer 恢复
- `pipeline_stage == "drafted"` → 跳过 ChapterWriter/StyleRefiner/Summarizer，从 QualityJudge + ContentCritic 并行恢复
- `pipeline_stage == "judged"` → 读取 `staging/evaluations/chapter-{C:03d}-eval-raw.json`（QJ）和 `staging/evaluations/chapter-{C:03d}-content-eval-raw.json`（CC），直接执行门控决策 + commit 阶段；任一文件不存在或 JSON 无效 → 降级到 `pipeline_stage == "drafted"`（从 QJ+CC 重新评估）
- `pipeline_stage == "revising"` → 修订中断，从 ChapterWriter 重启（保留 revision_count 以防无限循环）
- `pipeline_stage == "direct_fixing"` → 定向修订耗尽后的直接修复中断：检查 `staging/chapters/chapter-{C:03d}.md` 修改时间是否晚于上次 eval-raw → 已修改则从 SR(lite) 恢复；未修改则重跑 Task agent

恢复章完成 commit 后，再继续从 `last_completed_chapter + 1` 续写后续章节，直到累计提交 N 章（包含恢复章）。

## Step 1.6: 错误处理（ERROR_RETRY）

当流水线任意阶段发生错误（Task 超时/崩溃、结构化 JSON 无法解析、写入失败、锁冲突等）时：

1. **自动重试一次**：对失败步骤重试 1 次（避免瞬时错误导致整章中断）
2. **重试成功**：继续执行流水线（不得推进 `last_completed_chapter`，直到 commit 成功）
3. **重试仍失败**：
   - 更新 `.checkpoint.json.orchestrator_state = "ERROR_RETRY"`（保留 `pipeline_stage`/`inflight_chapter` 便于恢复）
   - 释放并发锁（`rm -rf .novel.lock`）
   - 输出提示并暂停：请用户运行 `/novel:start` 决策下一步（重试/回看/调整方向）
