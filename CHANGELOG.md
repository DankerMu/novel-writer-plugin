# Changelog

## v2.0.0

### 架构：9 Agent → 5 Agent 整合

1. **WorldBuilder 吸收 CharacterWeaver + StyleAnalyzer** — Mode 4-6（角色创建/更新/退场）+ Mode 7-8（风格提取/漂移检测）合并为 WorldBuilder 的 8 种运行模式
2. **ChapterWriter 吸收 StyleRefiner** — Phase 2 润色内化到 ChapterWriter，省去一次独立 Agent 调用
3. **QualityJudge 吸收 AudienceEval** — Track 3 读者参与度评估内化到 QualityJudge 的三轨验收流程
4. **3 步流水线** — 单章流水线从 CW→SR→Sum→AE→QJ 简化为 CW→Sum→QJ
5. **全 Agent Opus 统一** — 5 个 Agent 均使用 opus 模型

### 反朱雀统计特征检测（Anti-AI Detection Upgrade）

6. **7 指标风格自然度评分** — 从旧版 4 指标（黑名单+句式重复+破折号+匹配度）升级为 7 指标三区范围判定（新增句长标准差、段落长度 CV、叙述连接词密度、修饰词重复），含向后兼容退化
7. **统计分布目标（§2.8）** — 6 维度统计参照（句长方差、段落长度变异、词汇多样性、叙述连接词、语域混合、情感弧线），ChapterWriter 内隐参照
8. **人性化技法工具箱（§2.9）** — 12 种技法随机采样（thought_interrupt / sensory_intrusion / self_correction / emotion_whiplash 等），零配额设计
9. **黑名单扩展** — 45→82 词，新增 3 个分类（narration_connector 仅叙述禁/对话允、paragraph_opener、smooth_transition），增长上限 80→120
10. **style-profile 统计字段** — 新增 sentence_length_std_dev / paragraph_length_cv / emotional_volatility / register_mixing / vocabulary_richness（均 nullable）
11. **lint-blacklist.sh narration_only 感知** — 中文引号奇偶校验区分对话内/外命中，输出 narration_only_stats
12. **ChapterWriter C16-C18** — 句长方差意识 + 叙述连接词零容忍 + 人性化技法自然融入；Phase 2 新增步骤 6.5（连接词清除）+ 6.6（修饰词去重）
13. **QualityJudge 扩展输出** — anti_ai 新增 sentence_length_stats + statistical_profile + detected_humanize_techniques（不影响评分，供 dashboard 跨章统计）
14. **人性化技法跨章追踪** — 每 5 章检测 humanize_drought，含旧 eval 数据可用性前置检查

## v1.9.0

### M7：AudienceEval 读者视角评估

1. **AudienceEval Agent** — 第 9 个 Agent，以第一人称读者视角评估章节吸引力；4 套平台 persona（番茄碎片阅读者/起点付费追更者/晋江情感投入者/通用普通读者）
2. **6 维度读者评分** — continue_reading / hook_effectiveness / skip_urge / confusion / empathy / freshness，权重因平台而异
3. **跳读检测** — 标注 1-3 个最可能被读者跳过的段落（severity: high/medium）
4. **情感弧线** — 逐段采样情绪强度，分类弧线形状（V型/上升型/下降型/W型/平坦型等）
5. **平台信号** — 番茄（读完率/三日留存/追更冲动）、起点（首订/均订/月票）、晋江（留评/CP感/营养液）+ 第一人称一句话读后感
6. **参与门控** — 黄金三章 engagement<3.0 → revise；普通章 pass+engagement<2.5 → polish；失败降级到仅 QJ 门控
7. **Dashboard 读者参与度** — 新增读者参与度区块（6 维度均值、跳读警告、弧线分布、平台信号趋势、读后感）

### 其他

8. **Python venv 隔离** — 所有 scripts/*.sh 优先使用 .venv/bin/python3，fallback 系统 python3

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
