# Design: 上下文质量增强

## Context

竞品分析发现其 agent 上下文读取规则在三个方面值得借鉴：正典/预案区分、平台写作指南动态加载、爽点类型显式标注。本项目的 Manifest Mode 架构已具备条件加载能力，这三个特性可以低成本集成。

## Goals / Non-Goals

**Goals:**
- 防止 ChapterWriter 将未确立的规划内容当作已知事实
- 支持不同网文平台的写作风格差异化
- 让爽点设计从隐性意图变为显式合约，可验证

**Non-Goals:**
- 不改变 Manifest Mode 架构本身
- 不增加新的 Agent
- 不改变质量门控阈值
- 不在本 change 内创建完整的平台指南内容（仅搭建框架 + 番茄模板作为示例）
- 不引入 genre+platform 组合矩阵（平台模板内部用条件段落覆盖类型差异）

## Decisions

### 1. Canon Status 采用字段标记而非文件分离

**备选方案**：
- A) 在 JSON 中增加 `canon_status` 字段（`established` / `planned`）
- B) 将已确立和规划内容分成两个文件（如 `rules-canon.json` + `rules-planned.json`）

**选择 A**：字段标记。原因：
- 避免文件数膨胀
- 编排器升级状态时只需 patch 字段，不需跨文件移动
- 向后兼容（字段缺失默认 `established`）

**注意**：向后兼容默认值意味着旧项目升级后，所有现有规则自动视为 `established`。若旧项目中实际包含预案性规则，需要一次性人工审查。迁移指南中应包含此提示。

### 2. L2 Canon Status 由编排器预过滤

L2 角色契约中 `abilities`/`known_facts`/`relationships` 的 `planned` 条目，**由编排器在 manifest 组装阶段过滤**，而非依赖 agent 运行时判断。原因：
- 保持 Manifest Mode 的核心不变量："确定性过滤在编排器层完成"
- 避免将语义判断下放到 LLM 层面（增加 prompt 复杂度和出错概率）
- 与 `hard_rules_list` 的 L1 过滤方式对称

具体实现：Step 2.4 角色裁剪逻辑中，对每个角色 JSON 过滤掉 `canon_status: "planned"` 的子条目后再传入 `paths.character_contracts[]`。例外：当 chapter_contract.preconditions 显式引入某个 `planned` 能力时（表示"本章即将确立该能力"），该条目以 `introducing: true` 标记注入，而非过滤。

### 3. Platform Guide 采用约定式映射

不维护平台枚举列表。`style-profile.json` 的 `platform` 字段接受任意字符串值，编排器按约定查找 `templates/platforms/{platform}.md`：
- 文件存在 → 加载
- 文件不存在 → WARNING + 跳过

天然可扩展，用户可自行创建新平台模板（如 `ciweimao.md`）。

**优先级规则**：`style-profile > platform_guide`。用户个性化风格优先于平台基线。平台指南仅作为 style-profile 未覆盖维度的回退参考。ChapterWriter 明确接收此优先级指示。

### 4. Excitement Type 使用枚举 + 可选自由文本

预定义枚举集合（8 种），附加可选 `excitement_note: string` 自由文本字段：

| Type | 含义 |
|------|------|
| `power_up` | 实力提升 / 获得新能力 |
| `reversal` | 局势逆转 / 反杀 |
| `cliffhanger` | 章末悬念 |
| `emotional_peak` | 情感高潮 / 虐心 / 甜蜜 |
| `mystery_reveal` | 谜底揭晓 / 真相大白 |
| `confrontation` | 正面对决 / 高燃对抗 |
| `worldbuilding_wow` | 世界观震撼展示 |
| `setup` | 铺垫章（无显式爽点，为后续蓄力） |

每章 1-2 个枚举值。`setup` 不可与其他类型混用（互斥）。

`excitement_note` 允许 PlotArchitect 在枚举不够覆盖时补充说明，QualityJudge 遇到未知枚举值时 log warning 而非 crash。

**储备候选**（未来扩展，不在本 change 实现）：`face_slap`（打脸/正名）、`treasure_acquisition`（获宝/机缘）、`social_triumph`（社交胜利）。

### 5. Canon 升级采用 Summarizer hints + 编排器确定性执行

**否决原方案**：直接让 Summarizer 输出 `canon_upgrade` op。原因：
- Summarizer 职责已重（摘要 + state_ops + 串线检测 + 线级记忆 + 实体报告 + context 标记），新增 canon 升级需要额外读取 `rules.json` 和角色契约，增加 context 体积约 2-4K tokens
- Canon 升级是语义推理任务（判断"正文描述的事件是否确立了某条规划"），与 Summarizer 擅长的信息提取任务认知负载不同
- 存在误升级风险（角色"谈论"planned 规则 ≠ 规则在正文中"发生"），且当前设计无 established→planned 降级机制

**选择方案**：两阶段分工
1. **Summarizer** 新增 `canon_hints` 输出字段（轻量，仅列出"本章可能确立了哪些 planned 内容"的 ID 列表），不需要额外读取 rules.json
2. **编排器 commit 阶段** 基于 `canon_hints` + `state_ops` 做确定性交叉验证：只有当 state_ops 中存在与 planned rule/fact 匹配的 set/foreshadow op 时，才执行升级
3. **QualityJudge** 的 planned-reference WARNING 作为兜底

优势：最终决策在编排器（确定性代码），而非 LLM。Summarizer manifest 不需要扩展。

### 6. excitement_type 为章节 contract 根级字段

当前 L3 contract 的 `objectives` 是 array 类型。`excitement_type` 是章节级属性（一章 1-2 种爽点），不应嵌套在 objectives 数组的单个条目内。放在 contract 根级（与 `preconditions`、`objectives`、`postconditions` 平级）。

**字段语义**：
- 缺失 = 跳过爽点评估（向后兼容旧 contract）
- `["setup"]` = 放宽 pacing 评估，改用"铺垫有效性"标准
- `["power_up", "confrontation"]` = 双重爽点要求，QualityJudge 分别评估
- `[]`（空数组）= schema 校验应拒绝，等同于缺失

## Risks / Trade-offs

| 风险 | 缓解 |
|------|------|
| Canon hints 遗漏（Summarizer 未列出相关 rule） | QualityJudge planned-reference WARNING 兜底 |
| Canon hints 误报（Summarizer 列出未真正确立的 rule） | 编排器二次验证：只有 state_ops 中存在匹配 op 时才执行升级 |
| 平台指南内容质量参差 | M5.2 仅交付番茄模板作为示例；其他平台由用户或后续迭代补充 |
| 平台指南与 style-profile 冲突 | 明确优先级：style-profile > platform_guide |
| `excitement_type` 枚举不够覆盖 | `excitement_note` 自由文本兜底；枚举可通过 openspec 流程扩展 |
| Token 预算增量 | platform_guide 约 +0.7-1.5K，canon 过滤反而减少体积，总增量 <1.5K |
| 旧项目迁移 | 字段缺失默认 established（向后兼容）；提供迁移指南提示人工审查 |
| 风格漂移检测误报 | 漂移检测基线应考虑 platform_guide 的修正值 |

## References

- 竞品分析：L1 核心三件套读取规则（2026-03-01 对比记录）
- `skills/continue/references/context-contracts.md` — Manifest schema 权威定义
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md` — PRD §9 Data Schemas
- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md` — PRD §8 Orchestrator
