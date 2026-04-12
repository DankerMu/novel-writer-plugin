## Why

当前修订回环在 gate_decision="revise" 时全量重跑 CW → SR → Summarizer → [QJ+CC]，每次回环等于重跑整章 pipeline。实测单次回环消耗约 80-100K tokens（CW 修订 ~30K + SR ~15K + Sum ~12K + QJ ~16K + CC ~14K），而大部分 revise 场景只有 1-2 个维度失分，全量重跑存在严重浪费：

| 问题 | 影响 |
|------|------|
| CW 收到笼统修订指令，全章重写而非定向修改 | Token 消耗 2-3x，引入新问题概率高 |
| SR 对已润色的文本重复处理 | 15K tokens 浪费（格式问题在首次 SR 已修复） |
| Summarizer 全量重跑（章节事件未变时） | 12K tokens 浪费，canon_hints/crossref 重复计算 |
| QJ/CC 对所有维度重新评估 | 30K tokens 浪费，通过维度的分数可能因重新评估产生波动 |

优化后 revise 回环 token 消耗可从 ~90K 降至 ~35-45K（降幅 50-60%），写作进度提升约 40%。

## What Changes

### 1. 门控输出增加 `failed_dimensions` + `failed_tracks`

Gate decision 输出结构新增：
- `failed_dimensions[]`: QJ Track 2 中触发 revise 的具体维度（如 `["tonal_variance", "plot_logic"]`）
- `failed_tracks[]`: 标记哪些 Track 需要复检（`["track1", "track2", "track4"]` 等）
- `revision_scope`: `"targeted"` | `"full"`（targeted = 定向修改，full = 全面重写）

### 2. 分级回环策略

| 档位 | 触发条件 | 回环范围 | Token 估算 |
|------|---------|---------|-----------|
| polish | 3.5–3.9 | SR(polish_only) → commit（现有行为，不变） | ~15K |
| revise_targeted | 3.0–3.4 且无 high_violation 且无 substance_violation | CW(targeted) → SR(lite) → Sum(patch) → 失分 Track 复检 | ~35-45K |
| revise_full | <3.0 或 high_violation 或 substance_violation | CW → SR → Sum → [QJ+CC] 全量（现有行为） | ~90K |

### 3. StyleRefiner lite 模式

revise_targeted 时 SR 只做最小化处理：
- 仅扫描被 CW 修改的段落（通过 diff 定位）
- 跳过全文格式统一（首次 SR 已处理）

### 4. Summarizer patch 模式

修订未改变章节核心事件时（diff 行数 < 30%）：
- 读取上次 summary + delta，仅对修改部分做增量更新
- canon_hints 仅检查新增/修改段落
- crossref 沿用上次结果（除非修改涉及跨线内容）

### 5. QJ/CC recheck 模式

revise_targeted 时：
- 只传入修改段落 + 上次 eval JSON + 失分维度列表
- 通过维度的分数直接沿用（不重新评估）
- 输出仅覆盖失分维度的重新评分
- Context 从 14-16K 降到 ~6-8K

## Capabilities

### New Capabilities

- `revision_scope` 决策（gate-decision.md 新增逻辑）
- `recheck_mode` 参数（QJ/CC agent 新增输入模式）
- `patch_mode` 参数（Summarizer agent 新增输入模式）
- `lite_mode` 参数（StyleRefiner 修订时的轻量模式）

### Modified Capabilities

- gate-decision.md：输出增加 `failed_dimensions` + `failed_tracks` + `revision_scope`
- continue/SKILL.md Step 5：修订分支按 `revision_scope` 走不同子流水线
- agents/quality-judge.md：支持 `recheck_mode` 输入
- agents/content-critic.md：支持 `recheck_mode` 输入
- agents/summarizer.md：支持 `patch_mode` 输入
- agents/style-refiner.md：支持 `lite_mode` 输入（修订时）

## Impact

- 影响范围：`skills/continue/references/gate-decision.md`、`skills/continue/SKILL.md`、`agents/quality-judge.md`、`agents/content-critic.md`、`agents/summarizer.md`、`agents/style-refiner.md`、`CLAUDE.md`
- 依赖关系：无新外部依赖
- 兼容性：纯增量。`recheck_mode`/`patch_mode`/`lite_mode` 均为可选参数，缺失时走现有全量路径。旧 checkpoint 无 `revision_scope` 字段时默认 `"full"`
- 风险：recheck 模式下沿用旧分数可能掩盖新引入的问题；通过 `revision_scope="full"` 的兜底条件缓解（有 high_violation/substance_violation 时强制全量）

## Milestone Mapping

- M9.2: 修订回环优化

## References

- 当前 gate-decision.md 修订逻辑（revision_count < 2 分支）
- continue/SKILL.md Step 3-5 流水线
- 博文 §六 熵控策略：控制回环成本是熵控的一部分
