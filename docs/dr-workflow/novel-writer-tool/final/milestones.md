# 实施里程碑分解 v5

基于 v5 PRD 的卷制滚动工作流 + 规范驱动写作体系 + 多线叙事体系（DR-021 验证）+ 实体映射 + 注入安全 + 路径审计，分解为 4 个 Milestone。

---

## Milestone 1: 续写引擎原型（2 周）

**目标**：验证核心续写能力 + 去 AI 化 + 质量评估 + Spec 基础能力

### 任务分解

| # | 任务 | 优先级 | 预估工时 |
|---|------|--------|---------|
| 1.0 | 搭建 Plugin 脚手架（plugin.json + 4 skills（3 用户可调用 + 1 自动加载）+ 8 agents + templates + hooks） | P0 | 6h |
| 1.1 | 搭建项目结构（目录、配置、checkpoint，含 storylines/ + logs/ + research/ 目录） | P0 | 2h |
| 1.2 | 实现 Agent Prompt 管理（plugin `agents/*.md` + 入口 Skill 变量注入） | P0 | 4h |
| 1.3 | 实现 ChapterWriter Agent（续写模式，增量 context，支持 L1/L2/L3 Spec + 故事线 context 注入） | P0 | 8h |
| 1.4 | 实现 Summarizer（章节摘要 + 状态增量更新 + storyline_id 标记 + cross_references + storyline memory.md 更新 + entity_id_map 消费 + unknown_entities 输出） | P0 | 5h |
| 1.5 | 实现 StyleAnalyzer（风格提取 → style-profile.json） | P0 | 6h |
| 1.6 | 实现 StyleRefiner Agent（去 AI 化润色） | P0 | 6h |
| 1.7 | 实现 QualityJudge Agent（双轨验收：合规检查 + 8 维度评分） | P0 | 8h |
| 1.8 | 实现 checkpoint 机制（写入/读取/恢复） | P0 | 3h |
| 1.9 | 实现 staging → commit 事务写入（staging/ 暂存 + pipeline_stage 幂等恢复 + §10.9 DATA delimiter 注入） | P1 | 4h |
| 1.10 | 实现 L1 世界规则 Spec（WorldBuilder 输出 rules.json） | P0 | 4h |
| 1.11 | 实现 storylines.json 基础结构（WorldBuilder 协助初始化） | P1 | 3h |
| 1.12 | 集成测试：风格样本 + 大纲 → 试写 3 章（完整流水线含 Summarizer）→ Spec 验收 + 评估 | P0 | 4h |

### 验收标准
- [ ] Plugin 结构完整：plugin.json（name: `novel`）可被 Claude Code 识别，3 个 skill 可调用（/novel:start、/novel:continue、/novel:dashboard），8 个 agent 可派生
- [ ] 输入风格样本 + 手写大纲 → 续写 3 章（各 2500-3500 字）
- [ ] QualityJudge 双轨验收：合规检查（L1 规则逐条通过/违反）+ 8 维度评分 ≥ 4.0/5.0（单线章节 storyline_coherence 默认 4 分）
- [ ] 风格自然度 ≥ 3.5（AI 黑名单命中 < 3 次/千字）
- [ ] 每章自动生成摘要（300 字）+ 状态 JSON + storyline_id + cross_references + unknown_entities
- [ ] entity_id_map 正确构建并传入 Summarizer，ops path 使用 slug ID
- [ ] checkpoint 写入/恢复正确
- [ ] WorldBuilder 输出 rules.json，ChapterWriter 可消费
- [ ] storylines.json 基础结构可创建，storyline_types 定义完整
- [ ] Summarizer 输出 cross_references[]，storylines/{id}/memory.md 每章自动更新

### 关键风险
- StyleRefiner 润色可能改变语义 → 增加语义一致性校验
- AI 黑名单初始化需要调研工作 → 先用手动维护的小黑名单
- L1 规则抽取精度不确定 → 初始由用户审核确认

---

## Milestone 2: 卷制循环 + Spec 体系 + 多线叙事（3 周）

**目标**：实现完整的卷规划 → 日更续写 → 卷末回顾 + 三层 Spec 全链路 + 多线叙事调度

### 任务分解

