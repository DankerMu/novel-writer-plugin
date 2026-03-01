## 11. 技术可行性分析

### 11.1 已验证技术

- **多 agent 协作**：BookWorld 论文证明 agent 社会可模拟复杂角色关系
- **分层写作**：Dramaturge 的 Global Review → Scene Review 模式可复用
- **状态管理**：Constella 的 JOURNALS 证明可追踪多角色内心状态

### 11.2 技术假设验证状态

| 假设 | 状态 | 结论 | DR |
|------|------|------|-----|
| Context window | ✅ 已验证 | 200K tokens 满足，单次调用最重 ~30K（ChapterWriter 交汇章） | [DR-001](../../v1/dr/dr-001-context-window.md) |
| 生成速度 | ✅ 已验证 | 单章 1.2 分钟 | [DR-004](../../v1/dr/dr-004-generation-speed.md) |
| Agent 并发 | ⚠️ 有约束 | 推荐 3-5 分批执行 | [DR-002](../../v1/dr/dr-002-agent-concurrency.md) |
| 状态同步 | ⚠️ 需优化 | 推荐 SQLite + WAL | [DR-003](../../v1/dr/dr-003-state-sync.md), [DR-006](../../v1/dr/dr-006-state-concurrency.md) |
| 风格分析 | ✅ 已验证 | BiberPlus/NeuroBiber 可用 | [DR-005](../../v1/dr/dr-005-style-analysis.md) |
| 伏笔检测 | ⚠️ 有上限 | 75-85% + 人工 | [DR-007](../../v1/dr/dr-007-foreshadowing.md) |
| NER 一致性 | ✅ 可用 | 分层策略 85-92% | [DR-011](../../v1/dr/dr-011-ner-consistency.md) |
| API 成本 | ✅ 已验证 | 混合策略 ~$0.85/章 | [DR-013](../../v2/dr/dr-013-api-cost.md) |
| Prompt 设计 | ✅ 已定义 | 四层结构 + 增量 context | [DR-014](../../v2/dr/dr-014-prompt-design.md) |
| 质量评估 | ✅ 可行 | LLM-as-Judge 8 维度 + 关键章双裁判 + 人工校准集 | [DR-015](../../v2/dr/dr-015-quality-eval.md) |

**状态存储决策**：MVP 阶段采用纯文件方案（JSON + Markdown），原因：
1. Claude Code Plugin 环境为单用户单进程，无并发写入场景
2. 章节写入采用 staging → validate → commit 事务模式，已避免数据损坏和中途 crash 不一致
3. DR-003/006 推荐的 SQLite + WAL 适用于多进程并发场景，MVP 暂不需要
4. 如未来引入 Web UI 或多设备同步，在 Milestone 3 评估是否升级

## 12. 成本分析

### 12.1 单章成本（混合策略）

| 组件 | 模型 | 输入 tokens | 输出 tokens | 成本 |
|------|------|-----------|-----------|------|
| ChapterWriter | Sonnet | ~20-25K | ~4.5K | $0.15 |
| Summarizer | Sonnet | ~10-12K | ~1K | $0.05 |
| StyleRefiner | Opus | ~8K | ~4.5K | $0.43 |

> **成本优化选项**：StyleRefiner 默认使用 Opus 以保证润色质量。对于成本敏感场景，可通过 plugin 设置降级为 Sonnet（预估 $0.05/章），或改为条件触发模式（仅当 ChapterWriter 初稿的 AI 黑名单命中率 > 3 次/千字 或风格自然度预估偏低时才调用 Opus，其余章节使用 Sonnet）。
| QualityJudge | Sonnet | ~14-16K | ~1K | $0.07 |
| **单章合计** | | | | **~$0.70** |

（含重写预算 15% + 质量评估开销 ~5%）**实际均摊 ~$0.85/章**

### 12.2 按规模估算

| 规模 | 章数 | 字数 | 成本 |
|------|------|------|------|
| 试写 | 3 章 | 1 万字 | ~$4（含初始设定） |
| 一卷 | 30 章 | 9 万字 | ~$30（含卷规划+回顾） |
| 中篇 | 100 章 | 30 万字 | ~$95 |
| 长篇 | 300 章 | 90 万字 | ~$280 |

### 12.3 质量评估额外成本

- 每 10 章一致性检查：~$0.30
- 风格漂移监控（每 5 章）：~$0.10
- 占总成本 < 5%

## 13. 实施路线图

### Milestone 1: 续写引擎原型（2 周）

