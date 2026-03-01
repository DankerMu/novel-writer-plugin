# M6: 黄金三章正式化 + 受众视角评价

## Why

1. **黄金三章被浪费**：当前 Quick Start Step F 试写 chapter 001-003 使用弱 pipeline（无 L3 合约、无 LS 检查、无 excitement_type、无 platform_guide），但网文前 3 章是读者决定是否追更的黄金留存窗口。业界编辑经验数据估计：前 300 字跳出率约 78%，前 3 章留存率不足 5%。用最弱的 pipeline 写最关键的内容，是结构性缺陷。正式卷规划从第 4 章开始时，前 3 章已成既定事实，无法回溯优化。
   - 不同类型的黄金三章关键要素差异显著：玄幻靠金手指想象空间、都市靠困境代入感、科幻靠世界观冲击、悬疑靠解谜欲、言情靠 CP 化学反应（详见 `docs/dr-workflow/m6-golden-chapters-research/final/main.md` §二）
   - 不同平台的前 3 章要求存在结构性差异：番茄要求 200 字内建立冲突、每 300 字一个钩子；起点允许 3 万字窗口、重设定深度；晋江重人设和 CP 互动（详见同报告 §三）

2. **评价体系缺乏受众视角**：M5.2 的 platform_guide 仅影响 ChapterWriter（写作端），QualityJudge（评价端）仍使用通用 8 维度等权评分。不同平台读者的核心期待差异巨大（番茄重节奏爽点、起点重设定深度、晋江重情感人设），通用评分无法识别「在目标平台上好不好看」。
   - 调研确认读者自发使用的评价维度与 QJ 8 维度高度吻合，无需新增维度，仅需按平台调整权重（详见调研报告 §四）
   - 番茄三高维度：节奏(0.18) + 爽感(0.18) + 代入感(0.18)；起点三高：设定(0.18) + 逻辑(0.16)；晋江三高：人设(0.20) + 情感(0.18)

## Capabilities

### New Capabilities

- **Step F0 迷你卷规划**：Quick Start 中在试写前插入 PlotArchitect 调用，为前 3 章生成临时 outline + L3 contracts + excitement_type
- **受众权重配置**：platform_guide 新增「评估权重调整」section，定义各平台对 8 维度的权重偏好
- **QualityJudge 平台感知**：QualityJudge manifest 新增可选 `paths.platform_guide`，评分时按平台权重加权

### Modified Capabilities

- **Quick Start Step F**：从弱 pipeline 升级为完整 pipeline（与 `/novel:continue` 一致），包含 L3 合约检查、LS 检查、excitement_type 评估、platform_guide、关键章 Double-Judge
- **Quick Start Step G**：用户确认后，卷规划继承前 3 章的 summaries/contracts，PlotArchitect 从第 4 章开始规划
- **platform_guide 模板**：每个平台模板增加 `## 评估权重` section
- **QualityJudge 评分逻辑**：`overall_final` 从等权平均改为加权平均（权重来自 platform_guide，无 platform 时退化为等权）

## Impact

- **影响范围**：`/novel:start` Quick Start 流程（Step F0/F/G）+ QualityJudge agent 定义 + platform_guide 模板 + `/novel:continue` QualityJudge manifest
- **依赖**：M5 完成（platform_guide 框架 + excitement_type + canon_status）
- **兼容性**：无 platform_guide 时 QualityJudge 退化为等权评分（向后兼容）；旧项目前 3 章不受影响
- **用户体验**：Quick Start 时间从约 30 分钟增至 50-60 分钟，但产出物质量显著提升

## Milestone Mapping

| 子任务 | 描述 |
|--------|------|
| M6.1 | 黄金三章正式化 — Step F0 迷你卷规划 + Step F 升级为完整 pipeline + Step G 继承衔接 |
| M6.2 | 受众视角评价 — platform_guide 评估权重 + QualityJudge 加权评分 + manifest 扩展 |

## References

- `docs/dr-workflow/m6-golden-chapters-research/final/main.md` — 黄金三章 + 受众评价深度调研综合报告（91/100，4 份 DR 子报告）
- `skills/start/SKILL.md` — Quick Start 流程定义
- `skills/continue/SKILL.md` — 完整 pipeline 参考
- `agents/quality-judge.md` — 8 维度评分逻辑
- `skills/novel-writing/references/quality-rubric.md` — 评分标准
- `templates/platforms/` — 平台指南模板（M5.2）
