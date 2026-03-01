# Changelog

## v1.8.0

### M5：上下文质量增强

1. **L1/L2 canon_status 生命周期** — 世界规则和角色契约支持 `established` / `planned` / `deprecated` 三态，ChapterWriter 仅以 established 为硬约束
2. **平台写作指南** — 新增 `templates/platforms/{fanqie,qidian,jinjiang}.md`，含节奏密度、章末钩子、设定展示、情感线、对话密度等平台差异化参数；`style-profile.json` 新增 `platform` 字段，编排器条件加载
3. **excitement_type 爽点标注** — L3 章节契约新增爽点类型（reversal/face_slap/power_up/reveal/cliffhanger/setup），QualityJudge pacing 维度叠加爽点落地评估，setup 章使用铺垫有效性替代标准
4. **用户文档** — `docs/user/quick-start.md` + `migration-guide.md`

### M6：黄金三章 + 受众评估

5. **Step F0 迷你卷规划** — 快速起步阶段为前 3 章生成 L3 契约 + 故事线调度 + 伏笔计划，试写获得与正式写作相同的 Spec-Driven 支撑
6. **题材→爽点映射表** — 6 大题材（玄幻/都市/科幻/历史/悬疑/言情）各自的黄金三章 excitement_type 分配规则
7. **题材特定黄金三章标准** — 各题材差异化评审标准 + Genre×Platform 无效/少见组合 WARNING
8. **平台硬门（Ch001-003）** — 番茄（200 字登场+冲突、章末钩子、反转/打脸/升级）、起点（体系存在感、immersion≥3.5）、晋江（行为展现人设、CP lead 登场、情感基调、style_naturalness≥3.5），任一 fail 强制 revise
9. **平台加权评分** — 三大平台各维度乘数，`overall_weighted = Σ(score_i × multiplier_i) / Σ(multiplier_i)`，门控决策使用加权分

### Review 修复

10. **Manifest Mode 架构统一** — 全插件从 `<DATA>` 注入改为路径引用，Agent 按需 Read；start/SKILL.md 重构（497→216 行，Steps A-G 提取到 quick-start-workflow.md）
11. **门控标签双枚举** — QJ 输出 `recommendation`（pass/polish/revise/review/rewrite），编排器映射为 `gate_decision`（pass/polish/revise/pause_for_user/pause_for_user_force_rewrite）
12. **StyleAnalyzer 工具修正** — 移除无效 SDK 工具，reference 模式改用 MCP 降级路径
13. **角色语癖降频** — 从强制每角色口头禅改为可选、每 3-5 章偶现，优先用说话风格区分角色
14. **标点限频规则** — 破折号≤1/千字、省略号≤2/千字、感叹号≤3/千字；对话统一中文双引号
15. **元数据补全** — marketplace.json 版本同步 0.2.0、MIT LICENSE、CI 覆盖 agents/skills 目录 + JSON 校验、eval schema enum 化
