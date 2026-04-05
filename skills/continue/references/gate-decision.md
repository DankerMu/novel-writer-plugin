# 质量门控决策引擎（Gate Decision Engine）

## 输入：双 Agent 评估结果

编排器在门控阶段读取两份评估文件（QualityJudge + ContentCritic 并行产出）：

- `staging/evaluations/chapter-{C:03d}-eval-raw.json`（QJ: Track 1 合规 + Track 2 评分）
- `staging/evaluations/chapter-{C:03d}-content-eval-raw.json`（CC: Track 3 读者参与度 + Track 4 内容实质性）

## high_violation 函数定义与 hard gate 输入（仅认 high confidence）

- high_violation(eval) := 任一 contract_verification.{l1,l2,l3}_checks 中存在 status="violation" 且 confidence="high"
  或任一 contract_verification.ls_checks 中存在 status="violation" 且 confidence="high" 且（constraint_type 缺失或 == "hard"）
- platform_hard_gate_fail(eval) := 任一 contract_verification.platform_hard_gates 中存在 status="fail"（章节 001-003 且有 platform_guide 时才可能非空）
- has_high_confidence_violation：取自 Step 4 的计算结果（关键章=双裁判 OR 合并，普通章=单裁判）
  > confidence=medium/low 仅记录警告，不触发 hard gate（避免误报疲劳）

## ContentCritic 门控信号

从 `content-eval-raw.json` 提取：

- `substance_violation(cc_eval)` := 任一 content_substance.{information_density, plot_progression, dialogue_efficiency}.score < 3
- `substance_severe(cc_eval)` := content_substance.content_substance_overall < 2.0
- `engagement_override(cc_eval, qj_recommendation)`:
  ```
  if cc_eval.reader_evaluation == null:
      return null  # Track 3 fallback，不影响门控
  engagement = cc_eval.reader_evaluation.overall_engagement
  if is_golden_chapter and engagement < 3.0:
      return "revise"
  elif qj_recommendation == "pass" and engagement < 2.5:
      return "polish"
  elif qj_recommendation == "pass" and engagement < 3.0:
      return "warning"  # 不降级，仅 risk_flag
  else:
      return null
  ```

## 固化门控决策函数（输出 gate_decision）

> `overall_final` 来源：QualityJudge 输出 `overall`（有 platform_guide 且含评估权重时为 `overall_weighted`，否则为 `overall_raw`）；关键章双裁判取 `min(primary.overall, secondary.overall)`。

```
# Step A: QJ 基础决策（Track 1+2）
if has_high_confidence_violation:
    qj_decision = "revise"
elif platform_hard_gate_fail(eval):
    qj_decision = "revise"
else:
    if overall_final >= 4.0: qj_decision = "pass"
    elif overall_final >= 3.5: qj_decision = "polish"
    elif overall_final >= 3.0: qj_decision = "revise"
    elif overall_final >= 2.0: qj_decision = "pause_for_user"
    else: qj_decision = "pause_for_user_force_rewrite"

# Step B: CC 内容实质性硬门（Track 4）
if substance_violation(cc_eval):
    substance_decision = "revise"
elif substance_severe(cc_eval):
    substance_decision = "pause_for_user"
else:
    substance_decision = null

# Step C: CC 读者参与度 overlay（Track 3，只降级不升级）
engagement_decision = engagement_override(cc_eval, qj_decision)

# Step D: 合并取最严（severity: pause_for_user_force_rewrite > pause_for_user > revise > polish > pass）
gate_decision = max_severity(qj_decision, substance_decision, engagement_decision)
# engagement_decision == "warning" 时不参与 max_severity，仅 append risk_flag
```

## 自动修订闭环（max revisions = 2）

- 若 gate_decision="revise" 且 revision_count < 2：
  - 更新 checkpoint: orchestrator_state="CHAPTER_REWRITE", pipeline_stage="revising", revision_count += 1
  - 组装修订指令（合并 QJ + CC 来源）：
    - 从 QJ eval: `required_fixes`（主要来源）
    - 从 CC eval: `substance_issues`（severity=high）转化为 `required_fixes` 格式追加
    - 从 CC eval: `reader_evaluation.reader_feedback` + `reader_evaluation.suspicious_skim_paragraphs`（如存在）追加到修订指令
    - `track3_mode == "lite"` 时 `suspicious_skim_paragraphs` 不可用，仅注入 `reader_feedback`
  - 调用 ChapterWriter 修订模式（Task(subagent_type="chapter-writer", model="opus")）：
    - 输入: chapter_writer_revision_manifest（追加 inline 字段 `required_fixes` + `high_confidence_violations` + `substance_fixes`）
    - 约束：定向修改指定段落，尽量保持其余内容不变
  - 回到 ChapterWriter(revision+polish) → Summarizer → [QualityJudge + ContentCritic 并行] → 门控

- 若 gate_decision="revise" 且 revision_count == 2（次数耗尽）：
  - 若 has_high_confidence_violation=false 且 platform_hard_gate_fail(eval)=false 且 overall_final >= 3.0 且 substance_violation(cc_eval)=false 且 !(is_golden_chapter 且 cc_eval.reader_evaluation.overall_engagement < 3.0)：
    - 设置 force_passed=true，允许提交（避免无限循环）
    - 记录：eval metadata + log 中标记 force_passed=true
    - 将 gate_decision 覆写为 "pass"
  - 否则：
    - 释放并发锁（rm -rf .novel.lock）并暂停，提示用户在 `/novel:start` 决策下一步

## 其他决策的后续动作

- gate_decision="pass"：直接进入 commit
- gate_decision="polish"：更新 checkpoint: pipeline_stage="revising" -> ChapterWriter Phase 2 re-run (polish_only) 后进入 commit（不再重复 QJ/CC 以控成本）
- gate_decision="pause_for_user" / "pause_for_user_force_rewrite"：释放并发锁（rm -rf .novel.lock）并暂停，等待用户通过 `/novel:start` 决策

## 写入评估与门控元数据（可追溯）

- 读取 staging/evaluations/chapter-{C:03d}-eval-raw.json（QJ 直接落盘的评估结果）
- 读取 staging/evaluations/chapter-{C:03d}-content-eval-raw.json（CC 直接落盘的评估结果）
- 组装最终 staging/evaluations/chapter-{C:03d}-eval.json：
  - 内容：`{chapter, eval_used: <QJ raw 内容>, content_eval: <CC raw 内容>, metadata: {...}}`
  - eval_used = 普通章的 primary_eval-raw；关键章取 overall 更低的一次
  - content_eval = CC content-eval-raw 内容
  - metadata 至少包含：
    - judges: {primary:{model,overall,overall_raw,overall_weighted?}, secondary?:{model,overall,overall_raw,overall_weighted?}, used, overall_final}
    - content_critic: {model, content_substance_overall, overall_engagement（如有）}
    - gate: {decision: gate_decision, revisions: revision_count, force_passed: bool, substance_violation: bool}
- 删除 staging/evaluations/chapter-{C:03d}-eval-raw.json 和 staging/evaluations/chapter-{C:03d}-content-eval-raw.json（清理中间文件）
