# 质量门控决策引擎（Gate Decision Engine）

## high_violation 函数定义与 hard gate 输入（仅认 high confidence）

- high_violation(eval) := 任一 contract_verification.{l1,l2,l3}_checks 中存在 status="violation" 且 confidence="high"
  或任一 contract_verification.ls_checks 中存在 status="violation" 且 confidence="high" 且（constraint_type 缺失或 == "hard"）
- platform_hard_gate_fail(eval) := 任一 contract_verification.platform_hard_gates 中存在 status="fail"（章节 001-003 且有 platform_guide 时才可能非空）
- has_high_confidence_violation：取自 Step 4 的计算结果（关键章=双裁判 OR 合并，普通章=单裁判）
  > confidence=medium/low 仅记录警告，不触发 hard gate（避免误报疲劳）

## 固化门控决策函数（输出 gate_decision）

> `overall_final` 来源：QualityJudge 输出 `overall`（有 platform_guide 且含评估权重时为 `overall_weighted`，否则为 `overall_raw`）；关键章双裁判取 `min(primary.overall, secondary.overall)`。

```
if has_high_confidence_violation:
  gate_decision = "revise"
elif platform_hard_gate_fail(eval):
  gate_decision = "revise"  # 平台硬门失败，强制修订（章节 001-003 且有 platform_guide 时）
else:
  if overall_final >= 4.0: gate_decision = "pass"
  elif overall_final >= 3.5: gate_decision = "polish"
  elif overall_final >= 3.0: gate_decision = "revise"
  elif overall_final >= 2.0: gate_decision = "pause_for_user"
  else: gate_decision = "pause_for_user_force_rewrite"
```

## 自动修订闭环（max revisions = 2）

- 若 gate_decision="revise" 且 revision_count < 2：
  - 更新 checkpoint: orchestrator_state="CHAPTER_REWRITE", pipeline_stage="revising", revision_count += 1
  - 调用 ChapterWriter 修订模式（Task(subagent_type="chapter-writer", model="opus")）：
    - 输入: chapter_writer_revision_manifest（在 chapter_writer_manifest 基础上追加 inline 字段 `required_fixes` + `high_confidence_violations`，paths 追加 `chapter_draft` 指向 staging 中的现有正文）
    - 修订指令：以 eval.required_fixes 作为最小修订指令；若 required_fixes 为空，则用 high_confidence_violations 生成 3-5 条最小修订指令兜底；若两者均为空（score 3.0-3.4 无 violation 触发），则从 eval 的 8 维度中取最低分 2 个维度的 feedback 作为修订方向
    - 约束：定向修改 required_fixes 指定段落，尽量保持其余内容不变
  - 回到步骤 2 重新走 Summarizer -> StyleRefiner -> QualityJudge -> 门控（保证摘要/state/crossref 与正文一致）

- 若 gate_decision="revise" 且 revision_count == 2（次数耗尽）：
  - 若 has_high_confidence_violation=false 且 platform_hard_gate_fail(eval)=false 且 overall_final >= 3.0：
    - 设置 force_passed=true，允许提交（避免无限循环）
    - 记录：eval metadata + log 中标记 force_passed=true（门控被上限策略终止）
    - 将 gate_decision 覆写为 "pass"
  - 否则：
    - 释放并发锁（rm -rf .novel.lock）并暂停，提示用户在 `/novel:start` 决策下一步（手动修订/重写/接受）

## 其他决策的后续动作

- gate_decision="pass"：直接进入 commit
- gate_decision="polish"：更新 checkpoint: pipeline_stage="revising" -> StyleRefiner 二次润色后进入 commit（不再重复 QualityJudge 以控成本）
- gate_decision="pause_for_user" / "pause_for_user_force_rewrite"：释放并发锁（rm -rf .novel.lock）并暂停，等待用户通过 `/novel:start` 决策

## 写入评估与门控元数据（可追溯）

- 写入 staging/evaluations/chapter-{C:03d}-eval.json：
  - 内容：eval_used（普通章=primary_eval；关键章=overall 更低的一次）+ metadata
  - metadata 至少包含：
    - judges: {primary:{model,overall,overall_raw,overall_weighted?}, secondary?:{model,overall,overall_raw,overall_weighted?}, used, overall_final}
    - gate: {decision: gate_decision, revisions: revision_count, force_passed: bool}