**目标**：验证核心续写能力 + 去 AI 化 + 质量评估

**任务**：
- 实现 ChapterWriter + Summarizer + StyleRefiner + QualityJudge
- 实现 Prompt 模板系统
- 实现 StyleAnalyzer（风格提取）
- 实现 checkpoint 机制

**验收标准**：
- [ ] 输入风格样本 + 手写大纲 → 续写 3 章
- [ ] QualityJudge 8 维度评分 ≥ 4.0/5.0（单线章节 storyline_coherence 默认 4 分）
- [ ] 风格自然度维度 ≥ 3.5（AI 黑名单命中 < 3 次/千字）
- [ ] 每章生成摘要 + 状态更新
- [ ] checkpoint 可正确恢复

### Milestone 2: 卷制循环（3 周）

**目标**：实现完整的卷规划 → 日更续写 → 卷末回顾循环

**任务**：
- 实现 Orchestrator 状态机
- 实现 WorldBuilder + CharacterWeaver + PlotArchitect
- 实现 context 组装和 state 裁剪
- 实现卷规划和卷末回顾

**验收标准**：
- [ ] 完成一卷 30 章的完整循环（规划→续写→回顾）
- [ ] 在第 30 章时各 Agent context 用量与 §8.4 估算一致（非硬上限）
- [ ] Orchestrator 冷启动正确恢复状态
- [ ] 状态文件跨章正确传递

### Milestone 3: 质量保证系统（2 周）

**目标**：自动化质量检测

**任务**：
- 实现 NER 一致性检查
- 实现伏笔追踪系统（卷内 + 跨卷）
- 评估状态存储是否升级 SQLite + WAL（可选，默认继续纯文件方案）
- 实现质量门控自动流程

**验收标准**：
- [ ] NER 检出率 > 80%
- [ ] 伏笔追踪准确率 > 75%
- [ ] 质量门控正确触发（低分→修订→通过）

### Milestone 4: 完整体验（2 周）

**目标**：用户可完成一部完整网文

**任务**：
- 实现快速起步流程
- 实现用户审核点和交互
- 实现按需工具调用（新增角色/世界观更新）
- 端到端测试：完成 3 卷 / 100 章

**验收标准**：
- [ ] 快速起步 30 分钟内输出 3 章
- [ ] 3 卷 100 章端到端完成，一致性错误 < 10 处
- [ ] 人工审核时间占比 30-50%

## 14. 成功指标

**功能指标**：
- 一致性错误 < 10 处（100 章尺度，含跨故事线时间线一致性）
- 伏笔回收率 > 75%（自动）
- 角色行为符合人设 > 85%
- QualityJudge 章节均分 ≥ 3.5/5.0（8 维度加权）
- 风格自然度 ≥ 3.5/5.0
- Spec + LS 合规率 > 95%（100 章中 violation < 5 处）
- 交汇事件达成率 > 80%（预规划交汇在预定章节范围内触发）
- 故事线串线率 ≤ 3%（跨线实体泄漏检测）[DR-021]

**效率指标**：
- 单章续写耗时 < 3 分钟（含摘要+润色+评估）
- 人工审核占比 30-50%（可调）
- 冷启动恢复 < 30 秒

**成本指标**：
- 单章均摊成本 ≤ $0.85

## 15. 风险与缓解

| 风险 | 影响 | 缓解措施 | 相关 DR |
|------|------|---------|---------|
| AI 味明显 | 高 | 4 层去 AI 化策略（风格锚定+约束+润色+检测） | DR-015 |
| 跨百章一致性崩塌 | 高 | 增量 state + 摘要滑动窗口 + 每 10 章 NER 检查 | DR-003, DR-011 |
| Agent 生成质量不稳定 | 高 | 8 维度评估 + Spec 双轨验收 + 质量门控 + 自动修订 | DR-015 |
| API 成本过高 | 中 | 混合模型 + Haiku 摘要 + 按需调用 | DR-013 |
| Context 超限 | 高 | 单次最重 ~30K，200K window 余量充足，摘要替代全文 | DR-001 |
| Session 中断 | 中 | 文件即状态 + checkpoint + 冷启动 | - |
| 需要 Claude Code 环境 | 高 | MVP 面向技术型用户，长期考虑 Web UI | DR-017 |
| 大厂快速跟进 | 中 | 聚焦中文网文垂直场景 | DR-017 |

## 16. 附录

### 16.1 深度调研报告索引

#### v1 调研（技术可行性）

