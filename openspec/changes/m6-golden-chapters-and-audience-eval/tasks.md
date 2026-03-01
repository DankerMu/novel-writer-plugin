# Tasks: 黄金三章正式化 + 受众视角评价

## 1. 黄金三章正式化（M6.1）

- [ ] 1.1 修改 `skills/start/SKILL.md`：在 Step E 和 Step F 之间插入 Step F0（迷你卷规划）
- [ ] 1.2 定义 Step F0 的 PlotArchitect 调用参数：输入精简（无 prev review）、输出限定 3 章、读取 platform_guide 的 `## 黄金三章参数` section
- [ ] 1.3 修改 Step F：从弱 pipeline 升级为完整 pipeline（复用 `/novel:continue` 的 manifest 组装逻辑）
- [ ] 1.4 修改 `skills/start/SKILL.md`：Step F 中第 1 章启用 Double-Judge（卷首 = 关键章节）
- [ ] 1.5 修改 `skills/start/SKILL.md`：Step F 中启用质量门控（pass/polish/revise/review/rewrite），与正式写作一致
- [ ] 1.6 修改 `quick_start_step` 支持 `"F0"` 值，中断恢复逻辑覆盖 F0→F 衔接
- [ ] 1.7 修改 Step G：checkpoint 写入 `current_volume=1, last_completed_chapter=3`
- [ ] 1.8 修改卷规划流程：PlotArchitect 接收前 3 章 summaries/contracts，从第 4 章开始扩展 outline
- [ ] 1.9 修改 `agents/plot-architect.md`：增加「继承模式」输入定义（已有 outline + summaries → 扩展）。继承模式下允许在 outline.md 前 3 章条目中追加 `[NOTE]` 标记行，但 L3 contracts JSON 和章节文本只读
- [ ] 1.10 更新 Step A 用户提示：预期时间从 30 分钟调整为 50 分钟

## 2. 类型特定黄金三章（M6.1 — 调研驱动新增）

- [ ] 2.1 修改 `agents/plot-architect.md`：Step F0 模式下根据 genre 生成类型特定的 L3 acceptance_criteria（玄幻: golden_finger_hinted / 言情: both_leads_appeared + first_interaction / 悬疑: core_mystery_presented / 历史: era_anchored / 科幻: world_unique_element_shown / 都市: protagonist_dilemma_established）
- [ ] 2.2 修改 `agents/quality-judge.md`：支持检查 genre-specific acceptance_criteria 合规性
- [ ] 2.3 创建 L3 acceptance_criteria 类型参考表：`skills/novel-writing/references/golden-chapter-criteria.md`
- [ ] 2.4 修改 `skills/start/SKILL.md`：实现 genre × platform 无效组合 WARNING 逻辑（Step F0 入口处检查）

## 3. 平台硬门（M6.1 — 调研驱动新增）

- [ ] 3.1 修改 `agents/quality-judge.md`：章节 001-003 评估时增加平台硬门检查（番茄: 200 字主角+冲突 / 起点: 世界观骨架+immersion≥3.5 / 晋江: 行为展现人设+CP 登场+style≥3.5）
- [ ] 3.2 修改 `agents/quality-judge.md`：硬门失败时强制 verdict 为 `revise`，附带平台特定的修改建议
- [ ] 3.3 修改 `agents/quality-judge.md`：无 platform 时跳过硬门（向后兼容）

## 4. 受众视角评价（M6.2）

- [ ] 4.1 更新 `templates/platforms/fanqie.md`：增加 `## 评估权重` section（pacing=1.5, emotional_impact=1.5, immersion=1.5, character=0.8, style_naturalness=0.5, plot_logic=0.8, storyline_coherence=0.8, foreshadowing=1.0）
- [ ] 4.2 更新 `templates/platforms/qidian.md`：增加评估权重（storyline_coherence=1.5, plot_logic=1.3, pacing=1.0, character=1.0, style_naturalness=0.8, immersion=0.8, emotional_impact=0.8, foreshadowing=1.0）
- [ ] 4.3 更新 `templates/platforms/jinjiang.md`：增加评估权重（character=1.6, emotional_impact=1.5, immersion=1.1, style_naturalness=1.0, pacing=0.8, plot_logic=0.8, storyline_coherence=0.8, foreshadowing=0.8）
- [ ] 4.4 更新三个平台模板：增加 `## 黄金三章参数` section（章节字数、钩子密度、主角登场时限、CP 互动要求）
- [ ] 4.5 修改 `agents/quality-judge.md`：支持读取 platform_guide 的评估权重 section，加权计算 overall_weighted；权重范围 [0.5, 2.0] 外的值执行钳位并 log WARNING
- [ ] 4.6 修改 QualityJudge 输出 schema：增加 `overall_raw`、`overall_weighted`、`platform_weights` 字段
- [ ] 4.7 修改 `/novel:continue` manifest 组装：QualityJudge manifest 增加可选 `paths.platform_guide`
- [ ] 4.8 修改 gate decision 逻辑：有 platform 时使用 `overall_weighted`，无 platform 时使用 `overall_raw`
- [ ] 4.9 修改 `skills/dashboard/SKILL.md`：质量趋势区展示通用均分 + 平台适配分，标签格式「{platform_display_name}适配分」从 platform 字段动态生成

## 5. excitement_type 对齐（M6 — 调研驱动新增）

- [ ] 5.1 创建类型→excitement_type 默认推荐映射表：`skills/novel-writing/references/excitement-type-by-genre.md`
- [ ] 5.2 修改 `agents/plot-architect.md`：Step F0 模式下参考类型→excitement_type 映射表生成默认组合。M6 范围内仅使用 M5 已有枚举，新增枚举用 `excitement_note` 文本兜底
- [ ] 5.3 （M6 范围外，需单独 PR）通过 openspec 流程提议新增 3 种枚举：`underdog_rise`、`tension_build`、`chemistry_spark`

## 6. 文档与测试

- [ ] 6.1 更新 `docs/user/quick-start.md`：新增 Step F0 说明、时间预期调整
- [ ] 6.2 更新 `skills/continue/references/context-contracts.md`：QualityJudge manifest 新增 platform_guide
- [ ] 6.3 更新 `skills/novel-writing/references/quality-rubric.md`：补充加权评分说明 + 平台硬门说明
- [ ] 6.4 更新 `eval/schema/`：evaluation JSON schema 增加 overall_raw/overall_weighted/platform_weights
- [ ] 6.5 补充 `eval/fixtures/` 中的 smoke test 用例（加权评分场景 + 硬门触发场景）
- [ ] 6.6 将调研报告 `docs/dr-workflow/m6-golden-chapters-research/` 纳入版本管理

## References

- `docs/dr-workflow/m6-golden-chapters-research/final/main.md` — 深度调研综合报告
- `skills/start/SKILL.md` — Quick Start 流程
- `agents/quality-judge.md` — 评分逻辑
- `skills/continue/references/context-contracts.md` — Manifest 契约
- `templates/platforms/` — 平台指南模板
- `openspec/changes/m5-context-quality-enhancements/specs/context-quality-enhancements/spec.md` — M5 excitement_type 枚举
