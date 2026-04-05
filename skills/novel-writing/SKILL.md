---
name: novel-writing
is_user_facing: false
description: >
  小说创作共享方法论知识库（内部引用，非用户直接调用）。
  包含卷制滚动工作流、Spec-Driven Writing 四层规范体系、多线叙事管理、去 AI 化四层策略、8 维度质量评分标准。
  This skill is a passive reference library. It should not be triggered by user queries.
  Entry skills (/novel:start, /novel:continue) read its references/ directory
  and inject content into Agent contexts programmatically.
---

# 小说创作方法论

本知识库为 novel 插件系统提供共享方法论。入口 Skill（`/novel:continue`、`/novel:start`）在 context 组装阶段读取本目录下的 references，按需注入到各 Agent 的 prompt 中。

## 卷制滚动工作流

网文创作采用"边写边想"模式，以卷（30-50 章）为单位滚动规划：

1. **卷规划**：PlotArchitect 生成本卷大纲 + 伏笔计划 + L3 章节契约
2. **日更续写**：ChapterWriter(含润色) → Summarizer → [QualityJudge + ContentCritic 并行]（单章流水线）
3. **定期检查**：每 5 章自动执行滑窗一致性校验（窗口 10 章、步长 5，形成 ch1-10/ch6-15/ch11-20… 重叠覆盖）+ 质量简报 + 风格漂移监控；每 10 章深度盘点（伏笔盘点 + 跨线桥梁检查 + 故事线节奏分析）
4. **卷末自动核查**：到达卷末章时自动执行全卷 NER 一致性 + 伏笔/桥梁/节奏分析；State 清理和下卷规划由 `/novel:start` 完成

核心循环状态机：`VOL_PLANNING → WRITING ⟲ (每章含内嵌门控+修订) → VOL_REVIEW → VOL_PLANNING`

## Spec-Driven Writing 原则

小说创作遵循"规范先行，实现随后，验收对齐规范"范式：

| 层级 | 内容 | 生成者 | 约束强度 |
|------|------|--------|---------|
| L1 世界规则 | 物理/魔法/社会硬约束 | WorldBuilder → `rules.json` | 不可违反 |
| L2 角色契约 | 能力边界/行为模式 | WorldBuilder（角色模式） → `contracts` | 可变更需走协议 |
| L3 章节契约 | 前置/后置条件/验收标准 | PlotArchitect → `chapter-contracts/` | 可协商须留痕 |

验收采用四轨制：Track 1 Contract Verification（合规检查 L1/L2/L3/LS，硬门槛）+ Track 2 Quality Scoring（8 维度评分，软评估）由 QualityJudge 执行；Track 3 Reader Engagement（读者参与度）+ Track 4 Content Substance（信息密度/剧情推进/对话效率，硬门槛）由 ContentCritic 并行执行。合规是编译通过，质量是 code review，内容实质是 regression test。

## 多线叙事体系

支持多 POV 群像、势力博弈暗线、跨卷伏笔交汇等复杂叙事结构：

- **小说级定义**：`storylines/storylines.json` 管理全部故事线（类型 + 范围 + 势力 + 桥梁关系）
- **卷级调度**：PlotArchitect 在卷规划时生成 `storyline-schedule.json`（volume_role: primary/secondary/seasoning + 交汇事件）
- **章级注入**：ChapterWriter 接收 storyline_context + concurrent_state + transition_hint
- **防串线**：三层策略（结构化 Context + 反串线指令 + QualityJudge 后验校验），每次续写为独立 LLM 调用
- **活跃线限制**：同时活跃 ≤ 4 条

## 去 AI 化四层策略

| 层 | 手段 | 执行者 |
|----|------|--------|
| L1 风格锚定 | 用户样本 → style-profile.json | WorldBuilder（风格提取模式） |
| L2 约束注入 | 黑名单 + 语癖 + 反直觉 + 句式多样 | ChapterWriter |
| L3 后处理 | 替换 AI 用语 + 匹配风格指纹 | ChapterWriter Phase 2 |
| L4 检测度量 | 黑名单命中率 + 句式重复率 + 风格匹配度 | QualityJudge |

核心指标：AI 黑名单命中 < 3 次/千字，相邻 5 句重复句式 < 2。

详见 `references/style-guide.md`。

## 质量评分标准

8 维度加权评分（详见 `references/quality-rubric.md`）：

| 维度 | 权重 |
|------|------|
| 情节逻辑 | 18% |
| 角色塑造 | 18% |
| 沉浸感 | 15% |
| 风格自然度 | 15% |
| 伏笔处理 | 10% |
| 节奏 | 8% |
| 情感冲击 | 8% |
| 故事线连贯 | 8% |

门控：≥4.0 通过，3.5-3.9 二次润色，3.0-3.4 自动修订，2.0-2.9 暂停用户审核，<2.0 暂停建议重写。有 contract violation（confidence=high，含 LS hard）时无条件强制修订。平台硬门任一 fail 时强制修订。LS-005（跨线实体泄漏）为 hard constraint。

## Context 管理

各 Agent context 用量参考（非硬上限，详见 `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` §8.4 按 Agent 分列表）：
- **ChapterWriter**：~19-24K（普通章）/ ~24-30K（交汇章）— 含大纲、摘要、状态、角色、故事线、契约、黑名单
- **Summarizer**：~10-12K — 章节全文 + 状态 + entity_id_map
- **QualityJudge**：~14-16K — 章节全文 + 大纲 + 角色 + 契约 + 故事线 spec + 读者评估

摘要替代全文 + L2 角色裁剪，确保第 500 章时 context 仍稳定。模型 context window（当前约 200K）远大于实际用量。