| ID | 主题 | 核心结论 | 文档 |
|----|------|---------|------|
| DR-001 | Context Window | 200K tokens 满足，单次最重 ~30K | [查看](../../v1/dr/dr-001-context-window.md) |
| DR-002 | Agent 并发 | 推荐 3-5 分批 | [查看](../../v1/dr/dr-002-agent-concurrency.md) |
| DR-003 | 状态同步 | 竞态风险，推荐 SQLite + WAL | [查看](../../v1/dr/dr-003-state-sync.md) |
| DR-004 | 生成速度 | 单章 1.2 分钟 | [查看](../../v1/dr/dr-004-generation-speed.md) |
| DR-005 | 风格分析 | BiberPlus/NeuroBiber 可用 | [查看](../../v1/dr/dr-005-style-analysis.md) |
| DR-006 | 状态并发 | JSON 高危，推荐 SQLite | [查看](../../v1/dr/dr-006-state-concurrency.md) |
| DR-007 | 伏笔检测 | 75-85% + 人工 | [查看](../../v1/dr/dr-007-foreshadowing.md) |
| DR-008 | 用户接受度 | 30-40% 人工可调 | [查看](../../v1/dr/dr-008-user-acceptance.md) |
| DR-009 | Backend 选型 | Claude Opus 4.6 | [查看](../../v1/dr/dr-009-codeagent-backend.md) |
| DR-010 | 关系图 Schema | 有向图 + JSON | [查看](../../v1/dr/dr-010-relationship-schema.md) |
| DR-011 | NER 一致性 | 分层 85-92% | [查看](../../v1/dr/dr-011-ner-consistency.md) |
| DR-012 | 工作流灵活性 | 推荐双模式 | [查看](../../v1/dr/dr-012-workflow-flexibility.md) |

#### v2 调研（产品与市场）

| ID | 主题 | 核心结论 | 文档 |
|----|------|---------|------|
| DR-013 | API 成本 | 混合策略 ~$0.80/章 | [查看](../../v2/dr/dr-013-api-cost.md) |
| DR-014 | Prompt 设计 | 四层结构 + 增量 context | [查看](../../v2/dr/dr-014-prompt-design.md) |
| DR-015 | 质量评估 | LLM-as-Judge 8 维度 + 关键章双裁判 | [查看](../../v2/dr/dr-015-quality-eval.md) |
| DR-016 | 用户细分 | MVP 聚焦网文作者 | [查看](../../v2/dr/dr-016-user-segments.md) |
| DR-017 | 竞品分析 | 差异化：卷制循环+去AI化 | [查看](../../v2/dr/dr-017-competitors.md) |

#### v4 调研（Plugin 与质量）

| ID | 主题 | 核心结论 | 文档 |
|----|------|---------|------|
| DR-018 | Plugin API 格式 | commands/ vs skills/ 区分，agent 需 frontmatter | [查看](../../v4/dr/dr-018-plugin-api.md) |
| DR-019 | Haiku Summarizer | 升级为 Sonnet，成本 +$0.02/章，避免误差累积 | [查看](../../v4/dr/dr-019-haiku-summarizer.md) |
| DR-020 | 单主命令 UX | 三命令混合模式：/novel:start + /novel:continue + /novel:dashboard | [查看](../../v4/dr/dr-020-single-command-ux.md) |

#### v5 调研（多线叙事）

| ID | 主题 | 核心结论 | 文档 |
|----|------|---------|------|
| DR-021 | LLM 多线叙事一致性 | 有条件可行：裸调用串线率 8-20%，三层防护降至 ≤2-3%，≤4 条活跃线 | [查看](../../v5/dr/dr-021-llm-multi-thread-narrative.md) |

### 16.2 参考文献

- BookWorld: agent 社会模拟（arXiv 2504.14538）
- Constella: 多 agent 角色创作（arXiv 2507.05820）
- Dramaturge: 分层叙事优化（arXiv 2510.05188）
- MT-Bench: LLM-as-Judge（Zheng et al., 2023）
- Chatbot Arena: LLM 评估（Chiang et al., 2024）
- Lost in the Middle: LLM 长上下文信息召回（Liu et al., 2023, arXiv 2307.03172）
- FABLES: 书级摘要忠实性评估（Kim et al., 2024, arXiv 2404.01261）
- Agents' Room: 多智能体叙事生成（Huot et al., 2024, arXiv 2410.02603）
- TimeChara: 角色时间线幻觉评估（Ahn et al., 2024, arXiv 2405.18027）
- StoryWriter: 多 agent 长篇故事框架（2025, arXiv 2506.16445）
