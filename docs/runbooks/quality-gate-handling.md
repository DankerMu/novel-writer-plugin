# 质量门控处理

## Trigger

QualityJudge 评分完成后（`pipeline_stage == "judged"`），编排器读取 `staging/evaluations/chapter-{C:03d}-eval-raw.json`，映射 `recommendation` 到 `gate_decision`。当 `gate_decision != "pass"` 时触发本 runbook。

## Diagnosis

从 `eval-raw.json` 读取以下关键字段，区分问题来源：

- **Violation-driven**：`contract_verification.has_violations == true`，检查 `l1_checks` / `l2_checks` / `l3_checks` / `ls_checks` / `platform_hard_gates` 中 `status == "violation"` 且 `confidence == "high"` 的条目
- **Score-driven**：`has_violations == false`，但 `overall_final < 4.0`（含 `overall_raw`、`overall_weighted`、双裁判 `min()` 结果）
- **Engagement-driven**：`reader_evaluation.overall_engagement` 触发降级（黄金三章 < 3.0 → revise；普通章 < 2.5 → polish）

同时检查 `.checkpoint.json.revision_count` 确认已修订次数。

## Actions

### polish（overall_final ∈ [3.5, 4.0)）

1. 调用 ChapterWriter Phase 2 二次润色（**不重复调用 QJ**）
2. 润色范围：QJ `required_fixes` + `suggestions` 中 `priority == "high"` 的条目
3. 输出覆盖 `staging/chapters/chapter-{C:03d}.md`
4. 直接进入 commit 阶段（不重新评分）

### revise（high violation / 平台硬门 fail / overall_final ∈ [3.0, 3.5)）

1. 更新 `.checkpoint.json`：`pipeline_stage = "revising"`, `revision_count += 1`
2. 组装修订指令：`required_fixes`（violation 详情 + 修复建议）+ engagement 反馈（如有降级）
3. 调用 ChapterWriter Opus 全量修订 → Summarizer → QualityJudge 完整重跑
4. 最多 2 轮修订（`revision_count <= 2`）

### pause_for_user（overall_final ∈ [2.0, 3.0)）

1. 更新 `.checkpoint.json`：`orchestrator_state = "CHAPTER_REWRITE"`
2. 输出评分详情 + 各维度低分原因 + 修复建议
3. 等待用户通过 `/novel:start → 重试上次操作` 决策下一步

### pause_for_user_force_rewrite（overall_final < 2.0）

1. 同 `pause_for_user`，但提示建议整章重写而非局部修订
2. `gate_decision` 标记为 `pause_for_user_force_rewrite`

## Acceptance

| 档位 | 退出条件 |
|------|---------|
| polish | Phase 2 润色完成，直接 commit |
| revise | 重跑 QJ 后 `overall_final >= 4.0` 且无 high violation 且无平台硬门 fail → pass |
| pause | 用户手动决策后恢复流水线，重新进入 revise/rewrite 循环 |

## Rollback

**修订超限兜底**（`revision_count >= 2` 且仍未 pass）：

- 满足以下全部条件 → `force_passed`：
  - 无 `confidence == "high"` 的 violation
  - 无平台硬门 fail
  - `overall_final >= 3.0`
  - 无 reader_evaluation 黄金三章硬门 fail（黄金三章 `overall_engagement < 3.0` 不允许 force_passed）
- 不满足 → 维持 `pause_for_user`，输出详细诊断报告，等待人工介入
- `force_passed` 章节在 `logs/chapter-{C:03d}-log.json` 中标记 `"force_passed": true`，便于后续质量回顾追溯
