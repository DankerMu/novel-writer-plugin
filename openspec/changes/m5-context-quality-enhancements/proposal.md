# M5: 上下文质量增强

## Why

当前 ChapterWriter 的上下文注入机制（Manifest Mode）在**架构层面**已优于竞品（按需读取、确定性 manifest、token 预算），但在**语义精度**上存在三个短板：

1. **正典 vs 预案不分**：`rules.json` 和角色档案中，已在正文确立的事实与卷规划中的预案混在一起。ChapterWriter 可能把未来剧情当已知事实写出，造成剧透或逻辑矛盾。
2. **缺乏平台适配**：番茄、起点、晋江等平台读者预期差异大（节奏密度、设定深度、情感线权重），但当前系统对所有平台使用同一套写作参数。
3. **爽点缺乏显式标注**：L3 chapter contract 只描述情节目标，不标注爽点类型。ChapterWriter 无法精准发力，QualityJudge 也无法评估"爽点是否到位"。

## Capabilities

### New Capabilities

- **Canon Status 字段**：L1 `rules.json` 和 L2 角色档案增加 `canon_status` 字段（`established` / `planned`），编排器预过滤后仅向 ChapterWriter 注入 `established` 内容
- **Platform Guide 动态加载**：新增 `templates/platforms/{platform}.md` 模板，`style-profile.json` 增加 `platform` 字段，ChapterWriter manifest 条件加载平台指南
- **Excitement Type 标注**：L3 chapter contract 根级增加 `excitement_type` 字段（8 种枚举 + 可选自由文本），QualityJudge 据此评估爽点落地效果

### Modified Capabilities

- **ChapterWriter manifest**：`hard_rules_list` 过滤逻辑叠加 `canon_status == "established"` 条件；L2 角色契约中 `planned` 条目由编排器预过滤；新增可选 `paths.platform_guide`
- **PlotArchitect**：生成 L3 contract 时自动填充 `excitement_type`
- **QualityJudge**：`l1_checks` status 枚举扩展 `warning`；`pacing` 维度增加爽点匹配评估
- **WorldBuilder**：创建/更新 rules 时初始化 `canon_status: "planned"`
- **Summarizer**：输出 `canon_hints` 列表（本章可能确立了哪些 planned 内容），由编排器 commit 阶段确定性执行升级
- **编排器 commit 阶段**：基于 Summarizer canon_hints + state_ops 确定性交叉验证，执行 canon_status 升级

## Impact

- **影响范围**：ChapterWriter、PlotArchitect、QualityJudge、WorldBuilder、Summarizer 的 agent 定义 + `/novel:continue` manifest 组装逻辑 + commit 阶段后处理 + `/novel:start` 快速启动流程
- **依赖**：M4 完成（quick-start + cross-volume 基础设施）
- **兼容性**：`canon_status` 字段缺失时默认为 `established`（向后兼容）；`platform` 字段缺失时跳过平台指南加载；`excitement_type` 字段缺失时 QualityJudge 跳过爽点评估
- **Token 预算影响**：platform_guide 约 +0.7-1.5K tokens；canon_status 过滤反而减少 hard_rules_list 体积；excitement_type 可忽略。总增量 <1.5K，在 200K context window 下无风险

## Milestone Mapping

| 子任务 | 描述 |
|--------|------|
| M5.1 | Canon Status — schema 扩展 + 编排器预过滤 + Summarizer hints + commit 阶段升级 |
| M5.2 | Platform Guide — 模板创建 + style-profile 扩展 + manifest 条件加载 |
| M5.3 | Excitement Type — L3 schema 扩展 + PlotArchitect 生成 + QualityJudge 评估 |

## References

- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` — PRD §8 Orchestrator
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md` — PRD §9 Data
- `docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md` — Spec §2 Skills
- `skills/continue/references/context-contracts.md` — Context Contracts
