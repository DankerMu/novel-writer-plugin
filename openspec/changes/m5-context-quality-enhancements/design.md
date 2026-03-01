# Design: 上下文质量增强

## Context

竞品分析发现其 agent 上下文读取规则在三个方面值得借鉴：正典/预案区分、平台写作指南动态加载、爽点类型显式标注。本项目的 Manifest Mode 架构已具备条件加载能力，这三个特性可以低成本集成。

## Goals

- 防止 ChapterWriter 将未确立的规划内容当作已知事实
- 支持不同网文平台的写作风格差异化
- 让爽点设计从隐性意图变为显式合约，可验证

## Non-Goals

- 不改变 Manifest Mode 架构本身
- 不增加新的 Agent
- 不改变质量门控阈值
- 不在本 change 内创建完整的平台指南内容（仅搭建框架 + 番茄模板作为示例）

## Decisions

### 1. Canon Status 采用字段标记而非文件分离

**备选方案**：
- A) 在 JSON 中增加 `canon_status` 字段（`established` / `planned`）
- B) 将已确立和规划内容分成两个文件（如 `rules-canon.json` + `rules-planned.json`）

**选择 A**：字段标记。原因：
- 避免文件数膨胀
- Summarizer 升级状态时只需 patch 字段，不需跨文件移动
- 向后兼容（字段缺失默认 `established`）

### 2. Platform Guide 粒度为平台级而非章节级

平台指南是相对稳定的写作参考，不需要每章变化。以 `templates/platforms/{platform}.md` 为单位，ChapterWriter 整个项目生命周期内加载同一份。

### 3. Excitement Type 使用枚举而非自由文本

预定义枚举集合，防止 PlotArchitect 生成不可识别的类型：



每章可标注 1-2 个 `excitement_type`。`setup` 表示本章为铺垫章，QualityJudge 对其爽点评估标准放宽。

### 4. Summarizer 负责 Canon 升级

Summarizer 在生成章节摘要时，已经提取 `state_ops`（状态变更）。增加一条规则：当 state_ops 涉及的 rule/fact 当前为 `planned` 状态时，将其升级为 `established`。这保证正典状态随正文推进自动更新。

## Risks / Trade-offs

| 风险 | 缓解 |
|------|------|
| `canon_status` 升级遗漏（Summarizer 未识别到相关 rule） | QualityJudge 在 L1 合规检查中增加 warning：引用了 `planned` 状态的 rule |
| 平台指南内容质量参差 | M5.2 仅交付番茄模板作为示例；其他平台由用户或后续迭代补充 |
| `excitement_type` 枚举不够覆盖 | 枚举集合可通过 openspec 流程扩展；PlotArchitect 可在 contract 中补充自由文本说明 |

## References

- 竞品分析：L1 核心三件套读取规则（2026-03-01 对比记录）
- [Context Contracts](../../skills/continue/references/context-contracts.md)
- [PRD §9 Data Schemas](../../docs/dr-workflow/novel-writer-tool/final/prd/09-data.md)