| # | 任务 | 优先级 | 预估工时 |
|---|------|--------|---------|
| 2.1 | 实现 Orchestrator 状态机（INIT→QUICK_START→VOL_PLANNING→WRITING→VOL_REVIEW） | P0 | 10h |
| 2.2 | 实现 context 组装规则（按 agent 类型动态组装，含 Spec + 故事线 context 注入 + entity_id_map 构建 + L2 角色契约裁剪） | P0 | 12h |
| 2.3 | 实现 WorldBuilder Agent（初始化 + 增量更新 + L1 规则抽取 + 协助 storylines.json 初始化） | P0 | 10h |
| 2.4 | 实现 CharacterWeaver Agent（新增/退场/更新 + L2 契约生成） | P0 | 8h |
| 2.5 | 实现 PlotArchitect Agent（卷级大纲 + L3 章节契约 + storyline-schedule.json + 交汇事件规划） | P0 | 12h |
| 2.6 | 实现冷启动恢复（从 checkpoint + 文件重建状态） | P0 | 4h |
| 2.7 | 实现 state 裁剪（退场角色归档、过期状态清理） | P1 | 4h |
| 2.8 | 实现用户审核点交互（大纲确认 + Spec 审核 + 故事线调度审核） | P0 | 5h |
| 2.9 | 实现 Spec 变更传播链（世界规则变更 → 角色契约 → 章节契约） | P0 | 6h |
| 2.10 | 实现 LS 故事线规范（storyline-spec.json + QualityJudge LS 检查） | P0 | 4h |
| 2.11 | 实现故事线 context 组装（storyline_context + concurrent_state + transition_hint） | P0 | 6h |
| 2.12 | 实现 SessionStart hook（inject-context.sh：自动注入 checkpoint + 最近摘要） | P1 | 2h |
| 2.13 | 实现"导入研究资料"功能（扫描 doc-workflow 产出 → research/，WorldBuilder/CharacterWeaver 自动引用） | P1 | 3h |
| 2.14 | 实现 PreToolUse 路径审计 hook（chapter pipeline 子代理 Write/Edit 白名单校验 staging/**，违规拦截 + 记录 audit.jsonl） | P1 | 3h |
| 2.15 | 集成测试：完成 1 卷 30 章循环（含多线叙事 + Spec 全链路验证） | P0 | 14h |

### 验收标准
- [ ] 完成一卷 30 章的完整循环（含至少 2 条故事线交织）
- [ ] Orchestrator 冷启动（新 session）正确恢复
- [ ] WorldBuilder 增量更新不破坏已有设定，rules.json 同步更新
- [ ] CharacterWeaver 正确处理新增/退场，contracts 自动生成
- [ ] PlotArchitect 产出卷纲时自动派生 chapter-contract + storyline-schedule
- [ ] 世界规则变更后，受影响的角色契约和章节契约自动标记需更新
- [ ] QualityJudge 能逐条验证 L1/L2/L3/LS Spec，输出 contract_verification
- [ ] 故事线切换章节能正确注入 storyline_context 和 concurrent_state
- [ ] 交汇事件能在预规划的章节范围内正确触发
- [ ] SessionStart hook 在新 session 自动注入 checkpoint + 最近摘要，非项目目录静默跳过
- [ ] PreToolUse 路径审计 hook 可拦截 chapter pipeline 子代理写入非 staging/ 目录的操作
- [ ] entity_id_map 自动从 characters/active/ 构建，L2 契约裁剪：有契约时加载契约指定角色（无硬上限），无契约时上限 15

### 依赖
- Milestone 1 完成

---

## Milestone 3: 质量保证系统（2 周）

**目标**：自动化一致性和伏笔检测，Spec 合规率统计，故事线一致性检查

### 任务分解

| # | 任务 | 优先级 | 预估工时 |
|---|------|--------|---------|
| 3.1 | 实现 NER 一致性检查（角色名/地名/时间线，含跨故事线时间线矛盾检测） | P0 | 10h |
| 3.2 | 实现伏笔追踪（卷内 + 跨卷 global.json + 跨故事线伏笔桥梁检查） | P0 | 8h |
| 3.3 | 实现质量门控自动流程（Spec + LS 合规检查 + 评分 → 修订 → 通过/拒绝） | P0 | 6h |
| 3.4 | 实现风格漂移检测（每 5 章提取特征对比） | P1 | 4h |
| 3.5 | 实现 AI 黑名单动态更新机制 | P1 | 3h |
| 3.6 | 实现故事线节奏分析（各线出场频率、休眠时长、交汇达成率统计） | P1 | 4h |
| 3.7 | 构建测试集：人工标注 30 章一致性错误 + Spec 违反 + 故事线问题 + QualityJudge 校准（人工评分 vs Judge 评分相关性） | P1 | 8h |
| 3.8 | 回归测试：对 M2 产出运行全部检查（含 Spec + LS 合规率统计） | P0 | 4h |
| 3.9 | 实现关键章双裁判（卷首/卷尾/交汇事件章 Opus 复核，取较低分） | P1 | 3h |

### 验收标准
- [ ] NER 检出率 > 80%（基于 30 章人工标注测试集）
- [ ] 伏笔追踪准确率 > 75%
- [ ] 质量门控：有 Spec/LS violation → 强制修订（不看印象分）
- [ ] 质量门控：低分（<3.0）+ 无 violation → 自动触发修订流程
- [ ] 风格漂移检测到后自动生成校正建议
- [ ] 跨故事线时间线矛盾检测可用（LS-001 hard 检查）
- [ ] 30 章 Spec + LS 合规率统计报告可生成
- [ ] QualityJudge 评分与人工评分 Pearson 相关系数 > 0.6，据此校准阈值
- [ ] 关键章双裁判可用，取较低分作为最终评分
- [ ] 故事线节奏分析报告可生成

### 依赖
- Milestone 2 完成（30 章产出作为测试数据）

---

## Milestone 4: 完整体验（2 周）

**目标**：端到端可用，完成 3 卷 / 100 章，含多线叙事全流程

### 任务分解

| # | 任务 | 优先级 | 预估工时 |
|---|------|--------|---------|
| 4.1 | 实现快速起步流程（30 分钟内完整体验，含 L1/L2 Spec + storylines.json 自动生成） | P0 | 8h |
| 4.2 | 实现跨卷衔接（卷末回顾→下卷规划→续写，含 Spec + 故事线传递） | P0 | 8h |
| 4.3 | 实现按需工具调用（新增角色/世界观更新/伏笔查询/故事线管理，触发 Spec 变更传播） | P0 | 8h |
| 4.4 | 端到端测试：3 卷 100 章（含多线叙事 + Spec 全链路合规验证） | P0 | 24h |
| 4.5 | 性能优化：冷启动速度、context 组装效率 | P1 | 4h |
| 4.6 | 用户文档（快速入门 + 常用操作 + Spec 体系 + 多线叙事说明） | P1 | 4h |

### 验收标准
- [ ] 快速起步 30 分钟内输出 3 章（含设定 + 风格提取 + L1/L2 Spec + storylines.json）
- [ ] 3 卷 100 章端到端完成（含至少 3 条故事线交织、至少 2 次交汇事件）
- [ ] Spec + LS 合规率 > 95%（100 章中 violation < 5 处）
- [ ] 一致性错误 < 10 处（含跨故事线时间线一致性）
- [ ] 冷启动恢复 < 30 秒
- [ ] 人工审核占比 30-50%
- [ ] 故事线休眠→激活转换正确，读者记忆重建提示可用

### 依赖
- Milestone 3 完成

---

## 跨 Milestone 对齐检查

| PRD Section | 覆盖 Milestone | 状态 |
|-------------|----------------|------|
| 2. 产品形态（Plugin） | M1（脚手架） | ✅ |
| 3. 用户画像 | M4（快速起步） | ✅ |
| 4. 系统架构 | M1-M2 | ✅ |
| 5. Prompt 设计 | M1-M2 | ✅ |
| 6. 工作流（Layer 1-3） | M1-M4 | ✅ |
| 6.5 规范驱动写作体系 | M1（L1基础）+ M2（L2/L3全链路）+ M3（合规统计）+ M4（端到端） | ✅ |
| 6.6 多线叙事体系 | M1（基础结构）+ M2（调度+context）+ M3（一致性检查）+ M4（端到端） | ✅ |
| 7. 去 AI 化策略 | M1+M3 | ✅ |
| 8. Orchestrator | M2 | ✅ |
| 9. 数据结构 | M1-M2 | ✅ |
| 10. 协作协议 | M1（§10.9 DATA delimiter）+ M2（状态机 + 路径审计 hook） | ✅ |
| 11. 技术可行性 | M1-M3 | ✅ |
| 12. 成本分析 | M1（验证） | ✅ |
| 13-15. 路线图/指标/风险 | M1-M4 | ✅ |

**全部 PRD 内容已映射到 Milestone，无遗漏。**
