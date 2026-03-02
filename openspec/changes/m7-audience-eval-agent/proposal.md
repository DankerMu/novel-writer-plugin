# M7: AudienceEval Agent — 读者视角评估

## Why

1. **QualityJudge 盲区**：QualityJudge 从第三人称评审视角评估「写得好不好」（8 维度质量评分），但无法回答「读者会不会继续读」。一章可以情节逻辑满分、角色塑造满分，但读者仍然弃书——因为节奏拖沓、没有钩子、代入感差。

2. **平台读者差异巨大**：
   - 番茄：算法驱动，核心指标是读完率 + 三日留存 + 追更率；碎片阅读者，500 字无冲突就滑走
   - 起点：付费订阅驱动，核心指标是首订 + 均订 + 月票；容忍铺垫但要求信息密度
   - 晋江：社区互动驱动，核心指标是留评率 + 营养液 + CP 感；情感投入强度决定留存

3. **M6 遗留**：M6 提案标题为「黄金三章 + 受众评价」，但受众评价部分仅实现了平台加权评分（调整 QJ 8 维度权重），未实现真正的读者视角模拟。

4. **学术验证**：Synthetic Reader Panels（arxiv 2602.14433, 2026）证明 LLM 可有效模拟不同读者画像进行评估；The Reader is the Metric（arxiv 2506.03310）论证评估者的读者画像必须纳入评分体系。

## Capabilities

### New Capabilities

- **AudienceEval Agent**：第 9 个 Agent，以第一人称读者身份评估章节吸引力
  - 4 套平台读者 persona（番茄碎片阅读者/起点付费追更者/晋江情感投入者/通用普通读者）
  - 6 个读者维度评分（continue_reading / hook_effectiveness / skip_urge / confusion / empathy / freshness）
  - 跳读检测（suspicious_skim_paragraphs，1-3 个最可能被跳过的段落）
  - 情感弧线（emotional_arc，逐段采样情绪强度+形状分类）
  - 平台特定信号（读完率预测/首订意愿/留评意愿等）
  - 黄金三章专属警告（golden_chapter_flags）

- **AudienceEval 参与门控**：读者体验下限检查
  - 黄金三章：engagement < 3.0 → revise（与平台硬门同级）
  - 普通章：QJ pass 但 engagement < 2.5 → 降为 polish
  - 失败降级：agent 超时/崩溃 → 仅用 QJ 门控（绝不阻断）
  - 修订融合：降级时将 reader_feedback + skip_paragraphs 注入修订指令

### Modified Capabilities

- **门控决策引擎**：在 QJ 门控基础上叠加 AudienceEval 降级逻辑
- **Dashboard**：新增「读者参与度」区块（6 维度均值、跳读警告、弧线分布、平台信号趋势）
- **章节 Pipeline**：Step 4.5 插入 AudienceEval 调用（QJ 之后、门控之前）

## Impact

- **影响范围**：新增 1 个 Agent + 修改 continue/SKILL.md + gate-decision.md + quality-rubric.md + context-contracts.md + dashboard
- **依赖**：M5（platform_guide）+ M6（平台硬门框架、excitement_type）
- **兼容性**：AudienceEval 失败时退化为纯 QJ 门控（向后兼容）；无 platform 时使用通用 persona
- **成本影响**：每章增加 1 次 sonnet 调用（约 +15-30s / +$0.01-0.03）

## Milestone Mapping

| 子任务 | 描述 |
|--------|------|
| M7.1 | AudienceEval Agent 定义 + 输出 schema + context manifest |
| M7.2 | Pipeline 集成 + 门控叠加逻辑 |
| M7.3 | Dashboard 集成 + eval fixtures |

## References

- 调研报告（本次 deep-research agent 输出）：平台指标体系、Beta Reader 实践、AI 模拟读者方案、可执行反馈维度、读者痛点
- Fred Zimmerman, "Synthetic Reader Panels", arxiv 2602.14433, 2026-02
- Marco et al., "The Reader is the Metric", arxiv 2506.03310, 2025
- `agents/quality-judge.md` — 现有 8 维度评分逻辑
- `skills/continue/SKILL.md` — 章节 Pipeline
- `skills/continue/references/gate-decision.md` — 门控决策引擎
- `templates/platforms/` — 平台指南模板
