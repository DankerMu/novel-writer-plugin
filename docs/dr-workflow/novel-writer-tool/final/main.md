# 小说自动化创作工具 PRD v5

基于 Claude Code 的多 agent 协作小说创作系统，面向中文网文作者，通过卷制滚动工作流实现长篇小说的高效续写和质量保证。

---

## 文档结构

### PRD（产品需求）

| 文件 | 内容 | 行数 |
|------|------|------|
| [prd/01-product.md](prd/01-product.md) | S1 产品概述 + S2 产品形态（Plugin 架构）+ S3 用户画像 | ~179 |
| [prd/02-architecture.md](prd/02-architecture.md) | S4 系统架构（Agent 团队 + 协作模式 + 模型策略） | ~48 |
| [prd/03-agents.md](prd/03-agents.md) | S5 Agent Prompt 设计（8 个 Agent 的角色/目标/约束/格式） | ~254 |
| [prd/04-workflow.md](prd/04-workflow.md) | S6.1-6.4 核心工作流（快速起步 + 卷制循环 + 全局维护 + 质量门控） | ~76 |
| [prd/05-spec-system.md](prd/05-spec-system.md) | S6.5 规范驱动写作体系（L1/L2/L3 三层 Spec + 变更传播 + 双轨验收） | ~141 |
| [prd/06-storylines.md](prd/06-storylines.md) | S6.6 多线叙事体系（数据模型 + 卷级调度 + 防串线 + LS 规范） | ~256 |
| [prd/07-anti-ai.md](prd/07-anti-ai.md) | S7 去 AI 化策略（4 层：锚定 + 约束 + 后处理 + 检测） | ~48 |
| [prd/08-orchestrator.md](prd/08-orchestrator.md) | S8 Orchestrator 设计（冷启动 + 状态机 + Context 组装 + 裁剪） | ~107 |
| [prd/09-data.md](prd/09-data.md) | S9 数据结构（项目目录 + Checkpoint + State + 评估 + Pipeline Log） | ~186 |
| [prd/10-protocols.md](prd/10-protocols.md) | S10 Agent 协作协议（返回值规范 + 事务写入 + 交互边界） | ~86 |
| [prd/11-appendix.md](prd/11-appendix.md) | S11-16 可行性分析 + 成本 + 路线图 + 成功指标 + 风险 + DR 索引 | ~213 |

### Tech Spec（实现规格）

| 文件 | 内容 | 行数 |
|------|------|------|
| [spec/01-overview.md](spec/01-overview.md) | 文件清单（20 个）+ 开发顺序 + plugin.json + Hooks 配置 | ~125 |
| [spec/02-skills.md](spec/02-skills.md) | 3 个入口 Skill 完整定义（/novel:start、/novel:continue、/novel:dashboard） | ~322 |
| [spec/03-agents.md](spec/03-agents.md) | Agent 通用约束 + 8 个 Agent 索引（链接到独立文件） | ~20 |
| [spec/04-quality.md](spec/04-quality.md) | 核心方法论 SKILL.md + 去 AI 化规则详解 + 8 维度评分标准 | ~348 |
| [spec/05-templates.md](spec/05-templates.md) | 3 个模板（brief-template + ai-blacklist + style-profile-template） | ~178 |
| [spec/06-extensions.md](spec/06-extensions.md) | 确定性工具扩展接口（M3+ 预留：4 扩展点 + CLI 约定 + MCP 路径） | ~55 |

### Agent 独立定义（spec/agents/）

| 文件 | Agent | 模型 |
|------|-------|------|
| [spec/agents/world-builder.md](spec/agents/world-builder.md) | WorldBuilder — 世界观构建 + L1 规则 | Opus |
| [spec/agents/character-weaver.md](spec/agents/character-weaver.md) | CharacterWeaver — 角色网络 + L2 契约 | Opus |
| [spec/agents/plot-architect.md](spec/agents/plot-architect.md) | PlotArchitect — 卷级大纲 + L3 契约 + 故事线调度 | Opus |
| [spec/agents/chapter-writer.md](spec/agents/chapter-writer.md) | ChapterWriter — 章节续写 + 防串线 | Sonnet |
| [spec/agents/summarizer.md](spec/agents/summarizer.md) | Summarizer — 摘要 + 状态增量 + 串线检测 | Sonnet |
| [spec/agents/style-analyzer.md](spec/agents/style-analyzer.md) | StyleAnalyzer — 风格指纹提取 | Sonnet |
| [spec/agents/style-refiner.md](spec/agents/style-refiner.md) | StyleRefiner — 去 AI 化润色 | Opus |
| [spec/agents/quality-judge.md](spec/agents/quality-judge.md) | QualityJudge — 双轨验收（合规 + 8 维度评分） | Sonnet |

### 里程碑

| 文件 | 内容 |
|------|------|
| [milestones.md](milestones.md) | 4 个 Milestone 分解（M1 续写引擎 → M2 卷制循环 → M3 质量保证 → M4 完整体验） |

---

## 核心设计要素速览

- **产品形态**：Claude Code Plugin（name: `novel`），3 入口 Skill + 8 Agent + 1 共享知识库
- **工作流**：卷制滚动（VOL_PLANNING → WRITING ⟲ → VOL_REVIEW），每章流水线含内嵌门控
- **Spec 体系**：L1 世界规则（hard）→ L2 角色契约 → L3 章节契约，QualityJudge 双轨验收
- **多线叙事**：storylines.json + 卷级 schedule + 章级 context 注入，三层防串线，≤4 活跃线
- **去 AI 化**：风格锚定 → 约束注入 → StyleRefiner 后处理 → 检测度量，黑名单 < 3 次/千字
- **成本**：混合模型（Opus + Sonnet），均摊 ~$0.85/章
- **冷启动**：.checkpoint.json + 文件状态，SessionStart hook 自动注入

## DR 报告

共 21 份深度调研报告，详见 [prd/11-appendix.md](prd/11-appendix.md) 中的 DR 索引表。
